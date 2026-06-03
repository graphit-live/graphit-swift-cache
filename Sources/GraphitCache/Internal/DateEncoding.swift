import Foundation

internal enum CacheDateEncoding {
    private static let microsecondsPerSecond: Double = 1_000_000

    static func microsecondsSinceEpoch(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * microsecondsPerSecond).rounded(.towardZero))
    }

    static func date(microsecondsSinceEpoch microseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(microseconds) / microsecondsPerSecond)
    }

    static func adding(_ microsecondsToAdd: Int64, to microseconds: Int64) throws -> Int64 {
        let result = microseconds.addingReportingOverflow(microsecondsToAdd)
        guard !result.overflow else {
            throw CacheError.invalidConfiguration("Expiration date is outside the supported range.")
        }
        return result.partialValue
    }
}
