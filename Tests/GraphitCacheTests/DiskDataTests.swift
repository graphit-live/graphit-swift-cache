import Foundation
import GraphitCache
import Testing

@Test func diskDataSetReadInfoAndRemoveEndToEnd() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let storedAt = Date(timeIntervalSince1970: 1_000)
    let clock = TestCacheClock(now: storedAt)
    let bucket = try makeDiskBucket(root: directory.url, clock: clock)
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

    let readAt = Date(timeIntervalSince1970: 1_001)
    clock.setNow(readAt)
    let cached = try await bucket.data(key)
    #expect(cached?.data == payload)
    #expect(cached?.info.lastAccessedAt == readAt)

    let infoAfterRead = try await bucket.dataInfo(for: key)
    #expect(infoAfterRead?.lastAccessedAt == readAt)

    let result = try await bucket.remove(key)
    #expect(result == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(4)))
    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try await bucket.data(key) == nil)
    #expect(try await bucket.remove(key) == .empty)
}

@Test func diskDataPersistsAcrossStoreRecreation() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let key = CacheKey("persisted")
    let payload = Data([9, 8, 7])

    do {
        let store = try makeDiskStore(root: directory.url, clock: TestCacheClock(now: Date(timeIntervalSince1970: 10)))
        let bucket = try store.bucket(CacheBucketID("disk"))
        try await bucket.setData(payload, for: key, options: .init(tags: [CacheTag("persist")]))
    }

    let reopened = try makeDiskStore(root: directory.url, clock: TestCacheClock(now: Date(timeIntervalSince1970: 11)))
    let bucket = try reopened.bucket(CacheBucketID("disk"))
    let cached = try await bucket.data(key)
    #expect(cached?.data == payload)
    #expect(cached?.info.tags == [CacheTag("persist")])
    #expect(cached?.info.storedAt == Date(timeIntervalSince1970: 10))
}

@Test func diskDataReplacementResetsMetadataAndUsesNewVersionedStorageRef() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 10))
    let bucket = try makeDiskBucket(root: directory.url, clock: clock)
    let key = CacheKey("replace")

    try await bucket.setData(Data([1, 1]), for: key, options: .init(tags: [CacheTag("old")]))
    let firstStorageRef = try storageRef(root: directory.url, bucket: "disk", key: key.rawValue)
    #expect(firstStorageRef != nil)

    clock.setNow(Date(timeIntervalSince1970: 11))
    _ = try await bucket.data(key)

    clock.setNow(Date(timeIntervalSince1970: 20))
    try await bucket.setData(Data([2, 2, 2]), for: key, options: .init(tags: [CacheTag("new")]))
    let secondStorageRef = try storageRef(root: directory.url, bucket: "disk", key: key.rawValue)

    #expect(secondStorageRef != nil)
    #expect(firstStorageRef != secondStorageRef)

    let info = try await bucket.dataInfo(for: key)
    #expect(info?.size == .bytes(3))
    #expect(info?.storedAt == Date(timeIntervalSince1970: 20))
    #expect(info?.tags == [CacheTag("new")])
    #expect(info?.lastAccessedAt == nil)

    if let firstStorageRef, let secondStorageRef {
        #expect(!FileManager.default.fileExists(atPath: directory.url.appendingStorageRef(firstStorageRef).path))
        #expect(FileManager.default.fileExists(atPath: directory.url.appendingStorageRef(secondStorageRef).path))
    }
}

@Test func diskDataRawKeysNeverAppearInPayloadPaths() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeDiskBucket(root: directory.url)
    let rawKey = "secret/user/raw/path"

    try await bucket.setData(Data([1]), for: CacheKey(rawKey))

    let optionalRef = try storageRef(root: directory.url, bucket: "disk", key: rawKey)
    let ref = try #require(optionalRef)
    #expect(!ref.contains(rawKey))
    #expect(!ref.contains("secret"))
    #expect(!ref.contains("user"))
    #expect(!ref.contains("raw"))
}

@Test func diskDataCapacityEvictionAndFailureMirrorMemoryBehavior() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeDiskBucket(root: directory.url, policy: .diskBacked(maxTotalSize: .bytes(4)))

    try await bucket.setData(Data([1, 2]), for: CacheKey("first"))
    try await bucket.setData(Data([3, 4, 5]), for: CacheKey("second"))

    #expect(try await bucket.data(CacheKey("first")) == nil)
    #expect(try await bucket.data(CacheKey("second"))?.data == Data([3, 4, 5]))

    await expectCacheError({
        try await bucket.setData(Data([6, 7, 8, 9, 10]), for: CacheKey("impossible"))
    }) { error in
        if case .capacityCannotBeSatisfied(let bucketID, .totalSize(let requiredBytes, let availableEvictableBytes)) = error {
            bucketID == bucket.id && requiredBytes == .bytes(5) && availableEvictableBytes == .zero
        } else {
            false
        }
    }

    #expect(try await bucket.data(CacheKey("impossible")) == nil)
    #expect(try await bucket.data(CacheKey("second"))?.data == Data([3, 4, 5]))
}

@Test func diskDataExpirationBehavesAbsentAndSlidingExtendsOnPayloadRead() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let fixedClock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let fixedBucket = try makeDiskBucket(
        root: directory.url.appendingPathComponent("fixed", isDirectory: true),
        policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .fixed(.seconds(10))),
        clock: fixedClock
    )

    try await fixedBucket.setData(Data([1]), for: CacheKey("fixed"))
    fixedClock.setNow(Date(timeIntervalSince1970: 10))
    #expect(try await fixedBucket.dataInfo(for: CacheKey("fixed")) == nil)

    let slidingClock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let slidingBucket = try makeDiskBucket(
        root: directory.url.appendingPathComponent("sliding", isDirectory: true),
        policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .sliding(.seconds(10))),
        clock: slidingClock
    )

    try await slidingBucket.setData(Data([2]), for: CacheKey("sliding"))
    slidingClock.setNow(Date(timeIntervalSince1970: 5))
    #expect(try await slidingBucket.dataInfo(for: CacheKey("sliding"))?.expiresAt == Date(timeIntervalSince1970: 10))

    slidingClock.setNow(Date(timeIntervalSince1970: 9))
    let cached = try await slidingBucket.data(CacheKey("sliding"))
    #expect(cached?.info.lastAccessedAt == Date(timeIntervalSince1970: 9))
    #expect(cached?.info.expiresAt == Date(timeIntervalSince1970: 19))

    slidingClock.setNow(Date(timeIntervalSince1970: 18))
    #expect(try await slidingBucket.dataInfo(for: CacheKey("sliding"))?.expiresAt == Date(timeIntervalSince1970: 19))

    slidingClock.setNow(Date(timeIntervalSince1970: 19))
    #expect(try await slidingBucket.dataInfo(for: CacheKey("sliding")) == nil)
}

private func makeDiskStore(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .bytes(100)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: root,
        buckets: [BucketConfiguration(id: CacheBucketID("disk"), policy: policy)],
        clock: clock
    ))
}

private func makeDiskBucket(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .bytes(100)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheBucket {
    try makeDiskStore(root: root, policy: policy, clock: clock).bucket(CacheBucketID("disk"))
}

private func storageRef(root: URL, bucket: String, key: String) throws -> String? {
    let database = try SQLiteTestDatabase(url: root.appendingPathComponent("index/metadata.sqlite"))
    return try database.storageRef(bucket: bucket, key: key)
}

private extension URL {
    func appendingStorageRef(_ storageRef: String) -> URL {
        storageRef.split(separator: "/").reduce(self) { url, component in
            url.appendingPathComponent(String(component), isDirectory: false)
        }
    }
}
