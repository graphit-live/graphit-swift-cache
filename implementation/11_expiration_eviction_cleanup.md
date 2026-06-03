# Expiration, eviction, cleanup

## Expiration resolution at write

Input: bucket `CacheExpirationPolicy` + `now`.

```text
never -> expiration mode never, expires nil
fixed(d) -> expiration mode fixed, duration d, expires now + d
sliding(d) -> expiration mode sliding, duration d, expires now + d
```

Persist resolved expiration mode/duration/expires. Future bucket config changes do not retroactively change existing entries.

## Read behavior

- missing -> nil.
- wrong payload shape for requested API -> nil.
- expired -> lazy remove/repair + nil.
- missing unleased payload metadata -> lazy repair + nil.
- missing leased file payload metadata -> nil, but repair is deferred until release.
- fixed -> no extension.
- sliding payload read -> update `lastAccessedAt` and `expiresAt = now + duration`.
- `dataInfo`/`fileInfo` do not update access metadata or sliding expiration.

## Capacity enforcement

Preconditions:

- if `size > maxItemSize`: throw `itemTooLarge`.
- if `size > maxTotalSize`: throw `capacityCannotBeSatisfied(.totalSize)` before storing.
- if item count cannot be satisfied after evicting eligible old entries: throw `capacityCannotBeSatisfied(.itemCount)` before storing.

Write rule: new entry should not be victim of the same write. If capacity cannot fit after evicting eligible old entries, throw and leave new entry absent.

Disk-backed algorithm:

```text
calculate current size/count excluding old same-key entry
required = postWrite - limits
select victims excluding new identity and leased files
if evictable insufficient: throw capacityCannotBeSatisfied
stage new metadata and victim metadata deletion in one SQLite transaction
move temp payload to final versioned path
commit SQLite transaction
remove old/victim files after commit; failed deletes become orphan cleanup work
```

Memory-only algorithm mirrors disk logic in memory.

## Built-in eviction policies

- LRU: oldest `lastAccessedAt`, nil first, tie `storedAt`.
- Oldest inserted first: oldest `storedAt`.

No largest-first, priority, protected, or custom eviction in v1.

## Cleanup

`cleanup()` is explicit manual maintenance. It can be expensive when orphan scanning is required.

Cleanup tasks:

1. expired entries.
2. orphan temp/final files.
3. metadata rows with missing files.
4. capacity enforcement per configured bucket.

`CacheStore.cleanup()` may remove store-level temp orphans. `CacheBucket.cleanup()` is bucket-scoped and does not remove store-level temp files.

Metadata rows with missing payload files are removed when unleased. If the missing payload is a leased file, cleanup skips/counts it and repair can happen after release.

No automatic full startup cleanup.

## Manual removal

- `removeAll()` removes all entries under the store root.
- `removeAll(in:)` removes a valid bucket ID, including old/unconfigured buckets for app migrations.
- exact-key removal uses `remove(_:)` and removes the named entry unless it is a leased file.
- same-key replacement throws while an existing file is leased.
- bulk removal/cleanup skip leased files and report `skippedLeasedEntries`.
- `removeAll(insertedBefore:)` uses strict `storedAt < date`.

## Result accounting

- removed bytes = authoritative bytes removed.
- skipped leased count for leased file candidates not removed.
- failures throw instead of being reported as partial-result counters.
- cleanup result keeps expired/orphan/evicted counters; usage does not expose expired breakdowns.

## Verification

- expired entries never returned.
- sliding extends on payload reads.
- LRU and FIFO proven by tests.
- new large write not immediately evicted.
- capacity unsatisfied leaves no new file/metadata.
- old/unconfigured bucket removal works through `removeAll(in:)`.
- cleanup result counts match actual removals.
