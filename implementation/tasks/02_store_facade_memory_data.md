# Task 02 — Store facade + memory-only data end-to-end

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/04_public_api_operations.md`
- `implementation/06_internal_architecture.md`
- `implementation/10_memory_engine.md`
- `.agents/SWIFT_CONCURRENCY_6_3.md`

## Prereqs

- Tasks 00–01 done.

## Implement

- `CacheStore` init, `bucket(_:)`, `configuredBuckets()`.
- `CacheBucket` handle retaining the engine and exposing validated policy snapshot.
- `CacheStoreEngine` actor with normalized active bucket registry.
- `MemoryCacheEngine` synchronous actor-owned component.
- Memory-only public behavior:
  - `setData`;
  - `data`;
  - `dataInfo`;
  - exact-key `remove(_:)`;
  - bucket `removeAll()`;
  - store `removeAll()` for memory entries.
- Basic replacement semantics for memory-only data entries.
- File APIs on memory-only buckets throw `unsupportedFileStorage(storageMode: .memoryOnly)`.

## Do not implement yet

- disk storage or SQLite.
- expiration/eviction beyond simple capacity checks required to keep tests passing.
- file leases.
- cleanup/orphan scanning.
- usage beyond simple memory totals if not needed until Task 03.

## Verify

```bash
swift build
swift test --filter Store
swift test --filter MemoryData
```

## Definition of done

- A caller can configure a memory-only store, get a bucket, set/read/info/remove `Data` through public API.
- Unknown active bucket throws synchronously.
- Bucket handles remain usable after being passed around because they retain the engine.
- No public `close()`.
- No core `MainActor` isolation.
