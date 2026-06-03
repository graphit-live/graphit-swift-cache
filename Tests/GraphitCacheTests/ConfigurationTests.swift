import Foundation
import GraphitCache
import Testing

@Test func configurationAcceptsValidMemoryOnlyStore() throws {
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(
                id: CacheBucketID("profiles.v1"),
                policy: .memoryOnly(maxTotalSize: .mb(10), maxItemSize: .mb(1), maxItemCount: 100)
            )
        ]
    ))

    #expect(store.configuredBuckets() == [CacheBucketID("profiles.v1")])
}

@Test func configurationAcceptsValidMixedStoreWithFileRoot() throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }

    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [
            BucketConfiguration(id: CacheBucketID("memory"), policy: .memoryOnly(maxTotalSize: .mb(1))),
            BucketConfiguration(id: CacheBucketID("disk"), policy: .diskBacked(maxTotalSize: .mb(10)))
        ]
    ))

    #expect(store.configuredBuckets() == [CacheBucketID("memory"), CacheBucketID("disk")])
}

@Test func configurationRejectsInvalidBucketIDs() {
    let invalidIDs = [
        "",
        ".",
        "..",
        "has space",
        "slash/name",
        "ümlaut",
        String(repeating: "a", count: 129)
    ]

    for id in invalidIDs {
        expectCacheError({
            _ = try CacheStore(configuration: CacheStoreConfiguration(
                rootDirectory: nil,
                buckets: [BucketConfiguration(id: CacheBucketID(id), policy: .memoryOnly(maxTotalSize: .mb(1)))]
            ))
        }) { error in
            if case .invalidConfiguration = error { true } else { false }
        }
    }
}

@Test func configurationAcceptsMaximumLengthBucketID() throws {
    let id = CacheBucketID(String(repeating: "a", count: 128))
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [BucketConfiguration(id: id, policy: .memoryOnly(maxTotalSize: .mb(1)))]
    ))

    #expect(store.configuredBuckets() == [id])
}

@Test func configurationRejectsDuplicateBuckets() {
    let duplicate = CacheBucketID("profiles")

    expectCacheError({
        _ = try CacheStore(configuration: CacheStoreConfiguration(
            rootDirectory: nil,
            buckets: [
                BucketConfiguration(id: duplicate, policy: .memoryOnly(maxTotalSize: .mb(1))),
                BucketConfiguration(id: duplicate, policy: .memoryOnly(maxTotalSize: .mb(2)))
            ]
        ))
    }) { error in
        error == .duplicateBucket(duplicate)
    }
}

@Test func configurationValidatesRootRules() {
    let diskBucket = BucketConfiguration(id: CacheBucketID("disk"), policy: .diskBacked(maxTotalSize: .mb(1)))
    let memoryBucket = BucketConfiguration(id: CacheBucketID("memory"), policy: .memoryOnly(maxTotalSize: .mb(1)))
    let fileRoot = URL(fileURLWithPath: "/tmp/graphit-cache-tests", isDirectory: true)
    let nonFileRoot = URL(string: "https://example.com/cache")!

    expectCacheError({
        _ = try CacheStore(configuration: CacheStoreConfiguration(rootDirectory: nil, buckets: [diskBucket]))
    }) { error in
        if case .invalidConfiguration = error { true } else { false }
    }

    expectCacheError({
        _ = try CacheStore(configuration: CacheStoreConfiguration(rootDirectory: fileRoot, buckets: [memoryBucket]))
    }) { error in
        if case .invalidConfiguration = error { true } else { false }
    }

    expectCacheError({
        _ = try CacheStore(configuration: CacheStoreConfiguration(rootDirectory: nonFileRoot, buckets: [diskBucket]))
    }) { error in
        if case .invalidConfiguration = error { true } else { false }
    }
}

@Test func configurationRejectsInvalidSizeAndCountLimits() {
    let invalidPolicies: [BucketPolicy] = [
        .memoryOnly(maxTotalSize: .zero),
        .memoryOnly(maxTotalSize: ByteCount(-1)),
        .memoryOnly(maxTotalSize: .mb(1), maxItemSize: .zero),
        .memoryOnly(maxTotalSize: .mb(1), maxItemSize: ByteCount(-1)),
        .memoryOnly(maxTotalSize: .mb(1), maxItemSize: .mb(2)),
        .memoryOnly(maxTotalSize: .mb(1), maxItemCount: 0),
        .memoryOnly(maxTotalSize: .mb(1), maxItemCount: -1)
    ]

    for policy in invalidPolicies {
        expectCacheError({
            _ = try CacheStore(configuration: CacheStoreConfiguration(
                rootDirectory: nil,
                buckets: [BucketConfiguration(id: CacheBucketID("bucket"), policy: policy)]
            ))
        }) { error in
            if case .invalidConfiguration = error { true } else { false }
        }
    }
}

@Test func configurationRejectsNonPositiveExpirationDurations() {
    let invalidPolicies: [BucketPolicy] = [
        .memoryOnly(maxTotalSize: .mb(1), expiration: .fixed(.zero)),
        .memoryOnly(maxTotalSize: .mb(1), expiration: .fixed(.seconds(-1))),
        .memoryOnly(maxTotalSize: .mb(1), expiration: .sliding(.zero)),
        .memoryOnly(maxTotalSize: .mb(1), expiration: .sliding(.seconds(-1)))
    ]

    for policy in invalidPolicies {
        expectCacheError({
            _ = try CacheStore(configuration: CacheStoreConfiguration(
                rootDirectory: nil,
                buckets: [BucketConfiguration(id: CacheBucketID("bucket"), policy: policy)]
            ))
        }) { error in
            if case .invalidConfiguration = error { true } else { false }
        }
    }
}
