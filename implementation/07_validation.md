# Validation rules

Constructors are nonthrowing. Validate before side effects where possible. Runtime input failure: `CacheError.invalidInput(String)`.

## Text values

Reject when used:

| Type | Rule |
|---|---|
| `CacheBucketID` | non-empty; ASCII letters/numbers/`.`/`_`/`-` only; not `.` or `..`; length <= 128 |
| `CacheTag` | non-empty; no NUL/control; length <= 256 |
| `CacheKey` | non-empty; no NUL/control; length <= 4096 |
| `CacheFileOptions.fileExtension` | if provided: non-empty after optional leading dot; no path separators; no NUL/control; length <= 32 |

Bucket IDs are strict because they appear in generated cache paths. Raw keys never appear in paths.

There is no public kind or content-type validation in v1.

## Sizes/counts

- `ByteCount.bytes >= 0` wherever policy/input validated.
- `maxTotalSize > 0` required for every bucket.
- `maxItemSize > 0` if present.
- `maxItemSize <= maxTotalSize` if present.
- `maxItemCount > 0` if present.

Do not support a special zero-size max-item edge case in v1. It is niche and complicates validation/capacity behavior.

## Durations

- `.fixed(duration)` and `.sliding(duration)` require positive duration.
- Store dates/durations as integer microseconds; positive sub-microsecond durations round up to 1 µs.
- No public duration helper extensions in v1.

## Store configuration

- bucket IDs unique for configured active buckets.
- root `nil` valid only if every bucket is `.memoryOnly`.
- root non-`nil` requires at least one `.diskBacked` bucket; all-memory stores must use `nil`.
- disk-backed root must be a file URL.
- `.diskBacked` buckets require root.
- when disk-backed buckets are present, init creates root/index/buckets/tmp dirs or throws `storageFailure`.
- operational contract: one active `CacheStore` with disk-backed buckets per root; v1 does not add hidden global registries or cross-store locks.
- `bucket(_:)` throws `unknownBucket` for unconfigured buckets.
- `removeAll(in:)` validates the bucket ID shape but may target an old/unconfigured bucket under the store root.

## Bucket policy

- `.memoryOnly`: supports data entries only; all file APIs throw `unsupportedFileStorage(storageMode: .memoryOnly)`.
- `.diskBacked`: supports data and file entries.
- `maxTotalSize` applies to authoritative storage: memory for memory-only, disk/index for disk-backed.

## Entry options

- tags validated as a set; duplicate tags collapse by value semantics.
- no kind/content-type metadata in v1.
- no priority/protected options in v1.
- no per-entry expiration in v1.

## Files

- `sourceURL.isFileURL == true`.
- file exists and is regular readable file.
- size from file attributes; never load file for size.
- memory-only `setFile` throws `unsupportedFileStorage(storageMode: .memoryOnly)`.
- explicit `fileExtension` is validated and normalized without a leading dot.
- if no explicit extension exists, use a valid source URL path extension if available; otherwise use `bin`.

## Error mapping

- invalid config: `invalidConfiguration` / `duplicateBucket` / `unknownBucket`.
- invalid runtime key/options/file URL shape: `invalidInput` unless a more specific case exists.
- source missing/unreadable: `sourceFileNotFound` / `sourceFileUnreadable`.
- SQLite/filesystem/import failures: `storageFailure`.
- item over max item: `itemTooLarge`.
- cannot satisfy bucket capacity: `capacityCannotBeSatisfied(bucket:constraint:)`.
