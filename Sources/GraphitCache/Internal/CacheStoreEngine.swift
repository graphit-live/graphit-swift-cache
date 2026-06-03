import Foundation

actor CacheStoreEngine {
    private static let unimplementedStorageMessage = "This storage behavior is not implemented yet."

    private let configuration: CacheStoreConfiguration
    private let bucketPolicies: [CacheBucketID: BucketPolicy]
    private var memory = MemoryCacheEngine()

    init(configuration: CacheStoreConfiguration) {
        self.configuration = configuration

        var bucketPolicies: [CacheBucketID: BucketPolicy] = [:]
        for bucket in configuration.buckets {
            bucketPolicies[bucket.id] = bucket.policy
        }
        self.bucketPolicies = bucketPolicies
    }

    func usage() -> CacheUsage {
        let bucketUsages = configuration.buckets.map { bucket in
            usage(bucket: bucket.id, policy: bucket.policy)
        }
        let totalBytes = bucketUsages.reduce(into: Int64(0)) { total, usage in
            total += usage.totalSize.bytes
        }
        let diskBytes = bucketUsages.reduce(into: Int64(0)) { total, usage in
            total += usage.diskSize.bytes
        }
        let memoryBytes = bucketUsages.reduce(into: Int64(0)) { total, usage in
            total += usage.memorySize.bytes
        }
        let entryCount = bucketUsages.reduce(into: 0) { total, usage in
            total += usage.entryCount
        }

        return CacheUsage(
            totalSize: ByteCount.bytes(totalBytes),
            diskSize: ByteCount.bytes(diskBytes),
            memorySize: ByteCount.bytes(memoryBytes),
            entryCount: entryCount,
            buckets: bucketUsages
        )
    }

    func usage(bucket: CacheBucketID, policy: BucketPolicy) -> BucketUsage {
        guard policy.storage == .memoryOnly else {
            return emptyUsage(bucket: bucket)
        }
        return memory.usage(in: bucket)
    }

    func cleanup() -> CacheCleanupResult {
        let now = configuration.clock.now()
        let expired = memory.removeExpired(now: now)
        var evictedEntries = 0
        var evictedBytes: Int64 = 0

        for bucket in configuration.buckets where bucket.policy.storage == .memoryOnly {
            let eviction = memory.enforceCapacity(in: bucket.id, policy: bucket.policy)
            evictedEntries += eviction.removedEntries
            evictedBytes += eviction.removedBytes.bytes
        }

        return CacheCleanupResult(
            removedExpiredEntries: expired.removedEntries,
            removedExpiredBytes: expired.removedBytes,
            evictedEntries: evictedEntries,
            evictedBytes: ByteCount.bytes(evictedBytes)
        )
    }

    func cleanup(bucket: CacheBucketID) -> CacheCleanupResult {
        guard let policy = bucketPolicies[bucket], policy.storage == .memoryOnly else {
            return .empty
        }

        let now = configuration.clock.now()
        let expired = memory.removeExpired(in: bucket, now: now)
        let eviction = memory.enforceCapacity(in: bucket, policy: policy)

        return CacheCleanupResult(
            removedExpiredEntries: expired.removedEntries,
            removedExpiredBytes: expired.removedBytes,
            evictedEntries: eviction.removedEntries,
            evictedBytes: eviction.removedBytes
        )
    }

    func removeAll() -> CacheRemovalResult {
        memory.removeAll()
    }

    func removeAll(in bucket: CacheBucketID) -> CacheRemovalResult {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return .empty
        }
        return memory.removeAll(in: bucket)
    }

    func removeAll(tagged tag: CacheTag) -> CacheRemovalResult {
        memory.removeAll(tagged: tag)
    }

    func removeAll(insertedBefore date: Date) -> CacheRemovalResult {
        memory.removeAll(insertedBefore: date)
    }

    func removeAll(in bucket: CacheBucketID, tagged tag: CacheTag) -> CacheRemovalResult {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return .empty
        }
        return memory.removeAll(in: bucket, tagged: tag)
    }

    func removeAll(in bucket: CacheBucketID, insertedBefore date: Date) -> CacheRemovalResult {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return .empty
        }
        return memory.removeAll(in: bucket, insertedBefore: date)
    }

    func dataInfo(bucket: CacheBucketID, key: CacheKey) -> CacheEntryInfo? {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return nil
        }
        return memory.dataInfo(bucket: bucket, key: key, now: configuration.clock.now())
    }

    func fileInfo(bucket: CacheBucketID, key: CacheKey, policy: BucketPolicy) throws -> CacheEntryInfo? {
        try requireFileStorage(policy)
        return nil
    }

    func data(bucket: CacheBucketID, key: CacheKey) -> CachedData? {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return nil
        }
        return memory.data(bucket: bucket, key: key, accessedAt: configuration.clock.now())
    }

    func setData(_ data: Data, bucket: CacheBucketID, key: CacheKey, options: CacheEntryOptions) throws {
        guard let policy = bucketPolicies[bucket] else {
            throw CacheError.unknownBucket(bucket)
        }

        switch policy.storage {
        case .memoryOnly:
            try memory.setData(
                data,
                bucket: bucket,
                key: key,
                policy: policy,
                tags: options.tags,
                storedAt: configuration.clock.now()
            )
        case .diskBacked:
            throw CacheError.storageFailure(Self.unimplementedStorageMessage)
        }
    }

    func leaseFile(bucket: CacheBucketID, key: CacheKey, policy: BucketPolicy) throws -> CachedFileLease? {
        try requireFileStorage(policy)
        return nil
    }

    func setFile(
        at sourceURL: URL,
        bucket: CacheBucketID,
        key: CacheKey,
        options: CacheFileOptions,
        policy: BucketPolicy
    ) throws {
        try requireFileStorage(policy)
        throw CacheError.storageFailure(Self.unimplementedStorageMessage)
    }

    func remove(bucket: CacheBucketID, key: CacheKey) -> CacheRemovalResult {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return .empty
        }
        return memory.remove(bucket: bucket, key: key)
    }

    private func requireFileStorage(_ policy: BucketPolicy) throws {
        if policy.storage == .memoryOnly {
            throw CacheError.unsupportedFileStorage(storageMode: policy.storage)
        }
    }

    private func emptyUsage(bucket: CacheBucketID) -> BucketUsage {
        BucketUsage(
            bucket: bucket,
            totalSize: .zero,
            diskSize: .zero,
            memorySize: .zero,
            entryCount: 0
        )
    }
}
