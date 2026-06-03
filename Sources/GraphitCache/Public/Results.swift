import Foundation

/// The result of a removal operation.
public struct CacheRemovalResult: Sendable, Hashable {
    /// The number of entries removed.
    public let removedEntries: Int

    /// The number of bytes removed.
    public let removedBytes: ByteCount

    /// The number of leased file entries skipped by a broad removal operation.
    public let skippedLeasedEntries: Int

    /// Creates a removal result.
    ///
    /// - Parameters:
    ///   - removedEntries: The number of entries removed.
    ///   - removedBytes: The number of bytes removed.
    ///   - skippedLeasedEntries: The number of leased file entries skipped by a broad removal operation.
    public init(
        removedEntries: Int = 0,
        removedBytes: ByteCount = .zero,
        skippedLeasedEntries: Int = 0
    ) {
        self.removedEntries = removedEntries
        self.removedBytes = removedBytes
        self.skippedLeasedEntries = skippedLeasedEntries
    }

    /// A removal result representing no removed entries and no skipped leases.
    public static let empty = CacheRemovalResult()
}

/// The result of an explicit cleanup operation.
public struct CacheCleanupResult: Sendable, Hashable {
    /// The number of expired entries removed.
    public let removedExpiredEntries: Int

    /// The number of expired bytes removed.
    public let removedExpiredBytes: ByteCount

    /// The number of orphaned files removed.
    public let removedOrphanedFiles: Int

    /// The number of orphaned bytes removed.
    public let removedOrphanedBytes: ByteCount

    /// The number of entries evicted to satisfy capacity.
    public let evictedEntries: Int

    /// The number of bytes evicted to satisfy capacity.
    public let evictedBytes: ByteCount

    /// The number of leased file entries skipped by cleanup.
    public let skippedLeasedEntries: Int

    /// Creates a cleanup result.
    ///
    /// - Parameters:
    ///   - removedExpiredEntries: The number of expired entries removed.
    ///   - removedExpiredBytes: The number of expired bytes removed.
    ///   - removedOrphanedFiles: The number of orphaned files removed.
    ///   - removedOrphanedBytes: The number of orphaned bytes removed.
    ///   - evictedEntries: The number of entries evicted to satisfy capacity.
    ///   - evictedBytes: The number of bytes evicted to satisfy capacity.
    ///   - skippedLeasedEntries: The number of leased file entries skipped by cleanup.
    public init(
        removedExpiredEntries: Int = 0,
        removedExpiredBytes: ByteCount = .zero,
        removedOrphanedFiles: Int = 0,
        removedOrphanedBytes: ByteCount = .zero,
        evictedEntries: Int = 0,
        evictedBytes: ByteCount = .zero,
        skippedLeasedEntries: Int = 0
    ) {
        self.removedExpiredEntries = removedExpiredEntries
        self.removedExpiredBytes = removedExpiredBytes
        self.removedOrphanedFiles = removedOrphanedFiles
        self.removedOrphanedBytes = removedOrphanedBytes
        self.evictedEntries = evictedEntries
        self.evictedBytes = evictedBytes
        self.skippedLeasedEntries = skippedLeasedEntries
    }

    /// A cleanup result representing no cleanup work performed.
    public static let empty = CacheCleanupResult()
}
