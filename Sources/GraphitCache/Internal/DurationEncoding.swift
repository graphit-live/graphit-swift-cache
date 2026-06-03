import Foundation

internal enum CacheDurationEncoding {
    private static let microsecondsPerSecond: Int64 = 1_000_000
    private static let attosecondsPerMicrosecond: Int64 = 1_000_000_000_000

    static func microseconds(_ duration: Duration) throws -> Int64 {
        let components = duration.components
        let secondsResult = components.seconds.multipliedReportingOverflow(by: microsecondsPerSecond)
        guard !secondsResult.overflow else {
            throw CacheError.invalidConfiguration("Duration is outside the supported range.")
        }

        var total = secondsResult.partialValue
        let attoseconds = components.attoseconds
        if attoseconds >= 0 {
            let wholeMicroseconds = attoseconds / attosecondsPerMicrosecond
            let remainder = attoseconds % attosecondsPerMicrosecond
            total = try adding(wholeMicroseconds, to: total)
            if remainder > 0 {
                total = try adding(1, to: total)
            }
        } else {
            let wholeMicroseconds = attoseconds / attosecondsPerMicrosecond
            let remainder = attoseconds % attosecondsPerMicrosecond
            total = try adding(wholeMicroseconds, to: total)
            if remainder < 0 {
                total = try adding(-1, to: total)
            }
        }

        return total
    }

    private static func adding(_ value: Int64, to total: Int64) throws -> Int64 {
        let result = total.addingReportingOverflow(value)
        guard !result.overflow else {
            throw CacheError.invalidConfiguration("Duration is outside the supported range.")
        }
        return result.partialValue
    }
}
