# Task 06 — Cleanup, old buckets, corruption/orphan recovery

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/07_validation.md`
- `implementation/09_disk_file_store.md`
- `implementation/11_expiration_eviction_cleanup.md`
- `implementation/08_sqlite_index.md`

## Prereqs

- Tasks 00–05 done.

## Implement

- Store/bucket `cleanup()` complete behavior.
- Expired entry cleanup for memory and disk.
- Disk orphan temp removal.
- Disk orphan final file removal, including stale versioned replacement payloads.
- Metadata-with-missing-file repair.
- Read-time missing-file repair.
- `removeAll(in:)` behavior for old/unconfigured bucket IDs.
- Capacity enforcement during cleanup.
- Cleanup/removal result accounting.

## Required behavior

- No automatic full startup cleanup.
- Missing payload file makes read return nil and removes metadata.
- File without metadata is removed by manual cleanup.
- `bucket(_:)` still throws for unconfigured active buckets.
- `usage()` reports configured active buckets only.
- `removeAll(in:)` validates ID shape and can remove an old bucket under the store root.
- Leased files are skipped and counted.

## Do not implement

- cache rebuild scanner as primary path unless separately aligned.
- checksum verification.
- silent swallowing of filesystem errors that should be surfaced.
- startup auto-delete of old buckets.

## Verify

```bash
swift build
swift test --filter Cleanup
swift test --filter Corruption
swift test --filter Orphan
swift test --filter OldBucket
```

## Definition of done

- Cleanup and recovery behavior is explicit, deterministic, and tested.
- Old bucket migration cleanup works without adding public query structs.
