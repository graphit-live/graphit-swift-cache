# Task index

Each task is independently assignable after prerequisites. Required in every task: read `implementation/README.md`, `implementation/00_decisions.md`, task refs; if implementation shifts from task/spec, stop and align before continuing.

Lean v1 scope: bounded `Data` + file cache. No hot tier, no codecs, no typed value API, no public kind/content-type API, no priority/protection, no public query structs, no grouped/detailed usage reports, no public instrumentation, no public testing product.

## Vertical order

0. Bootstrap package and API shell.
1. Public values, validation, config, clock, errors.
2. Store facade + memory-only data end-to-end.
3. Memory expiration, eviction, removal, usage.
4. Disk-backed data foundation.
5. File import + leases.
6. Cleanup, old buckets, corruption/orphan recovery.
7. Concurrency and cancellation hardening.
8. Public docs and README audit.
9. Test hardening and release check.

Why this order: every slice proves user-visible behavior before adding deeper internals. This keeps the implementation simple, refactorable, and hard to break.
