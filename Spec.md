# GraphitCache Swift SDK — Lean V1 Product and Engineering Specification

**Version:** Draft 4 lean vertical v1  
**Date:** 2026-06-02  
**Primary goal:** a small, reliable, Apple-native cache SDK for Swift developers.  
**Core rule:** GraphitCache stores and manages cached bytes and files. It does not fetch, compute, encode business models, decode business models, retry, render, navigate, or update UI.

---

## 1. Executive summary

GraphitCache v1 is a **bounded `Data` + file cache** with explicit buckets, tags, expiration, eviction, manual cleanup, simple usage reporting, and file leases.

It supports:

- process-local memory-only `Data` buckets;
- disk-backed `Data` and file buckets;
- one strongly typed key type for both data and files;
- bucket-level size and count limits;
- bucket-level expiration;
- LRU and FIFO eviction;
- flexible tag metadata;
- explicit cleanup/removal;
- simple total and per-bucket usage reporting;
- file leases for playback and long reads.

It intentionally does **not** include typed value APIs, codecs, loaders, content-type handling, semantic kind APIs, grouped usage reports, public instrumentation, or UI adapters in v1. Consumers decide how their models become bytes and how they categorize entries.

```swift
let encoded = try JSONEncoder().encode(profile)
try await profiles.setData(
    encoded,
    for: .profile(userID),
    options: .init(tags: [AppCache.Tags.profile, AppCache.Tags.user(userID)])
)

if let cached = try await profiles.data(.profile(userID)) {
    let profile = try JSONDecoder().decode(Profile.self, from: cached.data)
}
```

For media and large payloads, consumers import files:

```swift
let (temporaryURL, _) = try await URLSession.shared.download(from: remoteVideoURL)

try await reels.setFile(
    at: temporaryURL,
    for: .reel(reelID),
    options: .init(
        tags: [AppCache.Tags.reel, AppCache.Tags.homeFeed],
        fileExtension: "mp4"
    )
)
```

---

## 2. Platform and toolchain

- Swift 6.3.x.
- Swift language mode 6.
- SwiftPM source package.
- Official v1 product focus: iOS 18+.
- Package also supports macOS 15+ so SwiftPM builds/tests can run locally and so Mac app support can be proven without a different implementation shape.
- No Linux support claim in v1.
- No third-party Swift dependencies.

Core imports allowed in v1: Swift standard library, Foundation, CryptoKit, SQLite3, Synchronization.

---

## 3. Non-negotiable v1 decisions

### 3.1 Simplicity over breadth

V1 is a solid foundation, not a maximal cache framework. If a feature adds broad public API and implementation complexity for niche benefit, defer it.

### 3.2 No loader API

No `getOrLoad`, stale-while-revalidate, single-flight, retry, URL loading, or background refresh APIs in v1. Apps fetch/compute data themselves, then call `setData` or `setFile`.

### 3.3 No codec or typed value API

No `CacheValueKey<Value>`, `CacheValueCodec`, `JSONCacheValueCodec`, `get<Value>`, or `set<Value>` in v1.

GraphitCache stores bytes. Consumers own model encoding/decoding.

### 3.4 No disk-backed hot memory tier

V1 has two storage modes only:

- `.memoryOnly`;
- `.diskBacked`.

There is no disk-backed hot memory tier in v1. It can be added later after disk/index behavior is proven.

### 3.5 No priority/protected entries

No `CachePriority` and no protected-entry behavior in v1. If data needs different retention or eviction behavior, use a different bucket with a different policy.

### 3.6 No public query system

No `CacheUsageQuery`, `CacheRemovalQuery`, `BucketRemovalQuery`, or `CacheCleanupQuery` in v1. Keep common operations only:

```swift
try await cache.removeAll(in: AppCache.Buckets.reels)
try await cache.removeAll(tagged: AppCache.Tags.homeFeed)
try await cache.removeAll(insertedBefore: oldCutoffDate)
try await cache.cleanup()
```

### 3.7 No semantic kind or content type

No `CacheKind`, no `CacheContentType`, no MIME validation, and no built-in media/content constants in v1. Apps can model categories with tags:

```swift
CacheTag("kind:profile")
CacheTag("format:json")
CacheTag("feed:home")
```

### 3.8 Simple usage reports only

V1 reports total usage and per-bucket usage. It does not expose grouped reports, data/file breakdowns, or expired-entry usage breakdowns.

### 3.9 No public `contains` APIs

No `containsData` or `containsFile`. They duplicate metadata APIs and are not correctness locks.

Use:

```swift
if try await bucket.dataInfo(for: key) != nil {
    // Metadata exists now, but another task can still remove it later.
}
```

### 3.10 No public instrumentation product

No `CacheEventSink`, event model, OSLog adapter, or background event dispatch in v1. Observability can be added later after core behavior stabilizes.

### 3.11 No public `GraphitCacheTesting` product

V1 ships one public product: `GraphitCache`. Test helpers stay internal to the package test suite. Consumers can make their own fake clock because `CacheClock` is public and small.

### 3.12 Every bucket is bounded

Every bucket requires `maxTotalSize`. A cache without a bound becomes accidental storage.

---

## 4. Concept model

### 4.1 Store

`CacheStore` is the top-level object. It owns configured buckets, disk root setup, metadata index, cleanup, leases, and lifecycle.

### 4.2 Bucket

A `CacheBucket` is a named cache collection with one policy:

- storage mode;
- maximum total size;
- optional maximum item size;
- optional maximum item count;
- expiration;
- eviction strategy.

Use different buckets for different retention and quota needs.

### 4.3 Key

`CacheKey` is the app-defined identity for one cached entry inside a bucket.

A dedicated key type is intentionally used instead of raw `String` to avoid mixing keys, tags, and bucket IDs at call sites.

One bucket key maps to **one** cached entry. That entry is either data-backed or file-backed.

```swift
CacheKey("profile-json:\(userID)")
CacheKey("profile-avatar-file:\(userID)")
```

### 4.4 Data entry

A data entry stores caller-provided `Data`.

Use for JSON bytes, protobuf bytes, small image bytes, thumbnails, metadata blobs, and small generated binary data.

### 4.5 File entry

A file entry imports a local file into the cache-managed directory.

Use for videos, large images, PDFs, exports, downloaded files, and any payload that should not be loaded into memory.

### 4.6 Bucket vs tag

Bucket = policy and quota.  
Tag = flexible grouping label.

```swift
enum AppCache {
    enum Buckets {
        static let profiles = CacheBucketID("profiles")
        static let avatars = CacheBucketID("avatars")
        static let homeReels = CacheBucketID("home-reels")
    }

    enum Tags {
        static let profile = CacheTag("kind:profile")
        static let avatar = CacheTag("kind:avatar")
        static let reel = CacheTag("kind:reel")
        static let homeFeed = CacheTag("feed:home")
        static func user(_ id: String) -> CacheTag { CacheTag("user:\(id)") }
    }
}

extension CacheKey {
    static func profile(_ id: String) -> Self { Self("profile:\(id)") }
    static func avatar(_ id: String) -> Self { Self("avatar:\(id)") }
    static func reel(_ id: String) -> Self { Self("reel:\(id)") }
}
```

---

## 5. Public API surface — lean v1

### 5.1 ByteCount

```swift
public struct ByteCount: Hashable, Comparable, Codable, Sendable, ExpressibleByIntegerLiteral {
    public let bytes: Int64

    public init(_ bytes: Int64)
    public init(integerLiteral value: Int64)

    public static func bytes(_ value: Int64) -> ByteCount
    public static func kb(_ value: Int64) -> ByteCount
    public static func mb(_ value: Int64) -> ByteCount
    public static func gb(_ value: Int64) -> ByteCount

    public static let zero: ByteCount

    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool
}
```

Policy validation rejects negative sizes. V1 does not add public `Duration` convenience extensions.

### 5.2 String-backed values

```swift
public struct CacheBucketID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init(rawValue: String)
    public var description: String { get }
}

public struct CacheTag: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init(rawValue: String)
    public var description: String { get }
}

public struct CacheKey: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init(rawValue: String)
    public var description: String { get }
}
```

No `ExpressibleByStringLiteral`: this encourages schema constants instead of scattered magic strings.

`CacheBucketID` is validated when used as a filesystem-safe name: ASCII letters, numbers, `.`, `_`, and `-`; non-empty; not `.` or `..`; length <= 128. Bucket IDs are strict because they become generated path components.

### 5.3 Storage mode

```swift
public enum CacheStorageMode: Sendable, Hashable {
    case memoryOnly
    case diskBacked
}
```

- `.memoryOnly`: process-local `Data` entries only.
- `.diskBacked`: `Data` and file entries persisted under the cache root with SQLite metadata.

`CacheStorageMode` is not `Codable` in v1.

### 5.4 Expiration

```swift
public enum CacheExpirationPolicy: Sendable, Hashable {
    case never
    case fixed(Duration)
    case sliding(Duration)
}
```

V1 supports bucket-level expiration only. No per-entry expiration override.

### 5.5 Eviction

```swift
public enum CacheEvictionPolicy: Sendable, Hashable {
    case leastRecentlyUsed
    case oldestInsertedFirst
}
```

- `.leastRecentlyUsed`: best general-purpose default.
- `.oldestInsertedFirst`: useful for feeds, reels, stories, and browsing windows.

No largest-first or priority-based eviction in v1. `CacheEvictionPolicy` is not `Codable` in v1.

### 5.6 Bucket policy

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

`maxTotalSize` is required for every bucket.

### 5.7 Store configuration

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

    public init(
        rootDirectory: URL?,
        buckets: [BucketConfiguration],
        clock: any CacheClock = SystemCacheClock()
    )
}
```

Storage mode is bucket-level. `CacheStoreConfiguration` has one initializer so callers explicitly provide either a disk root or `nil`. Use `rootDirectory: nil` for all-memory configurations. Use a file URL root for any configuration that includes a `.diskBacked` bucket, including mixed memory/disk configurations.

Rules:

- `rootDirectory == nil` is valid only if every bucket is `.memoryOnly`.
- `rootDirectory != nil` requires at least one `.diskBacked` bucket; all-memory stores must use `nil`.
- `.diskBacked` buckets require a file URL root directory.
- A disk root is owned by one active `CacheStore` instance with disk-backed buckets at a time. V1 does not coordinate leases or removal across multiple stores sharing the same root.
- Bucket IDs must be unique.
- When disk-backed buckets are present, initialization performs bounded synchronous local filesystem and SQLite setup.
- No full cleanup runs automatically at startup.

### 5.8 Entry options

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

`CacheFileOptions.fileExtension` is a file path extension hint, not MIME/content-type metadata.

Extension resolution for `setFile`:

1. explicit `fileExtension` if provided;
2. source URL path extension if present and valid;
3. `bin`.

`setData` stores data payloads with an internal `.bin` extension.

### 5.9 Cached data wrapper

```swift
public struct CachedData: Sendable {
    public let data: Data
    public let info: CacheEntryInfo

    public init(data: Data, info: CacheEntryInfo)
}
```

File payloads are accessed through `CachedFileLease` only. V1 does not return unleased cache file URLs.

### 5.10 File lease

```swift
public final class CachedFileLease: Sendable {
    public let url: URL
    public let info: CacheEntryInfo

    public func release()
}
```

A lease prevents cleanup, eviction, removal, and same-key replacement from deleting or replacing an actively used cached file. `release()` is synchronous and idempotent. `deinit` releases as a safety net, but apps should release explicitly.

### 5.11 Entry info

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

The payload shape is implied by the API that returned the info (`dataInfo`, `fileInfo`, `data`, or `leaseFile`). Internally, the SDK still stores whether the entry is data or file-backed.

### 5.12 CacheStore

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

`bucket(_:)` only returns configured active buckets. `removeAll(in:)` may remove any valid bucket ID under the store root, including old buckets no longer configured by the current app version.

### 5.13 CacheBucket

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

`dataInfo` and `fileInfo` do not update `lastAccessedAt` or sliding expiration. Payload reads (`data`, `leaseFile`) do update access metadata.

`CacheBucket.cleanup()` is bucket-scoped. Store-level temporary file cleanup is performed by `CacheStore.cleanup()`.

One key maps to one entry:

- `setData` may replace an existing data or file entry;
- `setFile` may replace an existing data or file entry;
- if the existing entry is a leased file, same-key replacement/removal throws `fileIsLeased`;
- `dataInfo`/`data` return `nil` for a file entry;
- `fileInfo`/`leaseFile` return `nil` for a data entry.

### 5.14 Usage reporting

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

- memory-only `diskSize = 0`;
- disk-backed `memorySize = 0` in v1 because no hot memory tier;
- usage uses memory metadata or SQLite metadata, not filesystem scans;
- no public usage grouping or data/file/expired breakdown in v1.

`CacheUsage` and `BucketUsage` are SDK-produced snapshots. V1 does not need public initializers for them.

### 5.15 Results

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

### 5.16 Clock

```swift
public protocol CacheClock: Sendable {
    func now() -> Date
}

public struct SystemCacheClock: CacheClock {
    public init()
    public func now() -> Date
}
```

### 5.17 Errors

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

No low-level non-Sendable `Error` associated values.

---

## 6. Required behavior

### 6.1 Configuration validation

`CacheStore.init` validates before side effects where possible:

- bucket IDs valid and unique;
- all buckets have nonnegative, nonzero `maxTotalSize`;
- optional limits are valid;
- `.diskBacked` buckets require a file URL root;
- all-memory stores must omit the root;
- a non-`nil` root requires at least one `.diskBacked` bucket;
- when disk-backed buckets are present, initialization creates required directories and SQLite schema.

### 6.2 Data writes

`setData` flow:

```text
validate key/options
measure data size
validate maxItemSize and maxTotalSize
resolve expiration from bucket policy
write to memory or disk/index
preselect and remove eviction victims if needed
return after durable state is committed
```

For disk-backed buckets, data bytes are stored as files under the cache root. SQLite stores metadata only.

Disk-backed `setData` uses a two-phase I/O shape like file import:

```text
actor: validate, check existing leased file, plan temp destination
@concurrent non-actor helper: write Data -> temp
actor: revalidate cancellation/lease/capacity
actor transaction: upsert metadata/tags and delete selected victim metadata
actor: move temp -> final versioned path
actor: commit transaction
post-commit: delete old/victim payload files best effort
```

No `Task.detached`. No `await` occurs inside SQLite transactions.

### 6.3 Data reads

`data(_:)` flow:

```text
lookup metadata
if missing or current entry is a file -> nil
if expired -> remove/repair and nil
load data bytes
update lastAccessedAt
extend sliding expiration if needed
return CachedData
```

### 6.4 File writes

`setFile` imports a local file into the cache directory.

Rules:

- source URL must be a local file URL;
- source file remains caller-owned;
- file size is read from attributes, not by loading bytes;
- all file APIs on memory-only buckets throw `unsupportedFileStorage(storageMode: .memoryOnly)`;
- final cache paths are hashed and versioned;
- replacements never overwrite old bytes in place;
- replacing a leased file key throws `fileIsLeased`.

Disk-backed `setFile` uses a two-phase shape:

```text
actor: validate bucket/key/policy/source metadata, check existing leased file, plan temp destination
@concurrent non-actor file helper: copy source -> temp without loading whole file
actor: revalidate cancellation/lease/capacity
actor transaction: upsert metadata/tags and delete selected victim metadata
actor: move temp -> final versioned path
actor: commit transaction
post-commit: delete old/victim payload files best effort
```

No `Task.detached`. No `await` occurs inside SQLite transactions. The final same-volume move may happen during the actor commit path because it should be cheap compared with the source-file copy.

### 6.5 File reads and leases

V1 exposes cached file URLs only through `leaseFile(_:)`. The returned lease must be retained for as long as the caller uses the file URL.

`leaseFile(_:)` returns a retained lease that blocks eviction, removal, and same-key replacement while active. Direct `remove(_:)` or `setData`/`setFile` for a leased file key throws `fileIsLeased`. Bulk removal/cleanup skip leased files and report `skippedLeasedEntries`. If corruption or external deletion makes a leased payload file missing, new reads/leases return `nil`, but metadata repair is deferred until the lease is released.

### 6.6 Info APIs

`dataInfo` and `fileInfo` are metadata-oriented APIs. They do not read data bytes and do not update access metadata.

They are useful for cheap checks, but they are not correctness locks.

### 6.7 Expiration

- `.never`: no time expiration.
- `.fixed(duration)`: expires duration after storage/replacement.
- `.sliding(duration)`: expires duration after storage/replacement and extends after each successful payload read.

Expired entries behave absent.

### 6.8 Eviction and capacity

Every bucket has `maxTotalSize`. Optional `maxItemSize` and `maxItemCount` add stricter bounds.

When a write would exceed capacity:

1. validate the new item can ever fit;
2. preselect eligible existing victims according to eviction policy;
3. exclude the newly written identity from same-write eviction;
4. commit new metadata and victim metadata deletion atomically where possible;
5. delete victim files after commit.

For disk-backed writes, the synchronous actor commit path stages metadata/victim changes in a SQLite transaction, moves the temp payload to its final versioned path, then commits the transaction. If a crash leaves a final file without committed metadata, manual cleanup treats it as an orphan.

If capacity cannot be satisfied, the write throws and the new entry must not remain.

### 6.9 Cleanup

`cleanup()` is explicit manual maintenance. It may:

- remove expired entries;
- remove temp or orphan files;
- remove metadata rows whose payload files are missing;
- enforce bucket capacity.

`CacheStore.cleanup()` may remove store-level temp orphans. `CacheBucket.cleanup()` is bucket-scoped and does not remove store-level temp files.

Metadata rows with missing payload files are removed when unleased. If the missing payload is a leased file, cleanup skips and counts it; repair can occur after release.

No full cleanup runs automatically at startup.

### 6.10 Removal

Supported broad removals:

```swift
removeAll()
removeAll(in:)
removeAll(tagged:)
removeAll(insertedBefore:)
```

`insertedBefore(date)` means `storedAt < date`.

`removeAll()` removes all cache entries managed under the store root, including old bucket data. `removeAll(in:)` can remove old/unconfigured bucket IDs if the ID is valid. This gives apps an explicit migration cleanup path without surprising startup deletion.

Exact-key removal uses:

```swift
bucket.remove(key)
```

### 6.11 Resource lifecycle

There is no public `close()` in v1. Cache resources are released when no `CacheStore` or `CacheBucket` handles still reference them.

Stores with disk-backed buckets should not share a root with another active `CacheStore`. V1 lease and removal coordination is store-local, not cross-store or cross-process.

### 6.12 Cancellation

- If cancelled before commit, no partial entry should remain.
- Temp files should be cleaned best effort.
- Cleanup cancellation may leave completed removals removed.
- Cancellation is not converted into a generic cache error.

---

## 7. Internal architecture

```text
CacheStore
  └─ CacheStoreEngine actor
       ├─ normalized config and active bucket registry
       ├─ MemoryCacheEngine
       ├─ PersistentFileStore
       ├─ SQLiteMetadataIndex
       └─ LeaseTable
```

Rules:

- Public facade is not `@MainActor`.
- Shared mutable state is actor-owned or protected by tiny reviewed synchronization.
- SQLite connection is actor-owned.
- Large disk writes/copies run through tiny `@concurrent` helpers outside the store actor, then actor state is revalidated before commit.
- File leases use `Synchronization.Mutex` because v1 targets iOS 18/macOS 15 and `release()`/`deinit` must be synchronous.
- No hidden `Task.detached`.
- No UI, networking, image, or video framework imports in core.
- Build in vertical behavior slices; do not split planner/provider abstractions until implementation needs them.

---

## 8. Disk and SQLite design

### 8.1 Stable entry IDs

Internal entry IDs use SHA-256:

```text
SHA256(bucket + "\0" + rawKey)
```

Do not use Swift `hashValue` for persistence.

Because one key maps to one entry, data and file entries do not need separate public or persistent key namespaces.

### 8.2 File layout

```text
GraphitCacheRoot/
  index/metadata.sqlite[,-wal,-shm]
  buckets/<bucket>/<h0h1>/<h2h3>/<entry-id>-<write-id>.<ext>
  tmp/<uuid>.tmp
```

Raw keys are never used in paths.

### 8.3 SQLite metadata

SQLite stores metadata, not payload BLOBs. It stores an internal payload kind (`data` or `file`) to know how to interpret the current entry for a key.

Core columns:

- id;
- bucket;
- key;
- payload_kind;
- storage_ref;
- size_bytes;
- stored and last-access dates;
- expiration metadata.

Tags are stored in a separate table.

Lean v1 starts with only indexes clearly needed by current behavior:

```sql
CREATE INDEX IF NOT EXISTS idx_entries_bucket_stored_at
ON entries(bucket, stored_at_us);

CREATE INDEX IF NOT EXISTS idx_entries_bucket_lru
ON entries(bucket, last_accessed_at_us, stored_at_us);

CREATE INDEX IF NOT EXISTS idx_entries_expires_at
ON entries(expires_at_us);

CREATE INDEX IF NOT EXISTS idx_tags_tag_entry
ON tags(tag, entry_id);
```

Additional indexes can be added later when measured.

### 8.4 Atomic replacement

Replacements use a new versioned file path. Old payload files are deleted only after new metadata is committed. If a crash occurs after the new file is moved but before metadata commit, the new file is an orphan cleanup candidate. V1 prefers repairable file orphans over committed metadata pointing at missing files.

Same-key replacement changes the payload kind if needed:

- data -> data;
- file -> file;
- data -> file;
- file -> data, unless the old file is leased.

---

## 9. Examples

### 9.1 Configure disk-backed app cache

```swift
let cache = try CacheStore(configuration: .init(
    rootDirectory: cacheDirectory,
    buckets: [
        .init(
            id: AppCache.Buckets.profiles,
            policy: .diskBacked(
                maxTotalSize: .mb(100),
                maxItemSize: .mb(1),
                expiration: .sliding(.seconds(30 * 24 * 60 * 60)),
                eviction: .leastRecentlyUsed
            )
        ),
        .init(
            id: AppCache.Buckets.homeReels,
            policy: .diskBacked(
                maxTotalSize: .gb(2),
                maxItemSize: .mb(250),
                expiration: .fixed(.seconds(24 * 60 * 60)),
                eviction: .oldestInsertedFirst
            )
        )
    ]
))
```

### 9.2 Memory-only cache

```swift
let cache = try CacheStore(configuration: .init(
    rootDirectory: nil,
    buckets: [
        .init(
            id: CacheBucketID("calculations"),
            policy: .memoryOnly(
                maxTotalSize: .mb(50),
                maxItemSize: .mb(1),
                maxItemCount: 1_000
            )
        )
    ]
))
```

### 9.3 JSON profile data

```swift
let profiles = try cache.bucket(AppCache.Buckets.profiles)
let key = CacheKey.profile(userID)

if let cached = try await profiles.data(key) {
    let profile = try JSONDecoder().decode(Profile.self, from: cached.data)
    render(profile)
} else {
    let profile = try await api.fetchProfile(userID)
    let data = try JSONEncoder().encode(profile)

    try await profiles.setData(
        data,
        for: key,
        options: .init(tags: [AppCache.Tags.profile, AppCache.Tags.user(userID)])
    )

    render(profile)
}
```

### 9.4 Video playback with lease

```swift
try await reels.setFile(
    at: downloadedFileURL,
    for: .reel(reelID),
    options: .init(
        tags: [AppCache.Tags.reel, AppCache.Tags.homeFeed],
        fileExtension: "mp4"
    )
)

@MainActor
final class ReelViewModel: ObservableObject {
    private let reels: CacheBucket
    private var lease: CachedFileLease?
    @Published var player: AVPlayer?

    init(reels: CacheBucket) {
        self.reels = reels
    }

    func play(reelID: String) async throws {
        stop()
        guard let lease = try await reels.leaseFile(.reel(reelID)) else { return }
        self.lease = lease
        self.player = AVPlayer(url: lease.url)
        self.player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
        lease?.release()
        lease = nil
    }
}
```

### 9.5 Usage and cleanup

```swift
let usage = try await cache.usage()
let oldCutoffDate = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)

try await cache.removeAll(tagged: AppCache.Tags.reel)
try await cache.removeAll(insertedBefore: oldCutoffDate)
try await cache.cleanup()
```

### 9.6 Migration cleanup for old buckets

```swift
// The app no longer configures "avatars-v1", but can explicitly remove it.
try await cache.removeAll(in: CacheBucketID("avatars-v1"))
```

---

## 10. Deferred features

Explicitly not v1:

- typed value APIs;
- codecs;
- disk-backed hot memory tier;
- loader APIs;
- stale fallback;
- networking integration;
- SwiftUI/UIKit/AppKit adapters;
- image decoding;
- video processing;
- semantic `CacheKind` API;
- MIME/content-type API;
- priority/protected entries;
- largest-first eviction;
- custom eviction strategies;
- data/file/expired usage breakdowns;
- grouped usage reports;
- advanced query structs;
- public instrumentation/events;
- public testing helper product;
- encryption;
- compression;
- checksums;
- Linux support claim.

---

## 11. Engineering quality bar

- Swift 6 language mode.
- iOS 18+ and macOS 15+ package floor.
- Public APIs are documented.
- Public behavior implemented in vertical slices with deterministic tests.
- No core `MainActor` pollution.
- No hidden global mutable state.
- No service locator.
- No third-party Swift dependencies.
- No raw user keys in paths.
- No unbounded caches.
- No unchecked concurrency escape without written review.
- No `Task.detached` for cache I/O.
- Tests prioritize public behavior over vanity coverage.

GraphitCache v1 should be small enough to understand quickly and solid enough to build on later.
