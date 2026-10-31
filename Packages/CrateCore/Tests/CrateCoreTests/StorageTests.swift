import XCTest
@testable import CrateCore

final class FileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrateTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWritesReadsAndDeletes() throws {
        let store = try FileStore(directory: directory)
        XCTAssertNil(try store.data(forKey: "missing"))
        try store.set(Data("hello".utf8), forKey: "greeting")
        XCTAssertEqual(try store.data(forKey: "greeting"), Data("hello".utf8))
        try store.set(nil, forKey: "greeting")
        XCTAssertNil(try store.data(forKey: "greeting"))
        try store.set(nil, forKey: "never-existed")
    }

    func testKeysAreSanitisedIntoSafeFileNames() throws {
        let store = try FileStore(directory: directory)
        try store.set(Data("x".utf8), forKey: "../escape/attempt")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["___escape_attempt.json"])
    }

    func testCodableStorageDiscardsOtherSchemaVersions() throws {
        let store = InMemoryStore()
        try CodableStorage(store: store, schemaVersion: 1).save(["a", "b"], key: "list")
        XCTAssertEqual(CodableStorage(store: store, schemaVersion: 1).load([String].self, key: "list"), ["a", "b"])
        XCTAssertNil(CodableStorage(store: store, schemaVersion: 2).load([String].self, key: "list"))
    }

    func testCodableStorageSurvivesCorruptData() throws {
        let store = InMemoryStore()
        try store.set(Data("{not json".utf8), forKey: "list")
        XCTAssertNil(CodableStorage(store: store).load([String].self, key: "list"))
    }
}

final class LibraryCacheTests: XCTestCase {
    func testSnapshotPersistsAcrossInstances() async throws {
        let store = InMemoryStore()
        let cache = LibraryCache(store: store)
        try await cache.save(snapshot: LibrarySnapshot(username: "example_digger", collection: Fixtures.collection, wants: Fixtures.wants, syncedAt: Date(timeIntervalSince1970: 0)))

        let reopened = LibraryCache(store: store)
        let snapshot = await reopened.snapshot
        XCTAssertEqual(snapshot?.collection.count, 3)
        XCTAssertEqual(snapshot?.wants.count, 2)
        let index = await reopened.ownershipIndex()
        XCTAssertEqual(index.status(releaseID: 4000001, masterID: 300001).ownedCopies, 2)
    }

    func testOwnershipIndexRebuildsWhenSnapshotChanges() async throws {
        let cache = LibraryCache(store: InMemoryStore())
        let empty = await cache.ownershipIndex()
        XCTAssertTrue(empty.isEmpty)
        try await cache.save(snapshot: LibrarySnapshot(username: "u", collection: Fixtures.collection, wants: [], syncedAt: Date()))
        let rebuilt = await cache.ownershipIndex()
        XCTAssertFalse(rebuilt.isEmpty)
    }

    func testEvictsOldestReleasesBeyondLimit() async throws {
        let clock = TestClock()
        let cache = LibraryCache(store: InMemoryStore(), limits: .init(maxReleases: 2), now: { clock.now })
        try await cache.store(releases: [Fixtures.release(4000001)])
        clock.advance(10)
        try await cache.store(releases: [Fixtures.release(4000002)])
        clock.advance(10)
        try await cache.store(releases: [Fixtures.release(4000003)])
        let count = await cache.cachedReleaseCount
        let hasOldest = await cache.hasRelease(id: 4000001)
        XCTAssertEqual(count, 2)
        XCTAssertFalse(hasOldest)
    }

    func testFreshnessOfReleasesAndPrices() async throws {
        let clock = TestClock()
        let cache = LibraryCache(store: InMemoryStore(), limits: .init(releaseFreshness: 100, priceFreshness: 50), now: { clock.now })
        try await cache.store(releases: [Fixtures.release(4000001)])
        let price = PriceInfo(releaseID: 4000001, currency: "GBP", stats: nil, suggestions: [], fetchedAt: clock.now)
        try await cache.store(price: price)

        var fresh = await cache.freshRelease(id: 4000001)
        var priceIsFresh = await cache.isFresh(price)
        XCTAssertNotNil(fresh)
        XCTAssertTrue(priceIsFresh)

        clock.advance(60)
        priceIsFresh = await cache.isFresh(price)
        XCTAssertFalse(priceIsFresh)

        clock.advance(60)
        fresh = await cache.freshRelease(id: 4000001)
        XCTAssertNil(fresh)
        let stale = await cache.release(id: 4000001)
        XCTAssertNotNil(stale, "stale data is still available for offline use")
    }

    func testLocalCandidatesByBarcodeMatrixAndCatalogue() async throws {
        let cache = LibraryCache(store: InMemoryStore())
        try await cache.store(releases: [Fixtures.release(4000001), Fixtures.release(4000002)])
        try await cache.save(snapshot: LibrarySnapshot(username: "u", collection: [], wants: Fixtures.wants, syncedAt: Date()))

        let byBarcode = await cache.localCandidates(for: .barcode(Barcode("5012345600291")!))
        XCTAssertEqual(byBarcode.map(\.summary.id), [4000002])

        let byMatrix = await cache.localCandidates(for: .matrix("GCR 012 A-1 PORKY"))
        XCTAssertEqual(byMatrix.map(\.summary.id), [4000001])

        let byCatno = await cache.localCandidates(for: .catalogueNumber("KS 6.24011"))
        XCTAssertEqual(byCatno.map(\.summary.id), [4000003], "found via the wantlist even without cached details")
        XCTAssertNil(byCatno.first?.release)

        let nothing = await cache.localCandidates(for: .catalogueNumber("NOPE 9"))
        XCTAssertTrue(nothing.isEmpty)
    }

    func testClearRemovesEverything() async throws {
        let store = InMemoryStore()
        let cache = LibraryCache(store: store)
        try await cache.store(releases: [Fixtures.release(4000001)])
        try await cache.save(snapshot: LibrarySnapshot(username: "u", collection: [], wants: [], syncedAt: Date()))
        try await cache.clear()
        let snapshot = await cache.snapshot
        XCTAssertNil(snapshot)
        XCTAssertTrue(store.keys.isEmpty)
    }
}
