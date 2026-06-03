import Foundation

/// A handle for operations in a configured cache bucket.
///
/// A bucket handle is a lightweight value that retains the store internals. It is not isolated to
/// the main actor and can be passed across concurrency domains.
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
    /// Metadata reads do not update last-access metadata or sliding expiration.
    ///
    /// - Parameter key: The key to inspect.
    /// - Returns: Entry metadata when a current data entry exists, or `nil` when absent.
    /// - Throws: A `CacheError` if the lookup fails.
    public func dataInfo(for key: CacheKey) async throws -> CacheEntryInfo? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.dataInfo(bucket: id, key: key)
    }

    /// Returns metadata for a file entry without leasing or reading payload bytes.
    ///
    /// Metadata reads do not update last-access metadata or sliding expiration.
    ///
    /// - Parameter key: The key to inspect.
    /// - Returns: Entry metadata when a current file entry exists, or `nil` when absent.
    /// - Throws: A `CacheError` if the lookup fails.
    public func fileInfo(for key: CacheKey) async throws -> CacheEntryInfo? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.fileInfo(bucket: id, key: key, policy: policy)
    }

    /// Returns cached data for a key.
    ///
    /// Payload reads update access metadata.
    ///
    /// - Parameter key: The key to read.
    /// - Returns: Cached data when a current data entry exists, or `nil` when absent.
    /// - Throws: A `CacheError` if the read fails.
    public func data(_ key: CacheKey) async throws -> CachedData? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.data(bucket: id, key: key)
    }

    /// Stores data for a key.
    ///
    /// GraphitCache validates input, enforces capacity, and stores bytes according to the bucket policy.
    ///
    /// - Parameters:
    ///   - data: The data bytes to store.
    ///   - key: The key to associate with the data.
    ///   - options: Tags and other data-entry options.
    /// - Throws: A `CacheError` if the write fails.
    public func setData(_ data: Data, for key: CacheKey, options: CacheEntryOptions = .init()) async throws {
        try CacheValidation.validateKeyForInput(key)
        try CacheValidation.validateEntryOptionsForInput(options)
        try await engine.setData(data, bucket: id, key: key, options: options)
    }

    /// Returns a retained lease for a cached file.
    ///
    /// The caller must retain the returned lease for as long as the file URL is used.
    ///
    /// - Parameter key: The key to lease.
    /// - Returns: A file lease when a current file entry exists, or `nil` when absent.
    /// - Throws: A `CacheError` if leasing fails or file storage is unsupported.
    public func leaseFile(_ key: CacheKey) async throws -> CachedFileLease? {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.leaseFile(bucket: id, key: key, policy: policy)
    }

    /// Imports a local file into the cache.
    ///
    /// The source file remains caller-owned after import. GraphitCache copies the file into cache-managed storage.
    ///
    /// - Parameters:
    ///   - sourceURL: The local file URL to import.
    ///   - key: The key to associate with the file.
    ///   - options: Tags and file path extension options.
    /// - Throws: A `CacheError` if the import fails or file storage is unsupported.
    public func setFile(at sourceURL: URL, for key: CacheKey, options: CacheFileOptions = .init()) async throws {
        try CacheValidation.validateKeyForInput(key)
        if policy.storage != .memoryOnly {
            try CacheValidation.validateFileOptionsForInput(options)
        }
        try await engine.setFile(at: sourceURL, bucket: id, key: key, options: options, policy: policy)
    }

    /// Removes the entry for a key.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: A removal result describing the removed entry.
    /// - Throws: A `CacheError` if removal fails or the current file is leased.
    public func remove(_ key: CacheKey) async throws -> CacheRemovalResult {
        try CacheValidation.validateKeyForInput(key)
        return try await engine.remove(bucket: id, key: key)
    }

    /// Removes all entries in this bucket.
    ///
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails.
    public func removeAll() async throws -> CacheRemovalResult {
        try await engine.removeAll(in: id)
    }

    /// Removes all entries in this bucket that have a specific tag.
    ///
    /// - Parameter tag: The tag whose entries should be removed.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails.
    public func removeAll(tagged tag: CacheTag) async throws -> CacheRemovalResult {
        try CacheValidation.validateTagForInput(tag)
        return try await engine.removeAll(in: id, tagged: tag)
    }

    /// Removes all entries in this bucket stored before a date.
    ///
    /// The comparison is strict: entries match when `storedAt < date`.
    ///
    /// - Parameter date: The exclusive stored-at cutoff date.
    /// - Returns: A removal result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if removal fails.
    public func removeAll(insertedBefore date: Date) async throws -> CacheRemovalResult {
        try await engine.removeAll(in: id, insertedBefore: date)
    }

    /// Returns a usage snapshot for this bucket.
    ///
    /// - Returns: A bucket usage snapshot.
    /// - Throws: A `CacheError` if usage cannot be read.
    public func usage() async throws -> BucketUsage {
        try await engine.usage(bucket: id, policy: policy)
    }

    /// Performs explicit maintenance for this bucket.
    ///
    /// - Returns: A cleanup result describing removed entries and skipped leases.
    /// - Throws: A `CacheError` if cleanup fails.
    public func cleanup() async throws -> CacheCleanupResult {
        try await engine.cleanup(bucket: id)
    }
}
