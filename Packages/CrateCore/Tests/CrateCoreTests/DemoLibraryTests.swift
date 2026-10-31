#if DEBUG
import XCTest
@testable import CrateCore

/// The demo data drives the app's demo mode and the README screenshots, so
/// these tests pin down the stories the screenshots tell.
final class DemoLibraryTests: XCTestCase {
    private var cache: LibraryCache!
    private var digLog: DigLogStore!
    private var service: LookupService!

    override func setUp() async throws {
        cache = LibraryCache(store: InMemoryStore())
        digLog = DigLogStore(store: InMemoryStore())
        try await DemoLibrary.seed(cache: cache, digLog: digLog)
        service = LookupService(api: DemoDiscogsAPI(latency: .zero), cache: cache, queue: LookupQueue(store: InMemoryStore()))
    }

    func testEveryBarcodeIsValid() {
        for release in DemoLibrary.releases {
            for value in release.barcodes {
                let barcode = Barcode(value)
                XCTAssertNotNil(barcode, "\(release.id): \(value)")
                XCTAssertTrue(barcode?.hasValidCheckDigit ?? false, "\(release.id): \(value)")
            }
        }
    }

    func testReleaseIDsAreUnique() {
        let ids = DemoLibrary.releases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSeedFillsLibraryPricesAndDigLog() async throws {
        let stored = await cache.snapshot
        let snapshot = try XCTUnwrap(stored)
        XCTAssertEqual(snapshot.username, DemoLibrary.username)
        XCTAssertEqual(snapshot.collection.count, 10)
        XCTAssertEqual(snapshot.wants.count, 5)
        let cachedCount = await cache.cachedReleaseCount
        XCTAssertEqual(cachedCount, DemoLibrary.releases.count)
        let price = await cache.price(for: 4000003)
        XCTAssertNotNil(price?.stats?.lowestPrice)
        let visits = await digLog.visits()
        XCTAssertEqual(visits.count, 3)
        XCTAssertEqual(visits.first?.shop, DemoLibrary.currentShop)
    }

    func testWantedBarcodeIsUniqueMatchOnWantlistWithOwnedOtherPressing() async throws {
        let barcode = try XCTUnwrap(Barcode(DemoLibrary.wantedBarcode))
        let result = try await service.lookup(.barcode(barcode), options: LookupOptions(currency: "GBP"))

        let match = try XCTUnwrap(result.bestMatch)
        XCTAssertEqual(match.id, 4000003)
        XCTAssertEqual(match.evidence, .barcode)
        let ownership = result.ownership(for: match.id)
        XCTAssertEqual(ownership.headline, .wanted)
        XCTAssertEqual(ownership.otherPressingsOwned.map(\.id), [4000001])
        let price = try XCTUnwrap(result.prices[match.id])
        XCTAssertEqual(price.stats?.lowestPrice, Money(amount: Decimal(string: "24.5")!, currency: "GBP"))
        XCTAssertEqual(price.suggestions.first?.condition, .mint)
    }

    func testSharedCatalogueNumberOffersAChoiceWithDistinguishingRunOuts() async throws {
        let result = try await service.lookup(.catalogueNumber(DemoLibrary.sharedCatalogueNumber), options: LookupOptions(currency: "GBP"))

        XCTAssertTrue(result.isAmbiguous)
        XCTAssertEqual(Set(result.choices.map(\.id)), [4000001, 4000002])
        XCTAssertFalse(result.distinguishingMatrices[4000001, default: []].isEmpty)
        XCTAssertEqual(result.ownership(for: 4000001).headline, .owned)
        XCTAssertEqual(result.ownership(for: 4000002).headline, .wantedOtherPressing)
    }

    func testRunOutSearchFindsThePressing() async throws {
        let result = try await service.lookup(.matrix("SW 1986-A"), options: LookupOptions(currency: "GBP"))
        XCTAssertEqual(result.candidates.first?.id, 4000004)
    }

    func testPagingCoversTheWholeCollection() async throws {
        let api = DemoDiscogsAPI(latency: .zero)
        let all = try await api.fullCollection(username: DemoLibrary.username, perPage: 3)
        XCTAssertEqual(all.count, 10)
    }
}
#endif
