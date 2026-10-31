import XCTest
@testable import CrateCore

final class LookupQueueTests: XCTestCase {
    private static func result(for query: LookupQuery) -> LookupResult {
        LookupResult(query: query, candidates: [], isAmbiguous: false, source: .discogs, lookedUpAt: Date(timeIntervalSince1970: 0))
    }

    func testEnqueueDeduplicatesAndPersists() async throws {
        let store = InMemoryStore()
        let queue = LookupQueue(store: store)
        let first = try await queue.enqueue(.catalogueNumber("GCR 012"), shopName: "Oxfam Truro")
        let again = try await queue.enqueue(.catalogueNumber("GCR 012"), shopName: "Oxfam Truro")
        try await queue.enqueue(.matrix("GCR 012 A-1"), shopName: nil)
        XCTAssertEqual(first.id, again.id)

        let reopened = LookupQueue(store: store)
        let pending = await reopened.pending
        XCTAssertEqual(pending.map(\.query), [.catalogueNumber("GCR 012"), .matrix("GCR 012 A-1")])
        XCTAssertEqual(pending.first?.shopName, "Oxfam Truro")
    }

    func testDrainResolvesInOrderAndKeepsResultsForReview() async throws {
        let queue = LookupQueue(store: InMemoryStore())
        try await queue.enqueue(.catalogueNumber("A 1"), shopName: nil)
        try await queue.enqueue(.catalogueNumber("B 2"), shopName: nil)
        let order = OrderRecorder()

        let report = await queue.drain { query in
            order.append(query)
            return LookupQueueTests.result(for: query)
        }

        XCTAssertEqual(report, DrainReport(resolved: 2, failed: 0, remaining: 0))
        XCTAssertEqual(order.values, [.catalogueNumber("A 1"), .catalogueNumber("B 2")])
        let resolved = await queue.resolved
        XCTAssertEqual(resolved.count, 2)
        try await queue.acknowledge(id: resolved[0].id)
        let afterAck = await queue.resolved
        XCTAssertEqual(afterAck.count, 1)
    }

    func testDrainStopsWhenStillOfflineWithoutUsingUpAttempts() async throws {
        let queue = LookupQueue(store: InMemoryStore())
        try await queue.enqueue(.catalogueNumber("A 1"), shopName: nil)
        try await queue.enqueue(.catalogueNumber("B 2"), shopName: nil)
        let calls = OrderRecorder()

        let report = await queue.drain { query in
            calls.append(query)
            throw DiscogsError.offline
        }

        XCTAssertEqual(report.stoppedBecause, .offline)
        XCTAssertEqual(report.remaining, 2)
        XCTAssertEqual(calls.values.count, 1, "no point trying the second item")
        let pending = await queue.pending
        XCTAssertEqual(pending.map(\.attempts), [0, 0])
    }

    func testUnauthorisedStopsTheDrainAndRecordsTheReason() async throws {
        let queue = LookupQueue(store: InMemoryStore())
        try await queue.enqueue(.catalogueNumber("A 1"), shopName: nil)
        let report = await queue.drain { _ in throw DiscogsError.unauthorised(message: nil) }
        XCTAssertEqual(report.stoppedBecause, .unauthorised(message: nil))
        let pending = await queue.pending
        XCTAssertEqual(pending.first?.attempts, 0)
        XCTAssertNotNil(pending.first?.lastError)
    }

    func testPermanentErrorsCountUntilTheItemFails() async throws {
        let queue = LookupQueue(store: InMemoryStore(), maxAttempts: 2)
        let item = try await queue.enqueue(.catalogueNumber("A 1"), shopName: nil)
        try await queue.enqueue(.catalogueNumber("B 2"), shopName: nil)

        let first = await queue.drain { query in
            if query == .catalogueNumber("A 1") { throw DiscogsError.decoding("bad") }
            return LookupQueueTests.result(for: query)
        }
        XCTAssertEqual(first.resolved, 1, "a bad item does not block the ones behind it")
        XCTAssertEqual(first.failed, 0)

        let second = await queue.drain { _ in throw DiscogsError.decoding("bad") }
        XCTAssertEqual(second.failed, 1)
        XCTAssertEqual(second.remaining, 0)
        var pending = await queue.pending
        XCTAssertEqual(pending.first?.hasFailed, true)

        // Failed items are skipped until the user retries them.
        let third = await queue.drain { _ in XCTFail("should not run"); throw DiscogsError.offline }
        XCTAssertEqual(third.remaining, 0)

        try await queue.retry(id: item.id)
        pending = await queue.pending
        XCTAssertEqual(pending.first?.hasFailed, false)
        XCTAssertEqual(pending.first?.attempts, 0)
    }

    func testFailedItemDoesNotBlockReEnqueue() async throws {
        let queue = LookupQueue(store: InMemoryStore(), maxAttempts: 1)
        let first = try await queue.enqueue(.catalogueNumber("A 1"), shopName: nil)
        _ = await queue.drain { _ in throw DiscogsError.decoding("bad") }
        let second = try await queue.enqueue(.catalogueNumber("A 1"), shopName: nil)
        XCTAssertNotEqual(first.id, second.id)
    }
}

final class OrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [LookupQuery] = []
    var values: [LookupQuery] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: LookupQuery) { lock.lock(); _values.append(value); lock.unlock() }
}
