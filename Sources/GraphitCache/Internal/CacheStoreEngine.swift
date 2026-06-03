import Foundation

actor CacheStoreEngine {
    private static let unimplementedStorageMessage = "Cache storage behavior is not implemented in the bootstrap API shell."

    private let configuration: CacheStoreConfiguration

    init(configuration: CacheStoreConfiguration) {
        self.configuration = configuration
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
        .empty
    }

    func removeAll(in bucket: CacheBucketID) -> CacheRemovalResult {
        .empty
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
        nil
    }

    func fileInfo(bucket: CacheBucketID, key: CacheKey, policy: BucketPolicy) throws -> CacheEntryInfo? {
        try requireFileStorage(policy)
        return nil
    }

    func data(bucket: CacheBucketID, key: CacheKey) -> CachedData? {
        nil
    }

    func setData(_ data: Data, bucket: CacheBucketID, key: CacheKey, options: CacheEntryOptions) throws {
        throw CacheError.storageFailure(Self.unimplementedStorageMessage)
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
        .empty
    }

    private func requireFileStorage(_ policy: BucketPolicy) throws {
        if policy.storage == .memoryOnly {
            throw CacheError.unsupportedFileStorage(storageMode: policy.storage)
        }
    }
}
