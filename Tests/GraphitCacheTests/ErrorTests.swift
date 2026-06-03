import Foundation
import GraphitCache
import Testing

@Test func cacheErrorDescriptionsAreNonEmpty() {
    let bucket = CacheBucketID("bucket")
    let key = CacheKey("key")
    let url = URL(fileURLWithPath: "/tmp/source")
    let errors: [CacheError] = [
        .invalidConfiguration("bad config"),
        .invalidInput("bad input"),
        .unknownBucket(bucket),
        .duplicateBucket(bucket),
        .unsupportedFileStorage(storageMode: .memoryOnly),
        .itemTooLarge(size: .mb(2), limit: .mb(1)),
        .capacityCannotBeSatisfied(
            bucket: bucket,
            constraint: .totalSize(requiredBytes: .mb(2), availableEvictableBytes: .mb(1))
        ),
        .capacityCannotBeSatisfied(
            bucket: bucket,
            constraint: .itemCount(requiredEvictions: 2, availableEvictableEntries: 1)
        ),
        .sourceFileNotFound(url),
        .sourceFileUnreadable(url),
        .fileIsLeased(bucket: bucket, key: key),
        .storageFailure("disk failed"),
        .internalInconsistency("broken invariant")
    ]

    for error in errors {
        #expect(!error.description.isEmpty)
    }
}
