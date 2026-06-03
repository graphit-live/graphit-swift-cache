import Foundation
@testable import GraphitCache
import Testing

@Test func conditionalMissingPayloadRepairDoesNotRemoveReplacement() throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }

    let databaseURL = directory.url.appendingPathComponent("metadata.sqlite", isDirectory: false)
    let index = try SQLiteMetadataIndex(databaseURL: databaseURL)
    let bucket = CacheBucketID("disk")
    let key = CacheKey("same-key")
    let entryID = StableKeyHasher.entryID(bucket: bucket, key: key)
    let policy = BucketPolicy.diskBacked(maxTotalSize: .bytes(100))
    let oldRef = "buckets/disk/aa/bb/\(entryID)-old.bin"
    let newRef = "buckets/disk/aa/bb/\(entryID)-new.bin"

    _ = try index.commitWrite(
        DiskEntryWrite(
            id: entryID,
            bucket: bucket,
            key: key,
            payloadKind: .data,
            storageRef: oldRef,
            size: .bytes(1),
            storedAtUS: 0,
            expiresAtUS: nil,
            expirationKind: .never,
            expirationDurationUS: nil,
            tags: []
        ),
        policy: policy,
        moveTemporaryToFinal: {}
    )

    _ = try index.commitWrite(
        DiskEntryWrite(
            id: entryID,
            bucket: bucket,
            key: key,
            payloadKind: .data,
            storageRef: newRef,
            size: .bytes(2),
            storedAtUS: 1,
            expiresAtUS: nil,
            expirationKind: .never,
            expirationDurationUS: nil,
            tags: []
        ),
        policy: policy,
        moveTemporaryToFinal: {}
    )

    let staleRepair = try index.removeEntry(bucket: bucket, key: key, matchingStorageRef: oldRef)
    #expect(staleRepair.removal == .empty)
    #expect(try index.fetchEntry(bucket: bucket, key: key)?.storageRef == newRef)

    let currentRepair = try index.removeEntry(bucket: bucket, key: key, matchingStorageRef: newRef)
    #expect(currentRepair.removal == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(2)))
    #expect(try index.fetchEntry(bucket: bucket, key: key) == nil)
}
