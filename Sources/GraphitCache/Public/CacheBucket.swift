import Foundation

/// A handle for operations in a configured cache bucket.
///
/// A bucket handle is a lightweight value that retains the store internals. It is not isolated to
/// the main actor and can be passed across concurrency domains. Async operations preserve
/// cancellation semantics. File URLs are exposed only through retained leases.
public struct CacheBucket: Sendable {
    /// The identifier of the bucket.
    public let id: CacheBucketID

    /// The validated policy snapshot for the bucket.
    public let policy: BucketPolicy

    let engine: CacheStoreEngine

    init(id: CacheBucketID, policy: BucketPolicy, engine: CacheStoreEngine) {
        self.id = id
        self.policy = policy
        self.engine = engine
    }

    /// Returns metadata for a data entry without reading payload bytes.
    ///
    /// Metadata reads do not update last-access metadata or sliding expiration. Missing, expired,
    /// or current file-backed entries return `nil`.
    ///
    /// - Parameter key: The key to inspect.
    /// - Returns: Entry metadata when a current data entry exists, or `nil` when absent.
    /// - Throws: A `CacheError` if the lookup fails. Cancellation is preserved.
    public func dataInfo(for key: CacheKey) async throws -> CacheEntryInfo? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.dataInfo(bucket: id, key: key)
    }

    /// Returns metadata for a file entry without leasing or reading payload bytes.
    ///
    /// Metadata reads do not update last-access metadata or sliding expiration. Missing, expired,
    /// or current data-backed entries return `nil`.
    ///
    /// - Parameter key: The key to inspect.
    /// - Returns: Entry metadata when a current file entry exists, or `nil` when absent.
    /// - Throws: `CacheError.unsupportedFileStorage` for memory-only buckets, or another
    ///   `CacheError` if the lookup fails. Cancellation is preserved.
    public func fileInfo(for key: CacheKey) async throws -> CacheEntryInfo? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.fileInfo(bucket: id, key: key, policy: policy)
    }

    /// Returns cached data for a key.
    ///
    /// Payload reads update last-access metadata and sliding expiration. Missing, expired, or
    /// current file-backed entries return `nil`.
    ///
    /// - Parameter key: The key to read.
    /// - Returns: Cached data when a current data entry exists, or `nil` when absent.
    /// - Throws: A `CacheError` if the read fails. Cancellation is preserved.
    public func data(_ key: CacheKey) async throws -> CachedData? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.data(bucket: id, key: key)
    }

    /// Stores data for a key.
    ///
    /// GraphitCache validates input, enforces capacity, and stores bytes according to the bucket
    /// policy. A data write may replace an existing data or file entry for the same key, unless
    /// the existing file entry is leased.
    ///
    /// - Parameters:
    ///   - data: The data bytes to store.
    ///   - key: The key to associate with the data.
    ///   - options: Tags and other data-entry options.
    /// - Throws: A `CacheError` if validation, capacity enforcement, storage, or lease checks fail.
    ///   Cancellation is preserved and pre-commit cancellation does not leave a committed entry.
    public func setData(_ data: Data, for key: CacheKey, options: CacheEntryOptions = .init()) async throws {
        try CacheValidation.validateKeyForInput(key)
        try CacheValidation.validateEntryOptionsForInput(options)
        try await engine.setData(data, bucket: id, key: key, options: options)
    }

    /// Returns a retained lease for a cached file.
    ///
    /// The caller must retain the returned lease for as long as the file URL is used. Missing,
    /// expired, current data-backed, or externally missing file payloads return `nil`.
    ///
    /// - Parameter key: The key to lease.
    /// - Returns: A file lease when a current file entry exists, or `nil` when absent.
    /// - Throws: `CacheError.unsupportedFileStorage` for memory-only buckets, or another
    ///   `CacheError` if leasing fails. Cancellation is preserved.
    public func leaseFile(_ key: CacheKey) async throws -> CachedFileLease? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.leaseFile(bucket: id, key: key, policy: policy)
    }

    /// Imports a local file into the cache.
    ///
    /// The source file remains caller-owned after import. GraphitCache copies the file into
    /// cache-managed storage. A file write may replace an existing data or file entry for the same
    /// key, unless the existing file entry is leased.
    ///
    /// - Parameters:
    ///   - sourceURL: The local file URL to import.
    ///   - key: The key to associate with the file.
    ///   - options: Tags and file path extension options.
    /// - Throws: `CacheError.unsupportedFileStorage` for memory-only buckets, or another
    ///   `CacheError` if validation, capacity enforcement, storage, or lease checks fail.
    ///   Cancellation is preserved and pre-commit cancellation does not leave a committed entry.
    public func setFile(at sourceURL: URL, for key: CacheKey, options: CacheFileOptions = .init()) async throws {
        try CacheValidation.validateKeyForInput(key)
        if policy.storage != .memoryOnly {
            try CacheValidation.validateFileOptionsForInput(options)
        }
        try await engine.setFile(at: sourceURL, bucket: id, key: key, options: options, policy: policy)
    }

    /// Removes the entry for a key.
    ///
    /// Exact-key removal throws if the current file entry is leased.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: A removal result describing the removed entry.
    /// - Throws: A `CacheError` if removal fails or the current file is leased. Cancellation is preserved.
    public func remove(_ key: CacheKey) async throws -> CacheRemovalResult {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.remove(bucket: id, key: key)
    }

    /// Removes all entries in this bucket.
    ///
    /// Leased file entries are skipped and counted instead of being deleted.
    ///
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails. Cancellation is preserved.
    public func removeAll() async throws -> CacheRemovalResult {
        try await engine.removeAll(in: id)
    }

    /// Removes all entries in this bucket that have a specific tag.
    ///
    /// Leased file entries are skipped and counted instead of being deleted.
    ///
    /// - Parameter tag: The tag whose entries should be removed.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails. Cancellation is preserved.
    public func removeAll(tagged tag: CacheTag) async throws -> CacheRemovalResult {
        try CacheValidation.validateTagForInput(tag)
        return try await engine.removeAll(in: id, tagged: tag)
    }

    /// Removes all entries in this bucket stored before a date.
    ///
    /// The comparison is strict: entries match when `storedAt < date`. Leased file entries are
    /// skipped and counted instead of being deleted.
    ///
    /// - Parameter date: The exclusive stored-at cutoff date.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails. Cancellation is preserved.
    public func removeAll(insertedBefore date: Date) async throws -> CacheRemovalResult {
        try await engine.removeAll(in: id, insertedBefore: date)
    }

    /// Returns a usage snapshot for this bucket.
    ///
    /// Usage is based on cache metadata and reports simple size/count values only.
    ///
    /// - Returns: A bucket usage snapshot.
    /// - Throws: A `CacheError` if usage cannot be read. Cancellation is preserved.
    public func usage() async throws -> BucketUsage {
        try await engine.usage(bucket: id, policy: policy)
    }

    /// Performs explicit maintenance for this bucket.
    ///
    /// Bucket cleanup may remove expired entries, bucket-scoped disk orphans, and entries evicted
    /// to satisfy capacity. It does not remove store-level temporary files.
    ///
    /// - Returns: A cleanup result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if cleanup fails. Cancellation is preserved; completed removals
    ///   remain removed.
    public func cleanup() async throws -> CacheCleanupResult {
        try await engine.cleanup(bucket: id)
    }
}
