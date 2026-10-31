import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CrateCore

final class LookupServiceTests: XCTestCase {
    private var transport: MockTransport!
    private var cache: LibraryCache!
    private var queue: LookupQueue!
    private var clock: TestClock!
    private var service: LookupService!

    override func setUp() async throws {
        transport = MockTransport()
        clock = TestClock()
        let now: @Sendable () -> Date = { [clock] in clock!.now }
        cache = LibraryCache(store: InMemoryStore(), now: now)
        queue = LookupQueue(store: InMemoryStore(), now: now)
        service = LookupService(api: DiscogsClient.test(transport: transport), cache: cache, queue: queue, now: now)
        try await cache.save(snapshot: LibrarySnapshot(username: "example_digger", collection: Fixtures.collection, wants: Fixtures.wants, syncedAt: clock.now))
    }

    private func searchValues(_ name: String) -> [String] {
        transport.requests(to: "/database/search").compactMap {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
    }

    func testBarcodeLookupIdentifiesPressingWithOwnershipAndPrice() async throws {
        transport.on("/database/search", .json("search_barcode"))
        transport.on("/releases/4000002", .json("release_4000002"))
        transport.on("/marketplace/stats/4000002", .json("marketplace_stats_4000002"))
        transport.on("/marketplace/price_suggestions/4000002", .status(404, body: #"{"message":"Seller settings required"}"#))

        let result = try await service.lookup(.barcode(Barcode("5012345600291")!), options: LookupOptions(currency: "GBP"))

        let match = try XCTUnwrap(result.bestMatch)
        XCTAssertEqual(match.id, 4000002)
        XCTAssertEqual(match.evidence, .barcode)
        XCTAssertNotNil(match.release, "details were fetched")
        XCTAssertEqual(result.source, .discogs)
        XCTAssertEqual(result.ownership(for: 4000002).headline, .wantedOtherPressing)
        XCTAssertEqual(result.ownership(for: 4000002).otherPressingsOwned.map(\.id), [4000001])
        let price = try XCTUnwrap(result.prices[4000002])
        XCTAssertEqual(price.stats?.numForSale, 0)
        XCTAssertTrue(price.suggestions.isEmpty, "missing seller settings is not an error")
        let cachedRelease = await cache.hasRelease(id: 4000002)
        XCTAssertTrue(cachedRelease)
    }

    func testUPCFallsBackToEAN13Form() async throws {
        transport.on("/database/search", .json("search_empty"), .json("search_upc"))
        transport.on("/releases/4000004", .json("release_4000004"))
        transport.on("/marketplace/stats/4000004", .json("marketplace_stats_4000002"))

        let result = try await service.lookup(.barcode(Barcode("073311224458")!), options: LookupOptions(includePriceSuggestions: false))

        XCTAssertEqual(searchValues("barcode"), ["073311224458", "0073311224458"])
        XCTAssertEqual(result.bestMatch?.id, 4000004)
        XCTAssertTrue(result.ownership(for: 4000004).isWanted)
        XCTAssertTrue(transport.requests(to: "/marketplace/price_suggestions/4000004").isEmpty)
    }

    func testSharedCatalogueNumberIsAmbiguousWithRunOutHints() async throws {
        transport.on("/database/search", .json("search_catno"))
        transport.on("/releases/4000001", .json("release_4000001"))
        transport.on("/releases/4000002", .json("release_4000002"))

        let result = try await service.lookup(.catalogueNumber("GCR 012"), options: LookupOptions())

        XCTAssertTrue(result.isAmbiguous)
        XCTAssertNil(result.bestMatch)
        XCTAssertEqual(result.choices.map(\.id), [4000001, 4000002])
        XCTAssertEqual(result.distinguishingMatrices[4000001], ["GCR 012 A-1 PORKY", "GCR 012 B-1"])
        XCTAssertEqual(result.ownership(for: 4000001).ownedCopies, 2)
        XCTAssertTrue(result.prices.isEmpty, "prices wait until the user picks a pressing")
        XCTAssertTrue(transport.requests(to: "/marketplace/stats/4000001").isEmpty)
    }

    func testDetailFetchesAreCapped() async throws {
        transport.on("/database/search", .json("search_catno"))
        transport.on("/releases/4000001", .json("release_4000001"))
        _ = try await service.lookup(.catalogueNumber("GCR 012"), options: LookupOptions(maxDetailFetches: 1))
        let releaseRequests = transport.requests.filter { $0.url?.path.hasPrefix("/releases/") == true }
        XCTAssertEqual(releaseRequests.count, 1)
    }

    func testCachedReleaseDetailsAreReused() async throws {
        try await cache.store(releases: [Fixtures.release(4000002)])
        transport.on("/database/search", .json("search_barcode"))
        transport.on("/marketplace/stats/4000002", .json("marketplace_stats_4000002"))
        _ = try await service.lookup(.barcode(Barcode("5012345600291")!), options: LookupOptions(includePriceSuggestions: false))
        XCTAssertTrue(transport.requests(to: "/releases/4000002").isEmpty)
    }

    func testCatalogueNumberFallsBackToTextSearch() async throws {
        transport.on("/database/search", .json("search_empty"), .json("search_catno"))
        transport.on("/releases/4000001", .json("release_4000001"))
        transport.on("/releases/4000002", .json("release_4000002"))
        _ = try await service.lookup(.catalogueNumber("GCR012"), options: LookupOptions())
        XCTAssertEqual(searchValues("catno"), ["GCR012"])
        XCTAssertEqual(searchValues("q"), ["GCR012"])
    }

    func testMatrixSearchTriesIdentifierFieldFirst() async throws {
        transport.on("/database/search", .json("search_catno"))
        transport.on("/releases/4000001", .json("release_4000001"))
        transport.on("/releases/4000002", .json("release_4000002"))
        transport.on("/marketplace/stats/4000002", .json("marketplace_stats_4000002"))

        let result = try await service.lookup(.matrix("GCR012-A2 RE"), options: LookupOptions(includePriceSuggestions: false))

        XCTAssertEqual(searchValues("barcode"), ["GCR012-A2 RE"])
        XCTAssertEqual(result.bestMatch?.id, 4000002)
        XCTAssertEqual(result.bestMatch?.evidence, .matrixExact)
    }

    func testNoResults() async throws {
        transport.on("/database/search", .json("search_empty"))
        let result = try await service.lookup(.catalogueNumber("ZZZ 999"), options: LookupOptions())
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.bestMatch)
    }

    func testOfflineLookupIsQueuedWithLocalAnswer() async throws {
        try await cache.store(releases: [Fixtures.release(4000001)])
        try await cache.store(price: PriceInfo(releaseID: 4000001, currency: "GBP", stats: MarketplaceStats(lowestPrice: Money(amount: 18, currency: "GBP"), numForSale: 3), suggestions: [], fetchedAt: clock.now))
        transport.failEverything(with: URLError(.notConnectedToInternet))

        let outcome = try await service.lookupOrQueue(.barcode(Barcode("5012345600123")!), shopName: "Redruth market", options: LookupOptions())

        guard case .queued(let pending, let local) = outcome else { return XCTFail("Expected queued, got \(outcome)") }
        XCTAssertEqual(pending.shopName, "Redruth market")
        let localResult = try XCTUnwrap(local)
        XCTAssertEqual(localResult.source, .deviceCache)
        XCTAssertEqual(localResult.bestMatch?.id, 4000001)
        XCTAssertEqual(localResult.ownership(for: 4000001).ownedCopies, 2)
        XCTAssertEqual(localResult.prices[4000001]?.stats?.numForSale, 3)
        let queued = await queue.pending
        XCTAssertEqual(queued.count, 1)
    }

    func testOfflineCatalogueLookupFindsWantlistItem() async throws {
        transport.failEverything(with: URLError(.timedOut))
        let outcome = try await service.lookupOrQueue(.catalogueNumber("ks 6.24011"), shopName: nil, options: LookupOptions())
        guard case .queued(_, let local) = outcome else { return XCTFail("Expected queued") }
        XCTAssertEqual(local?.candidates.first?.id, 4000003)
        XCTAssertTrue(local?.ownership(for: 4000003).isWanted ?? false)
    }

    func testOfflineWithNothingLocalStillQueues() async throws {
        transport.failEverything(with: URLError(.notConnectedToInternet))
        let outcome = try await service.lookupOrQueue(.catalogueNumber("ZZZ 1"), shopName: nil, options: LookupOptions())
        guard case .queued(_, let local) = outcome else { return XCTFail("Expected queued") }
        XCTAssertNil(local)
    }

    func testAuthFailureIsNotQueued() async {
        transport.on("/database/search", .json("error_401", status: 401))
        do {
            _ = try await service.lookupOrQueue(.catalogueNumber("GCR 012"), shopName: nil, options: LookupOptions())
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .unauthorised(message: "You must authenticate to access this resource."))
        }
        let queued = await queue.pending
        XCTAssertTrue(queued.isEmpty)
    }

    func testQueuedLookupResolvesWhenBackOnline() async throws {
        transport.failEverything(with: URLError(.notConnectedToInternet))
        _ = try await service.lookupOrQueue(.barcode(Barcode("5012345600291")!), shopName: nil, options: LookupOptions())

        transport.reset()
        transport.on("/database/search", .json("search_barcode"))
        transport.on("/releases/4000002", .json("release_4000002"))
        transport.on("/marketplace/stats/4000002", .json("marketplace_stats_4000002"))
        let service = self.service!
        let report = await queue.drain { query in
            try await service.lookup(query, options: LookupOptions(includePriceSuggestions: false))
        }

        XCTAssertEqual(report.resolved, 1)
        let resolved = await queue.resolved
        XCTAssertEqual(resolved.first?.result.bestMatch?.id, 4000002)
    }

    func testPriceInfoUsesFreshCacheAndRefetchesStaleOrOtherCurrency() async throws {
        transport.on("/marketplace/stats/4000001", .json("marketplace_stats_4000001"))
        transport.on("/marketplace/price_suggestions/4000001", .json("price_suggestions_4000001"))
        let options = LookupOptions(currency: "GBP")

        let first = try await service.priceInfo(for: 4000001, options: options)
        XCTAssertEqual(first.suggestions.count, 8)
        _ = try await service.priceInfo(for: 4000001, options: options)
        XCTAssertEqual(transport.requests(to: "/marketplace/stats/4000001").count, 1, "fresh cache reused")

        _ = try await service.priceInfo(for: 4000001, options: LookupOptions(currency: "EUR"))
        XCTAssertEqual(transport.requests(to: "/marketplace/stats/4000001").count, 2, "different currency refetched")

        clock.advance(25 * 3600)
        _ = try await service.priceInfo(for: 4000001, options: LookupOptions(currency: "EUR"))
        XCTAssertEqual(transport.requests(to: "/marketplace/stats/4000001").count, 3, "stale price refetched")
    }

    func testPriceSuggestionsOfflineErrorPropagates() async {
        transport.on("/marketplace/stats/4000001", .json("marketplace_stats_4000001"))
        transport.on("/marketplace/price_suggestions/4000001", .fail(URLError(.networkConnectionLost)))
        do {
            _ = try await service.priceInfo(for: 4000001, options: LookupOptions())
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .offline)
        }
    }
}
