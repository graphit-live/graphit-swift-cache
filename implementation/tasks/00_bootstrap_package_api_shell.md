# Task 00 — Bootstrap package and API shell

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/01_package_layout.md`
- `implementation/02_public_api_values.md`
- `implementation/03_public_api_policies_config.md`
- `implementation/04_public_api_operations.md`
- `implementation/05_public_api_usage_results_clock_errors.md`
- `.agents/PACKAGE_RELEASE.md`
- `.agents/PUBLIC_API_DESIGN.md`

## Prereqs

- `swift --version` shows 6.3.x.
- `git status --short` reviewed; no unrelated overwrite.

## Implement

- Create `Package.swift` with tools version 6.3.
- Platforms: `.iOS(.v18)`, `.macOS(.v15)`.
- Public product: `GraphitCache` only.
- Targets: `GraphitCache`, `GraphitCacheTests`.
- Link system SQLite via `.linkedLibrary("sqlite3")`.
- Add compile-ready public API declarations matching Draft 4:
  - values/keys/tags/buckets;
  - policies/config/options;
  - info/data/usage/results/clock/errors;
  - `CacheStore`, `CacheBucket`, `CachedFileLease` facades with placeholder internals where needed.
- Public doc comments for every public symbol introduced.
- Add smoke tests only as needed for test discovery.

## Do not implement

- storage behavior beyond minimal placeholders.
- public testing product.
- UI/platform adapters.
- codecs/loaders/kind/content-type/query/instrumentation APIs.
- `Task.detached`.

## Verify

```bash
swift package describe
swift build
swift test
```

## Definition of done

- Package resolves/builds/tests empty/smoke suite.
- Public API shape matches Spec Draft 4.
- No extra public symbols.
- No UI imports.
