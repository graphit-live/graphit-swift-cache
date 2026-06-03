import Foundation
import GraphitCache
import Testing

@Test func concurrencyConcurrentSetsDifferentDiskKeys() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<20 {
            group.addTask {
                try await bucket.setData(Data([UInt8(index)]), for: CacheKey("key-\(index)"))
            }
        }
        try await group.waitForAll()
    }

    let usage = try await bucket.usage()
    #expect(usage.entryCount == 20)
    #expect(usage.totalSize == .bytes(20))

    for index in 0..<20 {
        let cached = try await bucket.data(CacheKey("key-\(index)"))
        #expect(cached?.data == Data([UInt8(index)]))
    }
}

@Test func concurrencyConcurrentGetsSameDiskKey() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)
    let key = CacheKey("shared-read")
    let payload = Data((0..<32).map(UInt8.init))

    try await bucket.setData(payload, for: key)

    try await withThrowingTaskGroup(of: Data?.self) { group in
        for _ in 0..<20 {
            group.addTask {
                try await bucket.data(key)?.data
            }
        }

        for try await data in group {
            #expect(data == payload)
        }
    }

    #expect(try await bucket.dataInfo(for: key)?.lastAccessedAt != nil)
}

@Test func concurrencyConcurrentSameKeyReplacementLeavesOneValidEntry() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)
    let key = CacheKey("replace-me")
    let payloads = (0..<20).map { index in Data(repeating: UInt8(index), count: index + 1) }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for payload in payloads {
            group.addTask {
                try await bucket.setData(payload, for: key)
            }
        }
        try await group.waitForAll()
    }

    let cached = try #require(try await bucket.data(key))
    #expect(payloads.contains(cached.data))
    #expect(try await bucket.usage().entryCount == 1)
}

@Test func concurrencyConcurrentDataAndFileReplacementLeavesOnePayloadShape() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)
    let key = CacheKey("data-file-race")
    let dataPayload = Data([1, 2, 3])
    let filePayload = Data([4, 5, 6, 7])
    let sourceURL = try writeConcurrencySourceFile(in: directory.url, name: "race.bin", data: filePayload)

    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await bucket.setData(dataPayload, for: key)
        }
        group.addTask {
            try await bucket.setFile(at: sourceURL, for: key)
        }
        try await group.waitForAll()
    }

    let cachedData = try await bucket.data(key)
    let fileInfo = try await bucket.fileInfo(for: key)
    #expect((cachedData != nil) != (fileInfo != nil))

    if let cachedData {
        #expect(cachedData.data == dataPayload)
    } else {
        let lease = try #require(try await bucket.leaseFile(key))
        defer { lease.release() }
        #expect(try Data(contentsOf: lease.url) == filePayload)
    }
}

@Test func concurrencyLeasedFileBlocksConcurrentReplacementAndRemoval() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)
    let key = CacheKey("leased-race")
    let sourceURL = try writeConcurrencySourceFile(in: directory.url, name: "leased.bin", data: Data([1, 2]))
    let replacementURL = try writeConcurrencySourceFile(in: directory.url, name: "replacement.bin", data: Data([3, 4]))

    try await bucket.setFile(at: sourceURL, for: key)
    let lease = try #require(try await bucket.leaseFile(key))
    defer { lease.release() }

    try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask {
            do {
                _ = try await bucket.remove(key)
                return false
            } catch CacheError.fileIsLeased(bucket: bucket.id, key: key) {
                return true
            }
        }
        group.addTask {
            do {
                try await bucket.setData(Data([5]), for: key)
                return false
            } catch CacheError.fileIsLeased(bucket: bucket.id, key: key) {
                return true
            }
        }
        group.addTask {
            do {
                try await bucket.setFile(at: replacementURL, for: key)
                return false
            } catch CacheError.fileIsLeased(bucket: bucket.id, key: key) {
                return true
            }
        }

        for try await blocked in group {
            #expect(blocked)
        }
    }

    #expect(try await bucket.fileInfo(for: key) != nil)
}

@Test func concurrencyCleanupWhileReadingKeepsLiveDataUsable() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)
    let key = CacheKey("live-data")
    let payload = Data([9, 8, 7, 6])

    try await bucket.setData(payload, for: key)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<20 {
            group.addTask {
                let cached = try await bucket.data(key)
                guard cached?.data == payload else {
                    throw ConcurrencyTestError.unexpectedPayload
                }
            }
        }
        for _ in 0..<5 {
            group.addTask {
                _ = try await bucket.cleanup()
            }
        }
        try await group.waitForAll()
    }

    #expect(try await bucket.data(key)?.data == payload)
}

@Test func concurrencyLeaseWhileCleanupKeepsLiveFileUsable() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let bucket = try makeConcurrencyDiskBucket(root: directory.url)
    let key = CacheKey("live-file")
    let payload = Data([1, 3, 5, 7])
    let sourceURL = try writeConcurrencySourceFile(in: directory.url, name: "live.bin", data: payload)

    try await bucket.setFile(at: sourceURL, for: key)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                guard let lease = try await bucket.leaseFile(key) else {
                    throw ConcurrencyTestError.missingLease
                }
                defer { lease.release() }
                guard (try Data(contentsOf: lease.url)) == payload else {
                    throw ConcurrencyTestError.unexpectedPayload
                }
            }
        }
        for _ in 0..<5 {
            group.addTask {
                _ = try await bucket.cleanup()
            }
        }
        try await group.waitForAll()
    }

    #expect(try await bucket.fileInfo(for: key) != nil)
}

@Test func cancellationAfterDiskDataTemporaryWriteBeforeCommitLeavesNoEntryOrPayloadFile() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = BlockingCacheClock()
    let bucket = try makeConcurrencyDiskBucket(root: directory.url, clock: clock)
    let key = CacheKey("cancel-data")

    clock.blockNextNow()
    let task = Task {
        try await bucket.setData(Data([1, 2, 3]), for: key)
    }

    await clock.waitUntilBlocked()
    defer {
        task.cancel()
        clock.releaseBlockedNow()
    }
    #expect(try temporaryFileCount(in: directory.url) == 1)

    task.cancel()
    clock.releaseBlockedNow()

    await expectCancellation(task)
    #expect(try await bucket.dataInfo(for: key) == nil)
    #expect(try temporaryFileCount(in: directory.url) == 0)
    #expect(try finalPayloadFileCount(in: directory.url) == 0)
}

@Test func cancellationAfterFileImportTemporaryCopyBeforeCommitLeavesNoEntryOrPayloadFile() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = BlockingCacheClock()
    let bucket = try makeConcurrencyDiskBucket(root: directory.url, clock: clock)
    let key = CacheKey("cancel-file")
    let sourceURL = try writeConcurrencySourceFile(in: directory.url, name: "cancel.bin", data: Data([4, 5, 6]))

    clock.blockNextNow()
    let task = Task {
        try await bucket.setFile(at: sourceURL, for: key)
    }

    await clock.waitUntilBlocked()
    defer {
        task.cancel()
        clock.releaseBlockedNow()
    }
    #expect(try temporaryFileCount(in: directory.url) == 1)

    task.cancel()
    clock.releaseBlockedNow()

    await expectCancellation(task)
    #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    #expect(try await bucket.fileInfo(for: key) == nil)
    #expect(try temporaryFileCount(in: directory.url) == 0)
    #expect(try finalPayloadFileCount(in: directory.url) == 0)
}

@Test func cancellationBeforeMemoryWriteLeavesNoEntry() async throws {
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: nil,
        buckets: [BucketConfiguration(
            id: concurrencyBucketID,
            policy: .memoryOnly(maxTotalSize: .bytes(100))
        )]
    ))
    let bucket = try store.bucket(concurrencyBucketID)
    let key = CacheKey("cancel-memory")
    let gate = TaskStartGate()

    let task = Task {
        await gate.wait()
        try await bucket.setData(Data([1]), for: key)
    }
    await gate.waitUntilWaiting()
    task.cancel()
    await gate.resume()

    await expectCancellation(task)
    #expect(try await bucket.dataInfo(for: key) == nil)
}

@Test func cancellationAfterCleanupStartsBeforeDiskMaintenanceLeavesExistingDiskEntries() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = BlockingCacheClock()
    let bucket = try makeConcurrencyDiskBucket(root: directory.url, clock: clock)
    let key = CacheKey("cleanup-cancel")
    let payload = Data([8, 8, 8])

    try await bucket.setData(payload, for: key)

    clock.blockNextNow()
    let task = Task {
        _ = try await bucket.cleanup()
    }

    await clock.waitUntilBlocked()
    defer {
        task.cancel()
        clock.releaseBlockedNow()
    }

    task.cancel()
    clock.releaseBlockedNow()

    await expectCancellation(task)
    #expect(try await bucket.data(key)?.data == payload)
}

private let concurrencyBucketID = CacheBucketID("disk")

private func makeConcurrencyDiskStore(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .kb(64)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheStore {
    try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: root,
        buckets: [BucketConfiguration(id: concurrencyBucketID, policy: policy)],
        clock: clock
    ))
}

private func makeConcurrencyDiskBucket(
    root: URL,
    policy: BucketPolicy = .diskBacked(maxTotalSize: .kb(64)),
    clock: any CacheClock = TestCacheClock()
) throws -> CacheBucket {
    try makeConcurrencyDiskStore(root: root, policy: policy, clock: clock).bucket(concurrencyBucketID)
}

private func writeConcurrencySourceFile(in root: URL, name: String, data: Data) throws -> URL {
    let sourceDirectory = root.appendingPathComponent("source-files", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let url = sourceDirectory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url)
    return url
}

private func temporaryFileCount(in root: URL) throws -> Int {
    let temporaryDirectory = root.appendingPathComponent("tmp", isDirectory: true)
    guard FileManager.default.fileExists(atPath: temporaryDirectory.path) else {
        return 0
    }
    return try FileManager.default.contentsOfDirectory(
        at: temporaryDirectory,
        includingPropertiesForKeys: nil
    ).count
}

private func finalPayloadFileCount(in root: URL) throws -> Int {
    let bucketsDirectory = root.appendingPathComponent("buckets", isDirectory: true)
    guard FileManager.default.fileExists(atPath: bucketsDirectory.path) else {
        return 0
    }
    guard let enumerator = FileManager.default.enumerator(
        at: bucketsDirectory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return 0
    }

    var count = 0
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        if values.isRegularFile == true {
            count += 1
        }
    }
    return count
}

private func expectCancellation<Success>(_ task: Task<Success, Error>) async {
    do {
        _ = try await task.value
        Issue.record("Expected CancellationError, but operation succeeded.")
    } catch is CancellationError {
    } catch {
        Issue.record("Expected CancellationError, but received: \(error).")
    }
}

private actor TaskStartGate {
    private var waitContinuation: CheckedContinuation<Void, Never>?
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private var isWaiting = false

    func wait() async {
        await withCheckedContinuation { continuation in
            waitContinuation = continuation
            isWaiting = true
            waitingContinuation?.resume()
            waitingContinuation = nil
        }
    }

    func waitUntilWaiting() async {
        if isWaiting {
            return
        }
        await withCheckedContinuation { continuation in
            waitingContinuation = continuation
        }
    }

    func resume() {
        isWaiting = false
        waitContinuation?.resume()
        waitContinuation = nil
    }
}

private enum ConcurrencyTestError: Error {
    case missingLease
    case unexpectedPayload
}
