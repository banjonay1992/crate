import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CrateCore

final class SyncServiceTests: XCTestCase {
    private let collectionPath = "/users/example_digger/collection/folders/0/releases"
    private let wantsPath = "/users/example_digger/wants"

    func testSyncStoresSnapshotAndPrefetchesWantlistDetails() async throws {
        let transport = MockTransport()
        transport.on(collectionPath, .json("collection_page1"), .json("collection_page2"))
        transport.on(wantsPath, .json("wants_page1"))
        transport.on("/releases/4000003", .json("release_4000003"))
        transport.on("/releases/4000004", .json("release_4000004"))
        let cache = LibraryCache(store: InMemoryStore())
        let sync = SyncService(api: DiscogsClient.test(transport: transport), cache: cache)
        let events = EventRecorder()

        let report = try await sync.sync(username: "example_digger", prefetchWantlistDetails: true) { events.append($0) }

        XCTAssertEqual(report.collectionCount, 3)
        XCTAssertEqual(report.wantCount, 2)
        XCTAssertEqual(report.detailsFetched, 2)
        XCTAssertEqual(report.detailsOutstanding, 0)
        let snapshot = await cache.snapshot
        XCTAssertEqual(snapshot?.username, "example_digger")
        let has3 = await cache.hasRelease(id: 4000003)
        XCTAssertTrue(has3)
        XCTAssertEqual(events.values.last, .releaseDetails(fetched: 2, total: 2))
        XCTAssertTrue(events.values.contains(.collection(fetched: 3, total: 3)))

        // Offline barcode matching against the wantlist now works.
        let local = await cache.localCandidates(for: .barcode(Barcode("4009876500313")!))
        XCTAssertEqual(local.map(\.summary.id), [4000003])
    }

    func testSecondSyncOnlyFetchesMissingDetails() async throws {
        let transport = MockTransport()
        transport.on(collectionPath, .json("collection_page1"), .json("collection_page2"), .json("collection_page1"), .json("collection_page2"))
        transport.on(wantsPath, .json("wants_page1"))
        transport.on("/releases/4000003", .json("release_4000003"))
        transport.on("/releases/4000004", .json("release_4000004"))
        let cache = LibraryCache(store: InMemoryStore())
        let sync = SyncService(api: DiscogsClient.test(transport: transport), cache: cache)

        _ = try await sync.sync(username: "example_digger", prefetchWantlistDetails: true)
        let second = try await sync.sync(username: "example_digger", prefetchWantlistDetails: true)

        XCTAssertEqual(second.detailsFetched, 0)
        XCTAssertEqual(transport.requests(to: "/releases/4000003").count, 1)
    }

    func testPrefetchCapAndInterruptedPrefetchKeepProgress() async throws {
        let transport = MockTransport()
        transport.on(collectionPath, .json("collection_page1"), .json("collection_page2"))
        transport.on(wantsPath, .json("wants_page1"))
        transport.on("/releases/4000003", .json("release_4000003"))
        transport.on("/releases/4000004", .fail(URLError(.networkConnectionLost)))
        let cache = LibraryCache(store: InMemoryStore())
        let sync = SyncService(api: DiscogsClient.test(transport: transport), cache: cache)

        let report = try await sync.sync(username: "example_digger", prefetchWantlistDetails: true)

        XCTAssertEqual(report.detailsFetched, 1)
        XCTAssertEqual(report.detailsOutstanding, 1)
        let has3 = await cache.hasRelease(id: 4000003)
        XCTAssertTrue(has3)
    }

    func testWithoutPrefetchNoDetailRequests() async throws {
        let transport = MockTransport()
        transport.on(collectionPath, .json("collection_page1"), .json("collection_page2"))
        transport.on(wantsPath, .json("wants_page1"))
        let sync = SyncService(api: DiscogsClient.test(transport: transport), cache: LibraryCache(store: InMemoryStore()))
        let report = try await sync.sync(username: "example_digger", prefetchWantlistDetails: false)
        XCTAssertEqual(report.detailsFetched, 0)
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasPrefix("/releases/") == true })
    }

    func testSyncFailsCleanlyWhenOffline() async {
        let transport = MockTransport()
        transport.failEverything(with: URLError(.notConnectedToInternet))
        let cache = LibraryCache(store: InMemoryStore())
        let sync = SyncService(api: DiscogsClient.test(transport: transport), cache: cache)
        do {
            _ = try await sync.sync(username: "example_digger", prefetchWantlistDetails: true)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .offline)
        }
        let snapshot = await cache.snapshot
        XCTAssertNil(snapshot, "a failed sync leaves the old snapshot alone")
    }
}

final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [SyncProgress] = []
    var values: [SyncProgress] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: SyncProgress) { lock.lock(); _values.append(value); lock.unlock() }
}
