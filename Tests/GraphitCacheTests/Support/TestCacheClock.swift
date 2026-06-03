import Foundation
import GraphitCache
import Synchronization

final class TestCacheClock: CacheClock, Sendable {
    private let state: Mutex<Date>

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.state = Mutex(now)
    }

    func now() -> Date {
        state.withLock { date in
            date
        }
    }

    func setNow(_ date: Date) {
        state.withLock { current in
            current = date
        }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { current in
            current = current.addingTimeInterval(interval)
        }
    }
}
