import Foundation

/// A clock used by GraphitCache for timestamps and expiration decisions.
public protocol CacheClock: Sendable {
    /// Returns the current date.
    ///
    /// - Returns: The current date according to this clock.
    func now() -> Date
}

/// A cache clock backed by the system wall clock.
public struct SystemCacheClock: CacheClock {
    /// Creates a system cache clock.
    public init() {}

    /// Returns the current system date.
    ///
    /// - Returns: The current date.
    public func now() -> Date {
        Date()
    }
}
