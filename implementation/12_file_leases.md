# File leases

Purpose: prevent deleting or replacing active cached files during playback or long reads.

## Public behavior

```swift
public func leaseFile(_ key: CacheKey) async throws -> CachedFileLease?
```

- missing/expired/data entry -> nil.
- increments lease count before returning.
- normal eviction/cleanup skips leased files.
- direct `remove(_:)` or same-key `setData`/`setFile` of a leased file throws `CacheError.fileIsLeased(bucket:key:)`.
- `release()` is synchronous and idempotent.

## Internal model

```swift
internal final class LeaseTable: Sendable {
    private let state: Mutex<[LeaseIdentity: Int]>
    func acquire(_ identity: LeaseIdentity) -> LeaseToken
    func isLeased(_ identity: LeaseIdentity) -> Bool
}

internal final class LeaseToken: Sendable {
    func release()
    deinit { release() }
}
```

`LeaseIdentity` is internal and includes bucket + raw key. Public API does not expose payload kind.

The lease table is store-local. V1 expects one active `CacheStore` with disk-backed buckets per root; multiple active stores sharing a root could bypass each other's lease table and are unsupported instead of adding hidden global coordination.

Why lock table, not actor: `deinit` cannot `await`; no unstructured task allowed. State is tiny and synchronous. V1 targets iOS 18/macOS 15, so `Synchronization.Mutex` is available.

## Race rules

- acquire after file existence/metadata validation, before returning URL.
- removal and same-key replacement check lease table immediately before deleting or replacing a file.
- if cleanup selects victim then lease appears before delete: recheck and skip.
- if a leased payload file is externally deleted or missing, new reads/leases return nil but metadata repair is deferred until release.
- release does not auto-delete pending removals in v1; next cleanup/removal can delete.

## Usage examples

Short synchronous file use:

```swift
if let lease = try await files.leaseFile(key) {
    defer { lease.release() }
    try processFile(at: lease.url)
}
```

Playback/long async use: retain the lease for the whole playback lifetime.

```swift
@MainActor
final class ReelPlayerModel: ObservableObject {
    private let videos: CacheBucket
    private var lease: CachedFileLease?

    func play(reelID: String) async throws {
        stop()
        guard let lease = try await videos.leaseFile(.reel(reelID)) else { return }
        self.lease = lease
        player = AVPlayer(url: lease.url)
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
        lease?.release()
        lease = nil
    }
}
```

Do not release immediately after calling a player method that returns before playback finishes.

## Do not

- do not start a task in `deinit`.
- do not use `unowned(unsafe)`.
- do not expose lease count publicly.
- do not store file bytes in lease.

## Verification

- lease count increments/decrements.
- double release safe.
- deinit releases without async work.
- direct exact-key removal and same-key replacement while leased throw.
- bulk cleanup reports skipped leased.
- missing-file repair is deferred while leased and succeeds after release.
- after release, cleanup/removal succeeds.
