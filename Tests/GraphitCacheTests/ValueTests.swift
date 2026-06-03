import Foundation
import GraphitCache
import Testing

@Test func byteCountUnitsAndComparisonUseBinaryUnits() {
    #expect(ByteCount.zero.bytes == 0)
    #expect(ByteCount.bytes(12).bytes == 12)
    #expect(ByteCount.kb(1).bytes == 1_024)
    #expect(ByteCount.mb(2).bytes == 2 * 1_024 * 1_024)
    #expect(ByteCount.gb(3).bytes == 3 * 1_024 * 1_024 * 1_024)
    #expect(ByteCount.kb(1) < .mb(1))
}

@Test func stringBackedValuesExposeRawValueAndDescription() {
    let bucket = CacheBucketID("profiles")
    let tag = CacheTag("kind:profile")
    let key = CacheKey("profile:123")

    #expect(bucket.rawValue == "profiles")
    #expect(bucket.description == "profiles")
    #expect(CacheBucketID(rawValue: "profiles") == bucket)

    #expect(tag.rawValue == "kind:profile")
    #expect(tag.description == "kind:profile")
    #expect(CacheTag(rawValue: "kind:profile") == tag)

    #expect(key.rawValue == "profile:123")
    #expect(key.description == "profile:123")
    #expect(CacheKey(rawValue: "profile:123") == key)
}

@Test func cacheEntryInfoRequiresStoredAtAndChecksExpirationExplicitly() {
    let storedAt = Date(timeIntervalSince1970: 100)
    let expiresAt = Date(timeIntervalSince1970: 200)
    let info = CacheEntryInfo(
        bucket: CacheBucketID("profiles"),
        key: CacheKey("profile:123"),
        size: .bytes(42),
        storedAt: storedAt,
        tags: [CacheTag("kind:profile")],
        lastAccessedAt: nil,
        expiresAt: expiresAt
    )

    #expect(info.bucket == CacheBucketID("profiles"))
    #expect(info.key == CacheKey("profile:123"))
    #expect(info.size == .bytes(42))
    #expect(info.storedAt == storedAt)
    #expect(info.tags == [CacheTag("kind:profile")])
    #expect(info.lastAccessedAt == nil)
    #expect(info.expiresAt == expiresAt)
    #expect(!info.isExpired(at: Date(timeIntervalSince1970: 199.999)))
    #expect(info.isExpired(at: expiresAt))
}

@Test func resultEmptyValuesContainZeroCounters() {
    #expect(CacheRemovalResult.empty == CacheRemovalResult())
    #expect(CacheRemovalResult.empty.removedEntries == 0)
    #expect(CacheRemovalResult.empty.removedBytes == .zero)
    #expect(CacheRemovalResult.empty.skippedLeasedEntries == 0)

    #expect(CacheCleanupResult.empty == CacheCleanupResult())
    #expect(CacheCleanupResult.empty.removedExpiredEntries == 0)
    #expect(CacheCleanupResult.empty.removedExpiredBytes == .zero)
    #expect(CacheCleanupResult.empty.removedOrphanedFiles == 0)
    #expect(CacheCleanupResult.empty.removedOrphanedBytes == .zero)
    #expect(CacheCleanupResult.empty.evictedEntries == 0)
    #expect(CacheCleanupResult.empty.evictedBytes == .zero)
    #expect(CacheCleanupResult.empty.skippedLeasedEntries == 0)
}
