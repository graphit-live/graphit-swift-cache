import GraphitCache
import Testing

@Test func publicAPISmokeTest() throws {
    let bucketID = CacheBucketID("profiles")
    let configuration = CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [
            BucketConfiguration(
                id: bucketID,
                policy: .memoryOnly(maxTotalSize: .mb(1))
            )
        ]
    )

    let store = try CacheStore(configuration: configuration)
    let bucket = try store.bucket(bucketID)

    #expect(ByteCount.kb(1).bytes == 1024)
    #expect(store.configuredBuckets() == [bucketID])
    #expect(bucket.id == bucketID)
    #expect(bucket.policy.storage == .memoryOnly)
}
