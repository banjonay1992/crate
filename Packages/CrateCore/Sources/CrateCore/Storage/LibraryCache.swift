import Foundation

/// The user's collection and wantlist as of the last sync.
public struct LibrarySnapshot: Codable, Hashable, Sendable {
    public var username: String
    public var collection: [CollectionItem]
    public var wants: [Want]
    public var syncedAt: Date

    public init(username: String, collection: [CollectionItem], wants: [Want], syncedAt: Date) {
        self.username = username
        self.collection = collection
        self.wants = wants
        self.syncedAt = syncedAt
    }
}

/// A release detail fetched from Discogs, with when it was fetched.
public struct CachedRelease: Codable, Hashable, Sendable {
    public var release: Release
    public var fetchedAt: Date
}

/// Everything Crate needs to answer questions with no signal: the collection
/// and wantlist, release details seen before (which carry barcodes and matrix
/// strings), and recent prices.
public actor LibraryCache {
    public struct Limits: Sendable {
        /// Release details kept. Oldest are evicted first.
        public var maxReleases: Int
        /// Price data kept. Oldest are evicted first.
        public var maxPrices: Int
        /// After this, a cached release is re-fetched when online.
        public var releaseFreshness: TimeInterval
        /// After this, cached prices are re-fetched when online and shown with their age offline.
        public var priceFreshness: TimeInterval

        public init(
            maxReleases: Int = 1500,
            maxPrices: Int = 1500,
            releaseFreshness: TimeInterval = 30 * 24 * 3600,
            priceFreshness: TimeInterval = 24 * 3600
        ) {
            self.maxReleases = maxReleases
            self.maxPrices = maxPrices
            self.releaseFreshness = releaseFreshness
            self.priceFreshness = priceFreshness
        }
    }

    static let snapshotKey = "library"
    static let releasesKey = "releases"
    static let pricesKey = "prices"

    public nonisolated let limits: Limits
    private let storage: CodableStorage
    private let now: @Sendable () -> Date

    private var snapshotValue: LibrarySnapshot?
    private var releases: [ReleaseID: CachedRelease]
    private var prices: [ReleaseID: PriceInfo]
    private var indexValue: OwnershipIndex?

    public init(store: KeyValueStore, limits: Limits = Limits(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = CodableStorage(store: store)
        self.limits = limits
        self.now = now
        self.snapshotValue = storage.load(LibrarySnapshot.self, key: Self.snapshotKey)
        self.releases = storage.load([ReleaseID: CachedRelease].self, key: Self.releasesKey) ?? [:]
        self.prices = storage.load([ReleaseID: PriceInfo].self, key: Self.pricesKey) ?? [:]
    }

    // MARK: Collection and wantlist

    public var snapshot: LibrarySnapshot? { snapshotValue }

    public func save(snapshot: LibrarySnapshot) throws {
        snapshotValue = snapshot
        indexValue = nil
        try storage.save(snapshot, key: Self.snapshotKey, now: now())
    }

    /// Built lazily and kept until the snapshot changes.
    public func ownershipIndex() -> OwnershipIndex {
        if let indexValue { return indexValue }
        let index = OwnershipIndex(collection: snapshotValue?.collection ?? [], wants: snapshotValue?.wants ?? [])
        indexValue = index
        return index
    }

    // MARK: Release details

    public func release(id: ReleaseID) -> CachedRelease? { releases[id] }

    /// A cached release that is recent enough not to re-fetch.
    public func freshRelease(id: ReleaseID) -> Release? {
        guard let cached = releases[id], now().timeIntervalSince(cached.fetchedAt) < limits.releaseFreshness else { return nil }
        return cached.release
    }

    public func store(releases newReleases: [Release]) throws {
        guard !newReleases.isEmpty else { return }
        let date = now()
        for release in newReleases { releases[release.id] = CachedRelease(release: release, fetchedAt: date) }
        if releases.count > limits.maxReleases {
            let overflow = releases.count - limits.maxReleases
            for key in releases.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(overflow).map(\.key) {
                releases[key] = nil
            }
        }
        try storage.save(releases, key: Self.releasesKey, now: date)
    }

    public var cachedReleaseCount: Int { releases.count }

    public func hasRelease(id: ReleaseID) -> Bool { releases[id] != nil }

    // MARK: Prices

    public func price(for releaseID: ReleaseID) -> PriceInfo? { prices[releaseID] }

    public func isFresh(_ price: PriceInfo) -> Bool {
        now().timeIntervalSince(price.fetchedAt) < limits.priceFreshness
    }

    public func store(price: PriceInfo) throws {
        prices[price.releaseID] = price
        if prices.count > limits.maxPrices {
            let overflow = prices.count - limits.maxPrices
            for key in prices.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(overflow).map(\.key) {
                prices[key] = nil
            }
        }
        try storage.save(prices, key: Self.pricesKey, now: now())
    }

    // MARK: Offline matching

    /// Candidates for a query using only what is on the device: cached release
    /// details (barcodes, matrices, catalogue numbers) plus the catalogue
    /// numbers in the collection and wantlist.
    public func localCandidates(for query: LookupQuery) -> [(summary: ReleaseSummary, release: Release?)] {
        var results: [(summary: ReleaseSummary, release: Release?)] = []
        var seen = Set<ReleaseID>()
        func add(_ summary: ReleaseSummary, _ release: Release?) {
            guard seen.insert(summary.id).inserted else { return }
            results.append((summary, release))
        }

        // Deterministic order: most recently fetched first.
        let cached = releases.values.sorted { $0.fetchedAt > $1.fetchedAt }.map(\.release)
        for release in cached {
            let (evidence, _) = PressingMatcher.evaluate(query, summary: release.summary, release: release)
            if evidence != .searchResult { add(release.summary, release) }
        }

        if case .catalogueNumber(let text) = query {
            for summary in ownershipIndex().releases(matchingCatalogueNumber: text) {
                add(summary, releases[summary.id]?.release)
            }
        }
        return results
    }

    /// Removes everything, for example when the user disconnects their account.
    public func clear() throws {
        snapshotValue = nil
        releases = [:]
        prices = [:]
        indexValue = nil
        try storage.remove(key: Self.snapshotKey)
        try storage.remove(key: Self.releasesKey)
        try storage.remove(key: Self.pricesKey)
    }
}
