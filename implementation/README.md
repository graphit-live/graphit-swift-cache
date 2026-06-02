# GraphitCache implementation plan

Purpose: implement the lean v1 described by `Spec.md` Draft 4. V1 is a bounded `Data` + file cache. Consumers own model encoding/decoding and app-level categorization.

## Source order

1. `AGENTS.md`: engineering standard.
2. Relevant `.agents/*` companion guides.
3. `Spec.md`: lean v1 product/API contract.
4. `implementation/*.md`: implementation notes.
5. `implementation/tasks/*.md`: vertical implementation slices.

## Local docs map

- `00_decisions.md`: locked lean-v1 decisions.
- `01_package_layout.md`: SwiftPM products/targets/files.
- `02_public_api_values.md`: public byte counts, identifiers, tags, keys, storage mode.
- `03_public_api_policies_config.md`: expiration/eviction/policies/config/options.
- `04_public_api_operations.md`: `CacheStore`, `CacheBucket`, cached payloads, file leases.
- `05_public_api_usage_results_clock_errors.md`: simplified usage, results, clock, errors.
- `06_internal_architecture.md`: actor ownership, vertical slices, `@concurrent` I/O helpers.
- `07_validation.md`: validation rules.
- `08_sqlite_index.md`: metadata schema and lean indexes.
- `09_disk_file_store.md`: paths, atomic writes, imports, orphans.
- `10_memory_engine.md`: memory-only authoritative storage.
- `11_expiration_eviction_cleanup.md`: expiration, LRU/FIFO, cleanup.
- `12_file_leases.md`: lease model and player lifetime guidance.
- `13_deferred_features.md`: deferred codecs/kind/content/instrumentation rationale.
- `14_testing_strategy.md`: high-signal vertical test plan.
- `tasks/*.md`: behavior-first implementation slices.

## Global task protocol

Before task:
- read this file, `00_decisions.md`, relevant design docs, task file, and companion guides.
- check `swift --version`; require Swift 6.3.x.
- check `git status --short`; do not overwrite unrelated work.

During task:
- implement one vertical behavior slice at a time.
- add public doc comments as public symbols are introduced.
- do not add removed/deferred public APIs.
- no UI imports, networking wrappers, loader APIs, hot memory tier, codecs, public kind/content-type API, event sink, public testing product, or third-party Swift deps.
- no `Task.detached`; use tiny reviewed `@concurrent` helpers for disk I/O that must run outside the store actor.
- if reality shifts from task/spec: stop, document delta, and align before coding through it.

After task:
- run verification commands.
- leave clear follow-up notes for deferred work; do not hide TODOs in code.

## Why vertical slices

Implementation should prove public behavior before deep internal layering. Start with memory-only data end-to-end, then add disk-backed data, then files/leases, then cleanup/recovery. This keeps the design easy to refactor, hard to break, and aligned with the package standard: small modules, clear ownership, no fake abstractions, and tests that prove user-visible behavior.
