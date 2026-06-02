# Internal architecture

## Public facade

```swift
public final class CacheStore: Sendable {
    public let configuration: CacheStoreConfiguration
    private let engine: CacheStoreEngine
}

public struct CacheBucket: Sendable {
    public let id: CacheBucketID
    public let policy: BucketPolicy
    internal let engine: CacheStoreEngine
}
```

Why class store: identity/resource ownership. Why struct bucket: cheap handle, no independent lifecycle. `CacheStore` keeps an immutable validated bucket/policy snapshot so `bucket(_:)` remains synchronous without actor hops.

## State ownership

```text
CacheStore
  owns CacheStoreEngine actor
CacheStoreEngine actor
  owns normalized config, memory engine, SQLite connection, file store, lease table
MemoryCacheEngine
  synchronous component; actor-owned only
SQLiteConnection
  non-Sendable; actor-owned only
LeaseTable
  Sendable Mutex-protected; shared by engine + lease tokens
PersistentFileStore
  file helper; blocking writes/copies run through tiny @concurrent helpers
```

No hidden globals. No service locator. No public actor isolation.

## Vertical slice implementation

Build in behavior-first slices:

1. public API shell + validation;
2. memory-only data set/get/remove end-to-end;
3. memory expiration/eviction/usage;
4. disk-backed data set/get/remove end-to-end;
5. file import and leases;
6. cleanup, orphan repair, concurrency/cancellation hardening.

This keeps tests tied to user-visible behavior and lets internals evolve without API churn.

## Actor policy

- `CacheStoreEngine` serializes state/index coordination.
- Reentrancy rule: no invariant may span `await` without revalidation.
- SQLite transactions contain no `await`.
- Data and file disk I/O that may block must not run inside the store actor.
- Data APIs store caller-provided bytes; no SDK encoding/decoding layer.

## Disk I/O shape

Disk-backed `setData` and `setFile` both use a two-phase shape.

Data write:

```text
actor: validate bucket/key/options/size, check old leased file, plan temp destination
@concurrent file helper: write Data -> temp
actor: revalidate cancellation/lease/capacity
actor transaction: upsert metadata/tags and delete selected victim metadata
actor: move temp -> final versioned path
actor: commit transaction
post-commit: delete old/victim payload files best effort
```

File import:

```text
actor: validate bucket/key/policy/source metadata, check old leased file, plan temp destination
@concurrent file helper: copy source -> temp without loading whole file
actor: revalidate cancellation/lease/capacity
actor transaction: upsert metadata/tags and delete selected victim metadata
actor: move temp -> final versioned path
actor: commit transaction
post-commit: delete old/victim payload files best effort
```

Use `@concurrent` only on tiny internal helpers where the intent is to leave the caller/actor context for blocking file I/O. No `Task.detached`. No `await` inside SQLite transactions.

## Internal payload kind

Use an internal enum only:

```swift
internal enum StoredPayloadKind: String, Sendable {
    case data
    case file
}
```

This records the current payload shape in SQLite and memory metadata without exposing a public payload-kind API. It does not participate in stable entry ID hashing because one key maps to one entry.

## Operation pattern

Facade method:

```swift
public func setData(_ data: Data, for key: CacheKey, options: CacheEntryOptions) async throws {
    try await engine.setData(data, bucket: id, key: key, options: options)
}
```

Engine method flow:

```text
validate input/config
prepare metadata/storage ref
write memory or disk/index atomically
update access/expiration for payload reads
run write-time capacity enforcement
return public result
```

## Cancellation

- Check before side effects.
- Check after expensive disk helper work and before commit.
- If cancelled before commit: remove temp files, no entry remains.
- If cancelled during cleanup: completed removals stay removed.
- Preserve `CancellationError` where thrown by task checks.

## Sendable audit targets

- all public values: `Sendable`.
- `CacheStore`: stores actor + immutable configuration snapshot.
- `CachedFileLease`: final class with Sendable token.
- `LeaseTable`: tiny `Synchronization.Mutex` protected state; no unchecked Sendable needed if compiler accepts the shape.
- no unchecked Sendable unless separately justified.

## Resource lifecycle

- No public `close()` in v1.
- `CacheStore` creates the engine; `CacheBucket` handles also retain it so bucket handles remain usable when passed around.
- SQLite/file handles should have internal deterministic cleanup through ownership/deinit when no public handles retain the engine, but callers do not manage shutdown.
- Disk-backed lease and removal coordination is store-local; v1 expects one active disk-backed store per root instead of hidden global coordination.
