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
        return CacheUsage(
            totalSize: .zero,
            diskSize: .zero,
            memorySize: .zero,
            entryCount: 0,
            buckets: bucketUsages
        )
    }

    func usage(bucket: CacheBucketID, policy: BucketPolicy) -> BucketUsage {
        BucketUsage(
            bucket: bucket,
            totalSize: .zero,
            diskSize: .zero,
            memorySize: .zero,
            entryCount: 0
        )
    }

    func cleanup() -> CacheCleanupResult {
        .empty
    }

    func cleanup(bucket: CacheBucketID) -> CacheCleanupResult {
        .empty
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
        .empty
    }

    func removeAll(insertedBefore date: Date) -> CacheRemovalResult {
        .empty
    }

    func removeAll(in bucket: CacheBucketID, tagged tag: CacheTag) -> CacheRemovalResult {
        .empty
    }

    func removeAll(in bucket: CacheBucketID, insertedBefore date: Date) -> CacheRemovalResult {
        .empty
    }

    func dataInfo(bucket: CacheBucketID, key: CacheKey) -> CacheEntryInfo? {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return nil
        }
        return memory.dataInfo(bucket: bucket, key: key)
    }

    func fileInfo(bucket: CacheBucketID, key: CacheKey, policy: BucketPolicy) throws -> CacheEntryInfo? {
        try requireFileStorage(policy)
        return nil
    }

    func data(bucket: CacheBucketID, key: CacheKey) -> CachedData? {
        guard bucketPolicies[bucket]?.storage == .memoryOnly else {
            return nil
        }
        return memory.data(bucket: bucket, key: key)
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
}
