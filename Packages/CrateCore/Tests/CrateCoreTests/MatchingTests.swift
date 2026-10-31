import XCTest
@testable import CrateCore

final class PressingMatcherTests: XCTestCase {
    private var original: Release { Fixtures.release(4000001) }
    private var reissue: Release { Fixtures.release(4000002) }
    private var german: Release { Fixtures.release(4000003) }
    private var us: Release { Fixtures.release(4000004) }

    private func pairs(_ releases: [Release]) -> [(summary: ReleaseSummary, release: Release?)] {
        releases.map { ($0.summary, $0) }
    }

    func testBarcodePicksTheExactPressing() throws {
        let query = LookupQuery.barcode(try XCTUnwrap(Barcode("5012345600291")))
        let resolution = PressingMatcher.match(query, candidates: pairs([original, reissue, german]))
        guard case .unique(let candidate) = resolution else { return XCTFail("Expected unique, got \(resolution)") }
        XCTAssertEqual(candidate.id, 4000002)
        XCTAssertEqual(candidate.evidence, .barcode)
        XCTAssertEqual(candidate.matchedIdentifier, "5012345600291")
    }

    func testBarcodeMatchesPrintedFormWithSpaces() throws {
        let query = LookupQuery.barcode(try XCTUnwrap(Barcode("4009876500313")))
        let (evidence, identifier) = PressingMatcher.evaluate(query, summary: german.summary, release: german)
        XCTAssertEqual(evidence, .barcode)
        XCTAssertEqual(identifier, "4 009876 500313")
    }

    func testScannedEAN13MatchesReleasePrintedAsUPCA() throws {
        let query = LookupQuery.barcode(try XCTUnwrap(Barcode("0073311224458")))
        let (evidence, _) = PressingMatcher.evaluate(query, summary: us.summary, release: us)
        XCTAssertEqual(evidence, .barcode)
    }

    func testBarcodeMatchingWorksFromSearchSummariesAlone() throws {
        let summaries = Fixtures.searchResults("search_catno")
        let query = LookupQuery.barcode(try XCTUnwrap(Barcode("5012345600123")))
        let ranked = PressingMatcher.rank(query, candidates: summaries.map { ($0, nil) })
        XCTAssertEqual(ranked.first?.id, 4000001)
        XCTAssertEqual(ranked.first?.evidence, .barcode)
        XCTAssertEqual(ranked.dropFirst().map(\.evidence), [.searchResult, .searchResult])
    }

    func testSharedCatalogueNumberIsAmbiguous() {
        let resolution = PressingMatcher.match(.catalogueNumber("gcr-012"), candidates: pairs([original, reissue, german]))
        guard case .ambiguous(let candidates) = resolution else { return XCTFail("Expected ambiguous, got \(resolution)") }
        XCTAssertEqual(candidates.map(\.id), [4000001, 4000002])
        XCTAssertTrue(candidates.allSatisfy { $0.evidence == .catalogueNumber })
    }

    func testStrictCatalogueBeatsLooseAndUnrelatedResults() {
        let summaries = Fixtures.searchResults("search_catno")
        let ranked = PressingMatcher.rank(.catalogueNumber("GCR 12"), candidates: summaries.map { ($0, nil) })
        XCTAssertEqual(ranked.map(\.evidence), [.catalogueNumberLoose, .catalogueNumberLoose, .searchResult],
                       "GCR 0120 is a different catalogue number, not a loose match")
    }

    func testExactMatrixSeparatesOriginalFromReissue() {
        let resolution = PressingMatcher.match(.matrix("gcr 012 a1 porky"), candidates: pairs([original, reissue]))
        guard case .unique(let candidate) = resolution else { return XCTFail("Expected unique, got \(resolution)") }
        XCTAssertEqual(candidate.id, 4000001)
        XCTAssertEqual(candidate.evidence, .matrixExact)
    }

    func testPartialMatrixWhenUserTypesLess() {
        let resolution = PressingMatcher.match(.matrix("GCR012 A2"), candidates: pairs([original, reissue]))
        guard case .unique(let candidate) = resolution else { return XCTFail("Expected unique, got \(resolution)") }
        XCTAssertEqual(candidate.id, 4000002)
        XCTAssertEqual(candidate.evidence, .matrixPartial)
        XCTAssertEqual(candidate.matchedIdentifier, "GCR012-A2 RE")
    }

    func testPartialMatrixTokenOverlap() {
        // Tokens shared but in a different arrangement from the Discogs transcription.
        XCTAssertTrue(PressingMatcher.matrixPartiallyMatches(
            query: "SW-1986 A 77001", queryKey: "SW1986A77001",
            value: "77001 SW 1986-A", valueKey: "77001SW1986A"
        ))
    }

    func testShortFragmentsDoNotMatch() {
        let (evidence, _) = PressingMatcher.matchMatrix("A-1", against: ["GCR 012 A-1 PORKY"])
        XCTAssertEqual(evidence, .searchResult)
    }

    func testMatrixFromSearchSummaryIdentifiers() {
        let summaries = Fixtures.searchResults("search_catno")
        let ranked = PressingMatcher.rank(.matrix("GCR012-B2 RE"), candidates: summaries.map { ($0, nil) })
        XCTAssertEqual(ranked.first?.id, 4000002)
        XCTAssertEqual(ranked.first?.evidence, .matrixExact)
    }

    func testDuplicateCandidatesAreDropped() {
        let ranked = PressingMatcher.rank(.catalogueNumber("GCR 012"), candidates: pairs([original, original]))
        XCTAssertEqual(ranked.count, 1)
    }

    func testNoCandidates() {
        XCTAssertEqual(PressingMatcher.match(.catalogueNumber("XYZ 1"), candidates: []), .none)
    }

    func testDistinguishingMatrices() {
        let distinct = PressingMatcher.distinguishingMatrices(among: [original, reissue])
        XCTAssertEqual(distinct[4000001], ["GCR 012 A-1 PORKY", "GCR 012 B-1"])
        XCTAssertEqual(distinct[4000002], ["GCR012-A2 RE", "GCR012-B2 RE"])
    }

    func testDistinguishingMatricesIgnoresSharedEtchings() {
        var twin = reissue
        twin.id = 4000005
        twin.identifiers.append(ReleaseIdentifier(type: "Matrix / Runout", value: "GCR 012 B-1"))
        let distinct = PressingMatcher.distinguishingMatrices(among: [original, twin])
        XCTAssertEqual(distinct[4000001], ["GCR 012 A-1 PORKY"])
    }
}

final class OwnershipIndexTests: XCTestCase {
    private let index = OwnershipIndex(collection: Fixtures.collection, wants: Fixtures.wants)

    func testCountsMultipleCopies() {
        let status = index.status(releaseID: 4000001, masterID: 300001)
        XCTAssertEqual(status.ownedCopies, 2)
        XCTAssertFalse(status.isWanted)
        XCTAssertEqual(status.headline, .owned)
    }

    func testWantedBeatsOwnedOtherPressing() {
        let status = index.status(releaseID: 4000003, masterID: 300001)
        XCTAssertTrue(status.isWanted)
        XCTAssertEqual(status.otherPressingsOwned.map(\.id), [4000001], "owned copies are listed once per release")
        XCTAssertEqual(status.headline, .wanted)
    }

    func testOtherPressingOfSameMaster() {
        let status = index.status(releaseID: 4000002, masterID: 300001)
        XCTAssertFalse(status.isOwned)
        XCTAssertFalse(status.isWanted)
        XCTAssertEqual(status.otherPressingsWanted.map(\.id), [4000003])
        XCTAssertEqual(status.headline, .wantedOtherPressing)
        XCTAssertEqual(status.headline.text, "You want a different pressing")
    }

    func testOwnedOtherPressing() {
        let index = OwnershipIndex(collection: Fixtures.collection, wants: [])
        XCTAssertEqual(index.status(releaseID: 4000002, masterID: 300001).headline, .ownedOtherPressing)
    }

    func testUnrelatedRelease() {
        let status = index.status(releaseID: 999, masterID: nil)
        XCTAssertEqual(status, .unknown)
        XCTAssertEqual(status.headline, .neither)
    }

    func testReleaseWithoutMasterOnlyMatchesItself() {
        let status = index.status(releaseID: 4000004, masterID: nil)
        XCTAssertTrue(status.isWanted)
        XCTAssertTrue(status.otherPressingsOwned.isEmpty)
    }

    func testOfflineCatalogueLookup() {
        XCTAssertEqual(index.releases(matchingCatalogueNumber: "gcr12").map(\.id), [4000001])
        XCTAssertEqual(index.releases(matchingCatalogueNumber: "KS 6 24011").map(\.id), [4000003])
        XCTAssertTrue(index.releases(matchingCatalogueNumber: "NOPE 1").isEmpty)
    }
}
