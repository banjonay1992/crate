import XCTest
@testable import CrateCore

final class BarcodeTests: XCTestCase {
    func testParsesPrintedEAN13WithSpaces() throws {
        let barcode = try XCTUnwrap(Barcode("5 012345 600123"))
        XCTAssertEqual(barcode.symbology, .ean13)
        XCTAssertEqual(barcode.digits, "5012345600123")
        XCTAssertTrue(barcode.hasValidCheckDigit)
        XCTAssertEqual(barcode.canonical, "5012345600123")
    }

    func testUPCAAndEAN13WithLeadingZeroShareACanonicalForm() throws {
        let upc = try XCTUnwrap(Barcode("0 73311 22445 8"))
        XCTAssertEqual(upc.symbology, .upcA)
        XCTAssertTrue(upc.hasValidCheckDigit)
        let ean = try XCTUnwrap(Barcode("0073311224458"))
        XCTAssertEqual(upc.canonical, ean.canonical)
        XCTAssertEqual(upc.searchVariants, ["073311224458", "0073311224458"])
        XCTAssertEqual(ean.searchVariants, ["0073311224458", "073311224458"])
    }

    func testEAN8() throws {
        let barcode = try XCTUnwrap(Barcode("9638-5074"))
        XCTAssertEqual(barcode.symbology, .ean8)
        XCTAssertTrue(barcode.hasValidCheckDigit)
        XCTAssertEqual(barcode.canonical, "96385074")
    }

    func testDetectsBadCheckDigit() throws {
        let barcode = try XCTUnwrap(Barcode("5012345600124"))
        XCTAssertFalse(barcode.hasValidCheckDigit)
    }

    func testRejectsNonBarcodes() {
        XCTAssertNil(Barcode("GCR 012"))
        XCTAssertNil(Barcode("12345"))
        XCTAssertNil(Barcode(""))
        XCTAssertNil(Barcode("50123456001234"), "14 digits is not a retail barcode")
    }

    func testUPCEExpansion() throws {
        // Standard worked example of UPC-E zero suppression.
        XCTAssertEqual(Barcode.expandUPCE("04252614"), "042100005264")
        let upcE = try XCTUnwrap(Barcode(upcE: "04252614"))
        XCTAssertTrue(upcE.hasValidCheckDigit)
        XCTAssertEqual(upcE.canonical, "0042100005264")
        XCTAssertEqual(upcE.searchVariants.first, "042100005264")
        XCTAssertEqual(Barcode(upcE: "4252614")?.digits, "04252614", "7 digit form gets an assumed 0 number system")
        XCTAssertNil(Barcode(upcE: "54252614"), "number system must be 0 or 1")
    }

    func testUPCEExpansionRules() {
        XCTAssertEqual(Barcode.expandUPCE("01234530"), "012300000450")
        XCTAssertEqual(Barcode.expandUPCE("01234540"), "012340000050")
        XCTAssertEqual(Barcode.expandUPCE("01234560"), "012345000060")
    }

    func testCanonicalKeyIgnoresMatrixStrings() {
        XCTAssertEqual(Barcode.canonicalKey(for: "5 012345 600123"), "5012345600123")
        XCTAssertNil(Barcode.canonicalKey(for: "GCR 012 A-1 PORKY"))
    }

    func testCheckDigitComputation() {
        XCTAssertEqual(Barcode.computeCheckDigit([5, 0, 1, 2, 3, 4, 5, 6, 0, 0, 1, 2]), 3)
        XCTAssertEqual(Barcode.computeCheckDigit([0, 7, 3, 3, 1, 1, 2, 2, 4, 4, 5]), 8)
    }
}

final class IdentifierNormaliserTests: XCTestCase {
    func testCatalogueKeyIgnoresCaseSpacingAndPunctuation() {
        let key = IdentifierNormaliser.catalogueKey("GCR 012")
        XCTAssertEqual(key, "GCR012")
        XCTAssertEqual(IdentifierNormaliser.catalogueKey("gcr-012"), key)
        XCTAssertEqual(IdentifierNormaliser.catalogueKey(" g.c.r/012 "), key)
        XCTAssertEqual(IdentifierNormaliser.catalogueKey("KS 6.24011"), "KS624011")
    }

    func testCatalogueKeyFoldsAccents() {
        XCTAssertEqual(IdentifierNormaliser.catalogueKey("Été 7"), "ETE7")
    }

    func testLooseCatalogueKeyDropsLeadingZeros() {
        XCTAssertEqual(IdentifierNormaliser.looseCatalogueKey("GCR 012"), "GCR12")
        XCTAssertEqual(IdentifierNormaliser.looseCatalogueKey("GCR 12"), "GCR12")
        XCTAssertEqual(IdentifierNormaliser.looseCatalogueKey("GCR 0120"), "GCR120")
        XCTAssertEqual(IdentifierNormaliser.looseCatalogueKey("SW-000"), "SW0")
    }

    func testMatrixKeyAndTokens() {
        XCTAssertEqual(IdentifierNormaliser.matrixKey("GCR 012 A-1 PORKY"), "GCR012A1PORKY")
        XCTAssertEqual(IdentifierNormaliser.matrixKey("SW 1986-A  △ 77001"), "SW1986A77001")
        XCTAssertEqual(IdentifierNormaliser.matrixKey("A1 Ø"), "A10")
        XCTAssertEqual(IdentifierNormaliser.matrixTokens("GCR012-A2 RE"), ["GCR012", "A2", "RE"])
    }

    func testTidyCollapsesWhitespaceAndDashes() {
        XCTAssertEqual(IdentifierNormaliser.tidy("  GCR\u{2013}012\t A "), "GCR-012 A")
    }

    func testQueryInference() {
        XCTAssertEqual(LookupQuery.infer(from: "5012345600123")?.kind, .barcode)
        XCTAssertEqual(LookupQuery.infer(from: "5012345600124")?.kind, .catalogueNumber, "a bad check digit is probably not a barcode")
        XCTAssertEqual(LookupQuery.infer(from: "GCR 012"), .catalogueNumber("GCR 012"))
        XCTAssertNil(LookupQuery.infer(from: " - "))
    }

    func testExplicitQueryValidation() {
        XCTAssertNil(LookupQuery.make(kind: .barcode, text: "GCR 012"))
        XCTAssertNil(LookupQuery.make(kind: .matrix, text: "A1"))
        XCTAssertEqual(LookupQuery.make(kind: .matrix, text: " GCR 012  A-1 "), .matrix("GCR 012 A-1"))
    }

    func testQueryRoundTripsThroughCodable() throws {
        let queries: [LookupQuery] = [.barcode(Barcode("5012345600123")!), .catalogueNumber("GCR 012"), .matrix("GCR 012 A-1")]
        let data = try JSONEncoder().encode(queries)
        XCTAssertEqual(try JSONDecoder().decode([LookupQuery].self, from: data), queries)
    }
}
