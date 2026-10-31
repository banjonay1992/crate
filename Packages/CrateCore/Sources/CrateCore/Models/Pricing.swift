import Foundation

/// An amount of money in a named currency. Stored as `Decimal` so that
/// prices like 12.10 survive a round trip without binary rounding noise.
public struct Money: Codable, Hashable, Sendable {
    public var amount: Decimal
    /// ISO 4217 code, for example "GBP".
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }

    /// Builds a Money value from a JSON double without picking up float noise
    /// (12.1 becomes exactly 12.1, not 12.0999999...).
    public init(value: Double, currency: String) {
        let rounded = (value * 100).rounded() / 100
        self.amount = Decimal(string: String(format: "%.2f", rounded)) ?? Decimal(rounded)
        self.currency = currency
    }

    /// Formats the amount for display, for example "£12.50".
    public func formatted(locale: Locale = .current) -> String {
        amount.formatted(.currency(code: currency).locale(locale))
    }
}

/// The Discogs media condition grades, in order from best to worst.
public enum MediaCondition: String, Codable, CaseIterable, Sendable, Comparable {
    case mint = "Mint (M)"
    case nearMint = "Near Mint (NM or M-)"
    case veryGoodPlus = "Very Good Plus (VG+)"
    case veryGood = "Very Good (VG)"
    case goodPlus = "Good Plus (G+)"
    case good = "Good (G)"
    case fair = "Fair (F)"
    case poor = "Poor (P)"

    /// Short label for badges, for example "VG+".
    public var shortLabel: String {
        switch self {
        case .mint: "M"
        case .nearMint: "NM"
        case .veryGoodPlus: "VG+"
        case .veryGood: "VG"
        case .goodPlus: "G+"
        case .good: "G"
        case .fair: "F"
        case .poor: "P"
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: MediaCondition, rhs: MediaCondition) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// From `GET /marketplace/stats/{release_id}`: what is for sale right now.
public struct MarketplaceStats: Codable, Hashable, Sendable {
    public var lowestPrice: Money?
    public var numForSale: Int?
    public var blockedFromSale: Bool

    public init(lowestPrice: Money?, numForSale: Int?, blockedFromSale: Bool = false) {
        self.lowestPrice = lowestPrice
        self.numForSale = numForSale
        self.blockedFromSale = blockedFromSale
    }
}

/// One suggested price for a condition grade.
public struct PricePoint: Codable, Hashable, Sendable {
    public var condition: MediaCondition
    public var price: Money

    public init(condition: MediaCondition, price: Money) {
        self.condition = condition
        self.price = price
    }
}

/// Everything Crate knows about the price of a pressing, plus when it was fetched.
/// Price suggestions need the user to have filled in their Discogs seller settings,
/// so they are often empty; the marketplace stats are more widely available.
public struct PriceInfo: Codable, Hashable, Sendable {
    public var releaseID: ReleaseID
    public var stats: MarketplaceStats?
    /// Sorted best condition first.
    public var suggestions: [PricePoint]
    public var fetchedAt: Date

    public init(releaseID: ReleaseID, stats: MarketplaceStats?, suggestions: [PricePoint], fetchedAt: Date) {
        self.releaseID = releaseID
        self.stats = stats
        self.suggestions = suggestions.sorted { $0.condition < $1.condition }
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool { stats?.lowestPrice == nil && suggestions.isEmpty }

    public func suggestion(for condition: MediaCondition) -> Money? {
        suggestions.first { $0.condition == condition }?.price
    }
}
