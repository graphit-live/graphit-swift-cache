# Public API: usage, results, clocks, errors

Lean v1 has no public query structs, no grouped usage report model, no data/file/expired usage breakdowns, and no event/instrumentation model. This file defines the remaining public support API.

## Usage

```swift
public struct CacheUsage: Sendable {
    public let totalSize: ByteCount
    public let diskSize: ByteCount
    public let memorySize: ByteCount
    public let entryCount: Int
    public let buckets: [BucketUsage]
}

public struct BucketUsage: Sendable {
    public let bucket: CacheBucketID
    public let totalSize: ByteCount
    public let diskSize: ByteCount
    public let memorySize: ByteCount
    public let entryCount: Int
}
```

Rules:

- memory-only `diskSize = 0`.
- disk-backed `memorySize = 0` in v1 because no hot memory tier.
- normal usage uses memory metadata or SQLite metadata, not filesystem scans.
- store usage reports configured active buckets.
- no grouping by tag/kind/content type in v1.
- no data/file/expired breakdown fields in v1.
- no public initializers are required for usage snapshots in v1; they are SDK-produced values.
- no `Hashable` conformance in v1, leaving room for future fields without encouraging equality semantics consumers may not need.

## Results

```swift
public struct CacheRemovalResult: Sendable, Hashable {
    public let removedEntries: Int
    public let removedBytes: ByteCount
    public let skippedLeasedEntries: Int

    public init(
        removedEntries: Int = 0,
        removedBytes: ByteCount = .zero,
        skippedLeasedEntries: Int = 0
    )

    public static let empty: CacheRemovalResult
}

public struct CacheCleanupResult: Sendable, Hashable {
    public let removedExpiredEntries: Int
    public let removedExpiredBytes: ByteCount
    public let removedOrphanedFiles: Int
    public let removedOrphanedBytes: ByteCount
    public let evictedEntries: Int
    public let evictedBytes: ByteCount
    public let skippedLeasedEntries: Int

    public init(
        removedExpiredEntries: Int = 0,
        removedExpiredBytes: ByteCount = .zero,
        removedOrphanedFiles: Int = 0,
        removedOrphanedBytes: ByteCount = .zero,
        evictedEntries: Int = 0,
        evictedBytes: ByteCount = .zero,
        skippedLeasedEntries: Int = 0
    )

    public static let empty: CacheCleanupResult
}
```

No protected-entry counters in v1.

## Clock

```swift
public protocol CacheClock: Sendable { func now() -> Date }
public struct SystemCacheClock: CacheClock { public init(); public func now() -> Date }
```

Tests define internal `TestCacheClock` in `Tests/GraphitCacheTests/Support`; no public testing product.

## Errors

```swift
public enum CacheCapacityConstraint: Sendable, Hashable {
    case totalSize(requiredBytes: ByteCount, availableEvictableBytes: ByteCount)
    case itemCount(requiredEvictions: Int, availableEvictableEntries: Int)
}

public enum CacheError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidConfiguration(String)
    case invalidInput(String)
    case unknownBucket(CacheBucketID)
    case duplicateBucket(CacheBucketID)
    case unsupportedFileStorage(storageMode: CacheStorageMode)
    case itemTooLarge(size: ByteCount, limit: ByteCount)
    case capacityCannotBeSatisfied(bucket: CacheBucketID, constraint: CacheCapacityConstraint)
    case sourceFileNotFound(URL)
    case sourceFileUnreadable(URL)
    case fileIsLeased(bucket: CacheBucketID, key: CacheKey)
    case storageFailure(String)
    case internalInconsistency(String)
    public var description: String { get }
}
```

No raw low-level `Error` associated values. Convert implementation errors to safe strings.

## Deferred public APIs

- `CacheUsageQuery`.
- `CacheRemovalQuery`.
- `BucketRemovalQuery`.
- `CacheCleanupQuery`.
- `CacheUsageGrouping` / `CacheUsageReport` / grouped usage API.
- data/file/expired usage detail fields.
- `CacheInstrumentation`.
- `CacheEventSink` and event structs.
