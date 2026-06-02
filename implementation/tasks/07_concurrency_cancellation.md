# Task 07 — Concurrency and cancellation hardening

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/06_internal_architecture.md`
- `implementation/09_disk_file_store.md`
- `implementation/12_file_leases.md`
- `.agents/SWIFT_CONCURRENCY_6_3.md`
- `.agents/TESTING_QUALITY.md`

## Prereqs

- Tasks 00–06 done.

## Implement/check

- Audit every `await` inside `CacheStoreEngine` for revalidation needs.
- Ensure SQLite transactions contain no `await`.
- Ensure disk-backed Data temp writes and file imports use tiny `@concurrent` helpers, not `Task.detached`.
- Keep disk test roots isolated; shared active disk roots are unsupported in v1.
- Add cancellation checks:
  - before side effects;
  - after expensive disk helper work;
  - before commit.
- Best-effort temp cleanup on cancellation/failure.
- Concurrency tests:
  - concurrent sets different keys;
  - concurrent gets same key;
  - concurrent same-key replacement;
  - data replaces file when unleased;
  - file replaces data;
  - leased file blocks same-key replacement/removal;
  - cleanup while reading;
  - lease while cleanup.
- Cancellation tests:
  - cancellation before disk data commit;
  - cancellation before file import commit;
  - cleanup cancellation partial state documented.

## Do not implement

- unstructured background work.
- task in `deinit`.
- broad unchecked Sendable annotations.
- sleeps as synchronization.

## Verify

```bash
swift build
swift test --filter Concurrency
swift test --filter Cancellation
swift test --parallel
```

## Definition of done

- No concurrency warnings.
- Cancellation preserves `CancellationError` semantics.
- No partial committed entries after pre-commit cancellation.
- Tests are deterministic and parallel-safe.
