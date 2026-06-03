# Testing strategy

Goal: confidence, not volume. Prefer vertical scenario tests that fail for user-visible regressions.

## Frameworks

- Swift Testing for most tests.
- XCTest later for performance benchmarks only.
- No sleeps; use internal `TestCacheClock` and explicit synchronization.
- Each disk test uses unique temporary directory; no shared mutable state.
- V1 platform floor allows `Synchronization.Mutex` for test clock state.

## Test support

Internal test helpers under `Tests/GraphitCacheTests/Support`:

```swift
final class TestCacheClock: CacheClock, Sendable
struct TemporaryCacheDirectory: Sendable
```

No public `GraphitCacheTesting` product in v1.

## Vertical suites

1. Public values/configuration: duplicate buckets, strict bucket ID rules, root rules, required `maxTotalSize`, invalid limits, `CacheKey` raw-value behavior.
2. Memory-only data: set/get/info/remove, tags, same-key replacement, rejects file APIs.
3. Memory policies: fixed/sliding/never expiration, LRU, oldest-inserted-first, max item/count/total limits, simplified usage.
4. Disk-backed data: persistence across store recreation, versioned storage refs, two-phase temp write, replacement resets metadata, capacity failures leave no entry.
5. Files and leases: import copy semantics, source remains, leased managed URL, data/file same-key replacement, leased replacement/removal failure, bulk skip.
6. Cleanup/recovery: expired cleanup, store-level temp orphans, bucket-scoped final orphans, metadata missing file, missing leased payload repair after release, old/unconfigured bucket `removeAll(in:)`.
7. Usage: total/per-bucket size/count, memory/disk split only.
8. Concurrency/cancellation: concurrent sets/gets, same-key replacement, cleanup while leasing/reading, cancellation before commit.
9. Resource lifecycle: resources release when no store/bucket handles remain; no public close API; disk tests use isolated roots because v1 supports one active `CacheStore` with disk-backed buckets per root.

## Minimal verification command set

```bash
swift build
swift test
swift test --filter Configuration
swift test --filter Memory
swift test --filter DiskData
swift test --filter Lease
```

Filter names final after tests exist.

## Quality bar per test

- Proves public behavior, not private steps.
- Deterministic clock/path/input.
- Clear failure assertion.
- No real network.
- No wall-clock sleeps.
- Parallel-safe unless marked serialized with reason.

## Do not add

- protocols only for mocks.
- broad mock framework.
- huge fixture hierarchy.
- tests that only mirror implementation lines.
- vanity coverage.
