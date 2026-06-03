import Foundation
import GraphitCache
import Testing

@Test func diskStoreSQLiteInitializationCreatesDirectoriesSchemaAndLeanIndexes() throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }

    _ = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [BucketConfiguration(id: CacheBucketID("disk"), policy: .diskBacked(maxTotalSize: .mb(1)))]
    ))

    #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("index", isDirectory: true).path))
    #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("buckets", isDirectory: true).path))
    #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("tmp", isDirectory: true).path))
    #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("index/metadata.sqlite").path))

    let database = try SQLiteTestDatabase(url: directory.url.appendingPathComponent("index/metadata.sqlite"))
    let indexes = try database.strings(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'index' AND name NOT LIKE 'sqlite_autoindex%'
        ORDER BY name;
        """
    )

    #expect(indexes == [
        "idx_entries_bucket_lru",
        "idx_entries_bucket_stored_at",
        "idx_entries_expires_at",
        "idx_tags_tag_entry"
    ].sorted())
    #expect(try database.int("PRAGMA user_version;") == 1)
}

@Test func diskUsageReportsDiskOnlyAndCombinesWithMemoryUsage() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let memoryID = CacheBucketID("memory")
    let diskID = CacheBucketID("disk")
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [
            BucketConfiguration(id: memoryID, policy: .memoryOnly(maxTotalSize: .bytes(100))),
            BucketConfiguration(id: diskID, policy: .diskBacked(maxTotalSize: .bytes(100)))
        ],
        clock: TestCacheClock()
    ))
    let memory = try store.bucket(memoryID)
    let disk = try store.bucket(diskID)

    try await memory.setData(Data([1, 2]), for: CacheKey("m"))
    try await disk.setData(Data([3, 4, 5]), for: CacheKey("d"))

    let diskUsage = try await disk.usage()
    #expect(diskUsage.bucket == diskID)
    #expect(diskUsage.totalSize == .bytes(3))
    #expect(diskUsage.diskSize == .bytes(3))
    #expect(diskUsage.memorySize == .zero)
    #expect(diskUsage.entryCount == 1)

    let storeUsage = try await store.usage()
    #expect(storeUsage.totalSize == .bytes(5))
    #expect(storeUsage.diskSize == .bytes(3))
    #expect(storeUsage.memorySize == .bytes(2))
    #expect(storeUsage.entryCount == 2)
}

@Test func diskRemovalSelectorsRemoveMetadataTagsAndPayloadFiles() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let clock = TestCacheClock(now: Date(timeIntervalSince1970: 10))
    let store = try CacheStore(configuration: CacheStoreConfiguration(
        rootDirectory: directory.url,
        buckets: [BucketConfiguration(id: CacheBucketID("disk"), policy: .diskBacked(maxTotalSize: .bytes(100)))],
        clock: clock
    ))
    let disk = try store.bucket(CacheBucketID("disk"))
    let shared = CacheTag("shared")

    try await disk.setData(Data([1]), for: CacheKey("tagged"), options: .init(tags: [shared]))
    let optionalTaggedRef = try SQLiteTestDatabase(url: directory.url.appendingPathComponent("index/metadata.sqlite"))
        .storageRef(bucket: "disk", key: "tagged")
    let taggedRef = try #require(optionalTaggedRef)

    try await disk.setData(Data([2, 2]), for: CacheKey("untagged"))

    let taggedRemoval = try await store.removeAll(tagged: shared)
    #expect(taggedRemoval == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(1)))
    #expect(try await disk.dataInfo(for: CacheKey("tagged")) == nil)
    #expect(try await disk.dataInfo(for: CacheKey("untagged")) != nil)
    #expect(!FileManager.default.fileExists(atPath: directory.url.appendingStorageRefForDiskStoreTest(taggedRef).path))
    #expect(try SQLiteTestDatabase(url: directory.url.appendingPathComponent("index/metadata.sqlite"))
        .int("SELECT COUNT(*) FROM tags;") == 0)

    clock.setNow(Date(timeIntervalSince1970: 20))
    try await disk.setData(Data([3]), for: CacheKey("newer"))

    let oldRemoval = try await disk.removeAll(insertedBefore: Date(timeIntervalSince1970: 20))
    #expect(oldRemoval == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(2)))
    #expect(try await disk.dataInfo(for: CacheKey("untagged")) == nil)
    #expect(try await disk.dataInfo(for: CacheKey("newer")) != nil)

    let allRemoval = try await store.removeAll()
    #expect(allRemoval == CacheRemovalResult(removedEntries: 1, removedBytes: .bytes(1)))
    #expect(try await disk.usage().entryCount == 0)
}

private extension URL {
    func appendingStorageRefForDiskStoreTest(_ storageRef: String) -> URL {
        storageRef.split(separator: "/").reduce(self) { url, component in
            url.appendingPathComponent(String(component), isDirectory: false)
        }
    }
}
