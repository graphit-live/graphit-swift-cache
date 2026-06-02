# Task 03 — Memory expiration, eviction, removal, usage

If implementation shifts from this task/spec, stop and align before continuing.

## Refs

- `implementation/10_memory_engine.md`
- `implementation/11_expiration_eviction_cleanup.md`
- `implementation/05_public_api_usage_results_clock_errors.md`
- `.agents/PERFORMANCE_MEMORY.md`

## Prereqs

- Tasks 00–02 done.

## Implement

Memory-only behavior for:

- expiration resolution at write;
- fixed/sliding/never read behavior;
- access metadata update on `data`, not `dataInfo`;
- max total size, max item size, max item count;
- LRU and oldest-inserted-first eviction;
- `removeAll(tagged:)`;
- `removeAll(insertedBefore:)`;
- bucket/store `usage()` using simplified usage fields;
- bucket/store `cleanup()` for expired entries and capacity enforcement in memory.

## Required behavior

- Expired entries behave absent.
- Sliding expiration extends only on payload read.
- New write identity is never selected as a same-write eviction victim.
- Capacity failure leaves new entry absent.
- Usage reports total/memory/disk sizes and entry counts only.

## Do not implement

- data/file/expired usage detail fields.
- largest-first or priority eviction.
- public query structs.
- disk-backed behavior.

## Verify

```bash
swift build
swift test --filter MemoryPolicy
swift test --filter Expiration
swift test --filter Eviction
swift test --filter Usage
```

## Definition of done

- Memory-only cache has complete v1 behavior except disk/file features.
- Deterministic tests prove LRU, FIFO, expiration, usage, and removals.
