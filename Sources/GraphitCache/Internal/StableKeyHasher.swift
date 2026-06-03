import CryptoKit
import Foundation

internal enum StableKeyHasher {
    static func entryID(bucket: CacheBucketID, key: CacheKey) -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(bucket.rawValue.utf8.count + 1 + key.rawValue.utf8.count)
        bytes.append(contentsOf: bucket.rawValue.utf8)
        bytes.append(0)
        bytes.append(contentsOf: key.rawValue.utf8)

        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
