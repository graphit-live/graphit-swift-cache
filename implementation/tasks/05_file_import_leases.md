# Task 05 — File import + leases

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/04_public_api_operations.md`
- `implementation/09_disk_file_store.md`
- `implementation/12_file_leases.md`
- `.agents/SWIFT_CONCURRENCY_6_3.md`

## Prereqs

- Tasks 00–04 done.

## Implement

- `CachedFileLease` internals.
- `LeaseTable`, `LeaseToken` using `Synchronization.Mutex`.
- `fileInfo(for:)`.
- `leaseFile(_:)`.
- `setFile(at:for:options:)`.
- File extension resolution.
- File import to temp through a tiny `@concurrent` helper.
- Data/file same-key replacement semantics.
- Exact-key remove for file entries.
- Bulk removal skip/report leased files.

## Required behavior

- All file APIs on memory-only buckets throw `unsupportedFileStorage`.
- Source file remains caller-owned after import.
- File size comes from file attributes or copied-file attributes, not loading bytes into `Data`.
- Returned URL is cache-managed and protected by a retained lease.
- Direct leased remove/replacement throws `fileIsLeased`.
- Bulk removal/cleanup skips leased files and increments `skippedLeasedEntries`.
- `release()` is synchronous and idempotent; `deinit` releases synchronously.
- Revalidate cancellation/lease/capacity after the `@concurrent` file copy before commit.

## Do not implement

- public move mode.
- public unleased URL API.
- file bytes in memory.
- MIME/content-type handling.
- task in lease `deinit`.

## Verify

```bash
swift build
swift test --filter File
swift test --filter Lease
```

## Definition of done

- Files are imported, leased, removed, and replaced correctly through public APIs.
- Playback docs/examples retain lease beyond `play()` call.
- Same-key data/file replacement semantics are tested.
