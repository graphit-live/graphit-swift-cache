import Foundation

/// The configuration for a single cache bucket.
public struct BucketConfiguration: Sendable {
    /// The stable identifier for the bucket.
    public var id: CacheBucketID

    /// The policy applied to entries in the bucket.
    public var policy: BucketPolicy

    /// Creates a bucket configuration.
    ///
    /// - Parameters:
    ///   - id: The stable identifier for the bucket.
    ///   - policy: The policy applied to entries in the bucket.
    public init(id: CacheBucketID, policy: BucketPolicy) {
        self.id = id
        self.policy = policy
    }
}

/// The configuration used to create a cache store.
public struct CacheStoreConfiguration: Sendable {
    /// The disk root used when the configuration includes disk-backed buckets.
    ///
    /// Use `nil` for all-memory configurations.
    public var rootDirectory: URL?

    /// The buckets configured for the store.
    public var buckets: [BucketConfiguration]

    /// The clock used for expiration and metadata timestamps.
    public var clock: any CacheClock

    /// Creates a cache store configuration.
    ///
    /// - Parameters:
    ///   - rootDirectory: The disk root used when the configuration includes disk-backed buckets, or `nil` for all-memory configurations.
    ///   - buckets: The buckets configured for the store.
    ///   - clock: The clock used for expiration and metadata timestamps.
    public init(
        rootDirectory: URL?,
        buckets: [BucketConfiguration],
        clock: any CacheClock = SystemCacheClock()
    ) {
        self.rootDirectory = rootDirectory
        self.buckets = buckets
        self.clock = clock
    }
}
