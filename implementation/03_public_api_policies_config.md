# Public API: policies, configuration, options

## Expiration

```swift
public enum CacheExpirationPolicy: Sendable, Hashable {
    case never
    case fixed(Duration)
    case sliding(Duration)
}
```

Resolved at write from the bucket policy. No per-entry expiration override in v1.

## Eviction

```swift
public enum CacheEvictionPolicy: Sendable, Hashable {
    case leastRecentlyUsed
    case oldestInsertedFirst
}
```

- `leastRecentlyUsed`: default for general caches.
- `oldestInsertedFirst`: feed/reel/story/profile browsing windows where insertion order matters more than access.

No largest-first, priority-based, or custom eviction in v1.

`CacheEvictionPolicy` is not `Codable` in v1. Apps that need persisted or remote config can define their own codable wrapper and map to GraphitCache.

## Bucket policy

```swift
public struct BucketPolicy: Sendable {
    public var storage: CacheStorageMode
    public var maxTotalSize: ByteCount
    public var maxItemSize: ByteCount?
    public var maxItemCount: Int?
    public var expiration: CacheExpirationPolicy
    public var eviction: CacheEvictionPolicy

    public init(
        storage: CacheStorageMode,
        maxTotalSize: ByteCount,
        maxItemSize: ByteCount? = nil,
        maxItemCount: Int? = nil,
        expiration: CacheExpirationPolicy = .never,
        eviction: CacheEvictionPolicy = .leastRecentlyUsed
    )
}

public extension BucketPolicy {
    static func memoryOnly(
        maxTotalSize: ByteCount,
        maxItemSize: ByteCount? = nil,
        maxItemCount: Int? = nil,
        expiration: CacheExpirationPolicy = .never,
        eviction: CacheEvictionPolicy = .leastRecentlyUsed
    ) -> BucketPolicy

    static func diskBacked(
        maxTotalSize: ByteCount,
        maxItemSize: ByteCount? = nil,
        maxItemCount: Int? = nil,
        expiration: CacheExpirationPolicy = .never,
        eviction: CacheEvictionPolicy = .leastRecentlyUsed
    ) -> BucketPolicy
}
```

`maxTotalSize` is required for all buckets. `maxItemSize` and `maxItemCount` are optional secondary safeguards.

No `defaultKind`: apps use tags or buckets for categorization.

## Bucket/store configuration

```swift
public struct BucketConfiguration: Sendable {
    public var id: CacheBucketID
    public var policy: BucketPolicy
    public init(id: CacheBucketID, policy: BucketPolicy)
}

public struct CacheStoreConfiguration: Sendable {
    public var rootDirectory: URL?
    public var buckets: [BucketConfiguration]
    public var clock: any CacheClock
    public init(rootDirectory: URL?, buckets: [BucketConfiguration], clock: any CacheClock = SystemCacheClock())
}
```

Storage mode is bucket-level. `CacheStoreConfiguration` has one initializer so callers explicitly provide either a disk root or `nil`. Use `rootDirectory: nil` for all-memory configurations. Use a file URL root for any configuration that includes a `.diskBacked` bucket, including mixed memory/disk configurations. Do not add store-level `memoryOnly(...)` or `diskBacked(...)` conveniences because they imply a store-level mode and cannot enforce bucket-policy correctness.

No startup-cleanup configuration in v1. Apps call `cleanup()` explicitly.

Rules:

- `rootDirectory == nil` is valid only if every bucket is `.memoryOnly`.
- `rootDirectory != nil` requires at least one `.diskBacked` bucket; all-memory stores must use `nil`.
- `.diskBacked` buckets require a file URL root directory.
- disk-backed roots are store-owned while active: v1 expects one active `CacheStore` with disk-backed buckets per root. Multiple active stores sharing one root are unsupported because leases and removal coordination are store-local.

## Entry options

```swift
public struct CacheEntryOptions: Sendable, Hashable {
    public var tags: Set<CacheTag>
    public init(tags: Set<CacheTag> = [])
}

public struct CacheFileOptions: Sendable, Hashable {
    public var tags: Set<CacheTag>
    public var fileExtension: String?
    public init(tags: Set<CacheTag> = [], fileExtension: String? = nil)
}
```

`CacheFileOptions.fileExtension` is a path-extension hint only. It is not MIME/content-type metadata.

## Deliberately absent in v1

- `CacheMemoryPolicy` / hot memory tier.
- `CacheEntryExpiration`.
- `CachePriority` / protected entries.
- `CacheValueCodec` / JSON codec.
- `CacheKind` / `defaultKind`.
- `CacheContentType` / MIME handling.
- `CacheFileProtection` public policy.
