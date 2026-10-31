import Foundation
import Observation

/// User preferences, persisted in UserDefaults. Nothing secret lives here;
/// the token is in the Keychain.
@MainActor
@Observable
final class AppSettings {
    static let supportedCurrencies = ["GBP", "EUR", "USD", "CAD", "AUD", "JPY", "CHF", "SEK", "NZD", "MXN", "BRL", "ZAR"]

    private enum Key {
        static let currency = "currency"
        static let prefetch = "prefetchWantlistDetails"
        static let shop = "currentShop"
        static let username = "discogsUsername"
        static let priceSuggestions = "includePriceSuggestions"
    }

    private let defaults: UserDefaults

    var currency: String {
        didSet { defaults.set(currency, forKey: Key.currency) }
    }

    /// Fetch full details for wantlist items during sync so barcodes and
    /// run-outs match offline. Costs one request per item, the first time.
    var prefetchWantlistDetails: Bool {
        didSet { defaults.set(prefetchWantlistDetails, forKey: Key.prefetch) }
    }

    var includePriceSuggestions: Bool {
        didSet { defaults.set(includePriceSuggestions, forKey: Key.priceSuggestions) }
    }

    /// The shop the user says they are in. Typed, never detected.
    var currentShop: String {
        didSet { defaults.set(currentShop, forKey: Key.shop) }
    }

    /// Discogs username for the connected token. Public information.
    var username: String? {
        didSet { defaults.set(username, forKey: Key.username) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let localeCurrency = Locale.current.currency?.identifier ?? "GBP"
        let fallback = Self.supportedCurrencies.contains(localeCurrency) ? localeCurrency : "GBP"
        self.currency = defaults.string(forKey: Key.currency) ?? fallback
        self.prefetchWantlistDetails = defaults.object(forKey: Key.prefetch) as? Bool ?? true
        self.includePriceSuggestions = defaults.object(forKey: Key.priceSuggestions) as? Bool ?? true
        self.currentShop = defaults.string(forKey: Key.shop) ?? ""
        self.username = defaults.string(forKey: Key.username)
    }
}
