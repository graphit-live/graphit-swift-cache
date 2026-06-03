import Foundation
import GraphitCache
import Testing

@Test func memoryPolicyFixedExpirationExpiresAtOriginalDeadline() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makePolicyMemoryBucket(
        policy: .memoryOnly(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(10))),
        clock: clock
    )
    let key = CacheKey("fixed")

    try await bucket.setData(Data([1]), for: key)

    #expect(try await bucket.dataInfo(for: key)?.expiresAt == Date(timeIntervalSince1970: 10))

    clock.setNow(Date(timeIntervalSince1970: 9))
    #expect(try await bucket.data(key)?.data == Data([1]))
    #expect(try await bucket.dataInfo(for: key)?.expiresAt == Date(timeIntervalSince1970: 10))

    clock.setNow(Date(timeIntervalSince1970: 10))
    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try await bucket.data(key) == nil)
}

@Test func memoryPolicySlidingExpirationExtendsOnPayloadReadOnly() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makePolicyMemoryBucket(
        policy: .memoryOnly(maxTotalSize: .bytes(100), expiration: .sliding(.seconds(10))),
        clock: clock
    )
    let key = CacheKey("sliding")

    try await bucket.setData(Data([1, 2]), for: key)

    clock.setNow(Date(timeIntervalSince1970: 5))
    let infoAfterMetadataRead = try await bucket.dataInfo(for: key)
    #expect(infoAfterMetadataRead?.lastAccessedAt == nil)
    #expect(infoAfterMetadataRead?.expiresAt == Date(timeIntervalSince1970: 10))

    clock.setNow(Date(timeIntervalSince1970: 9))
    let cached = try await bucket.data(key)
    #expect(cached?.data == Data([1, 2]))
    #expect(cached?.info.lastAccessedAt == Date(timeIntervalSince1970: 9))
    #expect(cached?.info.expiresAt == Date(timeIntervalSince1970: 19))

    clock.setNow(Date(timeIntervalSince1970: 18))
    #expect(try await bucket.dataInfo(for: key)?.expiresAt == Date(timeIntervalSince1970: 19))

    clock.setNow(Date(timeIntervalSince1970: 19))
    #expect(try await bucket.dataInfo(for: key) == nil)
}

@Test func memoryPolicyNeverExpirationDoesNotExpireByTime() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makePolicyMemoryBucket(
        policy: .memoryOnly(maxTotalSize: .bytes(100), expiration: .never),
        clock: clock
    )
    let key = CacheKey("never")

    try await bucket.setData(Data([7]), for: key)

    clock.setNow(Date(timeIntervalSince1970: 1_000_000))
    #expect(try await bucket.dataInfo(for: key)?.expiresAt == nil)
    #expect(try await bucket.data(key)?.data == Data([7]))
}

@Test func memoryPolicyLeastRecentlyUsedEvictsUnaccessedEntriesFirst() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makePolicyMemoryBucket(
        policy: .memoryOnly(maxTotalSize: .bytes(6), eviction: .leastRecentlyUsed),
        clock: clock
    )

    try await bucket.setData(Data([1, 1, 1]), for: CacheKey("a"))
    clock.setNow(Date(timeIntervalSince1970: 1))
    try await bucket.setData(Data([2, 2, 2]), for: CacheKey("b"))

    clock.setNow(Date(timeIntervalSince1970: 2))
    #expect(try await bucket.data(CacheKey("a"))?.data == Data([1, 1, 1]))

    clock.setNow(Date(timeIntervalSince1970: 3))
    try await bucket.setData(Data([3, 3, 3]), for: CacheKey("c"))

    #expect(try await bucket.dataInfo(for: CacheKey("a")) != nil)
    #expect(try await bucket.dataInfo(for: CacheKey("b")) == nil)
    #expect(try await bucket.dataInfo(for: CacheKey("c")) != nil)
}

@Test func memoryPolicyOldestInsertedFirstIgnoresRecentAccessForEviction() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makePolicyMemoryBucket(
        policy: .memoryOnly(maxTotalSize: .bytes(6), eviction: .oldestInsertedFirst),
        clock: clock
    )

    try await bucket.setData(Data([1, 1, 1]), for: CacheKey("a"))
    clock.setNow(Date(timeIntervalSince1970: 1))
    try await bucket.setData(Data([2, 2, 2]), for: CacheKey("b"))

    clock.setNow(Date(timeIntervalSince1970: 2))
    #expect(try await bucket.data(CacheKey("a"))?.data == Data([1, 1, 1]))

    clock.setNow(Date(timeIntervalSince1970: 3))
    try await bucket.setData(Data([3, 3, 3]), for: CacheKey("c"))

    #expect(try await bucket.dataInfo(for: CacheKey("a")) == nil)
    #expect(try await bucket.dataInfo(for: CacheKey("b")) != nil)
    #expect(try await bucket.dataInfo(for: CacheKey("c")) != nil)
}

@Test func memoryPolicyMaxItemCountEvictsByConfiguredPolicy() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makePolicyMemoryBucket(
        policy: .memoryOnly(maxTotalSize: .bytes(100), maxItemCount: 2, eviction: .leastRecentlyUsed),
        clock: clock
    )

    try await bucket.setData(Data([1]), for: CacheKey("a"))
    clock.setNow(Date(timeIntervalSince1970: 1))
    try await bucket.setData(Data([2]), for: CacheKey("b"))

    clock.setNow(Date(timeIntervalSince1970: 2))
    #expect(try await bucket.data(CacheKey("a"))?.data == Data([1]))

    clock.setNow(Date(timeIntervalSince1970: 3))
    try await bucket.setData(Data([3]), for: CacheKey("c"))

    #expect(try await bucket.dataInfo(for: CacheKey("a")) != nil)
    #expect(try await bucket.dataInfo(for: CacheKey("b")) == nil)
    #expect(try await bucket.dataInfo(for: CacheKey("c")) != nil)
}

@Test func memoryPolicyNewWriteIsNotSelectedAsSameWriteEvictionVictim() async throws {
    let bucket = try makePolicyMemoryBucket(policy: .memoryOnly(maxTotalSize: .bytes(3)))

    try await bucket.setData(Data([1, 1, 1]), for: CacheKey("old"))
    try await bucket.setData(Data([2, 2, 2]), for: CacheKey("new"))

    #expect(try await bucket.dataInfo(for: CacheKey("old")) == nil)
    #expect(try await bucket.data(CacheKey("new"))?.data == Data([2, 2, 2]))
}

@Test func memoryPolicyOversizedTotalCapacityFailureLeavesExistingEntriesAndNewEntryAbsent() async throws {
    let bucket = try makePolicyMemoryBucket(policy: .memoryOnly(maxTotalSize: .bytes(3)))

    try await bucket.setData(Data([1, 1]), for: CacheKey("old"))

    await expectCacheError({
        try await bucket.setData(Data([2, 2, 2, 2]), for: CacheKey("too-large"))
    }) { error in
        if case .capacityCannotBeSatisfied(let bucketID, .totalSize(let requiredBytes, let availableEvictableBytes)) = error {
            bucketID == bucket.id && requiredBytes == .bytes(4) && availableEvictableBytes == .zero
        } else {
            false
        }
    }

    #expect(try await bucket.data(CacheKey("old"))?.data == Data([1, 1]))
    #expect(try await bucket.data(CacheKey("too-large")) == nil)
}

@Test func memoryPolicyRemoveAllTaggedCanBeBucketScopedOrStoreWide() async throws {
    let firstID = CacheBucketID("first")
    let secondID = CacheBucketID("second")
    let store = try makePolicyMemoryStore(bucketIDs: [firstID, secondID])
    let first = try store.bucket(firstID)
    let second = try store.bucket(secondID)
    let shared = CacheTag("shared")

    try await first.setData(Data([1]), for: CacheKey("first-shared"), options: .init(tags: [shared]))
    try await first.setData(Data([2]), for: CacheKey("first-other"), options: .init(tags: [CacheTag("other")]))
    try await second.setData(Data([3]), for: CacheKey("second-shared"), options: .init(tags: [shared]))

    let bucketResult = try await first.removeAll(tagged: shared)
    #expect(bucketResult == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(1)))
    #expect(try await first.dataInfo(for: CacheKey("first-shared")) == nil)
    #expect(try await first.dataInfo(for: CacheKey("first-other")) != nil)
    #expect(try await second.dataInfo(for: CacheKey("second-shared")) != nil)

    let storeResult = try await store.removeAll(tagged: shared)
    #expect(storeResult == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(1)))
    #expect(try await second.dataInfo(for: CacheKey("second-shared")) == nil)
}

@Test func memoryPolicyRemoveAllInsertedBeforeUsesStrictStoredAtCutoff() async throws {
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 10))
    let store = try makePolicyMemoryStore(clock: clock)
    let bucket = try store.bucket(CacheBucketID("memory"))

    try await bucket.setData(Data([1]), for: CacheKey("before"))
    clock.setNow(Date(timeIntervalSince1970: 20))
    try await bucket.setData(Data([2]), for: CacheKey("at-cutoff"))
    clock.setNow(Date(timeIntervalSince1970: 30))
    try await bucket.setData(Data([3]), for: CacheKey("after"))

    let result = try await bucket.removeAll(insertedBefore: Date(timeIntervalSince1970: 20))
    #expect(result == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(1)))
    #expect(try await bucket.dataInfo(for: CacheKey("before")) == nil)
    #expect(try await bucket.dataInfo(for: CacheKey("at-cutoff")) != nil)
    #expect(try await bucket.dataInfo(for: CacheKey("after")) != nil)

    let storeResult = try await store.removeAll(insertedBefore: Date(timeIntervalSince1970: 31))
    #expect(storeResult == CacheRemovalResult(removedEntries: 2, removedBytes: .bytes(2)))
}

private func makePolicyMemoryStore(
    bucketIDs: [CacheBucketID] = [CacheBucketID("memory")],
    policy: BucketPolicy = .memoryOnly(maxTotalSize: .bytes(100)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: bucketIDs.map { BucketConfiguration(id: $0, policy: policy) },
        clock: clock
    ))
}

private func makePolicyMemoryBucket(
    bucketID: CacheBucketID = CacheBucketID("memory"),
    policy: BucketPolicy,
    clock: any CacheClock = TestCacheClock()
) throws -> CacheBucket {
    try makePolicyMemoryStore(bucketIDs: [bucketID], policy: policy, clock: clock).bucket(bucketID)
}
