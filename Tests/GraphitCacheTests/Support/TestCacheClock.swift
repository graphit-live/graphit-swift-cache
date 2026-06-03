import Dispatch
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

final class BlockingCacheClock: CacheClock, Sendable {
    private struct State: Sendable {
        var now: Date
        var shouldBlockNextCall = false
        var isBlocked = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state: Mutex<State>
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.state = Mutex(State(now: now))
    }

    func now() -> Date {
        let result = state.withLock { state in
            let date = state.now
            guard state.shouldBlockNextCall else {
                return (date: date, shouldBlock: false, waiter: nil as CheckedContinuation<Void, Never>?)
            }

            state.shouldBlockNextCall = false
            state.isBlocked = true
            let waiter = state.waiter
            state.waiter = nil
            return (date: date, shouldBlock: true, waiter: waiter)
        }

        if result.shouldBlock {
            result.waiter?.resume()
            releaseSemaphore.wait()
        }

        return result.date
    }

    func setNow(_ date: Date) {
        state.withLock { state in
            state.now = date
        }
    }

    func blockNextNow() {
        state.withLock { state in
            state.shouldBlockNextCall = true
            state.isBlocked = false
        }
    }

    func waitUntilBlocked() async {
        if state.withLock({ state in state.isBlocked }) {
            return
        }

        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                if state.isBlocked {
                    return true
                }
                state.waiter = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func releaseBlockedNow() {
        let shouldSignal = state.withLock { state in
            guard state.isBlocked else {
                return false
            }
            state.isBlocked = false
            return true
        }

        if shouldSignal {
            releaseSemaphore.signal()
        }
    }
}
