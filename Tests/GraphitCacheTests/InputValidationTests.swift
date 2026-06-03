import Foundation
import GraphitCache
import Testing

@Test func runtimeValidationRejectsInvalidKeys() async throws {
    let bucket = try memoryBucket()
    let invalidKeys = [
        CacheKey(""),
        CacheKey("bad\u{0}key"),
        CacheKey(String(repeating: "a", count: 4_097))
    ]

    for key in invalidKeys {
        await expectCacheError({
            _ = try await bucket.dataInfo(for: key)
        }) { error in
            if case .invalidInput = error { true } else { false }
        }
    }
}

@Test func runtimeValidationRejectsInvalidTags() async throws {
    let store = try memoryStore()
    let bucket = try store.bucket(CacheBucketID("memory"))
    let invalidTags = [
        CacheTag(""),
        CacheTag("bad\u{0}tag"),
        CacheTag(String(repeating: "a", count: 257))
    ]

    for tag in invalidTags {
        await expectCacheError({
            _ = try await store.removeAll(tagged: tag)
        }) { error in
            if case .invalidInput = error { true } else { false }
        }

        await expectCacheError({
            _ = try await bucket.removeAll(tagged: tag)
        }) { error in
            if case .invalidInput = error { true } else { false }
        }
    }
}

@Test func runtimeValidationRejectsInvalidFileExtensionsForDiskBackedBuckets() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }

    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [BucketConfiguration(id: CacheBucketID("disk"), policy: .diskBacked(maxTotalSize: .mb(1)))]
    ))
    let bucket = try store.bucket(CacheBucketID("disk"))
    let invalidExtensions = [
        "",
        ".",
        "..mp4",
        "bad/name",
        "bad\\name",
        "bad\u{0}name",
        String(repeating: "a", count: 33)
    ]

    for fileExtension in invalidExtensions {
        await expectCacheError({
            try await bucket.setFile(
                at: URL(fileURLWithPath: "/tmp/source"),
                for: CacheKey("file"),
                options: CacheFileOptions(fileExtension: fileExtension)
            )
        }) { error in
            if case .invalidInput = error { true } else { false }
        }
    }
}

@Test func memoryOnlyFileAPIsReportUnsupportedStorage() async throws {
    let bucket = try memoryBucket()

    await expectCacheError({
        _ = try await bucket.fileInfo(for: CacheKey("file"))
    }) { error in
        error == .unsupportedFileStorage(storageMode: .memoryOnly)
    }

    await expectCacheError({
        _ = try await bucket.leaseFile(CacheKey("file"))
    }) { error in
        error == .unsupportedFileStorage(storageMode: .memoryOnly)
    }

    await expectCacheError({
        try await bucket.setFile(
            at: URL(fileURLWithPath: "/tmp/source"),
            for: CacheKey("file"),
            options: CacheFileOptions(fileExtension: "")
        )
    }) { error in
        error == .unsupportedFileStorage(storageMode: .memoryOnly)
    }
}

@Test func removeAllInValidatesBucketIDButAllowsUnconfiguredValidBuckets() async throws {
    let store = try memoryStore()

    await expectCacheError({
        _ = try await store.removeAll(in: CacheBucketID(".."))
    }) { error in
        if case .invalidInput = error { true } else { false }
    }

    let result = try await store.removeAll(in: CacheBucketID("old-bucket"))
    #expect(result == .empty)
}

private func memoryStore() throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [BucketConfiguration(id: CacheBucketID("memory"), policy: .memoryOnly(maxTotalSize: .mb(1)))]
    ))
}

private func memoryBucket() throws -> CacheBucket {
    try memoryStore().bucket(CacheBucketID("memory"))
}
