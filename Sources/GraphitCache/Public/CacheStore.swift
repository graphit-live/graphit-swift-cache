import Foundation

/// The top-level cache object that owns configured buckets and storage resources.
///
/// `CacheStore` is not isolated to the main actor. It is safe to pass across concurrency domains.
public final class CacheStore: Sendable {
    /// The immutable configuration snapshot used to create the store.
    public let configuration: CacheStoreConfiguration

    private let engine: CacheStoreEngine
    private let bucketPolicies: [CacheBucketID: BucketPolicy]

    /// Creates a cache store from a configuration.
    ///
    /// - Parameter configuration: The configuration used to create the store.
    /// - Throws: A `CacheError` if configuration or storage setup fails.
    public init(configuration: CacheStoreConfiguration) throws {
        self.configuration = configuration
        self.engine = CacheStoreEngine(configuration: configuration)

        var bucketPolicies: [CacheBucketID: BucketPolicy] = [:]
        for bucket in configuration.buckets {
            bucketPolicies[bucket.id] = bucket.policy
        }
        self.bucketPolicies = bucketPolicies
    }

    /// Returns a handle for a configured active bucket.
    ///
    /// - Parameter id: The configured bucket identifier.
    /// - Returns: A bucket handle that retains the store internals.
    /// - Throws: `CacheError.unknownBucket` if the bucket is not configured for this store.
    public func bucket(_ id: CacheBucketID) throws -> CacheBucket {
        guard let policy = bucketPolicies[id] else {
            throw CacheError.unknownBucket(id)
        }
        return CacheBucket(id: id, policy: policy, engine: engine)
    }

    /// Returns the active bucket identifiers configured for this store.
    ///
    /// - Returns: The configured bucket identifiers in configuration order.
    public func configuredBuckets() -> [CacheBucketID] {
        configuration.buckets.map(\.id)
    }

    /// Returns a snapshot of cache usage for the configured buckets.
    ///
    /// - Returns: A usage snapshot.
    /// - Throws: A `CacheError` if usage cannot be read.
    public func usage() async throws -> CacheUsage {
        await engine.usage()
    }

    /// Performs explicit cache maintenance.
    ///
    /// - Returns: A cleanup result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if cleanup fails.
    public func cleanup() async throws -> CacheCleanupResult {
        await engine.cleanup()
    }

    /// Removes all entries managed by the store.
    ///
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails.
    public func removeAll() async throws -> CacheRemovalResult {
        await engine.removeAll()
    }

    /// Removes all entries in a bucket under the store root.
    ///
    /// This operation can target old or unconfigured bucket IDs once disk-backed cleanup is
    /// implemented.
    ///
    /// - Parameter bucket: The bucket identifier to remove.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if the bucket ID is invalid or removal fails.
    public func removeAll(in bucket: CacheBucketID) async throws -> CacheRemovalResult {
        await engine.removeAll(in: bucket)
    }

    /// Removes all entries tagged with a specific tag.
    ///
    /// - Parameter tag: The tag whose entries should be removed.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails.
    public func removeAll(tagged tag: CacheTag) async throws -> CacheRemovalResult {
        await engine.removeAll(tagged: tag)
    }

    /// Removes all entries stored before a date.
    ///
    /// The comparison is strict: entries match when `storedAt < date`.
    ///
    /// - Parameter date: The exclusive stored-at cutoff date.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails.
    public func removeAll(insertedBefore date: Date) async throws -> CacheRemovalResult {
        await engine.removeAll(insertedBefore: date)
    }
}
