# Package layout

## Manifest target

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "GraphitCache",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "GraphitCache", targets: ["GraphitCache"])
    ],
    targets: [
        .target(
            name: "GraphitCache",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "GraphitCacheTests",
            dependencies: ["GraphitCache"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
```

Reason: one public product keeps v1 small. iOS 18 is the primary product target. macOS 15 keeps local SwiftPM builds/tests straightforward and uses the same modern concurrency/synchronization availability floor.

No public `GraphitCacheTesting` product in v1.

## Source tree

Start small and vertical. Files may be split only when a real boundary appears.

```text
Sources/GraphitCache/
  Public/
    ByteCount.swift
    Identifiers.swift
    CacheKey.swift
    Policies.swift
    Configuration.swift
    EntryOptions.swift
    EntryInfo.swift
    CachedData.swift
    Usage.swift
    Results.swift
    Clock.swift
    Errors.swift
    CacheStore.swift
    CacheBucket.swift
    CachedFileLease.swift
  Internal/
    CacheStoreEngine.swift
    Validation.swift
    StableKeyHasher.swift
    DurationEncoding.swift
    DateEncoding.swift
    StoredPayloadKind.swift
    StorageKey.swift
  Internal/Memory/
    MemoryCacheEngine.swift
    MemoryEntry.swift
  Internal/Disk/
    PersistentFileStore.swift
  Internal/SQLite/
    SQLiteConnection.swift
    SQLiteStatement.swift
    SQLiteMetadataIndex.swift
    SQLiteSchema.swift
  Internal/Leases/
    LeaseTable.swift
    LeaseToken.swift

Tests/GraphitCacheTests/
  Support/
    TestCacheClock.swift
    TemporaryCacheDirectory.swift
  ConfigurationTests.swift
  MemoryDataTests.swift
  MemoryPolicyTests.swift
  DiskDataTests.swift
  FileLeaseTests.swift
  CleanupRecoveryTests.swift
  UsageTests.swift
  ConcurrencyCancellationTests.swift
```

The tree is a guide, not a mandate. If a vertical slice is clearer with fewer files, prefer fewer files.

## Import rules

- Public files: `Foundation` only unless unavoidable.
- `StableKeyHasher.swift`: `Foundation`, `CryptoKit`.
- `SQLite/*`: `Foundation`, `SQLite3`.
- lease table and test clock: `Synchronization`.
- no SwiftUI/UIKit/AppKit/Combine/AVFoundation/ImageIO/Photos/BackgroundTasks in core.

## Access rules

- Public only symbols in the lean v1 API contract.
- Test helpers stay in `Tests`, not a public product.
- Internal implementation remains `internal`/`private`.
- Use `package` only if cross-target package collaboration appears later; v1 should not need it.
