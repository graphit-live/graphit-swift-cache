import Foundation

/// The storage backend used by a cache bucket.
public enum CacheStorageMode: Sendable, Hashable {
    /// Stores `Data` entries only in process-local memory.
    case memoryOnly

    /// Stores `Data` and file entries on disk with persistent metadata.
    case diskBacked
}

/// The bucket-level expiration policy for entries written to a cache bucket.
public enum CacheExpirationPolicy: Sendable, Hashable {
    /// Entries do not expire by time.
    case never

    /// Entries expire a fixed duration after storage or replacement.
    case fixed(Duration)

    /// Entries expire after a duration that extends on each successful payload read.
    case sliding(Duration)
}

/// The strategy used when GraphitCache must evict entries to satisfy bucket capacity.
public enum CacheEvictionPolicy: Sendable, Hashable {
    /// Evicts the least recently used entries first.
    case leastRecentlyUsed

    /// Evicts the oldest inserted entries first.
    case oldestInsertedFirst
}

/// The storage, expiration, and eviction policy for a cache bucket.
public struct BucketPolicy: Sendable {
    /// The storage backend used by the bucket.
    public var storage: CacheStorageMode

    /// The required maximum total size for entries in the bucket.
    public var maxTotalSize: ByteCount

    /// An optional maximum size for a single item in the bucket.
    public var maxItemSize: ByteCount?

    /// An optional maximum number of entries allowed in the bucket.
    public var maxItemCount: Int?

    /// The expiration policy applied to entries written to the bucket.
    public var expiration: CacheExpirationPolicy

    /// The eviction policy used when capacity must be reclaimed.
    public var eviction: CacheEvictionPolicy

    /// Creates a bucket policy.
    ///
    /// - Parameters:
    ///   - storage: The storage backend used by the bucket.
    ///   - maxTotalSize: The required maximum total size for entries in the bucket.
    ///   - maxItemSize: An optional maximum size for a single item in the bucket.
    ///   - maxItemCount: An optional maximum number of entries allowed in the bucket.
    ///   - expiration: The expiration policy applied to new entries.
    ///   - eviction: The eviction policy used when capacity must be reclaimed.
    public init(
        storage: CacheStorageMode,
        maxTotalSize: ByteCount,
        maxItemSize: ByteCount? = nil,
        maxItemCount: Int? = nil,
        expiration: CacheExpirationPolicy = .never,
        eviction: CacheEvictionPolicy = .leastRecentlyUsed
    ) {
        self.storage = storage
        self.maxTotalSize = maxTotalSize
        self.maxItemSize = maxItemSize
        self.maxItemCount = maxItemCount
        self.expiration = expiration
        self.eviction = eviction
    }
}

public extension BucketPolicy {
    /// Creates a memory-only bucket policy.
    ///
    /// - Parameters:
    ///   - maxTotalSize: The required maximum total size for entries in the bucket.
    ///   - maxItemSize: An optional maximum size for a single item in the bucket.
    ///   - maxItemCount: An optional maximum number of entries allowed in the bucket.
    ///   - expiration: The expiration policy applied to new entries.
    ///   - eviction: The eviction policy used when capacity must be reclaimed.
    /// - Returns: A memory-only bucket policy.
    static func memoryOnly(
        maxTotalSize: ByteCount,
        maxItemSize: ByteCount? = nil,
        maxItemCount: Int? = nil,
        expiration: CacheExpirationPolicy = .never,
        eviction: CacheEvictionPolicy = .leastRecentlyUsed
    ) -> BucketPolicy {
        BucketPolicy(
            storage: .memoryOnly,
            maxTotalSize: maxTotalSize,
            maxItemSize: maxItemSize,
            maxItemCount: maxItemCount,
            expiration: expiration,
            eviction: eviction
        )
    }

    /// Creates a disk-backed bucket policy.
    ///
    /// - Parameters:
    ///   - maxTotalSize: The required maximum total size for entries in the bucket.
    ///   - maxItemSize: An optional maximum size for a single item in the bucket.
    ///   - maxItemCount: An optional maximum number of entries allowed in the bucket.
    ///   - expiration: The expiration policy applied to new entries.
    ///   - eviction: The eviction policy used when capacity must be reclaimed.
    /// - Returns: A disk-backed bucket policy.
    static func diskBacked(
        maxTotalSize: ByteCount,
        maxItemSize: ByteCount? = nil,
        maxItemCount: Int? = nil,
        expiration: CacheExpirationPolicy = .never,
        eviction: CacheEvictionPolicy = .leastRecentlyUsed
    ) -> BucketPolicy {
        BucketPolicy(
            storage: .diskBacked,
            maxTotalSize: maxTotalSize,
            maxItemSize: maxItemSize,
            maxItemCount: maxItemCount,
            expiration: expiration,
            eviction: eviction
        )
    }
}
