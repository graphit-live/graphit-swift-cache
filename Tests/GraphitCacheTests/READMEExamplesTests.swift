import Foundation
import GraphitCache
import Testing

private enum READMEAppCache {
    enum Buckets {
        static let profiles = CacheBucketID("profiles")
        static let reels = CacheBucketID("reels")
    }

    enum Tags {
        static let profile = CacheTag("kind:profile")
        static let reel = CacheTag("kind:reel")
        static let homeFeed = CacheTag("feed:home")
        static func user(_ id: String) -> CacheTag { CacheTag("user:\(id)") }
    }
}

private extension CacheKey {
    static func readmeProfile(_ id: String) -> Self { Self("profile:\(id)") }
    static func readmeReel(_ id: String) -> Self { Self("reel:\(id)") }
}

private struct READMEProfile: Codable, Equatable {
    var name: String
}

@Test func readmeMemoryConfigurationExampleCompiles() throws {
    let cache = try CacheStore(configuration: .init(
        rootDirectory: nil,
        buckets: [
            .init(
                id: READMEAppCache.Buckets.profiles,
                policy: .memoryOnly(
                    maxTotalSize: .mb(50),
                    maxItemSize: .mb(1),
                    maxItemCount: 1_000
                )
            )
        ]
    ))

    #expect(cache.configuredBuckets() == [READMEAppCache.Buckets.profiles])
}

@Test func readmeDataEncodingExampleCompiles() async throws {
    let cache = try CacheStore(configuration: .init(
        rootDirectory: nil,
        buckets: [
            .init(
                id: READMEAppCache.Buckets.profiles,
                policy: .memoryOnly(maxTotalSize: .mb(1))
            )
        ]
    ))
    let profiles = try cache.bucket(READMEAppCache.Buckets.profiles)
    let userID = "123"
    let key = CacheKey.readmeProfile(userID)
    let profile = READMEProfile(name: "Blob")
    let data = try JSONEncoder().encode(profile)

    try await profiles.setData(
        data,
        for: key,
        options: .init(tags: [READMEAppCache.Tags.profile, READMEAppCache.Tags.user(userID)])
    )

    let cached = try #require(try await profiles.data(key))
    let decoded = try JSONDecoder().decode(READMEProfile.self, from: cached.data)

    #expect(decoded == profile)
}

@Test func readmeFileLeaseExampleCompiles() async throws {
    let directory = try TemporaryCacheDirectory()
    defer { directory.remove() }
    let cache = try CacheStore(configuration: .init(
        rootDirectory: directory.url,
        buckets: [
            .init(
                id: READMEAppCache.Buckets.reels,
                policy: .diskBacked(maxTotalSize: .mb(10), maxItemSize: .mb(1))
            )
        ]
    ))
    let reels = try cache.bucket(READMEAppCache.Buckets.reels)
    let sourceURL = directory.url.appendingPathComponent("download.mp4", isDirectory: false)
    try Data([1, 2, 3]).write(to: sourceURL)

    try await reels.setFile(
        at: sourceURL,
        for: .readmeReel("42"),
        options: .init(
            tags: [READMEAppCache.Tags.reel, READMEAppCache.Tags.homeFeed],
            fileExtension: "mp4"
        )
    )

    let lease = try #require(try await reels.leaseFile(.readmeReel("42")))
    defer { lease.release() }

    #expect(lease.url.pathExtension == "mp4")
    #expect(try Data(contentsOf: lease.url) == Data([1, 2, 3]))
}
