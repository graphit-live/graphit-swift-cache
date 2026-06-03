import Foundation

internal struct MemoryCacheEngine {
    private var entries: [MemoryEntryIdentity: MemoryEntry] = [:]

    func dataInfo(bucket: CacheBucketID, key: CacheKey) -> CacheEntryInfo? {
        entries[MemoryEntryIdentity(bucket: bucket, key: key)]?.info
    }

    func data(bucket: CacheBucketID, key: CacheKey) -> CachedData? {
        guard let entry = entries[MemoryEntryIdentity(bucket: bucket, key: key)] else {
            return nil
        }
        return CachedData(data: entry.data, info: entry.info)
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

        let identity = MemoryEntryIdentity(bucket: bucket, key: key)
        let existingEntry = entries[identity]
        let currentBucketBytes = totalBytes(in: bucket) - (existingEntry?.cost.bytes ?? 0)
        let postWriteBytes = currentBucketBytes + size.bytes
        guard postWriteBytes <= policy.maxTotalSize.bytes else {
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .totalSize(requiredBytes: size, availableEvictableBytes: .zero)
            )
        }

        if let maxItemCount = policy.maxItemCount {
            let currentBucketCount = entryCount(in: bucket) - (existingEntry == nil ? 0 : 1)
            let postWriteCount = currentBucketCount + 1
            guard postWriteCount <= maxItemCount else {
                throw CacheError.capacityCannotBeSatisfied(
                    bucket: bucket,
                    constraint: .itemCount(
                        requiredEvictions: postWriteCount - maxItemCount,
                        availableEvictableEntries: 0
                    )
                )
            }
        }

        let info = CacheEntryInfo(
            bucket: bucket,
            key: key,
            size: size,
            storedAt: storedAt,
            tags: tags,
            lastAccessedAt: nil,
            expiresAt: nil
        )
        entries[identity] = MemoryEntry(
            bucket: bucket,
            key: key,
            data: data,
            info: info,
            cost: size
        )
    }

    mutating func remove(bucket: CacheBucketID, key: CacheKey) -> CacheRemovalResult {
        guard let removed = entries.removeValue(forKey: MemoryEntryIdentity(bucket: bucket, key: key)) else {
            return .empty
        }
        return CacheRemovalResult(removedEntries: 1, removedBytes: removed.cost)
    }

    mutating func removeAll() -> CacheRemovalResult {
        let result = removalResult(for: entries.values)
        entries.removeAll()
        return result
    }

    mutating func removeAll(in bucket: CacheBucketID) -> CacheRemovalResult {
        let identities = entries.keys.filter { identity in
            identity.bucket == bucket
        }
        guard !identities.isEmpty else { return .empty }

        var removedEntries = 0
        var removedBytes: Int64 = 0
        for identity in identities {
            guard let removed = entries.removeValue(forKey: identity) else { continue }
            removedEntries += 1
            removedBytes += removed.cost.bytes
        }

        return CacheRemovalResult(
            removedEntries: removedEntries,
            removedBytes: ByteCount.bytes(removedBytes)
        )
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

    private func totalBytes(in bucket: CacheBucketID) -> Int64 {
        entries.values.reduce(into: Int64(0)) { total, entry in
            if entry.bucket == bucket {
                total += entry.cost.bytes
            }
        }
    }

    private func entryCount(in bucket: CacheBucketID) -> Int {
        entries.values.reduce(into: 0) { total, entry in
            if entry.bucket == bucket {
                total += 1
            }
        }
    }

    private func removalResult(for entries: Dictionary<MemoryEntryIdentity, MemoryEntry>.Values) -> CacheRemovalResult {
        let removedBytes = entries.reduce(into: Int64(0)) { total, entry in
            total += entry.cost.bytes
        }
        return CacheRemovalResult(
            removedEntries: entries.count,
            removedBytes: ByteCount.bytes(removedBytes)
        )
    }
}

private struct MemoryEntryIdentity: Hashable, Sendable {
    var bucket: CacheBucketID
    var key: CacheKey
}
