import XCTest
@testable import CrateCore

final class RateLimiterTests: XCTestCase {
    func testAllowsBurstUpToLimitMinusReserve() async {
        let clock = TestClock()
        let limiter = RateLimiter(policy: .init(window: 60, defaultLimit: 5, reserve: 1), now: { clock.now })
        for _ in 0..<4 {
            let wait = await limiter.reserveSlot()
            XCTAssertEqual(wait, 0)
        }
        // Fifth request has to wait for the first to leave the 60 second window.
        let wait = await limiter.reserveSlot()
        XCTAssertEqual(wait, 60, accuracy: 0.001)
    }

    func testSlotsFreeUpAsTheWindowMoves() async {
        let clock = TestClock()
        let limiter = RateLimiter(policy: .init(window: 60, defaultLimit: 3, reserve: 0), now: { clock.now })
        _ = await limiter.reserveSlot()
        clock.advance(20)
        _ = await limiter.reserveSlot()
        clock.advance(20)
        _ = await limiter.reserveSlot()
        clock.advance(5)
        // Oldest slot was 45 seconds ago, so 15 seconds to wait.
        let wait = await limiter.reserveSlot()
        XCTAssertEqual(wait, 15, accuracy: 0.001)
    }

    func testConcurrentCallersQueueRatherThanStampede() async {
        let clock = TestClock()
        let limiter = RateLimiter(policy: .init(window: 60, defaultLimit: 2, reserve: 0), now: { clock.now })
        var waits: [TimeInterval] = []
        for _ in 0..<6 { waits.append(await limiter.reserveSlot()) }
        XCTAssertEqual(waits, [0, 0, 60, 60, 120, 120])
    }

    func testHeadersUpdateLimitAndPauseWhenNearlyExhausted() async {
        let clock = TestClock()
        let limiter = RateLimiter(policy: .init(window: 60, defaultLimit: 60, reserve: 2), now: { clock.now })
        await limiter.record(headers: ["X-Discogs-Ratelimit": "25", "X-Discogs-Ratelimit-Remaining": "1"])
        let limit = await limiter.currentLimit
        XCTAssertEqual(limit, 25)
        // 60 / 25 = 2.4 seconds per request, two requests' worth because remaining is one below the reserve.
        let wait = await limiter.reserveSlot()
        XCTAssertEqual(wait, 4.8, accuracy: 0.001)
    }

    func testHeadersWithPlentyRemainingDoNotPause() async {
        let clock = TestClock()
        let limiter = RateLimiter(now: { clock.now })
        await limiter.record(headers: ["x-discogs-ratelimit": "60", "x-discogs-ratelimit-remaining": "40"])
        let wait = await limiter.reserveSlot()
        XCTAssertEqual(wait, 0)
    }

    func testBackoffIsExponentialCappedAndJittered() async {
        let clock = TestClock()
        let limiter = RateLimiter(
            policy: .init(baseBackoff: 2, maxBackoff: 30, jitter: 0.5),
            now: { clock.now },
            random: { 1 }
        )
        let first = await limiter.backoff(attempt: 0, retryAfter: nil)
        let second = await limiter.backoff(attempt: 1, retryAfter: nil)
        let capped = await limiter.backoff(attempt: 6, retryAfter: nil)
        XCTAssertEqual(first, 3, accuracy: 0.001)
        XCTAssertEqual(second, 6, accuracy: 0.001)
        XCTAssertEqual(capped, 30, accuracy: 0.001)
    }

    func testBackoffPausesOtherCallers() async {
        let clock = TestClock()
        let limiter = RateLimiter(policy: .init(jitter: 0), now: { clock.now })
        _ = await limiter.backoff(attempt: 0, retryAfter: 10)
        clock.advance(4)
        let wait = await limiter.reserveSlot()
        XCTAssertEqual(wait, 6, accuracy: 0.001)
    }
}
