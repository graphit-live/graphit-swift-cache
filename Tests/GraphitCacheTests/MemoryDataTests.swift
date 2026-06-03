import Foundation
import GraphitCache
import Testing

@Test func storeBucketLookupReturnsConfiguredBucketAndRejectsUnknownBucket() throws {
    let configuredID = CacheBucketID("memory")
    let store = try makeMemoryStore(bucketID: configuredID)

    let bucket = try store.bucket(configuredID)
    #expect(bucket.id == configuredID)
    #expect(bucket.policy.storage == .memoryOnly)
    #expect(store.configuredBuckets() == [configuredID])

    let missingID = CacheBucketID("missing")
    expectCacheError({
        _ = try store.bucket(missingID)
    }) { error in
        error == .unknownBucket(missingID)
    }
}

@Test func memoryDataSetReadInfoAndRemoveEndToEnd() async throws {
    let storedAt = Date(timeIntervalSince1970: 1_000)
    let clock = TestCacheClock(now: storedAt)
    let bucket = try makeMemoryBucket(clock: clock)
    let key = CacheKey("profile:1")
    let payload = Data([1, 2, 3, 4])
    let tags: Set<CacheTag> = [CacheTag("kind:profile"), CacheTag("user:1")]

    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try await bucket.data(key) == nil)

    try await bucket.setData(payload, for: key, options: CacheEntryOptions(tags: tags))

    let info = try await bucket.dataInfo(for: key)
    #expect(info?.bucket == bucket.id)
    #expect(info?.key == key)
    #expect(info?.size == .bytes(4))
    #expect(info?.storedAt == storedAt)
    #expect(info?.tags == tags)
    #expect(info?.lastAccessedAt == nil)
    #expect(info?.expiresAt == nil)

    let cached = try await bucket.data(key)
    #expect(cached?.data == payload)
    #expect(cached?.info == info)

    let result = try await bucket.remove(key)
    #expect(result == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(4)))
    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try await bucket.data(key) == nil)
    #expect(try await bucket.remove(key) == .empty)
}

@Test func memoryDataSameKeyReplacementOverwritesDataTagsAndMetadata() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 10))
    let bucket = try makeMemoryBucket(clock: clock)
    let key = CacheKey("profile:replace")

    try await bucket.setData(
        Data([1, 1]),
        for: key,
        options: CacheEntryOptions(tags: [CacheTag("old")])
    )

    clock.setNow(Date(timeIntervalSince1970: 20))
    try await bucket.setData(
        Data([2, 2, 2]),
        for: key,
        options: CacheEntryOptions(tags: [CacheTag("new")])
    )

    let cached = try await bucket.data(key)
    #expect(cached?.data == Data([2, 2, 2]))
    #expect(cached?.info.size == .bytes(3))
    #expect(cached?.info.storedAt == Date(timeIntervalSince1970: 20))
    #expect(cached?.info.tags == [CacheTag("new")])
    #expect(cached?.info.lastAccessedAt == nil)

    let result = try await bucket.remove(key)
    #expect(result == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(3)))
}

@Test func memoryBucketRemoveAllRemovesOnlyThatBucket() async throws {
    let firstID = CacheBucketID("first")
    let secondID = CacheBucketID("second")
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(id: firstID, policy: .memoryOnly(maxTotalSize: .mb(1))),
            BucketConfiguration(id: secondID, policy: .memoryOnly(maxTotalSize: .mb(1)))
        ],
        clock: TestCacheClock()
    ))
    let first = try store.bucket(firstID)
    let second = try store.bucket(secondID)

    try await first.setData(Data([1, 2]), for: CacheKey("a"))
    try await first.setData(Data([3]), for: CacheKey("b"))
    try await second.setData(Data([4, 5, 6]), for: CacheKey("c"))

    let result = try await first.removeAll()
    #expect(result == CacheRemovalResult(removedEntries: 2, removedBytes: .bytes(3)))
    #expect(try await first.data(CacheKey("a")) == nil)
    #expect(try await first.data(CacheKey("b")) == nil)
    #expect(try await second.data(CacheKey("c"))?.data == Data([4, 5, 6]))
}

@Test func storeRemoveAllRemovesMemoryEntriesAcrossBuckets() async throws {
    let firstID = CacheBucketID("first")
    let secondID = CacheBucketID("second")
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(id: firstID, policy: .memoryOnly(maxTotalSize: .mb(1))),
            BucketConfiguration(id: secondID, policy: .memoryOnly(maxTotalSize: .mb(1)))
        ],
        clock: TestCacheClock()
    ))
    let first = try store.bucket(firstID)
    let second = try store.bucket(secondID)

    try await first.setData(Data([1]), for: CacheKey("a"))
    try await second.setData(Data([2, 3]), for: CacheKey("b"))

    let result = try await store.removeAll()
    #expect(result == CacheRemovalResult(removedEntries: 2, removedBytes: .bytes(3)))
    #expect(try await first.data(CacheKey("a")) == nil)
    #expect(try await second.data(CacheKey("b")) == nil)
}

@Test func memoryBucketHandleRetainsStoreEngine() async throws {
    let bucket = try makeDetachedMemoryBucket()
    let key = CacheKey("retained")
    let payload = Data([9, 8, 7])

    try await bucket.setData(payload, for: key)

    #expect(try await bucket.data(key)?.data == payload)
}

@Test func memorySetDataEnforcesSimpleCapacityChecks() async throws {
    let itemLimitedBucket = try makeMemoryBucket(policy: .memoryOnly(maxTotalSize: .bytes(10), maxItemSize: .bytes(2)))

    await expectCacheError({
        try await itemLimitedBucket.setData(Data([1, 2, 3]), for: CacheKey("too-large"))
    }) { error in
        error == .itemTooLarge(size: .bytes(3), limit: .bytes(2))
    }

    let totalLimitedBucket = try makeMemoryBucket(policy: .memoryOnly(maxTotalSize: .bytes(4)))
    try await totalLimitedBucket.setData(Data([1, 2]), for: CacheKey("first"))

    await expectCacheError({
        try await totalLimitedBucket.setData(Data([3, 4, 5]), for: CacheKey("second"))
    }) { error in
        if case .capacityCannotBeSatisfied(let bucket, .totalSize(let requiredBytes, let availableEvictableBytes)) = error {
            bucket == totalLimitedBucket.id && requiredBytes == .bytes(3) && availableEvictableBytes == .zero
        } else {
            false
        }
    }

    #expect(try await totalLimitedBucket.data(CacheKey("second")) == nil)
}

private func makeMemoryStore(
    bucketID: CacheBucketID = CacheBucketID("memory"),
    policy: BucketPolicy = .memoryOnly(maxTotalSize: .mb(1)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [BucketConfiguration(id: bucketID, policy: policy)],
        clock: clock
    ))
}

private func makeMemoryBucket(
    bucketID: CacheBucketID = CacheBucketID("memory"),
    policy: BucketPolicy = .memoryOnly(maxTotalSize: .mb(1)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheBucket {
    try makeMemoryStore(bucketID: bucketID, policy: policy, clock: clock).bucket(bucketID)
}

private func makeDetachedMemoryBucket() throws -> CacheBucket {
    let store = try makeMemoryStore()
    return try store.bucket(CacheBucketID("memory"))
}
