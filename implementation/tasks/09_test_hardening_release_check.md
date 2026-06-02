# Task 09 — Test hardening and release check

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/14_testing_strategy.md`
- `.agents/TESTING_QUALITY.md`
- `.agents/SWIFT_CONCURRENCY_6_3.md`
- `.agents/PACKAGE_RELEASE.md`

## Prereqs

- Implementation feature-complete.

## Implement/check

- Remove low-value duplicate tests.
- Add missing high-signal scenario tests from strategy doc.
- Ensure public behavior is covered:
  - config validation;
  - memory-only data;
  - memory policies;
  - disk-backed data;
  - files and leases;
  - expiration/eviction/cleanup;
  - old bucket removal;
  - simplified usage;
  - corruption/orphan recovery;
  - concurrency/cancellation;
  - resource lifecycle.
- Add memory/resource tests where feasible:
  - lease deinit releases;
  - temp files cleaned after failed/cancelled write;
  - stale versioned payload files cleaned as orphans after replacement.
- Audit public API for accidental deferred types or fields.
- Audit SQLite schema for speculative indexes.
- Run debug and release builds if practical.

## Quality gates

- deterministic paths/clocks.
- no sleeps.
- no real network.
- tests parallel-safe by default.
- failures assert public behavior.
- no concurrency warnings.
- no public API outside Draft 4 without explicit alignment.

## Verify

```bash
swift build
swift build -c release
swift test
swift test --parallel
```

If `--parallel` exposes SQLite temp contention, fix test isolation; do not serialize whole suite unless aligned.

## Definition of done

- Meaningful coverage of handwritten core behavior.
- No concurrency warnings.
- Known untested risks documented as follow-up.
- Test count justified by regression value, not coverage vanity.
