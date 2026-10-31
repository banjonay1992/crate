import XCTest
@testable import CrateCore

final class DigLogTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    private func entry(_ shop: String, day: Int, hour: Int, outcome: DigLogEntry.Outcome = .bought, paid: Decimal? = nil, currency: String = "GBP") -> DigLogEntry {
        DigLogEntry(
            date: date(day, hour),
            shop: shop,
            outcome: outcome,
            release: Fixtures.release(4000001).summary,
            pricePaid: paid.map { Money(amount: $0, currency: currency) }
        )
    }

    func testEntriesAreNewestFirstAndPersist() async throws {
        let store = InMemoryStore()
        let log = DigLogStore(store: store)
        try await log.add(entry("Oxfam Truro", day: 1, hour: 10))
        try await log.add(entry("Redruth market", day: 3, hour: 9))
        try await log.add(entry("Oxfam Truro", day: 2, hour: 15))

        let reopened = DigLogStore(store: store)
        let shops = await reopened.entries.map(\.date)
        XCTAssertEqual(shops, [date(3, 9), date(2, 15), date(1, 10)])
    }

    func testUpdateAndDelete() async throws {
        let log = DigLogStore(store: InMemoryStore())
        var item = entry("Oxfam Truro", day: 1, hour: 10, outcome: .noted)
        try await log.add(item)
        item.outcome = .bought
        item.note = "Sleeve has a ring wear"
        try await log.update(item)
        var entries = await log.entries
        XCTAssertEqual(entries.first?.outcome, .bought)
        try await log.delete(id: item.id)
        entries = await log.entries
        XCTAssertTrue(entries.isEmpty)
    }

    func testRecentShopsFoldCaseAndSpacing() async throws {
        let log = DigLogStore(store: InMemoryStore())
        try await log.add(entry("oxfam  truro", day: 1, hour: 10))
        try await log.add(entry("Redruth market", day: 2, hour: 10))
        try await log.add(entry("Oxfam Truro", day: 3, hour: 10))
        let shops = await log.recentShops()
        XCTAssertEqual(shops, ["Oxfam Truro", "Redruth market"])
    }

    func testVisitsGroupByShopAndDayWithSpendPerCurrency() async throws {
        let log = DigLogStore(store: InMemoryStore())
        try await log.add(entry("Utrecht fair", day: 5, hour: 10, paid: 12, currency: "EUR"))
        try await log.add(entry("Utrecht fair", day: 5, hour: 11, paid: Decimal(string: "7.50"), currency: "EUR"))
        try await log.add(entry("Utrecht fair", day: 5, hour: 12, outcome: .passed, paid: 30, currency: "EUR"))
        try await log.add(entry("Utrecht fair", day: 5, hour: 13, paid: 5, currency: "GBP"))
        try await log.add(entry("Oxfam Truro", day: 5, hour: 16, paid: 3))
        try await log.add(entry("Utrecht fair", day: 6, hour: 10, paid: 1, currency: "EUR"))

        let visits = await log.visits(calendar: calendar)

        XCTAssertEqual(visits.map(\.shop), ["Utrecht fair", "Oxfam Truro", "Utrecht fair"])
        let fair = visits[2]
        XCTAssertEqual(fair.entries.count, 4)
        XCTAssertEqual(fair.boughtCount, 3)
        XCTAssertEqual(fair.spent["EUR"], Decimal(string: "19.5"), "passed records do not count as spent")
        XCTAssertEqual(fair.spent["GBP"], 5)
    }

    func testSearchMatchesShopTitleNoteAndCatalogueNumber() async throws {
        let log = DigLogStore(store: InMemoryStore())
        var noted = entry("Oxfam Truro", day: 1, hour: 10)
        noted.note = "Check for the inner sleeve"
        try await log.add(noted)
        try await log.add(DigLogEntry(date: date(2, 10), shop: "Car boot", outcome: .noted, query: .catalogueNumber("MSM12-004")))

        let byShop = await log.search("truro")
        let byNote = await log.search("inner")
        let byCatno = await log.search("gcr 012")
        let byQuery = await log.search("MSM12")
        let all = await log.search("  ")
        XCTAssertEqual(byShop.count, 1)
        XCTAssertEqual(byNote.count, 1)
        XCTAssertEqual(byCatno.count, 1)
        XCTAssertEqual(byQuery.first?.title, "MSM12-004")
        XCTAssertEqual(all.count, 2)
    }

    func testCSVExport() async throws {
        let log = DigLogStore(store: InMemoryStore())
        var bought = entry("Oxfam, Truro", day: 1, hour: 10, paid: Decimal(string: "4.50"))
        bought.note = "Said \"mint\", wasn't"
        try await log.add(bought)

        let csv = await log.csv()
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], DigLogCSV.header.joined(separator: ","))
        XCTAssertTrue(lines[1].contains("\"Oxfam, Truro\""))
        XCTAssertTrue(lines[1].contains(",bought,The Tidal Rooms,Harbour Lights,GCR 012,4000001,,4.5,GBP,,no,"))
        XCTAssertTrue(lines[1].hasSuffix("\"Said \"\"mint\"\", wasn't\""))
        XCTAssertEqual(lines.last, "")
    }

    func testCSVNeutralisesFormulae() {
        XCTAssertEqual(DigLogCSV.escape("=HYPERLINK(\"x\")"), "\"'=HYPERLINK(\"\"x\"\")\"")
        XCTAssertEqual(DigLogCSV.escape("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(DigLogCSV.escape("-1+cmd"), "'-1+cmd")
        XCTAssertEqual(DigLogCSV.escape("-4.5"), "-4.5", "plain negative numbers are left alone")
        XCTAssertEqual(DigLogCSV.escape("plain"), "plain")
    }

    func testEntryTitleFallbacks() {
        XCTAssertEqual(DigLogEntry(date: Date(), shop: "x", outcome: .noted).title, "Unidentified record")
        XCTAssertEqual(DigLogEntry(date: Date(), shop: "x", outcome: .noted, query: .matrix("ABC 123")).title, "ABC 123")
    }
}
