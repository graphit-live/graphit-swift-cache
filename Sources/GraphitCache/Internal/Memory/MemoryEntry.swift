import Foundation

internal struct MemoryEntry: Sendable {
    let bucket: CacheBucketID
    let key: CacheKey
    var data: Data
    var info: CacheEntryInfo
    var cost: ByteCount
    var expiration: MemoryExpiration
}

internal enum MemoryExpiration: Sendable {
    case never
    case fixed(Duration)
    case sliding(Duration)

    init(policy: CacheExpirationPolicy) {
        switch policy {
        case .never:
            self = .never
        case .fixed(let duration):
            self = .fixed(duration)
        case .sliding(let duration):
            self = .sliding(duration)
        }
    }

    func expiresAt(from date: Date) -> Date? {
        switch self {
        case .never:
            nil
        case .fixed(let duration), .sliding(let duration):
            date.addingCacheDuration(duration)
        }
    }

    func extendedExpiration(afterAccessAt date: Date, currentExpiresAt: Date?) -> Date? {
        switch self {
        case .never:
            nil
        case .fixed:
            currentExpiresAt
        case .sliding(let duration):
            date.addingCacheDuration(duration)
        }
    }
}

private extension Date {
    func addingCacheDuration(_ duration: Duration) -> Date {
        let components = duration.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return addingTimeInterval(seconds + attoseconds)
    }
}
