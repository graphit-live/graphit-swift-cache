# Memory engine

Purpose: deterministic in-memory authoritative storage for `.memoryOnly` buckets. Do not expose or rely on `NSCache` as the storage model.

## Modes

- `.memoryOnly`: memory is authoritative; supports `Data` entries only.
- `.diskBacked`: no hot memory tier in v1.

## Stored representation

```swift
internal struct MemoryEntry: Sendable {
    let bucket: CacheBucketID
    let key: CacheKey
    var data: Data
    var info: CacheEntryInfo
    var cost: ByteCount
}
```

Cost = `data.count`.

## Accounting

- `.memoryOnly` total size uses entry costs.
- `maxTotalSize` is required.
- `maxItemSize` and `maxItemCount` are optional secondary limits.
- File entries are not stored in memory-only buckets.
- Usage reports only total/memory/disk size and entry count.

## Eviction metadata

Maintain dictionary by internal storage key plus deterministic ordering support.

Need support:

- LRU updates on payload read;
- stored order for FIFO;
- cost accounting;
- per-bucket count/size limits.

Simplest v1: dictionary + sorted arrays on enforcement. If performance fails benchmarks, replace internals without changing public API.

## Operations

- `dataInfo`: metadata check; expired behaves absent; no access update.
- `fileInfo`: always nil for memory-only data storage.
- `data`: return `CachedData`; update access metadata and sliding expiration.
- `setData`: insert/update, enforce capacity.
- `remove`: exact-key removal.
- `removeAll`: selectors for all/tag/insertedBefore/expired/capacity.
- `usage`: derive from memory metadata.

## Verification

- deterministic LRU eviction.
- deterministic FIFO eviction.
- size/count limits enforced.
- expired entries not returned.
- sliding expiration extends on `data`, not info.
- usage snapshots accurate for memory-only simplified usage API.
