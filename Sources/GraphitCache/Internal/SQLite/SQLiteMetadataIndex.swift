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

internal struct DiskLeasedEntryIdentity: Hashable, Sendable {
    let bucket: CacheBucketID
    let key: CacheKey
}

internal struct DiskRemovalOutcome: Sendable {
    let removal: CacheRemovalResult
    let storageRefs: [String]
    let skippedLeasedEntries: Set<DiskLeasedEntryIdentity>

    static let empty = DiskRemovalOutcome(
        removal: .empty,
        storageRefs: [],
        skippedLeasedEntries: []
    )
}

internal typealias DiskFileLeaseCheck = (CacheBucketID, CacheKey) -> Bool

private enum LeasedRemovalHandling {
    case throwIfLeased
    case skipAndReport
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
        isFileLeased: DiskFileLeaseCheck = { _, _ in false },
        moveTemporaryToFinal: () throws -> Void
    ) throws -> DiskWriteCommitResult {
        try connection.transaction {
            let existing = try fetchEntryWithoutTags(bucket: write.bucket, key: write.key)
            if let existing, existing.id != write.id {
                throw CacheError.internalInconsistency("Stable entry ID mismatch for bucket/key lookup.")
            }
            if let existing, isLeasedFile(existing, isFileLeased: isFileLeased) {
                throw CacheError.fileIsLeased(bucket: write.bucket, key: write.key)
            }

            let victims = try victimsForWrite(
                size: write.size,
                bucket: write.bucket,
                newEntryID: write.id,
                policy: policy,
                isFileLeased: isFileLeased
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

    func removeEntry(
        bucket: CacheBucketID,
        key: CacheKey,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        guard let record = try fetchEntryWithoutTags(bucket: bucket, key: key) else {
            return .empty
        }
        return try remove(records: [record], leasedHandling: .throwIfLeased, isFileLeased: isFileLeased)
    }

    func removeEntry(
        bucket: CacheBucketID,
        key: CacheKey,
        matchingStorageRef storageRef: String,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        guard let record = try fetchEntryWithoutTags(bucket: bucket, key: key) else {
            return .empty
        }
        guard record.storageRef == storageRef else {
            return .empty
        }
        return try remove(records: [record], leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeAll(isFileLeased: DiskFileLeaseCheck = { _, _ in false }) throws -> DiskRemovalOutcome {
        try remove(records: allRecords(), leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeAll(
        in bucket: CacheBucketID,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        }
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeAll(
        tagged tag: CacheTag,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let sql = """
        SELECT \(Self.entryColumns)
        FROM entries
        INNER JOIN tags ON tags.entry_id = entries.id
        WHERE tags.tag = ?;
        """
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(tag.rawValue, at: 1)
        }
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeAll(
        in bucket: CacheBucketID,
        tagged tag: CacheTag,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
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
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeAll(
        insertedBefore date: Date,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let cutoff = CacheDateEncoding.microsecondsSinceEpoch(date)
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE stored_at_us < ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindInt64(cutoff, at: 1)
        }
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeAll(
        in bucket: CacheBucketID,
        insertedBefore date: Date,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let cutoff = CacheDateEncoding.microsecondsSinceEpoch(date)
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ? AND stored_at_us < ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindInt64(cutoff, at: 2)
        }
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
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

    func storageRefs() throws -> Set<String> {
        try Set(storageRefs(sql: "SELECT storage_ref FROM entries;") { _ in })
    }

    func storageRefs(in bucket: CacheBucketID) throws -> Set<String> {
        try Set(storageRefs(sql: "SELECT storage_ref FROM entries WHERE bucket = ?;") { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        })
    }

    func removeExpired(
        at date: Date,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let cutoff = CacheDateEncoding.microsecondsSinceEpoch(date)
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE expires_at_us IS NOT NULL AND expires_at_us <= ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindInt64(cutoff, at: 1)
        }
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeExpired(
        in bucket: CacheBucketID,
        at date: Date,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let cutoff = CacheDateEncoding.microsecondsSinceEpoch(date)
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ? AND expires_at_us IS NOT NULL AND expires_at_us <= ?;"
        let selected = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindInt64(cutoff, at: 2)
        }
        return try remove(records: selected, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeEntriesWithMissingPayloads(
        storageRefExists: (String) -> Bool,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let missing = try allRecords().filter { record in
            !storageRefExists(record.storageRef)
        }
        return try remove(records: missing, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func removeEntriesWithMissingPayloads(
        in bucket: CacheBucketID,
        storageRefExists: (String) -> Bool,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ?;"
        let records = try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        }
        let missing = records.filter { record in
            !storageRefExists(record.storageRef)
        }
        return try remove(records: missing, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
    }

    func enforceCapacity(
        in bucket: CacheBucketID,
        policy: BucketPolicy,
        isFileLeased: DiskFileLeaseCheck = { _, _ in false }
    ) throws -> DiskRemovalOutcome {
        let currentBytes = try scalarInt64(
            sql: "SELECT COALESCE(SUM(size_bytes), 0) FROM entries WHERE bucket = ?;"
        ) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        }
        let currentCount = try scalarInt64(sql: "SELECT COUNT(*) FROM entries WHERE bucket = ?;") { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        }
        let bytesToFree = max(Int64(0), currentBytes - policy.maxTotalSize.bytes)
        let entriesToFree: Int64
        if let maxItemCount = policy.maxItemCount {
            entriesToFree = max(Int64(0), currentCount - Int64(maxItemCount))
        } else {
            entriesToFree = 0
        }

        guard bytesToFree > 0 || entriesToFree > 0 else {
            return .empty
        }

        let candidates = try evictionCandidates(in: bucket, policy: policy)
        var victims: [DiskEntryRecord] = []
        var freedBytes: Int64 = 0
        var skippedLeasedEntries = Set<DiskLeasedEntryIdentity>()

        for candidate in candidates {
            if isLeasedFile(candidate, isFileLeased: isFileLeased) {
                skippedLeasedEntries.insert(DiskLeasedEntryIdentity(bucket: candidate.bucket, key: candidate.key))
                continue
            }

            victims.append(candidate)
            freedBytes += candidate.size.bytes
            if freedBytes >= bytesToFree && Int64(victims.count) >= entriesToFree {
                break
            }
        }

        let removal = try remove(records: victims, leasedHandling: .skipAndReport, isFileLeased: isFileLeased)
        skippedLeasedEntries.formUnion(removal.skippedLeasedEntries)
        return DiskRemovalOutcome(
            removal: CacheRemovalResult(
                removedEntries: removal.removal.removedEntries,
                removedBytes: removal.removal.removedBytes,
                skippedLeasedEntries: skippedLeasedEntries.count
            ),
            storageRefs: removal.storageRefs,
            skippedLeasedEntries: skippedLeasedEntries
        )
    }

    private func fetchEntryWithoutTags(bucket: CacheBucketID, key: CacheKey) throws -> DiskEntryRecord? {
        let sql = "SELECT \(Self.entryColumns) FROM entries WHERE bucket = ? AND key = ? LIMIT 1;"
        return try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(key.rawValue, at: 2)
        }.first
    }

    private func isLeasedFile(_ record: DiskEntryRecord, isFileLeased: DiskFileLeaseCheck) -> Bool {
        record.payloadKind == .file && isFileLeased(record.bucket, record.key)
    }

    private func allRecords() throws -> [DiskEntryRecord] {
        try records(sql: "SELECT \(Self.entryColumns) FROM entries;", includeTags: false) { _ in }
    }

    private func remove(
        records selectedRecords: [DiskEntryRecord],
        leasedHandling: LeasedRemovalHandling,
        isFileLeased: DiskFileLeaseCheck
    ) throws -> DiskRemovalOutcome {
        guard !selectedRecords.isEmpty else {
            return .empty
        }

        var removableRecords: [DiskEntryRecord] = []
        var skippedLeasedEntries = Set<DiskLeasedEntryIdentity>()
        for record in selectedRecords {
            if isLeasedFile(record, isFileLeased: isFileLeased) {
                switch leasedHandling {
                case .throwIfLeased:
                    throw CacheError.fileIsLeased(bucket: record.bucket, key: record.key)
                case .skipAndReport:
                    skippedLeasedEntries.insert(DiskLeasedEntryIdentity(bucket: record.bucket, key: record.key))
                    continue
                }
            }
            removableRecords.append(record)
        }

        guard !removableRecords.isEmpty else {
            return DiskRemovalOutcome(
                removal: CacheRemovalResult(skippedLeasedEntries: skippedLeasedEntries.count),
                storageRefs: [],
                skippedLeasedEntries: skippedLeasedEntries
            )
        }

        try connection.transaction {
            for record in removableRecords {
                try deleteEntry(id: record.id)
            }
        }

        let removedBytes = removableRecords.reduce(into: Int64(0)) { total, record in
            total += record.size.bytes
        }
        return DiskRemovalOutcome(
            removal: CacheRemovalResult(
                removedEntries: removableRecords.count,
                removedBytes: ByteCount.bytes(removedBytes),
                skippedLeasedEntries: skippedLeasedEntries.count
            ),
            storageRefs: removableRecords.map(\.storageRef),
            skippedLeasedEntries: skippedLeasedEntries
        )
    }

    private func victimsForWrite(
        size: ByteCount,
        bucket: CacheBucketID,
        newEntryID: String,
        policy: BucketPolicy,
        isFileLeased: DiskFileLeaseCheck
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
            .filter { record in
                !isLeasedFile(record, isFileLeased: isFileLeased)
            }
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
        let sql = """
        SELECT \(Self.entryColumns)
        FROM entries
        WHERE bucket = ? AND id != ?
        ORDER BY \(evictionOrdering(for: policy));
        """

        return try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
            try statement.bindText(excludedEntryID, at: 2)
        }
    }

    private func evictionCandidates(
        in bucket: CacheBucketID,
        policy: BucketPolicy
    ) throws -> [DiskEntryRecord] {
        let sql = """
        SELECT \(Self.entryColumns)
        FROM entries
        WHERE bucket = ?
        ORDER BY \(evictionOrdering(for: policy));
        """

        return try records(sql: sql, includeTags: false) { statement in
            try statement.bindText(bucket.rawValue, at: 1)
        }
    }

    private func evictionOrdering(for policy: BucketPolicy) -> String {
        switch policy.eviction {
        case .leastRecentlyUsed:
            "last_accessed_at_us IS NOT NULL ASC, last_accessed_at_us ASC, stored_at_us ASC, key ASC"
        case .oldestInsertedFirst:
            "stored_at_us ASC, key ASC"
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

    private func storageRefs(
        sql: String,
        bind: (SQLiteStatement) throws -> Void
    ) throws -> [String] {
        let statement = try connection.prepare(sql)
        try bind(statement)

        var refs: [String] = []
        while try statement.step() {
            guard let ref = statement.columnText(at: 0) else {
                throw CacheError.internalInconsistency("SQLite metadata row contains NULL storage_ref text.")
            }
            refs.append(ref)
        }
        return refs
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
