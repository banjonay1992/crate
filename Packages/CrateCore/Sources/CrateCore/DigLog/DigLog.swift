import Foundation

/// One record found while digging.
public struct DigLogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Outcome: String, Codable, CaseIterable, Sendable {
        case bought
        case passed
        case noted

        public var displayName: String {
            switch self {
            case .bought: "Bought"
            case .passed: "Left it"
            case .noted: "Noted"
            }
        }
    }

    public var id: UUID
    public var date: Date
    /// Typed by the user. Crate never records location.
    public var shop: String
    public var outcome: Outcome
    public var release: ReleaseSummary?
    /// What was scanned or typed, kept even when nothing matched.
    public var query: LookupQuery?
    public var pricePaid: Money?
    /// Lowest marketplace price at the time, if known, for "did I get a deal" later.
    public var marketPriceAtTime: Money?
    public var wasOnWantlist: Bool
    public var note: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        shop: String,
        outcome: Outcome,
        release: ReleaseSummary? = nil,
        query: LookupQuery? = nil,
        pricePaid: Money? = nil,
        marketPriceAtTime: Money? = nil,
        wasOnWantlist: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.shop = shop
        self.outcome = outcome
        self.release = release
        self.query = query
        self.pricePaid = pricePaid
        self.marketPriceAtTime = marketPriceAtTime
        self.wasOnWantlist = wasOnWantlist
        self.note = note
    }

    /// Title for lists: the release if known, otherwise what was looked up.
    public var title: String {
        release?.displayTitle ?? query?.displayText ?? "Unidentified record"
    }
}

/// All entries from one shop on one day.
public struct DigVisit: Hashable, Sendable, Identifiable {
    public var shop: String
    public var day: Date
    public var entries: [DigLogEntry]

    public var id: String { "\(shop.lowercased())|\(day.timeIntervalSince1970)" }

    public var boughtCount: Int { entries.filter { $0.outcome == .bought }.count }

    /// Money spent, per currency (a fair abroad may mix currencies).
    public var spent: [String: Decimal] {
        entries.reduce(into: [:]) { totals, entry in
            guard entry.outcome == .bought, let paid = entry.pricePaid else { return }
            totals[paid.currency, default: 0] += paid.amount
        }
    }
}

/// Persistent log of digging trips. Stored separately from the Discogs cache
/// because it is the user's own data and cannot be re-synced.
public actor DigLogStore {
    static let key = "dig-log"

    private let storage: CodableStorage
    private var items: [DigLogEntry]

    public init(store: KeyValueStore) {
        self.storage = CodableStorage(store: store)
        self.items = (storage.load([DigLogEntry].self, key: Self.key) ?? []).sorted { $0.date > $1.date }
    }

    /// Newest first.
    public var entries: [DigLogEntry] { items }

    public func add(_ entry: DigLogEntry) throws {
        items.append(entry)
        items.sort { $0.date > $1.date }
        try persist()
    }

    public func update(_ entry: DigLogEntry) throws {
        guard let index = items.firstIndex(where: { $0.id == entry.id }) else { return }
        items[index] = entry
        items.sort { $0.date > $1.date }
        try persist()
    }

    public func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
        try persist()
    }

    public func deleteAll() throws {
        items.removeAll()
        try persist()
    }

    /// Shop names used before, most recent first, with case and spacing
    /// variants folded together (the most recent spelling wins).
    public func recentShops(limit: Int = 10) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in items {
            let key = Self.shopKey(entry.shop)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(entry.shop)
            if result.count == limit { break }
        }
        return result
    }

    /// Entries grouped by shop and calendar day, newest visit first.
    public func visits(calendar: Calendar = .current) -> [DigVisit] {
        var groups: [String: DigVisit] = [:]
        var order: [String] = []
        for entry in items {
            let day = calendar.startOfDay(for: entry.date)
            let key = "\(Self.shopKey(entry.shop))|\(day.timeIntervalSince1970)"
            if groups[key] == nil {
                groups[key] = DigVisit(shop: entry.shop, day: day, entries: [])
                order.append(key)
            }
            groups[key]?.entries.append(entry)
        }
        return order.compactMap { groups[$0] }
    }

    public func search(_ text: String) -> [DigLogEntry] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        return items.filter { entry in
            [entry.shop, entry.title, entry.note ?? "", entry.release?.catalogueNumbers.joined(separator: " ") ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    /// CSV of every entry, oldest first, for a spreadsheet.
    public func csv() -> String {
        DigLogCSV.make(items.reversed())
    }

    static func shopKey(_ shop: String) -> String {
        IdentifierNormaliser.tidy(shop).lowercased()
    }

    private func persist() throws {
        try storage.save(items, key: Self.key)
    }
}

/// CSV export for the dig log.
public enum DigLogCSV {
    static let header = ["date", "shop", "outcome", "artist", "title", "catalogue_number", "discogs_release_id", "lookup", "price_paid", "currency", "market_lowest_at_time", "was_on_wantlist", "note"]

    public static func make<S: Sequence>(_ entries: S) -> String where S.Element == DigLogEntry {
        var lines = [header.joined(separator: ",")]
        for entry in entries {
            let fields: [String] = [
                entry.date.formatted(.iso8601),
                entry.shop,
                entry.outcome.rawValue,
                entry.release?.artist ?? "",
                entry.release?.title ?? "",
                entry.release?.catalogueNumbers.first ?? "",
                entry.release.map { String($0.id) } ?? "",
                entry.query?.displayText ?? "",
                entry.pricePaid.map { "\($0.amount)" } ?? "",
                entry.pricePaid?.currency ?? "",
                entry.marketPriceAtTime.map { "\($0.amount)" } ?? "",
                entry.wasOnWantlist ? "yes" : "no",
                entry.note ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes fields that need it, and neutralises leading characters that
    /// spreadsheet apps would treat as a formula (CSV injection).
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil {
            value = "'" + value
        }
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
