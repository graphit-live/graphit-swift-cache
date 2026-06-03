import Foundation

/// The top-level cache object that owns configured buckets and storage resources.
///
/// `CacheStore` is not isolated to the main actor. It is safe to pass across concurrency domains.
/// Async operations preserve cancellation semantics. When disk-backed buckets are configured,
/// initialization performs bounded local filesystem and SQLite setup. V1 expects one active
/// disk-backed store per root directory because file leases are coordinated within a store.
public final class CacheStore: Sendable {
    /// The immutable configuration snapshot used to create the store.
    public let configuration: CacheStoreConfiguration

    private let engine: CacheStoreEngine
    private let bucketPolicies: [CacheBucketID: BucketPolicy]

    /// Creates a cache store from a configuration.
    ///
    /// - Parameter configuration: The configuration used to create the store.
    /// - Throws: A `CacheError` if configuration validation fails, or if disk-backed filesystem
    ///   or SQLite setup cannot be completed.
    public init(configuration: CacheStoreConfiguration) throws {
        try CacheValidation.validateConfiguration(configuration)

        self.configuration = configuration

        var bucketPolicies: [CacheBucketID: BucketPolicy] = [:]
        for bucket in configuration.buckets {
            bucketPolicies[bucket.id] = bucket.policy
        }
        self.bucketPolicies = bucketPolicies
        self.engine = try CacheStoreEngine(configuration: configuration)
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
    /// Usage is based on cache metadata. It reports simple total and per-bucket size/count values,
    /// not grouped usage or data/file breakdowns.
    ///
    /// - Returns: A usage snapshot.
    /// - Throws: A `CacheError` if usage cannot be read. Cancellation is preserved.
    public func usage() async throws -> CacheUsage {
        try await engine.usage()
    }

    /// Performs explicit cache maintenance.
    ///
    /// Store cleanup may remove expired entries, store-level temporary files, disk orphans, and
    /// entries evicted to satisfy capacity. Cleanup is not run automatically at startup.
    ///
    /// - Returns: A cleanup result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if cleanup fails. Cancellation is preserved; completed removals
    ///   remain removed.
    public func cleanup() async throws -> CacheCleanupResult {
        try await engine.cleanup()
    }

    /// Removes all entries managed by the store.
    ///
    /// Leased file entries are skipped and counted instead of being deleted.
    ///
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails. Cancellation is preserved.
    public func removeAll() async throws -> CacheRemovalResult {
        try await engine.removeAll()
    }

    /// Removes all entries in a bucket under the store root.
    ///
    /// This operation can target valid old or unconfigured bucket IDs under the store root for
    /// explicit migration cleanup. Leased file entries are skipped and counted.
    ///
    /// - Parameter bucket: The bucket identifier to remove.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if the bucket ID is invalid or removal fails. Cancellation is preserved.
    public func removeAll(in bucket: CacheBucketID) async throws -> CacheRemovalResult {
        try CacheValidation.validateBucketIDForInput(bucket)
        return try await engine.removeAll(in: bucket)
    }

    /// Removes all entries tagged with a specific tag.
    ///
    /// Leased file entries are skipped and counted.
    ///
    /// - Parameter tag: The tag whose entries should be removed.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails. Cancellation is preserved.
    public func removeAll(tagged tag: CacheTag) async throws -> CacheRemovalResult {
        try CacheValidation.validateTagForInput(tag)
        return try await engine.removeAll(tagged: tag)
    }

    /// Removes all entries stored before a date.
    ///
    /// The comparison is strict: entries match when `storedAt < date`. Leased file entries are
    /// skipped and counted.
    ///
    /// - Parameter date: The exclusive stored-at cutoff date.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails. Cancellation is preserved.
    public func removeAll(insertedBefore date: Date) async throws -> CacheRemovalResult {
        try await engine.removeAll(insertedBefore: date)
    }
}
