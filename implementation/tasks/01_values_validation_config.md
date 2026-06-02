# Task 01 — Public values, validation, config, clock, errors

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/02_public_api_values.md`
- `implementation/03_public_api_policies_config.md`
- `implementation/05_public_api_usage_results_clock_errors.md`
- `implementation/07_validation.md`
- `.agents/PUBLIC_API_DESIGN.md`
- `.agents/TESTING_QUALITY.md`

## Prereqs

- Task 00 done.

## Implement

- Full implementations for:
  - `ByteCount`;
  - `CacheBucketID`, `CacheTag`, `CacheKey` as `RawRepresentable` values without string-literal conformance;
  - `CacheStorageMode` without `Codable`;
  - `CacheExpirationPolicy`, `CacheEvictionPolicy`;
  - `BucketPolicy`, `BucketConfiguration`, `CacheStoreConfiguration`;
  - `CacheEntryOptions`, `CacheFileOptions`;
  - `CacheEntryInfo` with required/defaulted initializer;
  - `CachedData` public initializer;
  - simplified `CacheUsage`/`BucketUsage` SDK-produced snapshots;
  - result public initializers and `empty` values;
  - `CacheClock`, `SystemCacheClock`;
  - `CacheCapacityConstraint`, `CacheError` descriptions.
- Internal validation helpers for text values, file extensions, policies, config, and options.
- Test-only `TestCacheClock` and `TemporaryCacheDirectory` using `Synchronization.Mutex` where useful.

## Required decisions

- `CacheEntryInfo.key` is `CacheKey`.
- `CacheEntryInfo` initializer requires `bucket`, `key`, `size`, `storedAt`; optional metadata defaults to empty/nil.
- Do not default `storedAt` to `Date()`.
- Usage has no data/file/expired breakdowns and no public initializer requirement.

## Do not implement

- `CacheKind`, `CacheContentType`, codecs, typed values.
- duration convenience extensions.
- public payload kind.
- public query structs.
- public testing product.

## Verify

```bash
swift build
swift test --filter Configuration
swift test --filter Value
swift test --filter Clock
```

## Definition of done

- Validation tests cover bucket ID whitelist and length <= 128, key/tag rules, file extension rules, root rules, duplicate buckets, size/count/duration limits.
- Public values conform exactly as specified.
- Runtime storage/eviction modes do not accidentally conform to `Codable`.
