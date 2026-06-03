import Foundation
import GraphitCache
import Testing

@Test func testCacheClockIsDeterministicAndMutable() {
    let initial = Date(timeIntervalSince1970: 10)
    let clock = TestCacheClock(now: initial)

    #expect(clock.now() == initial)

    clock.advance(by: 5)
    #expect(clock.now() == Date(timeIntervalSince1970: 15))

    let replacement = Date(timeIntervalSince1970: 100)
    clock.setNow(replacement)
    #expect(clock.now() == replacement)
}

@Test func systemCacheClockReadsCurrentDate() {
    let clock = SystemCacheClock()
    let before = Date()
    let now = clock.now()
    let after = Date()

    #expect(now >= before)
    #expect(now <= after)
}
