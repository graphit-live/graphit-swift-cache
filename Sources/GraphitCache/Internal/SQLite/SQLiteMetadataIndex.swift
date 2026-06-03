import Foundation

internal enum StoredExpirationKind: String, Sendable {
    case never
    case fixed
    case sliding
}

internal struct DiskEntryRecord: Sendable {
    let id: String
    let bucket: CacheBucketID
    let key: CacheKey
    let payloadKind: StoredPayloadKind
    let storageRef: String
    let size: ByteCount
    let storedAtUS: Int64
    let lastAccessedAtUS: Int64?
    let expiresAtUS: Int64?
    let expirationKind: StoredExpirationKind
    let expirationDurationUS: Int64?
    let tags: Set<CacheTag>

    func info(
        lastAccessedAtUS overrideLastAccessedAtUS: Int64? = nil,
        expiresAtUS overrideExpiresAtUS: Int64? = nil
    ) -> CacheEntryInfo {
        let effectiveLastAccessedAtUS = overrideLastAccessedAtUS ?? lastAccessedAtUS
        let effectiveExpiresAtUS = overrideExpiresAtUS ?? expiresAtUS
        return CacheEntryInfo(
            bucket: bucket,
            key: key,
            size: size,
            storedAt: CacheDateEncoding.date(microsecondsSinceEpoch: storedAtUS),
            tags: tags,
            lastAccessedAt: effectiveLastAccessedAtUS.map(CacheDateEncoding.date(microsecondsSinceEpoch:)),
            expiresAt: effectiveExpiresAtUS.map(CacheDateEncoding.date(microsecondsSinceEpoch:))
        )
    }
}

internal struct DiskEntryWrite: Sendable {
    let id: String
    let bucket: CacheBucketID
    let key: CacheKey
    let payloadKind: StoredPayloadKind
    let storageRef: String
    let size: ByteCount
    let storedAtUS: Int64
    let expiresAtUS: Int64?
    let expirationKind: StoredExpirationKind
    let expirationDurationUS: Int64?
    let tags: Set<CacheTag>
}

internal struct DiskWriteCommitResult: Sendable {
    let oldStorageRef: String?
    let victimStorageRefs: [String]

    var removableStorageRefs: [String] {
        var refs = victimStorageRefs
        if let oldStorageRef {
            refs.append(oldStorageRef)
        }
        return refs
    }
}

internal final class SQLiteMetadataIndex {
    private static let entryColumns = """
    id, bucket, key, payload_kind, storage_ref, size_bytes, stored_at_us,
    last_accessed_at_us, expires_at_us, expiration_kind, expiration_duration_us
    """

    private let connection: SQLiteConnection

    init(databaseURL: URL) throws {
        self.connection = try SQLiteConnection(url: databaseURL)
        try SQLiteSchema.apply(to: connection)
    }

    func fetchEntry(bucket: CacheBucketID, key: CacheKey) throws -> DiskEntryRecord? {
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ? AND key = ? LIMIT 1;"
        return try records(sql: sql, includeTags: true) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(key.rawValue, at: 2)
        }.first
    }

    func commitWrite(
        _ write: DiskEntryWrite,
        policy: BucketPolicy,
        moveTemporaryToFinal: () throws -> Void
    ) throws -> DiskWriteCommitResult {
        try connection.transaction {
            let existing = try fetchEntryWithoutTags(bucket: write.bucket, key: write.key)
            if let existing, existing.id != write.id {
                throw CacheError.internalInconsistency("Stable entry ID mismatch for bucket/key lookup.")
            }

            let victims = try victimsForWrite(
                size: write.size,
                bucket: write.bucket,
                newEntryID: write.id,
                policy: policy
            )

            try upsertEntry(write)
            try replaceTags(entryID: write.id, tags: write.tags)
            for victim in victims {
                try deleteEntry(id: victim.id)
            }
            try moveTemporaryToFinal()

            return DiskWriteCommitResult(
                oldStorageRef: existing?.storageRef,
                victimStorageRefs: victims.map(\.storageRef)
            )
        }
    }

    func updateAccess(entryID: String, lastAccessedAtUS: Int64, expiresAtUS: Int64?) throws {
        let statement = try connection.prepare(
            """
            UPDATE entries
            SET last_accessed_at_us = ?, expires_at_us = ?
            WHERE id = ?;
            """
        )
        try statement.bindInt64(lastAccessedAtUS, at: 1)
        try statement.bindOptionalInt64(expiresAtUS, at: 2)
        try statement.bindText(entryID, at: 3)
        try statement.run()
    }

    func removeEntry(bucket: CacheBucketID, key: CacheKey) throws -> (CacheRemovalResult, [String]) {
        guard let record = try fetchEntryWithoutTags(bucket: bucket, key: key) else {
            return (.empty, [])
        }
        return try remove(records: [record])
    }

    func removeAll() throws -> (CacheRemovalResult, [String]) {
        try remove(records: allRecords())
    }

    func removeAll(in bucket: CacheBucketID) throws -> (CacheRemovalResult, [String]) {
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        }
        return try remove(records: selected)
    }

    func removeAll(tagged tag: CacheTag) throws -> (CacheRemovalResult, [String]) {
        let sql = """
        SELECT \(Self.entryColumns)
        FROM entries
        INNER JOIN tags ON tags.entry_id = entries.id
        WHERE tags.tag = ?;
        """
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(tag.rawValue, at: 1)
        }
        return try remove(records: selected)
    }

    func removeAll(in bucket: CacheBucketID, tagged tag: CacheTag) throws -> (CacheRemovalResult, [String]) {
        let sql = """
        SELECT \(Self.entryColumns)
        FROM entries
        INNER JOIN tags ON tags.entry_id = entries.id
        WHERE entries.bucket = ? AND tags.tag = ?;
        """
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(tag.rawValue, at: 2)
        }
        return try remove(records: selected)
    }

    func removeAll(insertedBefore date: Date) throws -> (CacheRemovalResult, [String]) {
        let cutoff = CacheDateEncoding.microsecondsSinceEpoch(date)
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE stored_at_us < ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindInt64(cutoff, at: 1)
        }
        return try remove(records: selected)
    }

    func removeAll(in bucket: CacheBucketID, insertedBefore date: Date) throws -> (CacheRemovalResult, [String]) {
        let cutoff = CacheDateEncoding.microsecondsSinceEpoch(date)
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ? AND stored_at_us < ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindInt64(cutoff, at: 2)
        }
        return try remove(records: selected)
    }

    func usage(in bucket: CacheBucketID) throws -> BucketUsage {
        let statement = try connection.prepare(
            """
            SELECT COALESCE(SUM(size_bytes), 0), COUNT(*)
            FROM entries
            WHERE bucket = ?;
            """
        )
        try statement.bindText(bucket.rawValue, at: 1)
        guard try statement.step() else {
            throw CacheError.storageFailure("SQLite usage query returned no row.")
        }
        let totalSize = ByteCount.bytes(statement.columnInt64(at: 0))
        let count = Int(statement.columnInt64(at: 1))
        return BucketUsage(
            bucket: bucket,
            totalSize: totalSize,
            diskSize: totalSize,
            memorySize: .zero,
            entryCount: count
        )
    }

    private func fetchEntryWithoutTags(bucket: CacheBucketID, key: CacheKey) throws -> DiskEntryRecord? {
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ? AND key = ? LIMIT 1;"
        return try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(key.rawValue, at: 2)
        }.first
    }

    private func allRecords() throws -> [DiskEntryRecord] {
        try records(sql: "SELECT \(Self.entryColumns) FROM entries;", includeTags: false) { _ in }
    }

    private func remove(records selectedRecords: [DiskEntryRecord]) throws -> (CacheRemovalResult, [String]) {
        guard !selectedRecords.isEmpty else {
            return (.empty, [])
        }

        try connection.transaction {
            for record in selectedRecords {
                try deleteEntry(id: record.id)
            }
        }

        let removedBytes = selectedRecords.reduce(into: Int64(0)) { total, record in
            total += record.size.bytes
        }
        return (
            CacheRemovalResult(
                removedEntries: selectedRecords.count,
                removedBytes: ByteCount.bytes(removedBytes)
            ),
            selectedRecords.map(\.storageRef)
        )
    }

    private func victimsForWrite(
        size: ByteCount,
        bucket: CacheBucketID,
        newEntryID: String,
        policy: BucketPolicy
    ) throws -> [DiskEntryRecord] {
        let currentBytes = try scalarInt64(
            sql: "SELECT COALESCE(SUM(size_bytes), 0) FROM entries WHERE bucket = ? AND id != ?;"
        ) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(newEntryID, at: 2)
        }
        let currentCount = try scalarInt64(
            sql: "SELECT COUNT(*) FROM entries WHERE bucket = ? AND id != ?;"
        ) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(newEntryID, at: 2)
        }

        let postWriteBytes = currentBytes + size.bytes
        let postWriteCount = currentCount + 1
        let bytesToFree = max(Int64(0), postWriteBytes - policy.maxTotalSize.bytes)
        let entriesToFree: Int64
        if let maxItemCount = policy.maxItemCount {
            entriesToFree = max(Int64(0), postWriteCount - Int64(maxItemCount))
        } else {
            entriesToFree = 0
        }

        guard bytesToFree > 0 || entriesToFree > 0 else {
            return []
        }

        let candidates = try evictionCandidates(in: bucket, excluding: newEntryID, policy: policy)
        var victims: [DiskEntryRecord] = []
        var freedBytes: Int64 = 0

        for candidate in candidates {
            victims.append(candidate)
            freedBytes += candidate.size.bytes
            if freedBytes >= bytesToFree && Int64(victims.count) >= entriesToFree {
                break
            }
        }

        if freedBytes < bytesToFree {
            let availableBytes = candidates.reduce(into: Int64(0)) { total, candidate in
                total += candidate.size.bytes
            }
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .totalSize(
                    requiredBytes: size,
                    availableEvictableBytes: ByteCount.bytes(availableBytes)
                )
            )
        }

        if Int64(victims.count) < entriesToFree {
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .itemCount(
                    requiredEvictions: Int(entriesToFree),
                    availableEvictableEntries: candidates.count
                )
            )
        }

        return victims
    }

    private func evictionCandidates(
        in bucket: CacheBucketID,
        excluding excludedEntryID: String,
        policy: BucketPolicy
    ) throws -> [DiskEntryRecord] {
        let ordering: String
        switch policy.eviction {
        case .leastRecentlyUsed:
            ordering = "last_accessed_at_us IS NOT NULL ASC, last_accessed_at_us ASC, stored_at_us ASC, key ASC"
        case .oldestInsertedFirst:
            ordering = "stored_at_us ASC, key ASC"
        }

        let sql = """
        SELECT \(Self.entryColumns)
        FROM entries
        WHERE bucket = ? AND id != ?
        ORDER BY \(ordering);
        """

        return try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(excludedEntryID, at: 2)
        }
    }

    private func upsertEntry(_ write: DiskEntryWrite) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO entries (
                id, bucket, key, payload_kind, storage_ref, size_bytes, stored_at_us,
                last_accessed_at_us, expires_at_us, expiration_kind, expiration_duration_us
            ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)
            ON CONFLICT(bucket, key) DO UPDATE SET
                payload_kind = excluded.payload_kind,
                storage_ref = excluded.storage_ref,
                size_bytes = excluded.size_bytes,
                stored_at_us = excluded.stored_at_us,
                last_accessed_at_us = excluded.last_accessed_at_us,
                expires_at_us = excluded.expires_at_us,
                expiration_kind = excluded.expiration_kind,
                expiration_duration_us = excluded.expiration_duration_us;
            """
        )
        try statement.bindText(write.id, at: 1)
        try statement.bindText(write.bucket.rawValue, at: 2)
        try statement.bindText(write.key.rawValue, at: 3)
        try statement.bindText(write.payloadKind.rawValue, at: 4)
        try statement.bindText(write.storageRef, at: 5)
        try statement.bindInt64(write.size.bytes, at: 6)
        try statement.bindInt64(write.storedAtUS, at: 7)
        try statement.bindOptionalInt64(write.expiresAtUS, at: 8)
        try statement.bindText(write.expirationKind.rawValue, at: 9)
        try statement.bindOptionalInt64(write.expirationDurationUS, at: 10)
        try statement.run()
    }

    private func replaceTags(entryID: String, tags: Set<CacheTag>) throws {
        let delete = try connection.prepare("DELETE FROM tags WHERE entry_id = ?;")
        try delete.bindText(entryID, at: 1)
        try delete.run()

        for tag in tags.sorted(by: { $0.rawValue < $1.rawValue }) {
            let insert = try connection.prepare("INSERT INTO tags (entry_id, tag) VALUES (?, ?);")
            try insert.bindText(entryID, at: 1)
            try insert.bindText(tag.rawValue, at: 2)
            try insert.run()
        }
    }

    private func deleteEntry(id: String) throws {
        let statement = try connection.prepare("DELETE FROM entries WHERE id = ?;")
        try statement.bindText(id, at: 1)
        try statement.run()
    }

    private func records(
        sql: String,
        includeTags: Bool,
        bind: (SQLiteStatement) throws -> Void
    ) throws -> [DiskEntryRecord] {
        let statement = try connection.prepare(sql)
        try bind(statement)

        var records: [DiskEntryRecord] = []
        while try statement.step() {
            records.append(try record(from: statement, includeTags: includeTags))
        }
        return records
    }

    private func record(from statement: SQLiteStatement, includeTags: Bool) throws -> DiskEntryRecord {
        guard let id = statement.columnText(at: 0),
              let bucketRawValue = statement.columnText(at: 1),
              let keyRawValue = statement.columnText(at: 2),
              let payloadKindRawValue = statement.columnText(at: 3),
              let payloadKind = StoredPayloadKind(rawValue: payloadKindRawValue),
              let storageRef = statement.columnText(at: 4),
              let expirationKindRawValue = statement.columnText(at: 9),
              let expirationKind = StoredExpirationKind(rawValue: expirationKindRawValue)
        else {
            throw CacheError.internalInconsistency("SQLite metadata row contains invalid text fields.")
        }

        let tags = includeTags ? try tags(entryID: id) : []
        return DiskEntryRecord(
            id: id,
            bucket: CacheBucketID(bucketRawValue),
            key: CacheKey(keyRawValue),
            payloadKind: payloadKind,
            storageRef: storageRef,
            size: ByteCount.bytes(statement.columnInt64(at: 5)),
            storedAtUS: statement.columnInt64(at: 6),
            lastAccessedAtUS: statement.columnIsNull(at: 7) ? nil : statement.columnInt64(at: 7),
            expiresAtUS: statement.columnIsNull(at: 8) ? nil : statement.columnInt64(at: 8),
            expirationKind: expirationKind,
            expirationDurationUS: statement.columnIsNull(at: 10) ? nil : statement.columnInt64(at: 10),
            tags: tags
        )
    }

    private func tags(entryID: String) throws -> Set<CacheTag> {
        let statement = try connection.prepare("SELECT tag FROM tags WHERE entry_id = ? ORDER BY tag;")
        try statement.bindText(entryID, at: 1)

        var tags = Set<CacheTag>()
        while try statement.step() {
            guard let tag = statement.columnText(at: 0) else {
                throw CacheError.internalInconsistency("SQLite tag row contains NULL tag text.")
            }
            tags.insert(CacheTag(tag))
        }
        return tags
    }

    private func scalarInt64(sql: String, bind: (SQLiteStatement) throws -> Void) throws -> Int64 {
        let statement = try connection.prepare(sql)
        try bind(statement)
        guard try statement.step() else {
            throw CacheError.storageFailure("SQLite scalar query returned no row.")
        }
        return statement.columnInt64(at: 0)
    }
}
