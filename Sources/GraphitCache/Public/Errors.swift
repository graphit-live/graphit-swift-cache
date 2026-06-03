import Foundation

/// The capacity constraint that prevented a cache write from succeeding.
public enum CacheCapacityConstraint: Sendable, Hashable {
    /// The bucket could not free enough bytes for the requested write.
    case totalSize(requiredBytes: ByteCount, availableEvictableBytes: ByteCount)

    /// The bucket could not evict enough entries for the requested write.
    case itemCount(requiredEvictions: Int, availableEvictableEntries: Int)
}

/// Errors reported by GraphitCache public APIs.
public enum CacheError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The cache configuration is invalid.
    case invalidConfiguration(String)

    /// A runtime input value is invalid.
    case invalidInput(String)

    /// The requested bucket is not configured for the active store.
    case unknownBucket(CacheBucketID)

    /// The store configuration contains the same bucket more than once.
    case duplicateBucket(CacheBucketID)

    /// The requested file operation is not supported by the bucket storage mode.
    case unsupportedFileStorage(storageMode: CacheStorageMode)

    /// The item exceeds its configured maximum item size.
    case itemTooLarge(size: ByteCount, limit: ByteCount)

    /// The write cannot satisfy the bucket capacity constraints even after eligible eviction.
    case capacityCannotBeSatisfied(bucket: CacheBucketID, constraint: CacheCapacityConstraint)

    /// The source file for an import operation does not exist.
    case sourceFileNotFound(URL)

    /// The source file for an import operation cannot be read.
    case sourceFileUnreadable(URL)

    /// The existing cached file is leased and cannot be removed or replaced yet.
    case fileIsLeased(bucket: CacheBucketID, key: CacheKey)

    /// A storage operation failed.
    case storageFailure(String)

    /// GraphitCache detected an internal consistency problem.
    case internalInconsistency(String)

    /// A human-readable description of the error.
    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            "Invalid cache configuration: \(message)"
        case .invalidInput(let message):
            "Invalid cache input: \(message)"
        case .unknownBucket(let bucket):
            "Unknown cache bucket: \(bucket.rawValue)"
        case .duplicateBucket(let bucket):
            "Duplicate cache bucket: \(bucket.rawValue)"
        case .unsupportedFileStorage(let storageMode):
            "File storage is not supported for storage mode: \(storageMode)"
        case .itemTooLarge(let size, let limit):
            "Cache item size \(size.bytes) bytes exceeds limit \(limit.bytes) bytes"
        case .capacityCannotBeSatisfied(let bucket, let constraint):
            "Capacity cannot be satisfied for bucket \(bucket.rawValue): \(describe(constraint))"
        case .sourceFileNotFound(let url):
            "Source file was not found: \(url.path)"
        case .sourceFileUnreadable(let url):
            "Source file is unreadable: \(url.path)"
        case .fileIsLeased(let bucket, let key):
            "Cached file is leased for bucket \(bucket.rawValue), key \(key.rawValue)"
        case .storageFailure(let message):
            "Cache storage failure: \(message)"
        case .internalInconsistency(let message):
            "Cache internal inconsistency: \(message)"
        }
    }
}

private func describe(_ constraint: CacheCapacityConstraint) -> String {
    switch constraint {
    case .totalSize(let requiredBytes, let availableEvictableBytes):
        "requires \(requiredBytes.bytes) bytes; \(availableEvictableBytes.bytes) bytes are evictable"
    case .itemCount(let requiredEvictions, let availableEvictableEntries):
        "requires \(requiredEvictions) evictions; \(availableEvictableEntries) entries are evictable"
    }
}
