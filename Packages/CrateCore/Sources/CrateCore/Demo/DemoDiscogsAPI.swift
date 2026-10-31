#if DEBUG
import Foundation

/// A stand-in for the Discogs API that answers from `DemoLibrary` in memory.
/// It never touches the network, so demo mode and screenshots behave the same
/// everywhere. The search rules follow what Crate relies on from Discogs: the
/// barcode field also indexes run-out etchings, and catalogue number search
/// ignores spacing.
public struct DemoDiscogsAPI: DiscogsAPI {
    /// Pause before each answer, so loading states are visible as they would be.
    public var latency: Duration

    public init(latency: Duration = .milliseconds(250)) {
        self.latency = latency
    }

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    public func identity() async throws -> UserIdentity {
        try await pause()
        return UserIdentity(id: 1_000_001, username: DemoLibrary.username)
    }

    public func search(_ term: SearchTerm, page: Int, perPage: Int) async throws -> Page<ReleaseSummary> {
        try await pause()
        let matches = DemoLibrary.releases.filter { Self.release($0, matches: term) }.map(\.summary)
        let items = page == 1 ? Array(matches.prefix(perPage)) : []
        return Page(items: items, page: page, pages: 1, perPage: perPage, totalItems: matches.count)
    }

    static func release(_ release: Release, matches term: SearchTerm) -> Bool {
        switch term {
        case .barcode(let value):
            if let key = Barcode.canonicalKey(for: value),
               release.barcodes.contains(where: { Barcode.canonicalKey(for: $0) == key }) {
                return true
            }
            let key = IdentifierNormaliser.matrixKey(value)
            return !key.isEmpty && release.matrices.contains { IdentifierNormaliser.matrixKey($0.value).contains(key) }
        case .catalogueNumber(let value):
            let key = IdentifierNormaliser.catalogueKey(value)
            return !key.isEmpty && release.catalogueNumbers.contains { IdentifierNormaliser.catalogueKey($0) == key }
        case .text(let value):
            let needle = value.trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else { return false }
            return release.title.localizedCaseInsensitiveContains(needle)
                || release.artist.localizedCaseInsensitiveContains(needle)
                || release.catalogueNumbers.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    public func release(id: ReleaseID) async throws -> Release {
        try await pause()
        guard let release = DemoLibrary.release(id: id) else { throw DiscogsError.notFound }
        return release
    }

    public func marketplaceStats(releaseID: ReleaseID, currency: String) async throws -> MarketplaceStats {
        try await pause()
        return DemoLibrary.marketplaceStats(releaseID: releaseID, currency: currency)
    }

    public func priceSuggestions(releaseID: ReleaseID) async throws -> [PricePoint] {
        try await pause()
        return DemoLibrary.priceSuggestions(releaseID: releaseID)
    }

    public func collectionPage(username: String, page: Int, perPage: Int) async throws -> Page<CollectionItem> {
        try await pause()
        let all = DemoLibrary.collection(now: Date())
        return Self.page(of: all, page: page, perPage: perPage)
    }

    public func wantsPage(username: String, page: Int, perPage: Int) async throws -> Page<Want> {
        try await pause()
        let all = DemoLibrary.wants(now: Date())
        return Self.page(of: all, page: page, perPage: perPage)
    }

    private static func page<Item: Sendable>(of items: [Item], page: Int, perPage: Int) -> Page<Item> {
        let size = max(perPage, 1)
        let pages = max(1, (items.count + size - 1) / size)
        let start = min(max(page - 1, 0) * size, items.count)
        let slice = Array(items[start..<min(start + size, items.count)])
        return Page(items: slice, page: page, pages: pages, perPage: size, totalItems: items.count)
    }
}
#endif
