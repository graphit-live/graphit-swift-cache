import Foundation

internal struct MemoryCacheEngine {
    private var entries: [MemoryEntryIdentity: MemoryEntry] = [:]

    mutating func dataInfo(bucket: CacheBucketID, key: CacheKey, now: Date) -> CacheEntryInfo? {
        let identity = MemoryEntryIdentity(bucket: bucket, key: key)
        guard let entry = entries[identity] else {
            return nil
        }

        if entry.info.isExpired(at: now) {
            entries.removeValue(forKey: identity)
            return nil
        }

        return entry.info
    }

    mutating func data(bucket: CacheBucketID, key: CacheKey, accessedAt now: Date) -> CachedData? {
        let identity = MemoryEntryIdentity(bucket: bucket, key: key)
        guard var entry = entries[identity] else {
            return nil
        }

        if entry.info.isExpired(at: now) {
            entries.removeValue(forKey: identity)
            return nil
        }

        let updatedInfo = CacheEntryInfo(
            bucket: entry.bucket,
            key: entry.key,
            size: entry.info.size,
            storedAt: entry.info.storedAt,
            tags: entry.info.tags,
            lastAccessedAt: now,
            expiresAt: entry.expiration.extendedExpiration(
                afterAccessAt: now,
                currentExpiresAt: entry.info.expiresAt
            )
        )
        entry.info = updatedInfo
        entries[identity] = entry

        return CachedData(data: entry.data, info: updatedInfo)
    }

    mutating func setData(
        _ data: Data,
        bucket: CacheBucketID,
        key: CacheKey,
        policy: BucketPolicy,
        tags: Set<CacheTag>,
        storedAt: Date
    ) throws {
        let size = ByteCount.bytes(Int64(data.count))
        try validateItemSize(size, bucket: bucket, policy: policy)

        _ = removeExpired(in: bucket, now: storedAt)

        let identity = MemoryEntryIdentity(bucket: bucket, key: key)
        let victimIdentities = try victimsForWrite(
            size: size,
            bucket: bucket,
            newIdentity: identity,
            policy: policy
        )
        remove(victimIdentities)

        let expiration = MemoryExpiration(policy: policy.expiration)
        let info = CacheEntryInfo(
            bucket: bucket,
            key: key,
            size: size,
            storedAt: storedAt,
            tags: tags,
            lastAccessedAt: nil,
            expiresAt: expiration.expiresAt(from: storedAt)
        )
        entries[identity] = MemoryEntry(
            bucket: bucket,
            key: key,
            data: data,
            info: info,
            cost: size,
            expiration: expiration
        )
    }

    mutating func remove(bucket: CacheBucketID, key: CacheKey) -> CacheRemovalResult {
        remove([MemoryEntryIdentity(bucket: bucket, key: key)])
    }

    mutating func removeAll() -> CacheRemovalResult {
        let identities = Array(entries.keys)
        return remove(identities)
    }

    mutating func removeAll(in bucket: CacheBucketID) -> CacheRemovalResult {
        removeEntries { entry in
            entry.bucket == bucket
        }
    }

    mutating func removeAll(tagged tag: CacheTag) -> CacheRemovalResult {
        removeEntries { entry in
            entry.info.tags.contains(tag)
        }
    }

    mutating func removeAll(in bucket: CacheBucketID, tagged tag: CacheTag) -> CacheRemovalResult {
        removeEntries { entry in
            entry.bucket == bucket && entry.info.tags.contains(tag)
        }
    }

    mutating func removeAll(insertedBefore date: Date) -> CacheRemovalResult {
        removeEntries { entry in
            entry.info.storedAt < date
        }
    }

    mutating func removeAll(in bucket: CacheBucketID, insertedBefore date: Date) -> CacheRemovalResult {
        removeEntries { entry in
            entry.bucket == bucket && entry.info.storedAt < date
        }
    }

    func usage(in bucket: CacheBucketID) -> BucketUsage {
        let bucketEntries = entries.values.filter { entry in
            entry.bucket == bucket
        }
        let totalBytes = bucketEntries.reduce(into: Int64(0)) { total, entry in
            total += entry.cost.bytes
        }
        let totalSize = ByteCount.bytes(totalBytes)
        return BucketUsage(
            bucket: bucket,
            totalSize: totalSize,
            diskSize: .zero,
            memorySize: totalSize,
            entryCount: bucketEntries.count
        )
    }

    mutating func removeExpired(now: Date) -> CacheRemovalResult {
        removeEntries { entry in
            entry.info.isExpired(at: now)
        }
    }

    mutating func removeExpired(in bucket: CacheBucketID, now: Date) -> CacheRemovalResult {
        removeEntries { entry in
            entry.bucket == bucket && entry.info.isExpired(at: now)
        }
    }

    mutating func enforceCapacity(in bucket: CacheBucketID, policy: BucketPolicy) -> CacheRemovalResult {
        let currentBytes = totalBytes(in: bucket)
        let currentCount = entryCount(in: bucket)
        let bytesToFree = max(Int64(0), currentBytes - policy.maxTotalSize.bytes)
        let entriesToFree: Int
        if let maxItemCount = policy.maxItemCount {
            entriesToFree = max(0, currentCount - maxItemCount)
        } else {
            entriesToFree = 0
        }

        guard bytesToFree > 0 || entriesToFree > 0 else {
            return .empty
        }

        var freedBytes: Int64 = 0
        var victimIdentities: [MemoryEntryIdentity] = []
        for candidate in evictionCandidates(in: bucket, excluding: [], policy: policy) {
            victimIdentities.append(candidate.identity)
            freedBytes += candidate.entry.cost.bytes

            if freedBytes >= bytesToFree && victimIdentities.count >= entriesToFree {
                break
            }
        }

        return remove(victimIdentities)
    }

    private func validateItemSize(_ size: ByteCount, bucket: CacheBucketID, policy: BucketPolicy) throws {
        if let maxItemSize = policy.maxItemSize, size > maxItemSize {
            throw CacheError.itemTooLarge(size: size, limit: maxItemSize)
        }

        guard size <= policy.maxTotalSize else {
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .totalSize(requiredBytes: size, availableEvictableBytes: .zero)
            )
        }
    }

    private func victimsForWrite(
        size: ByteCount,
        bucket: CacheBucketID,
        newIdentity: MemoryEntryIdentity,
        policy: BucketPolicy
    ) throws -> [MemoryEntryIdentity] {
        let currentBytes = totalBytes(in: bucket, excluding: newIdentity)
        let currentCount = entryCount(in: bucket, excluding: newIdentity)
        let postWriteBytes = currentBytes + size.bytes
        let postWriteCount = currentCount + 1
        let bytesToFree = max(Int64(0), postWriteBytes - policy.maxTotalSize.bytes)
        let entriesToFree: Int
        if let maxItemCount = policy.maxItemCount {
            entriesToFree = max(0, postWriteCount - maxItemCount)
        } else {
            entriesToFree = 0
        }

        guard bytesToFree > 0 || entriesToFree > 0 else {
            return []
        }

        let candidates = evictionCandidates(in: bucket, excluding: [newIdentity], policy: policy)
        var victimIdentities: [MemoryEntryIdentity] = []
        var freedBytes: Int64 = 0

        for candidate in candidates {
            victimIdentities.append(candidate.identity)
            freedBytes += candidate.entry.cost.bytes

            if freedBytes >= bytesToFree && victimIdentities.count >= entriesToFree {
                break
            }
        }

        if freedBytes < bytesToFree {
            let availableEvictableBytes = candidates.reduce(into: Int64(0)) { total, candidate in
                total += candidate.entry.cost.bytes
            }
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .totalSize(
                    requiredBytes: size,
                    availableEvictableBytes: ByteCount.bytes(availableEvictableBytes)
                )
            )
        }

        if victimIdentities.count < entriesToFree {
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .itemCount(
                    requiredEvictions: entriesToFree,
                    availableEvictableEntries: candidates.count
                )
            )
        }

        return victimIdentities
    }

    private func evictionCandidates(
        in bucket: CacheBucketID,
        excluding excludedIdentities: Set<MemoryEntryIdentity>,
        policy: BucketPolicy
    ) -> [(identity: MemoryEntryIdentity, entry: MemoryEntry)] {
        entries.compactMap { identity, entry in
            guard entry.bucket == bucket, !excludedIdentities.contains(identity) else {
                return nil
            }
            return (identity, entry)
        }
        .sorted { lhs, rhs in
            isEvictionCandidate(lhs.entry, orderedBefore: rhs.entry, policy: policy)
        }
    }

    private func isEvictionCandidate(
        _ lhs: MemoryEntry,
        orderedBefore rhs: MemoryEntry,
        policy: BucketPolicy
    ) -> Bool {
        switch policy.eviction {
        case .leastRecentlyUsed:
            switch (lhs.info.lastAccessedAt, rhs.info.lastAccessedAt) {
            case (nil, nil):
                return tieBreaksBefore(lhs, rhs)
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case (.some(let lhsAccess), .some(let rhsAccess)):
                if lhsAccess != rhsAccess {
                    return lhsAccess < rhsAccess
                }
                return tieBreaksBefore(lhs, rhs)
            }
        case .oldestInsertedFirst:
            return tieBreaksBefore(lhs, rhs)
        }
    }

    private func tieBreaksBefore(_ lhs: MemoryEntry, _ rhs: MemoryEntry) -> Bool {
        if lhs.info.storedAt != rhs.info.storedAt {
            return lhs.info.storedAt < rhs.info.storedAt
        }
        if lhs.key.rawValue != rhs.key.rawValue {
            return lhs.key.rawValue < rhs.key.rawValue
        }
        return lhs.bucket.rawValue < rhs.bucket.rawValue
    }

    private func totalBytes(in bucket: CacheBucketID) -> Int64 {
        totalBytes(in: bucket, excluding: nil)
    }

    private func totalBytes(in bucket: CacheBucketID, excluding excludedIdentity: MemoryEntryIdentity?) -> Int64 {
        entries.reduce(into: Int64(0)) { total, element in
            if element.value.bucket == bucket && element.key != excludedIdentity {
                total += element.value.cost.bytes
            }
        }
    }

    private func entryCount(in bucket: CacheBucketID) -> Int {
        entryCount(in: bucket, excluding: nil)
    }

    private func entryCount(in bucket: CacheBucketID, excluding excludedIdentity: MemoryEntryIdentity?) -> Int {
        entries.reduce(into: 0) { total, element in
            if element.value.bucket == bucket && element.key != excludedIdentity {
                total += 1
            }
        }
    }

    private mutating func removeEntries(matching shouldRemove: (MemoryEntry) -> Bool) -> CacheRemovalResult {
        let identities = entries.compactMap { identity, entry in
            shouldRemove(entry) ? identity : nil
        }
        return remove(identities)
    }

    @discardableResult
    private mutating func remove(_ identities: [MemoryEntryIdentity]) -> CacheRemovalResult {
        guard !identities.isEmpty else {
            return .empty
        }

        var removedEntries = 0
        var removedBytes: Int64 = 0
        for identity in identities {
            guard let removed = entries.removeValue(forKey: identity) else {
                continue
            }
            removedEntries += 1
            removedBytes += removed.cost.bytes
        }

        return CacheRemovalResult(
            removedEntries: removedEntries,
            removedBytes: ByteCount.bytes(removedBytes)
        )
    }
}

private struct MemoryEntryIdentity: Hashable, Sendable {
    var bucket: CacheBucketID
    var key: CacheKey
}
