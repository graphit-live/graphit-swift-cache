import Foundation

/// The identifier for a configured cache bucket.
///
/// Bucket IDs are app-defined stable names for policy and quota boundaries. Disk-backed stores
/// validate bucket IDs as filesystem-safe path components when configurations or operations use them.
public struct CacheBucketID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    /// The raw app-defined bucket identifier.
    public let rawValue: String

    /// Creates a bucket identifier from a raw string.
    ///
    /// - Parameter rawValue: The app-defined bucket identifier.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a bucket identifier from a raw string.
    ///
    /// - Parameter rawValue: The app-defined bucket identifier.
    public init(rawValue: String) {
        self.init(rawValue)
    }

    /// A textual representation of the bucket identifier.
    public var description: String {
        rawValue
    }
}

/// An app-defined grouping label attached to cache entries.
///
/// Tags are useful for broad removal and app-owned categorization. GraphitCache does not assign
/// semantic meaning such as MIME type or model kind to tags. Avoid storing secrets in tags if your
/// app logs or displays their raw values.
public struct CacheTag: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    /// The raw app-defined tag value.
    public let rawValue: String

    /// Creates a cache tag from a raw string.
    ///
    /// - Parameter rawValue: The app-defined tag value.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a cache tag from a raw string.
    ///
    /// - Parameter rawValue: The app-defined tag value.
    public init(rawValue: String) {
        self.init(rawValue)
    }

    /// A textual representation of the tag.
    public var description: String {
        rawValue
    }
}

/// The app-defined identity for a cached entry within a bucket.
///
/// A single key maps to at most one current entry in a bucket. That entry is either data-backed or
/// file-backed. Raw keys are never used directly as disk payload paths. Avoid storing secrets in
/// keys if your app logs or displays their raw values.
public struct CacheKey: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    /// The raw app-defined cache key.
    public let rawValue: String

    /// Creates a cache key from a raw string.
    ///
    /// - Parameter rawValue: The app-defined cache key.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a cache key from a raw string.
    /// - Parameter rawValue: The app-defined cache key.
    public init(rawValue: String) {
        self.init(rawValue)
    }

    /// A textual representation of the key.
    public var description: String {
        rawValue
    }
}
