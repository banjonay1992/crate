#if DEBUG
import Foundation

/// Invented sample data for the app's demo mode, used for screenshots and for
/// trying the app without a Discogs account. Every artist, label, catalogue
/// number, barcode, run-out, shop and price here is made up, in the same style
/// as the test fixtures. Compiled into Debug builds only.
public enum DemoLibrary {
    public static let username = "example_digger"
    public static let currency = "GBP"

    /// Scanning this shows a unique match that is on the wantlist, with a
    /// different pressing of the same album already in the collection.
    public static let wantedBarcode = "4009876500313"
    /// Shared by an original and a reissue, so it produces a choice of pressings.
    public static let sharedCatalogueNumber = "GCR 012"
    /// The shop shown in the "Digging at" field.
    public static let currentShop = "Harbourside Record Fair"

    /// URL scheme for generated sleeve art. The app draws these itself;
    /// nothing is fetched.
    public static let artScheme = "crate-demo"

    // MARK: Releases

    public static var releases: [Release] { entries.map(\.release) }

    private struct Entry {
        var release: Release
        /// Suggested Near Mint price; other grades are scaled from it.
        var nearMint: Double
    }

    private static let entries: [Entry] = [
        record(4000001, master: 300001, artist: "The Tidal Rooms", title: "Harbour Lights", year: 1984, country: "UK",
               label: "Granite Coast Records", catno: "GCR 012",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"], text: "Gatefold"),
               barcode: "5012345600123",
               matrices: [("GCR 012 A-1 PORKY", "Side A, etched"), ("GCR 012 B-1", "Side B, etched")],
               tracks: [("A1", "Low Water", "3:41"), ("A2", "Engine House", "4:12"), ("A3", "Salt On The Glass", "3:58"),
                        ("B1", "Harbour Lights", "5:03"), ("B2", "Last Train To Penzance", "4:27")],
               have: 412, want: 1033, lowest: 18.10, forSale: 7, nearMint: 36.40),
        record(4000002, master: 300001, artist: "The Tidal Rooms", title: "Harbour Lights", year: 2019, country: "Europe",
               label: "Granite Coast Records", catno: "GCR 012",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album", "Reissue", "Remastered"], text: "180g"),
               barcode: "5012345600291",
               matrices: [("GCR012-A2 RE", "Side A"), ("GCR012-B2 RE", "Side B")],
               tracks: [("A1", "Low Water", "3:41"), ("A2", "Engine House", "4:12"), ("B1", "Harbour Lights", "5:03")],
               have: 230, want: 95, lowest: 21.99, forSale: 14, nearMint: 24.00),
        record(4000003, master: 300001, artist: "The Tidal Rooms", title: "Harbour Lights", year: 1985, country: "Germany",
               label: "Küstenlicht Schallplatten", catno: "KS 6.24011",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: "4009876500313",
               matrices: [("6.24011 A  KL-1", "Side A"), ("6.24011 B  KL-1", "Side B")],
               tracks: [("A1", "Low Water", "3:41"), ("A2", "Engine House", "4:12"), ("A3", "Salt On The Glass", "3:58"),
                        ("B1", "Harbour Lights", "5:03"), ("B2", "Last Train To Penzance", "4:27")],
               have: 61, want: 288, lowest: 24.50, forSale: 3, nearMint: 42.00),
        record(4000004, master: nil, artist: "Marsh Choir & Penhallow", title: "Quiet Ground", year: 1986, country: "US",
               label: "Saltwater Sound", catno: "SW-1986",
               format: FormatDescriptor(name: "Vinyl", quantity: 2, descriptions: ["LP", "Album"]),
               barcode: "073311224458",
               matrices: [("SW 1986-A  △ 77001", "Side A")],
               tracks: [("A1", "Reed Bed", "6:10"), ("B1", "Quiet Ground", "8:45")],
               have: 88, want: 410, lowest: 46.00, forSale: 2, nearMint: 58.00),
        record(4000010, master: 300010, artist: "Wheal Kitty", title: "Slate Roof Rain", year: 1991, country: "UK",
               label: "Mine Shaft Music", catno: "MSM12-004",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["12\"", "45 RPM", "EP"]),
               barcode: nil, matrices: [("MSM12-004-A", "Side A")],
               tracks: [("A", "Slate Roof Rain", "6:02"), ("B", "Count House", "5:40")],
               have: 140, want: 77, lowest: 9.00, forSale: 11, nearMint: 12.50),
        record(4000011, master: 300011, artist: "Helena Trevaskis", title: "Gull Weather", year: 1978, country: "UK",
               label: "Bracken Lane Records", catno: "BLR 3",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: nil, matrices: [("BLR-3-A1", "Side A")],
               tracks: [("A1", "Gull Weather", "3:12"), ("B1", "Mizzle", "4:03")],
               have: 302, want: 190, lowest: 14.00, forSale: 9, nearMint: 22.00),
        record(4000012, master: 300012, artist: "The Lugger Band", title: "Night Ferry To Roscoff", year: 1981, country: "UK",
               label: "Quayside", catno: "QS 101",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: "5023456100013", matrices: [("QS 101 A1", "Side A")],
               tracks: [("A1", "Night Ferry", "4:20"), ("B1", "Roscoff Light", "5:15")],
               have: 57, want: 240, lowest: 32.00, forSale: 2, nearMint: 38.00),
        record(4000013, master: 300013, artist: "Anna Pendeen Quartet", title: "Copper Sky", year: 1977, country: "UK",
               label: "Low Tide Jazz", catno: "LTJ 7702",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: nil, matrices: [("LTJ 7702 A-2", "Side A")],
               tracks: [("A1", "Copper Sky", "7:41"), ("B1", "Undertow", "9:02")],
               have: 120, want: 515, lowest: 28.00, forSale: 4, nearMint: 45.00),
        record(4000014, master: 300014, artist: "Tregarthen Dub Unit", title: "Pilchard Moon", year: 1995, country: "UK",
               label: "Granite Coast Records", catno: "GCR 031",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["12\"", "33 ⅓ RPM", "EP"]),
               barcode: "5012345603131", matrices: [("GCR 031 A", "Side A")],
               tracks: [("A", "Pilchard Moon", "7:30"), ("B", "Pilchard Dub", "7:12")],
               have: 64, want: 199, lowest: 15.00, forSale: 5, nearMint: 19.00),
        record(4000015, master: 300015, artist: "Morwenna Hale", title: "Fogbound", year: 1972, country: "UK",
               label: "Seabird Sound", catno: "SBS 214",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: nil, matrices: [("SBS 214 A1", "Side A")],
               tracks: [("A1", "Fogbound", "3:55"), ("B1", "Lantern", "4:40")],
               have: 211, want: 380, lowest: 18.50, forSale: 6, nearMint: 30.00),
        record(4000016, master: 300016, artist: "The Carn Brea Electric", title: "Signal Box", year: 1989, country: "UK",
               label: "Mine Shaft Music", catno: "MSM 011",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: "5034567011006", matrices: [("MSM 011 A", "Side A")],
               tracks: [("A1", "Signal Box", "4:01"), ("B1", "Points Failure", "3:33")],
               have: 95, want: 60, lowest: 11.00, forSale: 8, nearMint: 16.00),
        record(4000017, master: 300017, artist: "Holman & Vean", title: "Tin And Arsenic", year: 1975, country: "UK",
               label: "Bracken Lane Records", catno: "BLR 9",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: nil, matrices: [("BLR-9-A1", "Side A")],
               tracks: [("A1", "Tin And Arsenic", "5:20"), ("B1", "Stamps", "4:48")],
               have: 33, want: 170, lowest: 55.00, forSale: 1, nearMint: 60.00),
        record(4000018, master: 300018, artist: "The Tidal Rooms", title: "Rosewarne Sessions", year: 1986, country: "UK",
               label: "Granite Coast Records", catno: "GCR 018",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: "5012345601847", matrices: [("GCR 018 A-1", "Side A")],
               tracks: [("A1", "Rosewarne", "4:44"), ("B1", "Sessions", "6:06")],
               have: 180, want: 140, lowest: 16.00, forSale: 5, nearMint: 21.00),
        record(4000019, master: 300019, artist: "Gwithian Static", title: "Drift Signals", year: 1983, country: "UK",
               label: "Seabird Sound", catno: "SBS 301",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["LP", "Album"]),
               barcode: "5045678301009", matrices: [("SBS 301 A1", "Side A")],
               tracks: [("A1", "Drift Signals", "5:25"), ("B1", "Shortwave", "4:10")],
               have: 74, want: 260, lowest: 26.00, forSale: 3, nearMint: 34.00),
        record(4000020, master: 300020, artist: "Porthcurno Radio", title: "Wave Theory", year: 1997, country: "UK",
               label: "Low Tide Recordings", catno: "LTR 12-6",
               format: FormatDescriptor(name: "Vinyl", descriptions: ["12\"", "33 ⅓ RPM"]),
               barcode: "5056789120069", matrices: [("LTR 12-6 A", "Side A")],
               tracks: [("A", "Wave Theory", "6:40"), ("B", "Cable Hut", "6:15")],
               have: 150, want: 90, lowest: 7.50, forSale: 12, nearMint: 10.00),
    ]

    /// Release IDs in the collection, with a second copy of Fogbound.
    static let collectionIDs: [ReleaseID] = [4000001, 4000015, 4000015, 4000013, 4000012, 4000018, 4000011, 4000016, 4000010, 4000020]
    /// Release IDs on the wantlist, with notes.
    static let wantlist: [(ReleaseID, String?)] = [
        (4000003, "Only if the inner sleeve is there"),
        (4000017, nil),
        (4000004, "Both discs, check for warps"),
        (4000014, "Original only, not the 2012 repress"),
        (4000019, nil),
    ]

    public static func release(id: ReleaseID) -> Release? {
        entry(id)?.release
    }

    /// The summary as a collection or wantlist entry carries it (no barcodes).
    static func listSummary(_ id: ReleaseID) -> ReleaseSummary? {
        guard var summary = release(id: id)?.summary else { return nil }
        summary.barcodes = []
        return summary
    }

    public static func collection(now: Date) -> [CollectionItem] {
        collectionIDs.enumerated().compactMap { offset, id in
            listSummary(id).map {
                CollectionItem(instanceID: 880001 + offset, dateAdded: now.addingTimeInterval(-Double(offset + 1) * 9 * 86400), release: $0)
            }
        }
    }

    public static func wants(now: Date) -> [Want] {
        wantlist.enumerated().compactMap { offset, entry in
            listSummary(entry.0).map {
                Want(release: $0, dateAdded: now.addingTimeInterval(-Double(offset + 1) * 14 * 86400), notes: entry.1)
            }
        }
    }

    public static func snapshot(now: Date) -> LibrarySnapshot {
        LibrarySnapshot(username: username, collection: collection(now: now), wants: wants(now: now), syncedAt: now.addingTimeInterval(-2 * 3600))
    }

    // MARK: Prices

    private static func entry(_ id: ReleaseID) -> Entry? {
        entries.first { $0.release.id == id }
    }

    public static func marketplaceStats(releaseID: ReleaseID, currency: String) -> MarketplaceStats {
        let release = entry(releaseID)?.release
        return MarketplaceStats(
            lowestPrice: release?.lowestPrice.map { Money(value: $0, currency: currency) },
            numForSale: release?.numForSale ?? 0
        )
    }

    /// Suggested prices by condition, scaled from the Near Mint figure.
    public static func priceSuggestions(releaseID: ReleaseID, currency: String = currency) -> [PricePoint] {
        guard let nearMint = entry(releaseID)?.nearMint, nearMint > 0 else { return [] }
        let scale: [(MediaCondition, Double)] = [
            (.mint, 1.15), (.nearMint, 1.0), (.veryGoodPlus, 0.74), (.veryGood, 0.46), (.goodPlus, 0.26), (.good, 0.14),
        ]
        return scale.map { PricePoint(condition: $0.0, price: Money(value: nearMint * $0.1, currency: currency)) }
    }

    // MARK: Dig log

    public static func digLogEntries(now: Date, calendar: Calendar = .current) -> [DigLogEntry] {
        func at(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func gbp(_ value: Double) -> Money { Money(value: value, currency: currency) }
        let summary = { (id: ReleaseID) in listSummary(id) }
        return [
            DigLogEntry(date: at(daysAgo: 1, hour: 10, minute: 42), shop: currentShop, outcome: .bought,
                        release: summary(4000015), pricePaid: gbp(12), marketPriceAtTime: gbp(18.50),
                        note: "Second copy, better sleeve than mine"),
            DigLogEntry(date: at(daysAgo: 1, hour: 10, minute: 18), shop: currentShop, outcome: .passed,
                        release: summary(4000016), marketPriceAtTime: gbp(11), note: "Ring wear, too dear at £25"),
            DigLogEntry(date: at(daysAgo: 1, hour: 9, minute: 55), shop: currentShop, outcome: .noted,
                        query: .catalogueNumber("QS 104"), note: "No sleeve, look it up at home"),
            DigLogEntry(date: at(daysAgo: 4, hour: 14, minute: 5), shop: "Hospice shop, Fore Street", outcome: .bought,
                        release: summary(4000012), pricePaid: gbp(4), marketPriceAtTime: gbp(32),
                        wasOnWantlist: true, note: "Wantlist find in the 50p box, priced at £4"),
            DigLogEntry(date: at(daysAgo: 4, hour: 13, minute: 50), shop: "Hospice shop, Fore Street", outcome: .passed,
                        release: summary(4000020), marketPriceAtTime: gbp(7.50)),
            DigLogEntry(date: at(daysAgo: 9, hour: 11, minute: 30), shop: "Kelpie Records", outcome: .bought,
                        release: summary(4000013), pricePaid: gbp(22), marketPriceAtTime: gbp(28)),
            DigLogEntry(date: at(daysAgo: 9, hour: 11, minute: 10), shop: "Kelpie Records", outcome: .bought,
                        release: summary(4000018), pricePaid: gbp(15), marketPriceAtTime: gbp(16)),
            DigLogEntry(date: at(daysAgo: 9, hour: 10, minute: 52), shop: "Kelpie Records", outcome: .passed,
                        release: summary(4000011), marketPriceAtTime: gbp(14), note: "Already have it"),
        ]
    }

    /// Fills a cache and dig log with the demo data: collection, wantlist,
    /// release details for every demo release, and current prices.
    public static func seed(cache: LibraryCache, digLog: DigLogStore, now: Date = Date()) async throws {
        try await cache.save(snapshot: snapshot(now: now))
        try await cache.store(releases: releases)
        for release in releases {
            let info = PriceInfo(
                releaseID: release.id,
                currency: currency,
                stats: marketplaceStats(releaseID: release.id, currency: currency),
                suggestions: priceSuggestions(releaseID: release.id),
                fetchedAt: now.addingTimeInterval(-3 * 3600)
            )
            try await cache.store(price: info)
        }
        for entry in digLogEntries(now: now) {
            try await digLog.add(entry)
        }
    }

    // MARK: Builder

    private static func record(
        _ id: ReleaseID,
        master: MasterID?,
        artist: String,
        title: String,
        year: Int,
        country: String,
        label: String,
        catno: String,
        format: FormatDescriptor,
        barcode: String?,
        matrices: [(String, String)],
        tracks: [(String, String, String)],
        have: Int,
        want: Int,
        lowest: Double?,
        forSale: Int,
        nearMint: Double
    ) -> Entry {
        var identifiers: [ReleaseIdentifier] = []
        if let barcode { identifiers.append(ReleaseIdentifier(type: "Barcode", value: barcode, detail: "Scanned")) }
        identifiers += matrices.map { ReleaseIdentifier(type: "Matrix / Runout", value: $0.0, detail: $0.1) }
        let release = Release(
            id: id,
            masterID: master,
            title: title,
            artist: artist,
            year: year,
            country: country,
            released: String(year),
            labels: [LabelCredit(name: label, catalogueNumber: catno)],
            formats: [format],
            identifiers: identifiers,
            tracklist: tracks.map { Track(position: $0.0, title: $0.1, duration: $0.2) },
            thumbURL: URL(string: "\(artScheme)://sleeve/\(id)"),
            webURL: nil,
            community: CommunityStats(have: have, want: want),
            lowestPrice: lowest,
            numForSale: forSale
        )
        return Entry(release: release, nearMint: nearMint)
    }
}
#endif
