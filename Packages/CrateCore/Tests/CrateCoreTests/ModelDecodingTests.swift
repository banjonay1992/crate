import XCTest
@testable import CrateCore

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodesFullRelease() throws {
        let release = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000001")).toDomain()

        XCTAssertEqual(release.id, 4000001)
        XCTAssertEqual(release.masterID, 300001)
        XCTAssertEqual(release.title, "Harbour Lights")
        XCTAssertEqual(release.artist, "The Tidal Rooms")
        XCTAssertEqual(release.year, 1984)
        XCTAssertEqual(release.country, "UK")
        XCTAssertEqual(release.labels, [LabelCredit(name: "Granite Coast Records", catalogueNumber: "GCR 012")])
        XCTAssertEqual(release.formats.first?.displayText, "Vinyl, LP, Album (Gatefold)")
        XCTAssertEqual(release.barcodes, ["5 012345 600123", "5012345600123"])
        XCTAssertEqual(release.matrices.map(\.value), ["GCR 012 A-1 PORKY", "GCR 012 B-1"])
        XCTAssertEqual(release.matrices.first?.detail, "Side A, etched")
        XCTAssertEqual(release.community, CommunityStats(have: 412, want: 1033))
        XCTAssertEqual(release.webURL?.absoluteString, "https://www.discogs.com/release/4000001-The-Tidal-Rooms-Harbour-Lights")
        XCTAssertEqual(release.numForSale, 7)
    }

    func testTracklistSkipsHeadingsAndEmptyDurations() throws {
        let release = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000001")).toDomain()
        XCTAssertEqual(release.tracklist.map(\.position), ["A1", "A2", "B1", "B2"])
        XCTAssertNil(release.tracklist.last?.duration)
    }

    func testRelativeURIBecomesDiscogsWebURL() throws {
        let release = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000003")).toDomain()
        XCTAssertEqual(release.webURL?.absoluteString, "https://www.discogs.com/release/4000003-The-Tidal-Rooms-Harbour-Lights")
    }

    func testArtistNameVariationAndDisambiguationSuffix() throws {
        let german = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000003")).toDomain()
        XCTAssertEqual(german.artist, "Tidal Rooms", "anv should win over the canonical name")
        XCTAssertEqual(german.labels.first?.name, "Küstenlicht Schallplatten")

        let us = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000004")).toDomain()
        XCTAssertEqual(us.artist, "Marsh Choir & Penhallow")
    }

    func testStringYearZeroMasterAndNoneCatalogueNumber() throws {
        let release = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000004")).toDomain()
        XCTAssertEqual(release.year, 1986, "year arrives as a string here")
        XCTAssertNil(release.masterID, "master_id 0 means no master")
        XCTAssertEqual(release.catalogueNumbers, ["SW-1986"], "\"none\" is a Discogs placeholder, not a catalogue number")
        XCTAssertEqual(release.formats.first?.displayText, "2 x Vinyl, LP, Album")
        XCTAssertNil(release.thumbURL)
    }

    func testCleanArtistName() {
        XCTAssertEqual(DiscogsDTO.cleanArtistName("Penhallow (3)"), "Penhallow")
        XCTAssertEqual(DiscogsDTO.cleanArtistName("The Band (Live)"), "The Band (Live)")
        XCTAssertEqual(DiscogsDTO.cleanArtistName("()"), "()")
        XCTAssertEqual(DiscogsDTO.cleanArtistName("Plain"), "Plain")
    }

    func testSearchResultSplitsArtistAndTitle() throws {
        let page = try decoder.decode(DiscogsDTO.SearchPage.self, from: Fixture.data("search_catno"))
        let results = page.results.map { $0.toDomain() }
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].artist, "The Tidal Rooms")
        XCTAssertEqual(results[0].title, "Harbour Lights")
        XCTAssertEqual(results[0].year, 1984)
        XCTAssertEqual(results[0].catalogueNumbers, ["GCR 012"])
        XCTAssertNil(results[2].year, "empty year string decodes to nil")
        XCTAssertEqual(results[1].formats.first?.descriptions, ["LP", "Album", "Reissue", "Remastered"])
    }

    func testCollectionPageDecodesDatesAndPagination() throws {
        let dto = try decoder.decode(DiscogsDTO.CollectionPage.self, from: Fixture.data("collection_page1"))
        XCTAssertEqual(dto.pagination.pages, 2)
        XCTAssertEqual(dto.pagination.items, 3)
        let first = dto.releases[0]
        XCTAssertEqual(first.instanceID, 880001)
        let date = try XCTUnwrap(DiscogsDTO.date(first.dateAdded))
        XCTAssertEqual(date.timeIntervalSince1970, 1_741_972_925, accuracy: 1)
    }

    func testWantsPageDecodes() throws {
        let dto = try decoder.decode(DiscogsDTO.WantsPage.self, from: Fixture.data("wants_page1"))
        XCTAssertEqual(dto.wants.count, 2)
        XCTAssertEqual(dto.wants[0].notes, "Only if the inner sleeve is there")
        XCTAssertEqual(dto.wants[1].basicInformation.toDomain().artist, "Marsh Choir & Penhallow")
    }

    func testMarketplaceStatsWithAndWithoutPrice() throws {
        let stats = try decoder.decode(DiscogsDTO.MarketplaceStats.self, from: Fixture.data("marketplace_stats_4000001")).toDomain()
        XCTAssertEqual(stats.lowestPrice, Money(amount: Decimal(string: "18.10")!, currency: "GBP"))
        XCTAssertEqual(stats.numForSale, 7)

        let none = try decoder.decode(DiscogsDTO.MarketplaceStats.self, from: Fixture.data("marketplace_stats_4000002")).toDomain()
        XCTAssertNil(none.lowestPrice)
        XCTAssertEqual(none.numForSale, 0)
    }

    func testPriceSuggestionsAreSortedAndUnknownGradesDropped() throws {
        let points = try DiscogsDTO.priceSuggestions(from: Fixture.data("price_suggestions_4000001"), decoder: decoder)
        XCTAssertEqual(points.map(\.condition), MediaCondition.allCases)
        XCTAssertEqual(points.first?.price.amount, Decimal(string: "41.25"))
        XCTAssertEqual(points[2].condition.shortLabel, "VG+")
    }

    func testMoneyAvoidsFloatNoise() {
        XCTAssertEqual(Money(value: 12.1, currency: "GBP").amount, Decimal(string: "12.1"))
        XCTAssertEqual(Money(value: 0.1 + 0.2, currency: "GBP").amount, Decimal(string: "0.3"))
    }

    func testDomainModelsRoundTripThroughCodable() throws {
        let release = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000001")).toDomain()
        let encoded = try JSONEncoder().encode(release)
        let decoded = try JSONDecoder().decode(Release.self, from: encoded)
        XCTAssertEqual(decoded, release)
    }

    func testPressingLine() throws {
        let release = try decoder.decode(DiscogsDTO.Release.self, from: Fixture.data("release_4000001")).toDomain()
        XCTAssertEqual(release.summary.pressingLine, "Granite Coast Records GCR 012, UK, 1984")
        XCTAssertEqual(release.summary.displayTitle, "The Tidal Rooms - Harbour Lights")
    }
}
