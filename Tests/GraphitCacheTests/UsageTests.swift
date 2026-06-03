import Foundation
import GraphitCache
import Testing

@Test func usageReportsMemoryOnlyBucketAndStoreTotals() async throws {
    let firstID = CacheBucketID("first")
    let secondID = CacheBucketID("second")
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(id: firstID, policy: .memoryOnly(maxTotalSize: .bytes(100))),
            BucketConfiguration(id: secondID, policy: .memoryOnly(maxTotalSize: .bytes(100)))
        ],
        clock: TestCacheClock()
    ))
    let first = try store.bucket(firstID)
    let second = try store.bucket(secondID)

    try await first.setData(Data([1, 2]), for: CacheKey("a"))
    try await second.setData(Data([3, 4, 5]), for: CacheKey("b"))

    let firstUsage = try await first.usage()
    #expect(firstUsage.bucket == firstID)
    #expect(firstUsage.totalSize == .bytes(2))
    #expect(firstUsage.memorySize == .bytes(2))
    #expect(firstUsage.diskSize == .zero)
    #expect(firstUsage.entryCount == 1)

    let storeUsage = try await store.usage()
    #expect(storeUsage.totalSize == .bytes(5))
    #expect(storeUsage.memorySize == .bytes(5))
    #expect(storeUsage.diskSize == .zero)
    #expect(storeUsage.entryCount == 2)
    #expect(storeUsage.buckets.count == 2)
    #expect(storeUsage.buckets.first { $0.bucket == firstID }?.totalSize == .bytes(2))
    #expect(storeUsage.buckets.first { $0.bucket == secondID }?.totalSize == .bytes(3))
}

@Test func usageUpdatesAfterRemovalAndEviction() async throws {
    let bucket = try usageMemoryBucket(policy: .memoryOnly(maxTotalSize: .bytes(4)))

    try await bucket.setData(Data([1, 2]), for: CacheKey("a"))
    try await bucket.setData(Data([3, 4, 5]), for: CacheKey("b"))

    var usage = try await bucket.usage()
    #expect(usage.totalSize == .bytes(3))
    #expect(usage.memorySize == .bytes(3))
    #expect(usage.entryCount == 1)
    #expect(try await bucket.dataInfo(for: CacheKey("a")) == nil)

    _ = try await bucket.remove(CacheKey("b"))
    usage = try await bucket.usage()
    #expect(usage.totalSize == .zero)
    #expect(usage.memorySize == .zero)
    #expect(usage.entryCount == 0)
}

@Test func cleanupRemovesExpiredMemoryEntriesAndUpdatesUsage() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(
                id: CacheBucketID("memory"),
                policy: .memoryOnly(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5)))
            )
        ],
        clock: clock
    ))
    let bucket = try store.bucket(CacheBucketID("memory"))

    try await bucket.setData(Data([1, 2]), for: CacheKey("a"))
    try await bucket.setData(Data([3]), for: CacheKey("b"))

    clock.setNow(Date(timeIntervalSince1970: 5))
    let cleanup = try await bucket.cleanup()
    #expect(cleanup.removedExpiredEntries == 2)
    #expect(cleanup.removedExpiredBytes == .bytes(3))
    #expect(cleanup.evictedEntries == 0)
    #expect(cleanup.evictedBytes == .zero)

    let usage = try await store.usage()
    #expect(usage.totalSize == .zero)
    #expect(usage.memorySize == .zero)
    #expect(usage.entryCount == 0)
}

@Test func storeCleanupRemovesExpiredMemoryEntriesAcrossBuckets() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let firstID = CacheBucketID("first")
    let secondID = CacheBucketID("second")
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(id: firstID, policy: .memoryOnly(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(5)))),
            BucketConfiguration(id: secondID, policy: .memoryOnly(maxTotalSize: .bytes(100), expiration: .never))
        ],
        clock: clock
    ))
    let first = try store.bucket(firstID)
    let second = try store.bucket(secondID)

    try await first.setData(Data([1, 2]), for: CacheKey("expired"))
    try await second.setData(Data([3]), for: CacheKey("kept"))

    clock.setNow(Date(timeIntervalSince1970: 5))
    let cleanup = try await store.cleanup()
    #expect(cleanup.removedExpiredEntries == 1)
    #expect(cleanup.removedExpiredBytes == .bytes(2))

    let usage = try await store.usage()
    #expect(usage.totalSize == .bytes(1))
    #expect(usage.memorySize == .bytes(1))
    #expect(usage.entryCount == 1)
    #expect(try await first.dataInfo(for: CacheKey("expired")) == nil)
    #expect(try await second.data(CacheKey("kept"))?.data == Data([3]))
}

private func usageMemoryBucket(policy: BucketPolicy) throws -> CacheBucket {
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [BucketConfiguration(id: CacheBucketID("memory"), policy: policy)],
        clock: TestCacheClock()
    ))
    return try store.bucket(CacheBucketID("memory"))
}
