import Foundation

/// A strongly typed byte count used for cache sizes, limits, and usage snapshots.
public struct ByteCount: Hashable, Comparable, Codable, Sendable, ExpressibleByIntegerLiteral {
    /// The number of bytes represented by this value.
    public let bytes: Int64

    /// Creates a byte count from a raw byte value.
    ///
    /// Negative values can be represented so invalid policy input can be reported during validation.
    /// Cache policies reject negative sizes when they are used.
    ///
    /// - Parameter bytes: The raw byte value.
    public init(_ bytes: Int64) {
        self.bytes = bytes
    }

    /// Creates a byte count from an integer literal.
    ///
    /// - Parameter value: The raw byte value.
    public init(integerLiteral value: Int64) {
        self.init(value)
    }

    /// Creates a byte count from a raw byte value.
    ///
    /// - Parameter value: The raw byte value.
    /// - Returns: A byte count representing `value` bytes.
    public static func bytes(_ value: Int64) -> ByteCount {
        ByteCount(value)
    }

    /// Creates a byte count from kibibytes using a 1024-byte unit.
    ///
    /// - Parameter value: The number of kibibytes.
    /// - Returns: A byte count representing `value * 1024` bytes.
    public static func kb(_ value: Int64) -> ByteCount {
        ByteCount(value * 1024)
    }

    /// Creates a byte count from mebibytes using a 1024-byte unit.
    ///
    /// - Parameter value: The number of mebibytes.
    /// - Returns: A byte count representing `value * 1024 * 1024` bytes.
    public static func mb(_ value: Int64) -> ByteCount {
        ByteCount(value * 1024 * 1024)
    }

    /// Creates a byte count from gibibytes using a 1024-byte unit.
    ///
    /// - Parameter value: The number of gibibytes.
    /// - Returns: A byte count representing `value * 1024 * 1024 * 1024` bytes.
    public static func gb(_ value: Int64) -> ByteCount {
        ByteCount(value * 1024 * 1024 * 1024)
    }

    /// A byte count representing zero bytes.
    public static let zero = ByteCount(0)

    /// Returns whether the left-hand byte count is smaller than the right-hand byte count.
    ///
    /// - Parameters:
    ///   - lhs: The first byte count.
    ///   - rhs: The second byte count.
    /// - Returns: `true` when `lhs.bytes` is less than `rhs.bytes`.
    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool {
        lhs.bytes < rhs.bytes
    }
}
