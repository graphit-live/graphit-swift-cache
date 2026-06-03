# Locked decisions — lean v1

Change process: if implementation conflicts, stop and align. Do not silently drift.

## Product scope

- Implement lean `Spec.md` Draft 4.
- V1 is a bounded `Data` + file cache.
- Consumers own encoding/decoding of Swift models.
- Consumers own semantic categorization beyond cache tags.
- Official product focus: iOS 18+.
- Package also supports macOS 15+ for local SwiftPM builds/tests and future Mac app use.
- Linux is future work, not a v1 support claim.
- Core imports allowed: Swift standard library, Foundation, CryptoKit, SQLite3, Synchronization.
- No third-party Swift packages.
- No UI/framework adapters in v1.
- No loader/get-or-load APIs in v1.

## Package

- SwiftPM source package.
- Swift tools version: 6.3.
- Public product: `GraphitCache` only.
- Targets: `GraphitCache`, `GraphitCacheTests`.
- Platforms: `.iOS(.v18)`, `.macOS(.v15)`.
- No public `GraphitCacheTesting` product in v1.
- Link system SQLite via `.linkedLibrary("sqlite3")`.
- Core public API stays Foundation-based.

## Implementation posture

Build in vertical behavior slices:

1. public API shell and validation;
2. memory-only data path end-to-end;
3. memory expiration/eviction/usage;
4. disk-backed data path end-to-end;
5. file import and leases;
6. cleanup, corruption repair, hardening.

Do not build planner/provider/query frameworks before the implementation needs them. Internal layering may evolve after public behavior is proven.

## Removed/deferred from earlier drafts

Do not implement in v1:

- disk-backed hot memory tier;
- `CacheMemoryPolicy` / `CacheMemoryLimits`;
- typed value APIs (`CacheValueKey`, `get<Value>`, `set<Value>`);
- codecs (`CacheValueCodec`, `JSONCacheValueCodec`, `CacheCodecID`);
- public semantic kind API (`CacheKind`, `defaultKind`, `removeAll(kind:)`);
- public content/MIME API (`CacheContentType`, content-type grouping/constants/validation);
- public `containsData` / `containsFile`;
- public duration convenience extensions;
- per-entry expiration override;
- priority/protected entries;
- largest-first and priority-based eviction;
- data/file/expired usage breakdowns;
- grouped usage report API;
- advanced public query structs;
- public instrumentation/events;
- public testing helper product;
- file-protection public policy;
- checksums/compression/encryption.

## Storage modes

Public storage modes are only `.memoryOnly` and `.diskBacked`.

- `.memoryOnly`: process-local authoritative memory storage for `Data` entries only.
- `.diskBacked`: filesystem payload storage plus SQLite metadata for `Data` and file entries.
- A disk root is owned by one active `CacheStore` instance with disk-backed buckets at a time; v1 does not coordinate leases/removal across multiple stores or processes sharing one root.
- No hot memory tier for disk-backed buckets in v1.
- `CacheStorageMode` is not `Codable` in v1.

## Key model

V1 has one public key type: `CacheKey`.

- `CacheKey` is `RawRepresentable`, `Hashable`, `Codable`, `Sendable`, and `CustomStringConvertible`.
- Dedicated key/tag/bucket types prevent accidental raw-string mixups at public call sites.
- No `ExpressibleByStringLiteral`; use schema constants/extensions.
- `CacheBucketID` validates to a filesystem-safe ASCII name of length <= 128 when used.
- One bucket key maps to one cached entry.
- The current entry is either data-backed or file-backed.
- `setData` may replace an existing data or file entry.
- `setFile` may replace an existing data or file entry.
- If the existing entry is a leased file, exact-key removal or replacement throws `fileIsLeased`.
- Public APIs remain data/file-specific because read ownership differs.

No `CacheDataKey`, `CacheFileKey`, public `CachePayloadKind`, or public `CacheEntryIdentity` in v1.

## Metadata model

V1 exposes only tags for app-defined grouping.

- No public kind API.
- No public content-type/MIME API.
- Apps can use tags such as `kind:profile`, `format:json`, `feed:home` if useful.
- Normal usage reporting is total + per-bucket only.

`CacheEntryInfo.key` is a `CacheKey`, not a raw `String`.

`CacheEntryInfo` has a public initializer with required fields only:

```swift
public init(
    bucket: CacheBucketID,
    key: CacheKey,
    size: ByteCount,
    storedAt: Date,
    tags: Set<CacheTag> = [],
    lastAccessedAt: Date? = nil,
    expiresAt: Date? = nil
)
```

Do not default `storedAt` to `Date()`; hidden wall-clock reads hurt deterministic tests.

## Usage and results

Usage is intentionally simple:

- `CacheUsage`: total/disk/memory size, entry count, per-bucket usage.
- `BucketUsage`: bucket, total/disk/memory size, entry count.
- No public usage initializers needed in v1; usage snapshots are SDK-produced.
- No `Hashable` conformance on usage snapshots in v1.
- `CacheRemovalResult` and `CacheCleanupResult` have public initializers and `empty` constants.

## Bucket bounds

Every bucket requires `maxTotalSize`. A cache without a bound becomes accidental storage. Optional secondary bounds:

- `maxItemSize`;
- `maxItemCount`.

## Eviction

V1 keeps two runtime eviction strategies:

- `.leastRecentlyUsed`: general default.
- `.oldestInsertedFirst`: feeds/reels/stories/profile browsing windows.

No largest-first, custom eviction, or priority-based eviction in v1. `CacheEvictionPolicy` is not `Codable`.

## Protection model

No per-entry protected flag. Recommend separate buckets with different policy for different retention needs. If data must not be evicted, it is not cache data.

## Cleanup and old buckets

No automatic full startup cleanup in v1. `CacheStore.init` validates, creates directories, opens SQLite, and applies schema only.

- Reads lazily repair the specific expired/missing entry they touch.
- Writes enforce capacity for the affected bucket.
- Apps call `cleanup()` explicitly for expired entries, temp/final orphans, metadata rows with missing files, and capacity enforcement.
- `bucket(_:)` returns configured active buckets only.
- `usage()` reports configured buckets only.
- `removeAll(in:)` may remove any valid bucket ID under the store root, including buckets no longer configured by the current app version.
- Do not delete old/unconfigured buckets automatically at startup.

## Hashing and payload paths

Use CryptoKit SHA-256 in one internal helper:

```swift
internal enum StableKeyHasher {
    static func entryID(bucket: CacheBucketID, key: CacheKey) -> String
}
```

Stable entry ID:

```text
SHA256(bucket + "\0" + rawKey)
```

Per-write payload storage refs are root-relative and versioned:

```text
buckets/<bucket>/<h0h1>/<h2h3>/<entryID>-<writeID>.<ext>
```

Reject Swift `hashValue`, raw key paths, public hasher protocol, and deterministic in-place payload paths.

## Expiration API

Expose only:

```swift
public func isExpired(at date: Date) -> Bool
```

No hidden wall-clock property. Expired entries behave absent for per-key APIs.

## Store configuration and bucket snapshots

Expose original initialization snapshot:

```swift
public let configuration: CacheStoreConfiguration
```

Internals use validated normalized config. `CacheBucket` stores a validated policy snapshot so `bucket(_:)` stays synchronous.

Storage mode is bucket-level, not store-level. `CacheStoreConfiguration` has one designated initializer only. Do not add store-level `.memoryOnly(...)` or `.diskBacked(...)` conveniences because they imply a store-level mode and cannot enforce bucket-policy correctness.

Root rules:

- `rootDirectory == nil` is valid only when every bucket is `.memoryOnly`.
- `rootDirectory != nil` requires at least one `.diskBacked` bucket; all-memory stores must use `nil`.
- use the designated initializer for every configuration.

## File leases

Use explicit synchronous release plus synchronous `deinit` safety net. No `Task` in `deinit`.

- `CachedFileLease.release()` is synchronous and idempotent.
- Internal lease token decrements a `Synchronization.Mutex`-protected lease table synchronously.
- Bulk removal/cleanup skip leased files and report `skippedLeasedEntries`.
- Direct exact-key removal and same-key replacement of a leased file throw.
- Playback examples must retain the lease for the whole playback lifetime.

## Disk I/O and `@concurrent`

Large or potentially blocking disk I/O must not run inside `CacheStoreEngine` actor.

Use tiny internal `@concurrent` helpers for:

- disk-backed `Data` temp writes;
- source file copy/import to temp.

Shape:

```text
actor: validate/plan
@concurrent helper: write or copy to temp without actor isolation
actor: revalidate cancellation/lease/capacity
actor transaction: upsert metadata/tags and delete selected victim metadata
actor: move temp -> final versioned path
actor: commit transaction
post-commit: delete old/victim payload files best effort
```

No `Task.detached`. No `await` inside SQLite transactions. Revalidate any invariant after the `await` boundary.

## Persistence representation

Disk-backed `Data` and file payload bytes are filesystem files; SQLite stores metadata and root-relative versioned `storage_ref`, not payload BLOBs.

Replacement resets public metadata:

- `storedAt = now`;
- `lastAccessedAt = nil`.

SQLite date/duration storage uses integer microseconds.

During disk commit, move temp payloads to their final versioned path before committing SQLite metadata. A crash after final move but before commit creates an orphan file that cleanup can remove; do not intentionally commit metadata pointing at a not-yet-moved payload.

## SQLite indexes

Start with a lean index set only:

```sql
CREATE INDEX IF NOT EXISTS idx_entries_bucket_stored_at ON entries(bucket, stored_at_us);
CREATE INDEX IF NOT EXISTS idx_entries_bucket_lru ON entries(bucket, last_accessed_at_us, stored_at_us);
CREATE INDEX IF NOT EXISTS idx_entries_expires_at ON entries(expires_at_us);
CREATE INDEX IF NOT EXISTS idx_tags_tag_entry ON tags(tag, entry_id);
```

Rely on `UNIQUE(bucket, key)` and `PRIMARY KEY(entry_id, tag)` for lookup/cascade needs. Add more indexes later only with evidence.

## Public API shape

No unleased public file URL API. File payloads are accessed through `leaseFile(_:)` only.

No public `close()` in v1. Cache resources are released when no `CacheStore` or `CacheBucket` handles still reference them. Disk-backed roots should not be shared by multiple active stores.

## Tests

Prefer fewer high-signal deterministic tests over volume. Test user-visible regressions: config, data set/get/remove, file set/lease/remove, expiration, LRU/FIFO eviction, leases, corruption/orphans, usage, concurrency, and cancellation.
