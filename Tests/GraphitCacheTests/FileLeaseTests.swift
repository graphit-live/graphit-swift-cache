import Foundation
import GraphitCache
import Testing

@Test func fileImportCopiesSourceAndLeaseReturnsManagedURL() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let storedAt = Date(timeIntervalSince1970: 1_000)
    let clock = TestCacheClock(now: storedAt)
    let bucket = try makeFileBucket(root: directory.url, clock: clock)
    let key = CacheKey("video:1")
    let payload = Data([1, 2, 3, 4])
    let sourceURL = try writeSourceFile(in: directory.url, name: "download.tmp", data: payload)
    let tags: Set<CacheTag> = [CacheTag("kind:video"), CacheTag("feed:home")]

    try await bucket.setFile(
        at: sourceURL,
        for: key,
        options: CacheFileOptions(tags: tags, fileExtension: ".mp4")
    )

    #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try await bucket.data(key) == nil)

    let info = try await bucket.fileInfo(for: key)
    #expect(info?.bucket == bucket.id)
    #expect(info?.key == key)
    #expect(info?.size == .bytes(4))
    #expect(info?.storedAt == storedAt)
    #expect(info?.tags == tags)
    #expect(info?.lastAccessedAt == nil)

    let readAt = Date(timeIntervalSince1970: 1_001)
    clock.setNow(readAt)
    let optionalLease = try await bucket.leaseFile(key)
    let lease = try #require(optionalLease)

    #expect(lease.url.path.hasPrefix(directory.url.path))
    #expect(lease.url.pathExtension == "mp4")
    #expect(lease.info.lastAccessedAt == readAt)
    #expect(try Data(contentsOf: lease.url) == payload)
    #expect(try await bucket.fileInfo(for: key)?.lastAccessedAt == readAt)

    lease.release()
}

@Test func fileExtensionResolutionUsesSourceExtensionAndDefaultBin() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)

    let movSource = try writeSourceFile(in: directory.url, name: "clip.mov", data: Data([1]))
    try await bucket.setFile(at: movSource, for: CacheKey("mov"))
    let movLease = try #require(try await bucket.leaseFile(CacheKey("mov")))
    #expect(movLease.url.pathExtension == "mov")
    movLease.release()

    let extensionlessSource = try writeSourceFile(in: directory.url, name: "blob", data: Data([2]))
    try await bucket.setFile(at: extensionlessSource, for: CacheKey("default"))
    let defaultLease = try #require(try await bucket.leaseFile(CacheKey("default")))
    #expect(defaultLease.url.pathExtension == "bin")
    defaultLease.release()
}

@Test func fileAndDataCanReplaceEachOtherWhenUnleased() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)
    let key = CacheKey("same-key")

    try await bucket.setData(Data([9]), for: key)
    #expect(try await bucket.data(key)?.data == Data([9]))

    let sourceURL = try writeSourceFile(in: directory.url, name: "payload.dat", data: Data([1, 2, 3]))
    try await bucket.setFile(at: sourceURL, for: key)

    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try await bucket.data(key) == nil)
    #expect(try await bucket.fileInfo(for: key)?.size == .bytes(3))

    try await bucket.setData(Data([4, 5]), for: key)

    #expect(try await bucket.fileInfo(for: key) == nil)
    #expect(try await bucket.data(key)?.data == Data([4, 5]))
}

@Test func leasedFileBlocksDirectRemovalAndSameKeyReplacementUntilRelease() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)
    let key = CacheKey("leased")
    let firstSource = try writeSourceFile(in: directory.url, name: "first.bin", data: Data([1, 2]))
    let secondSource = try writeSourceFile(in: directory.url, name: "second.bin", data: Data([3, 4]))

    try await bucket.setFile(at: firstSource, for: key)
    let lease = try #require(try await bucket.leaseFile(key))

    await expectCacheError({
        _ = try await bucket.remove(key)
    }) { error in
        error == .fileIsLeased(bucket: bucket.id, key: key)
    }

    await expectCacheError({
        try await bucket.setData(Data([5]), for: key)
    }) { error in
        error == .fileIsLeased(bucket: bucket.id, key: key)
    }

    await expectCacheError({
        try await bucket.setFile(at: secondSource, for: key)
    }) { error in
        error == .fileIsLeased(bucket: bucket.id, key: key)
    }

    lease.release()
    lease.release()

    let removal = try await bucket.remove(key)
    #expect(removal == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(2)))
}

@Test func bulkRemovalSkipsLeasedFilesAndReportsSkippedCount() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let store = try makeFileStore(root: directory.url)
    let bucket = try store.bucket(fileBucketID)
    let leasedKey = CacheKey("leased")
    let freeKey = CacheKey("free")

    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "leased.bin", data: Data([1, 2])),
        for: leasedKey,
        options: CacheFileOptions(tags: [CacheTag("files")])
    )
    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "free.bin", data: Data([3, 4, 5])),
        for: freeKey,
        options: CacheFileOptions(tags: [CacheTag("files")])
    )

    let lease = try #require(try await bucket.leaseFile(leasedKey))

    let taggedRemoval = try await store.removeAll(tagged: CacheTag("files"))
    #expect(taggedRemoval == CacheRemovalResult(
        removedEntries: 1,
        removedBytes: .bytes(3),
        skippedLeasedEntries: 1
    ))
    #expect(try await bucket.fileInfo(for: leasedKey) != nil)
    #expect(try await bucket.fileInfo(for: freeKey) == nil)

    lease.release()

    let finalRemoval = try await bucket.removeAll()
    #expect(finalRemoval == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(2)))
}

@Test func leasedFilesAreNotEvictedForCapacity() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url, policy: .diskBacked(maxTotalSize: .bytes(4)))
    let fileKey = CacheKey("file")
    let dataKey = CacheKey("data")

    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "file.bin", data: Data([1, 2, 3])),
        for: fileKey
    )
    let lease = try #require(try await bucket.leaseFile(fileKey))

    await expectCacheError({
        try await bucket.setData(Data([4, 5, 6]), for: dataKey)
    }) { error in
        if case .capacityCannotBeSatisfied(let bucketID, .totalSize(let requiredBytes, let availableEvictableBytes)) = error {
            bucketID == bucket.id && requiredBytes == .bytes(3) && availableEvictableBytes == .zero
        } else {
            false
        }
    }
    #expect(try await bucket.data(dataKey) == nil)
    #expect(try await bucket.fileInfo(for: fileKey) != nil)

    lease.release()

    try await bucket.setData(Data([4, 5, 6]), for: dataKey)
    #expect(try await bucket.fileInfo(for: fileKey) == nil)
    #expect(try await bucket.data(dataKey)?.data == Data([4, 5, 6]))
}

@Test func fileLeaseDeinitReleasesSynchronously() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)
    let key = CacheKey("deinit")

    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "deinit.bin", data: Data([7])),
        for: key
    )

    do {
        let retainedLease = try #require(try await bucket.leaseFile(key))
        var lease: CachedFileLease? = retainedLease
        #expect(lease != nil)
        lease = nil
    }

    let removal = try await bucket.remove(key)
    #expect(removal == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(1)))
}

@Test func fileInfoDoesNotExtendSlidingExpirationButLeaseFileDoes() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 0))
    let bucket = try makeFileBucket(
        root: directory.url,
        policy: .diskBacked(maxTotalSize: .bytes(100), expiration: .sliding(.seconds(10))),
        clock: clock
    )
    let key = CacheKey("sliding-file")

    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "sliding.bin", data: Data([1, 2, 3])),
        for: key
    )

    clock.setNow(Date(timeIntervalSince1970: 5))
    let infoAfterMetadataRead = try await bucket.fileInfo(for: key)
    #expect(infoAfterMetadataRead?.lastAccessedAt == nil)
    #expect(infoAfterMetadataRead?.expiresAt == Date(timeIntervalSince1970: 10))

    clock.setNow(Date(timeIntervalSince1970: 9))
    let lease = try #require(try await bucket.leaseFile(key))
    #expect(lease.info.lastAccessedAt == Date(timeIntervalSince1970: 9))
    #expect(lease.info.expiresAt == Date(timeIntervalSince1970: 19))
    lease.release()

    clock.setNow(Date(timeIntervalSince1970: 18))
    let infoAfterLease = try await bucket.fileInfo(for: key)
    #expect(infoAfterLease?.lastAccessedAt == Date(timeIntervalSince1970: 9))
    #expect(infoAfterLease?.expiresAt == Date(timeIntervalSince1970: 19))

    clock.setNow(Date(timeIntervalSince1970: 19))
    #expect(try await bucket.fileInfo(for: key) == nil)
}

@Test func multipleFileLeasesKeepFileProtectedUntilEveryLeaseReleases() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)
    let key = CacheKey("multiple-leases")

    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "multi.bin", data: Data([1, 2])),
        for: key
    )

    let firstLease = try #require(try await bucket.leaseFile(key))
    let secondLease = try #require(try await bucket.leaseFile(key))

    firstLease.release()

    await expectCacheError({
        _ = try await bucket.remove(key)
    }) { error in
        error == .fileIsLeased(bucket: bucket.id, key: key)
    }

    secondLease.release()

    let removal = try await bucket.remove(key)
    #expect(removal == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(2)))
}

@Test func bucketScopedBulkRemovalSkipsLeasedFilesAndReportsSkippedCount() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)
    let leasedKey = CacheKey("leased-bucket-removal")
    let freeKey = CacheKey("free-bucket-removal")

    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "leased-bucket.bin", data: Data([1, 2])),
        for: leasedKey
    )
    try await bucket.setFile(
        at: try writeSourceFile(in: directory.url, name: "free-bucket.bin", data: Data([3, 4, 5])),
        for: freeKey
    )

    let lease = try #require(try await bucket.leaseFile(leasedKey))

    let removal = try await bucket.removeAll()
    #expect(removal == CacheRemovalResult(
        removedEntries: 1,
        removedBytes: .bytes(3),
        skippedLeasedEntries: 1
    ))
    #expect(try await bucket.fileInfo(for: leasedKey) != nil)
    #expect(try await bucket.fileInfo(for: freeKey) == nil)

    lease.release()

    let finalRemoval = try await bucket.removeAll()
    #expect(finalRemoval == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(2)))
}

@Test func fileImportValidatesSourceURL() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeFileBucket(root: directory.url)

    await expectCacheError({
        try await bucket.setFile(at: URL(string: "https://example.com/file.bin")!, for: CacheKey("remote"))
    }) { error in
        if case .invalidInput = error { true } else { false }
    }

    let missingURL = directory.url.appendingPathComponent("missing.bin")
    await expectCacheError({
        try await bucket.setFile(at: missingURL, for: CacheKey("missing"))
    }) { error in
        error == .sourceFileNotFound(missingURL)
    }

    let directorySource = directory.url.appendingPathComponent("source-directory", isDirectory: true)
    try FileManager.default.createDirectory(at: directorySource, withIntermediateDirectories: true)
    await expectCacheError({
        try await bucket.setFile(at: directorySource, for: CacheKey("directory"))
    }) { error in
        error == .sourceFileUnreadable(directorySource)
    }
}

private let fileBucketID = CacheBucketID("disk")

private func makeFileStore(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .bytes(100)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: root,
        buckets: [BucketConfiguration(id: fileBucketID, policy: policy)],
        clock: clock
    ))
}

private func makeFileBucket(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .bytes(100)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheBucket {
    try makeFileStore(root: root, policy: policy, clock: clock).bucket(fileBucketID)
}

private func writeSourceFile(in root: URL, name: String, data: Data) throws -> URL {
    let sourceDirectory = root.appendingPathComponent("source-files", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let url = sourceDirectory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url)
    return url
}
