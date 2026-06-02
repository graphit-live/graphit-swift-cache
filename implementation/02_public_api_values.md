# Public API: values, identifiers, keys

All public declarations require doc comments in implementation. All listed types are `Sendable` where declared.

## ByteCount

```swift
public struct ByteCount: Hashable, Comparable, Codable, Sendable, ExpressibleByIntegerLiteral {
    public let bytes: Int64
    public init(_ bytes: Int64)
    public init(integerLiteral value: Int64)
    public static func bytes(_ value: Int64) -> ByteCount
    public static func kb(_ value: Int64) -> ByteCount
    public static func mb(_ value: Int64) -> ByteCount
    public static func gb(_ value: Int64) -> ByteCount
    public static let zero: ByteCount
    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool
}
```

Constants/units: `zero = 0`; `kb = 1024`; `mb = 1024 * 1024`; `gb = 1024 * 1024 * 1024`. Unit helpers may precondition overflow; validation rejects negative sizes.

No public `Duration.minutes/hours/days` helpers in v1.

## String-backed identifiers

```swift
public struct CacheBucketID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init(rawValue: String)
    public var description: String { get }
}

public struct CacheTag: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init(rawValue: String)
    public var description: String { get }
}

public struct CacheKey: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init(rawValue: String)
    public var description: String { get }
}
```

Why not raw `String` everywhere:

- prevents accidentally passing a tag where a key is expected;
- prevents accidentally passing a bucket ID where a key is expected;
- gives apps a clear schema extension point;
- follows common Swift SDK style for string-backed domain names.

Example:

```swift
extension CacheKey {
    static func profile(_ id: String) -> Self { Self("profile:\(id)") }
}

try await profiles.data(.profile(userID))
```

No `ExpressibleByStringLiteral`: this keeps call sites explicit and discourages scattered magic strings.

`CacheBucketID` is validated with a strict filesystem-safe whitelist when used: ASCII letters, numbers, `.`, `_`, `-`; length <= 128; empty, `.`, and `..` are invalid.

Tags are app-defined grouping labels. Apps can use tags such as `kind:profile`, `format:json`, `feed:home`, or `user:123`.

No public `CacheKind` or `CacheContentType` in v1.

## Keys

One bucket key maps to one cached entry. The current entry is either data-backed or file-backed.

No `CacheDataKey`, `CacheFileKey`, or `CacheValueKey<Value>` in v1. Consumers encode models into `Data` and decode returned `CachedData.data` themselves.

## Storage

```swift
public enum CacheStorageMode: Sendable, Hashable {
    case memoryOnly
    case diskBacked
}
```

No `Codable` conformance for runtime storage mode in v1. Apps that need persisted configuration can define their own codable app config and map it to GraphitCache.

No public `CachePayloadKind` in v1. The data/file distinction is visible through operations. Internally use `StoredPayloadKind` for metadata only.
