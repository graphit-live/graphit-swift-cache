import Foundation

internal struct MemoryEntry: Sendable {
    let bucket: CacheBucketID
    let key: CacheKey
    var data: Data
    var info: CacheEntryInfo
    var cost: ByteCount
}
