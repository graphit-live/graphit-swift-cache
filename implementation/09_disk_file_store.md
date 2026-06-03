# Disk file store

Disk-backed payload bytes live in filesystem. SQLite stores a versioned root-relative `storage_ref` path.

## Layout

```text
GraphitCacheRoot/
  index/metadata.sqlite[,-wal,-shm]
  buckets/<bucket>/<h0h1>/<h2h3>/<entry-id>-<write-id>.<ext>
  tmp/<uuid>.tmp
```

`entry-id` = SHA-256 hex of `bucket + "\0" + rawKey`. `write-id` is unique per write attempt. Paths never use raw keys. Replacements never overwrite the old payload path in place.

## Extension choice

Data payloads use `bin`.

File payloads use:

1. explicit `CacheFileOptions.fileExtension`;
2. source URL path extension if present and valid;
3. `bin`.

The extension is for file-path usability only. It is not MIME/content-type metadata. Lookup never depends on extension; metadata does.

## Directory creation

During `CacheStore` initialization when disk-backed buckets are present:

- create root/index/buckets/tmp.
- apply backup exclusion best-effort to created dirs.
- no Documents default; caller supplies root.
- one active `CacheStore` with disk-backed buckets owns the root at a time; v1 does not coordinate multiple stores sharing a root.

Backup exclusion:

```swift
var values = URLResourceValues()
values.isExcludedFromBackup = true
try? url.setResourceValues(values)
```

No public file-protection policy in v1.

## Disk-backed data write

Disk-backed `Data` writes use the same two-phase shape as file imports so blocking file I/O does not run inside the store actor.

```text
actor: validate key/options/size, check existing leased file, plan temp path
@concurrent file helper: write Data -> tmp under same root
actor: revalidate cancellation/lease/capacity
actor transaction: upsert metadata + tags and delete selected victim metadata
actor: move tmp -> final versioned path
actor: commit transaction
post-commit: remove old/victim storage_refs best effort
on failure: rollback; remove tmp; orphan cleanup handles leftovers
```

No `Task.detached`. No `await` inside SQLite transactions; the final same-volume move is synchronous and part of the actor commit path.

## File import

```text
actor validates/plans temp path
@concurrent file helper copies source -> tmp without loading into Data
validate copied size
actor revalidates cancellation/lease/capacity
choose versioned final storage_ref
actor transaction: upsert metadata + tags and delete selected victim metadata
actor: move tmp -> final versioned path
actor: commit transaction
post-commit: remove old/victim storage_refs best effort
source remains caller-owned
```

No public move mode in v1.

## Atomic replacement

Same key replaces previous entry.

- tags replaced, not merged.
- old file not removed before new versioned file is committed in metadata.
- final path is always new for replacement.
- a crash after final move but before SQLite commit leaves a file orphan, not committed metadata pointing at a missing file.
- replacement resets `storedAt` and `lastAccessedAt`.
- file -> data or file -> file replacement throws while the old file is leased.

## Corruption/orphan handling

- temp files: remove on store cleanup; bucket cleanup does not remove store-level temp files.
- file without metadata: remove as orphan.
- metadata without file: remove metadata when unleased; read returns nil.
- metadata for a missing leased file payload is retained until release; new reads/leases return nil and cleanup skips/counts it.
- unreadable file: remove if safe or throw mapped storage error.

## Verification

- no raw key substring in path.
- source file still exists after `setFile`.
- imported file URL under root.
- file import does not load file bytes into memory.
- data temp write and file copy do not run inside the store actor.
- replacement never overwrites old bytes in place.
- stale versioned payloads are cleaned as orphans.
