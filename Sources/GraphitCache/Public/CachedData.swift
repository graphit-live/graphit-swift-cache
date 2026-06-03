import Foundation

/// A cached `Data` payload and its metadata.
public struct CachedData: Sendable {
    /// The cached data bytes.
    public let data: Data

    /// Metadata describing the cached entry.
    public let info: CacheEntryInfo

    /// Creates a cached data value.
    ///
    /// - Parameters:
    ///   - data: The cached data bytes.
    ///   - info: Metadata describing the cached entry.
    public init(data: Data, info: CacheEntryInfo) {
        self.data = data
        self.info = info
    }
}
