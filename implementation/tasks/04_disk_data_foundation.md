# Task 04 — Disk-backed data foundation

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/06_internal_architecture.md`
- `implementation/08_sqlite_index.md`
- `implementation/09_disk_file_store.md`
- `implementation/11_expiration_eviction_cleanup.md`
- CryptoKit: https://developer.apple.com/documentation/cryptokit
- SQLite C API: https://www.sqlite.org/c3ref/intro.html

## Prereqs

- Tasks 00–03 done.
- Package links SQLite and `import SQLite3` works.

## Implement

- `StableKeyHasher` using CryptoKit SHA-256 hex.
- `PersistentFileStore` root/index/buckets/tmp creation and path planning.
- Best-effort backup exclusion on created directories.
- `SQLiteConnection`, `SQLiteStatement`, `SQLiteSchema`, `SQLiteMetadataIndex` enough for disk data.
- Lean schema and lean index set only.
- Disk-backed `setData`, `data`, `dataInfo`, exact-key remove, store/bucket remove APIs.
- Disk-backed data temp write through a tiny `@concurrent` helper.
- Versioned root-relative `storage_ref` for every write.
- Data persistence across store recreation.
- Disk-backed usage using simplified usage fields.

## Required behavior

- SQLite stores metadata only; Data payload bytes are filesystem files.
- Raw keys never appear in paths.
- Replacement writes a new versioned storage ref.
- Replacement resets `storedAt` and `lastAccessedAt`.
- Capacity failures leave no new metadata/file.
- Disk commit moves temp payloads to final versioned paths before SQLite commit; crash leftovers are orphan files, not committed metadata for missing files.
- No `await` inside SQLite transactions.
- Revalidate after the `@concurrent` temp write before commit.

## Do not implement yet

- file payload import/lease behavior.
- orphan final-file cleanup beyond temp best-effort needed for failed writes.
- extra speculative SQLite indexes.
- public hasher protocol.

## Verify

```bash
swift build
swift test --filter DiskData
swift test --filter SQLite
swift test --filter DiskStore
```

## Definition of done

- Disk-backed data path is complete end-to-end through public API.
- Same bucket/key has stable entry ID across process runs.
- Each write has a unique versioned storage ref.
- Data write I/O does not run inside the store actor.
