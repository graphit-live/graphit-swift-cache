# Public API: operations and handles

## Cached data wrapper

```swift
public struct CachedData: Sendable {
    public let data: Data
    public let info: CacheEntryInfo
    public init(data: Data, info: CacheEntryInfo)
}
```

File payloads are accessed through `CachedFileLease` only. V1 does not return unleased cache file URLs.

## File lease

```swift
public final class CachedFileLease: Sendable {
    public let url: URL
    public let info: CacheEntryInfo
    public func release()
}
```

No public initializer. Engine creates leases. Release is synchronous/idempotent. `deinit` sync safety release; no task. A leased file key cannot be removed or replaced until the lease is released.

For playback, callers must retain the lease for the playback lifetime. `defer { lease.release() }` is only correct for short synchronous file use.

## Entry info

```swift
public struct CacheEntryInfo: Hashable, Sendable {
    public let bucket: CacheBucketID
    public let key: CacheKey
    public let tags: Set<CacheTag>
    public let size: ByteCount
    public let storedAt: Date
    public let lastAccessedAt: Date?
    public let expiresAt: Date?

    public init(
        bucket: CacheBucketID,
        key: CacheKey,
        size: ByteCount,
        storedAt: Date,
        tags: Set<CacheTag> = [],
        lastAccessedAt: Date? = nil,
        expiresAt: Date? = nil
    )

    public func isExpired(at date: Date) -> Bool
}
```

Required fields are explicit. Optional metadata defaults to empty/nil so tests and wrappers do not need to fill every possible field. Do not default `storedAt` to `Date()`; hidden wall-clock use hurts determinism.

No public `CacheEntryIdentity` or `CachePayloadKind` in v1. Payload shape is implied by the data/file metadata API that returned the info.

## Store facade

```swift
public final class CacheStore: Sendable {
    public let configuration: CacheStoreConfiguration
    public init(configuration: CacheStoreConfiguration) throws
    public func bucket(_ id: CacheBucketID) throws -> CacheBucket
    public func configuredBuckets() -> [CacheBucketID]
    public func usage() async throws -> CacheUsage
    public func cleanup() async throws -> CacheCleanupResult
    public func removeAll() async throws -> CacheRemovalResult
    public func removeAll(in bucket: CacheBucketID) async throws -> CacheRemovalResult
    public func removeAll(tagged tag: CacheTag) async throws -> CacheRemovalResult
    public func removeAll(insertedBefore date: Date) async throws -> CacheRemovalResult
}
```

`configuration` is an immutable snapshot. There is no public `close()` in v1; resources are released when no `CacheStore` or `CacheBucket` handles still reference them. Disk-backed roots should not be shared by multiple active stores in v1.

`bucket(_:)` returns configured active buckets only. `removeAll()` removes all cache entries managed under the store root. `removeAll(in:)` may remove any valid bucket ID under the store root, including buckets no longer configured by the current app version.

## Bucket facade

```swift
public struct CacheBucket: Sendable {
    public let id: CacheBucketID
    public let policy: BucketPolicy

    public func dataInfo(for key: CacheKey) async throws -> CacheEntryInfo?
    public func fileInfo(for key: CacheKey) async throws -> CacheEntryInfo?

    public func data(_ key: CacheKey) async throws -> CachedData?
    public func setData(_ data: Data, for key: CacheKey, options: CacheEntryOptions = .init()) async throws

    public func leaseFile(_ key: CacheKey) async throws -> CachedFileLease?
    public func setFile(at sourceURL: URL, for key: CacheKey, options: CacheFileOptions = .init()) async throws

    public func remove(_ key: CacheKey) async throws -> CacheRemovalResult

    public func removeAll() async throws -> CacheRemovalResult
    public func removeAll(tagged tag: CacheTag) async throws -> CacheRemovalResult
    public func removeAll(insertedBefore date: Date) async throws -> CacheRemovalResult

    public func usage() async throws -> BucketUsage
    public func cleanup() async throws -> CacheCleanupResult
}
```

Default `options` parameters use empty options. `dataInfo` and `fileInfo` do not update access metadata or sliding expiration. Only payload reads (`data`, `leaseFile`) count as access.

## Operation semantics summary

- `data`/`leaseFile`: missing, wrong payload shape, or expired => `nil`.
- `dataInfo`/`fileInfo`: cheap metadata-oriented checks; expired behaves absent.
- `setData/setFile`: validate before commit; oversized throws; replacement overwrites tags, resets `storedAt`, and clears last-access metadata.
- one key maps to one entry; data and file entries replace each other by key.
- all file APIs on memory-only buckets throw `unsupportedFileStorage`.
- exact-key removal and same-key replacement throw if the existing file is leased.
- broad removal/cleanup skip leased files and report.
- missing leased file payloads return absent for new reads/leases, but metadata repair is deferred until release.
- `CacheBucket.cleanup()` is bucket-scoped and does not remove store-level temp files; `CacheStore.cleanup()` handles store-level temp orphans.
- no public `contains` APIs in v1.
- no typed value get/set APIs in v1.
