# GraphitCache

GraphitCache is a small Swift cache SDK for bounded `Data` and cache-managed files.
It stores bytes and files; your app owns fetching, retrying, model encoding/decoding,
rendering, navigation, and UI updates.

## Platform support

- Swift 6.3+
- iOS 18+ is the primary supported platform.
- macOS 15+ is supported for SwiftPM builds/tests and Mac app use.
- GraphitCache does not claim Linux support in v1.
- The package has no third-party Swift dependencies.

## Install

Add the `GraphitCache` Swift package to your app and import the product:

```swift
import Foundation
import GraphitCache
```

## Core model

A `CacheStore` owns configured buckets. Each `CacheBucket` has one policy:
storage mode, size/count limits, expiration, and eviction behavior.

```swift
enum AppCache {
    enum Buckets {
        static let profiles = CacheBucketID("profiles")
        static let reels = CacheBucketID("reels")
    }

    enum Tags {
        static let profile = CacheTag("kind:profile")
        static let reel = CacheTag("kind:reel")
        static let homeFeed = CacheTag("feed:home")
        static func user(_ id: String) -> CacheTag { CacheTag("user:\(id)") }
    }
}

extension CacheKey {
    static func profile(_ id: String) -> Self { Self("profile:\(id)") }
    static func reel(_ id: String) -> Self { Self("reel:\(id)") }
}
```

GraphitCache uses dedicated `CacheKey`, `CacheTag`, and `CacheBucketID` types
instead of raw strings so call sites do not accidentally pass a tag where a key
or bucket ID is expected. There is one public key type. Inside one bucket, one
`CacheKey` maps to at most one current entry: either a data entry or a file
entry.

Bucket = policy and quota. Tag = flexible app-owned grouping label. GraphitCache
has no public kind or content-type API in v1; use tags such as `kind:profile` or
`format:json` if your app needs those labels.

Avoid putting secrets, tokens, or private user data in keys and tags if your app
logs or displays their raw values.

## Configure a store

Storage mode is bucket-level:

- `.memoryOnly` stores process-local `Data` entries only.
- `.diskBacked` stores `Data` and file entries under a caller-provided root
  directory with SQLite metadata.

`CacheStoreConfiguration` has one initializer. Pass `rootDirectory: nil` for an
all-memory store. Pass a file URL root when any configured bucket is disk-backed,
including mixed memory/disk configurations. Every bucket requires `maxTotalSize`.

```swift
let memoryCache = try CacheStore(configuration: .init(
    rootDirectory: nil,
    buckets: [
        .init(
            id: AppCache.Buckets.profiles,
            policy: .memoryOnly(
                maxTotalSize: .mb(50),
                maxItemSize: .mb(1),
                maxItemCount: 1_000
            )
        )
    ]
))
```

```swift
let cacheDirectory = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("GraphitCache", isDirectory: true)

let diskCache = try CacheStore(configuration: .init(
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
            id: AppCache.Buckets.reels,
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

When disk-backed buckets are present, initialization performs bounded synchronous
local filesystem and SQLite setup. V1 expects one active disk-backed `CacheStore`
per root directory; leases and removal coordination are store-local and do not
coordinate multiple active stores sharing a root.

There is no public `close()` API. Store resources are released when no
`CacheStore` or `CacheBucket` handles retain them.

## Store and read data

GraphitCache does not provide typed value or codec APIs. Consumers encode and
decode their own models.

```swift
struct Profile: Codable {
    var name: String
}

let profiles = try diskCache.bucket(AppCache.Buckets.profiles)
let userID = "123"
let key = CacheKey.profile(userID)

if let cached = try await profiles.data(key) {
    let profile = try JSONDecoder().decode(Profile.self, from: cached.data)
    print(profile.name)
} else {
    let profile = Profile(name: "Blob")
    let data = try JSONEncoder().encode(profile)

    try await profiles.setData(
        data,
        for: key,
        options: .init(tags: [AppCache.Tags.profile, AppCache.Tags.user(userID)])
    )
}
```

`dataInfo(for:)` returns metadata without reading bytes and does not update
last-access metadata or sliding expiration. `data(_:)` reads bytes and counts as
payload access.

## Import and lease files

Files are available only in disk-backed buckets. `setFile(at:for:options:)`
copies a local file into cache-managed storage. The source file remains
caller-owned.

```swift
let reels = try diskCache.bucket(AppCache.Buckets.reels)
let downloadedFileURL = URL(fileURLWithPath: "/path/to/downloaded.mp4")

try await reels.setFile(
    at: downloadedFileURL,
    for: .reel("42"),
    options: .init(
        tags: [AppCache.Tags.reel, AppCache.Tags.homeFeed],
        fileExtension: "mp4"
    )
)

if let lease = try await reels.leaseFile(.reel("42")) {
    defer { lease.release() }
    let url = lease.url
    // Use url only while the lease is retained.
}
```

Cached file URLs are cache-managed and are returned only through
`CachedFileLease`. Retain the lease for the entire file-use lifetime. For video
playback or other long reads, store the lease and release it when playback stops;
do not release immediately after calling a player method that returns before
playback finishes.

A leased file blocks same-key replacement and exact-key removal. Broad removal
and cleanup skip leased files and report skipped counts. If a leased payload file
is externally deleted, new reads/leases return `nil`, and metadata repair is
deferred until the lease is released.

## Expiration, eviction, and usage

Expiration is bucket-level:

- `.never` never expires by time.
- `.fixed(duration)` expires after storage or replacement.
- `.sliding(duration)` extends on successful payload reads.

Eviction options are intentionally small:

- `.leastRecentlyUsed` evicts entries with the oldest access first.
- `.oldestInsertedFirst` evicts entries by insertion order.

Usage reports are simple snapshots: total size, disk size, memory size, entry
count, and per-bucket usage. V1 does not expose grouped usage, data/file
breakdowns, or expired-entry usage breakdowns.

## Cleanup and removal

Cleanup is explicit manual maintenance. No full cleanup runs automatically at
startup.

```swift
let usage = try await diskCache.usage()
try await diskCache.removeAll(tagged: AppCache.Tags.homeFeed)
try await diskCache.removeAll(insertedBefore: Date.now.addingTimeInterval(-30 * 24 * 60 * 60))
try await diskCache.cleanup()
```

`CacheStore.cleanup()` may remove store-level temporary orphans and disk orphans.
`CacheBucket.cleanup()` is scoped to that bucket and does not remove store-level
temporary files.

`removeAll(in:)` can remove a valid old or unconfigured bucket ID under the store
root. This gives apps an explicit migration cleanup path without deleting old
bucket data automatically at startup.

```swift
try await diskCache.removeAll(in: CacheBucketID("avatars-v1"))
```

## Concurrency and cancellation

The public facade is not `MainActor`-isolated. Async operations can be called from
concurrent tasks. Disk-backed `Data` writes and file imports use internal
off-actor I/O helpers for blocking file work, then revalidate cancellation,
leases, and capacity before commit. Cancellation is preserved instead of being
turned into a generic cache error.

## Deferred from v1

GraphitCache v1 intentionally does not include:

- loader, networking, retry, or stale-while-revalidate APIs;
- SwiftUI/UIKit/AppKit adapters;
- typed value APIs or codecs;
- public kind/content-type APIs;
- public query structs;
- grouped or detailed usage reports;
- public instrumentation/events or OSLog adapter;
- public testing helper product;
- encryption, compression, or checksums.
