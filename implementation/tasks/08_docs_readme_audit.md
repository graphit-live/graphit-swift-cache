# Task 08 — Public docs and README audit

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/13_deferred_features.md`
- `.agents/PUBLIC_API_DESIGN.md` Documentation
- `.agents/PACKAGE_RELEASE.md`

## Prereqs

- Public API mostly complete.

## Implement

- Audit/add missing documentation comments for every public type/member.
- README user docs skeleton.
- Compile-check examples where practical.

## Docs must mention

- iOS 18+ primary support and macOS 15+ package support.
- no Linux support claim in v1.
- no loader/network/UI.
- consumers own encoding/decoding; SDK stores `Data` and files.
- why `CacheKey`, `CacheTag`, and `CacheBucketID` are dedicated types instead of raw strings.
- one `CacheKey` type; one key maps to one data or file entry.
- bucket vs tag.
- no public kind/content-type API; apps can use tags if needed.
- memory-only vs disk-backed as bucket-level storage modes.
- `CacheStoreConfiguration` has one initializer; callers pass `rootDirectory: nil` for all-memory configurations and a file URL root for disk-backed or mixed configurations.
- every bucket requires `maxTotalSize`.
- LRU vs oldest-inserted-first eviction.
- usage reports are intentionally simple.
- cleanup is explicit manual maintenance; no automatic full startup cleanup.
- `removeAll(in:)` can remove old/unconfigured buckets for migrations.
- when disk-backed buckets are present, initialization performs bounded synchronous local filesystem/SQLite setup.
- one active `CacheStore` with disk-backed buckets per root; v1 does not coordinate multiple active stores sharing a root.
- disk-backed Data writes and file imports use internal off-actor I/O helpers.
- cached file URLs are lease-only and cache-managed.
- file leases must be retained for playback/long reads.
- no public close lifecycle API.
- keys/tags should not contain sensitive data if app logs them.
- no public instrumentation/events in v1.
- no public testing helper product in v1.

## Do not implement

- `CacheInstrumentation`.
- event sink.
- OSLog adapter.
- background event dispatch task.
- kind/content-type docs as public API.

## Verify

```bash
swift build
swift test
```

## Definition of done

- Every public symbol has doc comment.
- README matches implemented API and lean-v1 decisions.
- Examples do not show deferred APIs.
