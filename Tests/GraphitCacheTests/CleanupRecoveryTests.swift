import Foundation
import GraphitCache
import Testing

@Test func cleanupRemovesExpiredDiskEntriesAndPayloads() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let store = try cleanupStore(
        root: directory.url,
        policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5))),
        clock: clock
    )
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("expired")

    try await bucket.setData(Data([1, 2, 3]), for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    let payloadURL = directory.url.appendingStorageRefForCleanup(ref)
    #expect(FileManager.default.fileExists(atPath: payloadURL.path))

    clock.setNow(Date(timeIntervalSince1970: 5))
    let cleanup = try await store.cleanup()

    #expect(cleanup.removedExpiredEntries == 1)
    #expect(cleanup.removedExpiredBytes == .bytes(3))
    #expect(cleanup.removedOrphanedFiles == 0)
    #expect(cleanup.evictedEntries == 0)
    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(!FileManager.default.fileExists(atPath: payloadURL.path))
}

@Test func bucketCleanupRemovesOnlyThatDiskBucketExpiredEntries() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let firstID = CacheBucketID("first")
    let secondID = CacheBucketID("second")
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [
            BucketConfiguration(id: firstID, policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5)))),
            BucketConfiguration(id: secondID, policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5))))
        ],
        clock: clock
    ))
    let first = try store.bucket(firstID)
    let second = try store.bucket(secondID)

    try await first.setData(Data([1]), for: CacheKey("expired-first"))
    try await second.setData(Data([2]), for: CacheKey("expired-second"))

    clock.setNow(Date(timeIntervalSince1970: 5))
    let cleanup = try await first.cleanup()

    #expect(cleanup.removedExpiredEntries == 1)
    #expect(try await first.usage().entryCount == 0)
    #expect(try await second.usage().entryCount == 1)
}

@Test func cleanupRemovesTemporaryAndFinalOrphanFiles() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)

    let temporaryOrphan = directory.url.appendingPathComponentsForCleanup(["tmp", "orphan.tmp"])
    try writeCleanupFile(at: temporaryOrphan, data: Data([1, 2]))

    let finalOrphan = directory.url.appendingPathComponentsForCleanup(["buckets", cleanupDiskID.rawValue, "aa", "bb", "orphan.bin"])
    try writeCleanupFile(at: finalOrphan, data: Data([3, 4, 5]))

    let cleanup = try await store.cleanup()

    #expect(cleanup.removedOrphanedFiles == 2)
    #expect(cleanup.removedOrphanedBytes == .bytes(5))
    #expect(!FileManager.default.fileExists(atPath: temporaryOrphan.path))
    #expect(!FileManager.default.fileExists(atPath: finalOrphan.path))
}

@Test func bucketCleanupDoesNotRemoveStoreLevelTemporaryOrphans() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)
    let bucket = try store.bucket(cleanupDiskID)

    let temporaryOrphan = directory.url.appendingPathComponentsForCleanup(["tmp", "bucket-cleanup-should-not-remove.tmp"])
    try writeCleanupFile(at: temporaryOrphan, data: Data([1, 2]))

    let bucketCleanup = try await bucket.cleanup()

    #expect(bucketCleanup.removedOrphanedFiles == 0)
    #expect(FileManager.default.fileExists(atPath: temporaryOrphan.path))

    let storeCleanup = try await store.cleanup()
    #expect(storeCleanup.removedOrphanedFiles == 1)
    #expect(storeCleanup.removedOrphanedBytes == .bytes(2))
    #expect(!FileManager.default.fileExists(atPath: temporaryOrphan.path))
}

@Test func cleanupRemovesStaleVersionedReplacementPayloadsAsFinalOrphans() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("replacement")

    try await bucket.setData(Data([1, 2, 3]), for: key)
    let optionalCurrentRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let currentRef = try #require(optionalCurrentRef)
    let currentURL = directory.url.appendingStorageRefForCleanup(currentRef)
    let currentStem = currentURL.deletingPathExtension().lastPathComponent
    let entryID = try #require(currentStem.split(separator: "-").first.map(String.init))
    let staleURL = currentURL.deletingLastPathComponent().appendingPathComponent("\(entryID)-stale.bin")
    try writeCleanupFile(at: staleURL, data: Data([9, 9]))

    let cleanup = try await store.cleanup()

    #expect(cleanup.removedOrphanedFiles == 1)
    #expect(cleanup.removedOrphanedBytes == .bytes(2))
    #expect(FileManager.default.fileExists(atPath: currentURL.path))
    #expect(!FileManager.default.fileExists(atPath: staleURL.path))
    #expect(try await bucket.data(key)?.data == Data([1, 2, 3]))
}

@Test func cleanupCorruptionRepairsMetadataRowsWhosePayloadFilesAreMissing() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("missing-payload")

    try await bucket.setData(Data([1, 2, 3, 4]), for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    try FileManager.default.removeItem(at: directory.url.appendingStorageRefForCleanup(ref))

    let cleanup = try await store.cleanup()

    #expect(cleanup.removedExpiredEntries == 0)
    #expect(cleanup.removedOrphanedFiles == 0)
    #expect(try await bucket.usage().entryCount == 0)
    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 0)
}

@Test func readTimeCorruptionMissingDataPayloadRepairReturnsNilAndRemovesMetadata() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try cleanupStore(root: directory.url).bucket(cleanupDiskID)
    let key = CacheKey("missing-data")

    try await bucket.setData(Data([5, 6]), for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    try FileManager.default.removeItem(at: directory.url.appendingStorageRefForCleanup(ref))

    #expect(try await bucket.data(key) == nil)
    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 0)
    #expect(try await bucket.usage().entryCount == 0)
}

@Test func readTimeCorruptionMissingFilePayloadRepairReturnsNilAndRemovesMetadata() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try cleanupStore(root: directory.url).bucket(cleanupDiskID)
    let key = CacheKey("missing-file")
    let sourceURL = try writeCleanupSourceFile(in: directory.url, name: "source.bin", data: Data([7, 8]))

    try await bucket.setFile(at: sourceURL, for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    try FileManager.default.removeItem(at: directory.url.appendingStorageRefForCleanup(ref))

    #expect(try await bucket.fileInfo(for: key) == nil)
    #expect(try await bucket.leaseFile(key) == nil)
    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 0)
}

@Test func cleanupOldBucketRemoveAllInRemovesUnconfiguredDiskBucketsWithoutMakingThemActive() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let oldID = CacheBucketID("old-bucket")
    let activeID = CacheBucketID("active")
    let oldKey = CacheKey("legacy")
    let oldRef: String

    do {
        let oldStore = try CacheStore(configuration: CacheStoreConfiguration(
            rootDirectory: directory.url,
            buckets: [BucketConfiguration(id: oldID, policy: .diskBacked(maxTotalSize: .bytes(100)))],
            clock: TestCacheClock()
        ))
        let oldBucket = try oldStore.bucket(oldID)
        try await oldBucket.setData(Data([1, 2, 3, 4]), for: oldKey)
        let optionalOldRef = try cleanupStorageRef(root: directory.url, bucket: oldID.rawValue, key: oldKey.rawValue)
        oldRef = try #require(optionalOldRef)
    }

    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [BucketConfiguration(id: activeID, policy: .diskBacked(maxTotalSize: .bytes(100)))],
        clock: TestCacheClock()
    ))

    expectCacheError({
        _ = try store.bucket(oldID)
    }) { error in
        error == .unknownBucket(oldID)
    }
    let usage = try await store.usage()
    #expect(usage.buckets.map(\.bucket) == [activeID])
    #expect(usage.entryCount == 0)

    let removal = try await store.removeAll(in: oldID)

    #expect(removal == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(4)))
    #expect(!FileManager.default.fileExists(atPath: directory.url.appendingStorageRefForCleanup(oldRef).path))
    #expect(try cleanupEntryCount(root: directory.url, bucket: oldID.rawValue, key: oldKey.rawValue) == 0)
}

@Test func cleanupEnforcesDiskCapacityAfterPolicyTightening() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))

    do {
        let store = try cleanupStore(root: directory.url, policy: .diskBacked(maxTotalSize: .bytes(8)), clock: clock)
        let bucket = try store.bucket(cleanupDiskID)
        try await bucket.setData(Data([1, 1, 1, 1]), for: CacheKey("first"))
        clock.setNow(Date(timeIntervalSince1970: 1))
        try await bucket.setData(Data([2, 2, 2, 2]), for: CacheKey("second"))
    }

    let reopened = try cleanupStore(root: directory.url, policy: .diskBacked(maxTotalSize: .bytes(4)), clock: clock)
    let bucket = try reopened.bucket(cleanupDiskID)

    let cleanup = try await reopened.cleanup()

    #expect(cleanup.evictedEntries == 1)
    #expect(cleanup.evictedBytes == .bytes(4))
    #expect(try await bucket.dataInfo(for: CacheKey("first")) == nil)
    #expect(try await bucket.data(CacheKey("second"))?.data == Data([2, 2, 2, 2]))
    #expect(try await bucket.usage().totalSize == .bytes(4))
}

@Test func cleanupSkipsLeasedExpiredFilesAndRemovesThemAfterRelease() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let store = try cleanupStore(
        root: directory.url,
        policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5))),
        clock: clock
    )
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("leased-expired")
    let sourceURL = try writeCleanupSourceFile(in: directory.url, name: "leased.bin", data: Data([1, 2, 3]))

    try await bucket.setFile(at: sourceURL, for: key)
    clock.setNow(Date(timeIntervalSince1970: 1))
    let lease = try #require(try await bucket.leaseFile(key))

    clock.setNow(Date(timeIntervalSince1970: 5))
    let skipped = try await store.cleanup()
    #expect(skipped.removedExpiredEntries == 0)
    #expect(skipped.skippedLeasedEntries == 1)
    #expect(try await bucket.usage().entryCount == 1)

    lease.release()
    let removed = try await store.cleanup()
    #expect(removed.removedExpiredEntries == 1)
    #expect(removed.removedExpiredBytes == .bytes(3))
    #expect(try await bucket.usage().entryCount == 0)
}

@Test func missingLeasedFilePayloadRepairIsDeferredUntilRelease() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("leased-missing-payload")
    let sourceURL = try writeCleanupSourceFile(in: directory.url, name: "leased-missing.bin", data: Data([4, 5, 6]))

    try await bucket.setFile(at: sourceURL, for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    let lease = try #require(try await bucket.leaseFile(key))
    try FileManager.default.removeItem(at: directory.url.appendingStorageRefForCleanup(ref))

    #expect(try await bucket.fileInfo(for: key) == nil)
    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 1)

    let skipped = try await store.cleanup()
    #expect(skipped.skippedLeasedEntries == 1)
    #expect(try await bucket.usage().entryCount == 1)

    lease.release()
    _ = try await store.cleanup()

    #expect(try await bucket.usage().entryCount == 0)
    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 0)
}

@Test func cleanupCountsMissingExpiredLeasedFileOnce() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let store = try cleanupStore(
        root: directory.url,
        policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5))),
        clock: clock
    )
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("leased-missing-expired")
    let sourceURL = try writeCleanupSourceFile(in: directory.url, name: "leased-missing-expired.bin", data: Data([7, 8, 9]))

    try await bucket.setFile(at: sourceURL, for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    let lease = try #require(try await bucket.leaseFile(key))
    try FileManager.default.removeItem(at: directory.url.appendingStorageRefForCleanup(ref))

    clock.setNow(Date(timeIntervalSince1970: 5))
    let skipped = try await store.cleanup()

    #expect(skipped.skippedLeasedEntries == 1)
    #expect(skipped.removedExpiredEntries == 0)
    #expect(try await bucket.usage().entryCount == 1)

    lease.release()
    let repaired = try await store.cleanup()

    #expect(repaired.skippedLeasedEntries == 0)
    #expect(repaired.removedExpiredEntries == 1)
    #expect(try await bucket.usage().entryCount == 0)
}

@Test func invalidStorageRefIsNotReadOutsideCacheRoot() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("invalid-ref-read")
    let outsideURL = directory.url.deletingLastPathComponent()
        .appendingPathComponent("outside-\(UUID().uuidString).bin", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: outsideURL) }

    try await bucket.setData(Data([1, 2, 3]), for: key)
    try Data([9, 9, 9]).write(to: outsideURL)
    try SQLiteTestDatabase(url: directory.url.appendingPathComponent("index/metadata.sqlite"))
        .updateStorageRef("../\(outsideURL.lastPathComponent)", bucket: cleanupDiskID.rawValue, key: key.rawValue)

    #expect(try await bucket.data(key) == nil)
    #expect(FileManager.default.fileExists(atPath: outsideURL.path))
    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 0)
}

@Test func cleanupRepairsInvalidStorageRefWithoutDeletingOutsideFile() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try cleanupStore(root: directory.url)
    let bucket = try store.bucket(cleanupDiskID)
    let key = CacheKey("invalid-ref-cleanup")
    let outsideURL = directory.url.deletingLastPathComponent()
        .appendingPathComponent("outside-\(UUID().uuidString).bin", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: outsideURL) }

    try await bucket.setData(Data([1, 2, 3]), for: key)
    let optionalRef = try cleanupStorageRef(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue)
    let ref = try #require(optionalRef)
    let originalPayloadURL = directory.url.appendingStorageRefForCleanup(ref)
    try Data([9, 9, 9]).write(to: outsideURL)
    try SQLiteTestDatabase(url: directory.url.appendingPathComponent("index/metadata.sqlite"))
        .updateStorageRef("../\(outsideURL.lastPathComponent)", bucket: cleanupDiskID.rawValue, key: key.rawValue)

    let cleanup = try await store.cleanup()

    #expect(try cleanupEntryCount(root: directory.url, bucket: cleanupDiskID.rawValue, key: key.rawValue) == 0)
    #expect(FileManager.default.fileExists(atPath: outsideURL.path))
    #expect(!FileManager.default.fileExists(atPath: originalPayloadURL.path))
    #expect(cleanup.removedOrphanedFiles == 1)
    #expect(cleanup.removedOrphanedBytes == .bytes(3))
}

private let cleanupDiskID = CacheBucketID("disk")

private func cleanupStore(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .bytes(100)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: root,
        buckets: [BucketConfiguration(id: cleanupDiskID, policy: policy)],
        clock: clock
    ))
}

private func cleanupStorageRef(root: URL, bucket: String, key: String) throws -> String? {
    let database = try SQLiteTestDatabase(url: root.appendingPathComponent("index/metadata.sqlite"))
    return try database.storageRef(bucket: bucket, key: key)
}

private func cleanupEntryCount(root: URL, bucket: String, key: String) throws -> Int64 {
    let database = try SQLiteTestDatabase(url: root.appendingPathComponent("index/metadata.sqlite"))
    return try database.int("SELECT COUNT(*) FROM entries WHERE bucket = '\(bucket)' AND key = '\(key)';")
}

private func writeCleanupSourceFile(in root: URL, name: String, data: Data) throws -> URL {
    let sourceDirectory = root.appendingPathComponent("source-files", isDirectory: true)
    let url = sourceDirectory.appendingPathComponent(name, isDirectory: false)
    try writeCleanupFile(at: url, data: data)
    return url
}

private func writeCleanupFile(at url: URL, data: Data) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private extension URL {
    func appendingStorageRefForCleanup(_ storageRef: String) -> URL {
        storageRef.split(separator: "/").reduce(self) { url, component in
            url.appendingPathComponent(String(component), isDirectory: false)
        }
    }

    func appendingPathComponentsForCleanup(_ components: [String]) -> URL {
        components.reduce(self) { url, component in
            url.appendingPathComponent(component, isDirectory: false)
        }
    }
}
