# SQLite metadata index

SQLite stores metadata only. Data and file payload bytes live in filesystem. `storage_ref` is a versioned root-relative path, not a deterministic in-place payload path.

## Connection

- Actor-owned/non-Sendable `SQLiteConnection` inside `CacheStoreEngine`.
- Open at disk-backed store init.
- `PRAGMA foreign_keys = ON;`
- `PRAGMA journal_mode = WAL;`
- `PRAGMA synchronous = NORMAL;`
- `PRAGMA user_version;` for schema versioning.
- Released when the owning engine deinitializes; no public `CacheStore.close()` in v1.
- Every C call maps to `CacheError.storageFailure` or `CacheError.internalInconsistency` with sqlite message string.

## Date/duration storage

Use integer microseconds since Unix epoch for dates. Use integer microseconds for expiration duration; positive sub-microsecond durations round up to 1 µs.

## Schema v1

```sql
CREATE TABLE IF NOT EXISTS entries (
    id TEXT PRIMARY KEY,
    bucket TEXT NOT NULL,
    key TEXT NOT NULL,
    payload_kind TEXT NOT NULL, -- internal: data/file
    storage_ref TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    stored_at_us INTEGER NOT NULL,
    last_accessed_at_us INTEGER,
    expires_at_us INTEGER,
    expiration_kind TEXT NOT NULL,
    expiration_duration_us INTEGER,
    UNIQUE(bucket, key)
);

CREATE TABLE IF NOT EXISTS tags (
    entry_id TEXT NOT NULL,
    tag TEXT NOT NULL,
    PRIMARY KEY (entry_id, tag),
    FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE
);
```

No `kind`, `content_type`, `codec_id`, `priority`, checksum, or usage-breakdown columns in v1.

## Lean index set

Start only with indexes required by current selectors and eviction policies:

```sql
CREATE INDEX IF NOT EXISTS idx_entries_bucket_stored_at
ON entries(bucket, stored_at_us);

CREATE INDEX IF NOT EXISTS idx_entries_bucket_lru
ON entries(bucket, last_accessed_at_us, stored_at_us);

CREATE INDEX IF NOT EXISTS idx_entries_expires_at
ON entries(expires_at_us);

CREATE INDEX IF NOT EXISTS idx_tags_tag_entry
ON tags(tag, entry_id);
```

Rely on:

- `UNIQUE(bucket, key)` for normal per-key lookup;
- `PRIMARY KEY(entry_id, tag)` for cascade/tag ownership behavior;
- `entries.id` primary key for metadata fetches.

Add more indexes later only when measured or required by a new public selector.

## Entry ID and storage refs

`id = SHA256(bucket + "\0" + rawKey)` hex.

`storage_ref = buckets/<bucket>/<h0h1>/<h2h3>/<entryID>-<writeID>.<ext>` root-relative path under the cache root.

On lookup, compare stored `bucket/key`; mismatch => `internalInconsistency` hash collision.

## Transactions

Use transactions for:

- entry upsert + tags replace;
- write-time capacity enforcement that upserts new entry and deletes victim metadata in one transaction;
- access metadata update;
- batch removal + tag cascade;
- cleanup metadata repair.

No `await` inside transaction. Disk write transactions are coordinated by the store actor: metadata/victim changes are staged, the temp payload is moved synchronously to its final versioned path, then the transaction commits. This avoids intentionally committing metadata for a payload that has not reached its final path; crash leftovers are repaired as orphan files.

## Upsert replacement

Replacement callers pass:

- current `payload_kind` (`data` or `file`);
- `stored_at_us = now`;
- `last_accessed_at_us = NULL`.

Delete old tags and insert new tags in the same transaction. Return old `storage_ref` and old `payload_kind` so file store can delete old payload after commit or check lease policy before replacement. Failures become orphan-cleanup work.

## Removal selection

Lean v1 does not expose public query structs. Internal removal selectors support:

- all entries;
- configured bucket;
- old/unconfigured bucket for `removeAll(in:)` migration cleanup;
- tag;
- stored-before date for the public `insertedBefore` selector;
- expired entries;
- capacity eviction.

## Built-in eviction queries

LRU:

```sql
SELECT * FROM entries
WHERE bucket = ?
ORDER BY last_accessed_at_us IS NOT NULL ASC, last_accessed_at_us ASC, stored_at_us ASC
LIMIT ?;
```

Oldest inserted first:

```sql
SELECT * FROM entries
WHERE bucket = ?
ORDER BY stored_at_us ASC
LIMIT ?;
```

Victim selection excludes the new write identity and skips leased file identities.

## Usage aggregates

V1 usage only needs:

- total size;
- disk size for disk-backed buckets;
- memory size is zero for disk-backed buckets;
- entry count;
- per-configured-bucket usage.

No data/file/expired usage breakdowns in v1.

## Verification

- create/open/release DB.
- schema idempotent.
- `PRAGMA user_version` set/read correctly.
- foreign key cascade removes tags.
- query filters correct for v1 selectors.
- data/file replacement changes `payload_kind` for the same key.
- lean indexes exist; no extra speculative indexes.
- WAL files allowed under `index/`.
