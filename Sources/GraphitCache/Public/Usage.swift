import Foundation

/// A snapshot of cache usage across the configured buckets in a store.
///
/// Usage snapshots are intentionally simple: total size, disk size, memory size, entry count, and
/// per-bucket usage. They do not include grouped usage or data/file/expired breakdowns in v1.
public struct CacheUsage: Sendable {
    /// The total size of all entries included in the snapshot.
    public let totalSize: ByteCount

    /// The disk-backed size included in the snapshot.
    public let diskSize: ByteCount

    /// The memory-only size included in the snapshot.
    public let memorySize: ByteCount

    /// The number of entries included in the snapshot.
    public let entryCount: Int

    /// Per-bucket usage snapshots for configured buckets.
    public let buckets: [BucketUsage]

    init(
        totalSize: ByteCount,
        diskSize: ByteCount,
        memorySize: ByteCount,
        entryCount: Int,
        buckets: [BucketUsage]
    ) {
        self.totalSize = totalSize
        self.diskSize = diskSize
        self.memorySize = memorySize
        self.entryCount = entryCount
        self.buckets = buckets
    }
}

/// A snapshot of cache usage for one bucket.
///
/// Memory-only buckets report `diskSize == .zero`; disk-backed buckets report
/// `memorySize == .zero` in v1 because there is no hot memory tier.
public struct BucketUsage: Sendable {
    /// The bucket represented by the snapshot.
    public let bucket: CacheBucketID

    /// The total size of entries included in the snapshot.
    public let totalSize: ByteCount

    /// The disk-backed size included in the snapshot.
    public let diskSize: ByteCount

    /// The memory-only size included in the snapshot.
    public let memorySize: ByteCount

    /// The number of entries included in the snapshot.
    public let entryCount: Int

    init(
        bucket: CacheBucketID,
        totalSize: ByteCount,
        diskSize: ByteCount,
        memorySize: ByteCount,
        entryCount: Int
    ) {
        self.bucket = bucket
        self.totalSize = totalSize
        self.diskSize = diskSize
        self.memorySize = memorySize
        self.entryCount = entryCount
    }
}
