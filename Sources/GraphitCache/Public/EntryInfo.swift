import Foundation

/// Metadata describing a cached entry.
///
/// The payload shape is implied by the API that returned the info, such as `dataInfo(for:)`,
/// `fileInfo(for:)`, `data(_:)`, or `leaseFile(_:)`.
public struct CacheEntryInfo: Hashable, Sendable {
    /// The bucket that owns the entry.
    public let bucket: CacheBucketID

    /// The entry key within the bucket.
    public let key: CacheKey

    /// App-defined grouping tags associated with the entry.
    public let tags: Set<CacheTag>

    /// The authoritative size of the cached payload.
    public let size: ByteCount

    /// The date the entry was stored or last replaced.
    public let storedAt: Date

    /// The date the entry payload was last successfully accessed, if any.
    public let lastAccessedAt: Date?

    /// The date the entry expires, or `nil` when it does not expire by time.
    public let expiresAt: Date?

    /// Creates cache entry metadata.
    ///
    /// - Parameters:
    ///   - bucket: The bucket that owns the entry.
    ///   - key: The entry key within the bucket.
    ///   - size: The authoritative size of the cached payload.
    ///   - storedAt: The date the entry was stored or last replaced.
    ///   - tags: App-defined grouping tags associated with the entry.
    ///   - lastAccessedAt: The date the entry payload was last successfully accessed, if any.
    ///   - expiresAt: The date the entry expires, or `nil` when it does not expire by time.
    public init(
        bucket: CacheBucketID,
        key: CacheKey,
        size: ByteCount,
        storedAt: Date,
        tags: Set<CacheTag> = [],
        lastAccessedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.bucket = bucket
        self.key = key
        self.tags = tags
        self.size = size
        self.storedAt = storedAt
        self.lastAccessedAt = lastAccessedAt
        self.expiresAt = expiresAt
    }

    /// Returns whether the entry is expired at the supplied date.
    ///
    /// - Parameter date: The date to compare against the entry expiration date.
    /// - Returns: `true` when `expiresAt` is not `nil` and `date` is at or after it.
    public func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return date >= expiresAt
    }
}
