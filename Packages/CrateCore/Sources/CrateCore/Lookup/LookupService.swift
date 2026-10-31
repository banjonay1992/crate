import Foundation

/// Everything Crate can say about a lookup.
public struct LookupResult: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Fresh from Discogs.
        case discogs
        /// From what is cached on the device, because there was no connection.
        case deviceCache
    }

    public var query: LookupQuery
    /// Ranked strongest first.
    public var candidates: [PressingCandidate]
    public var isAmbiguous: Bool
    public var ownership: [ReleaseID: OwnershipStatus]
    public var prices: [ReleaseID: PriceInfo]
    /// For ambiguous results: run-out strings that tell the candidates apart.
    public var distinguishingMatrices: [ReleaseID: [String]]
    public var source: Source
    public var lookedUpAt: Date

    public init(
        query: LookupQuery,
        candidates: [PressingCandidate],
        isAmbiguous: Bool,
        ownership: [ReleaseID: OwnershipStatus] = [:],
        prices: [ReleaseID: PriceInfo] = [:],
        distinguishingMatrices: [ReleaseID: [String]] = [:],
        source: Source,
        lookedUpAt: Date
    ) {
        self.query = query
        self.candidates = candidates
        self.isAmbiguous = isAmbiguous
        self.ownership = ownership
        self.prices = prices
        self.distinguishingMatrices = distinguishingMatrices
        self.source = source
        self.lookedUpAt = lookedUpAt
    }

    /// The identified pressing, when there is exactly one.
    public var bestMatch: PressingCandidate? {
        guard !isAmbiguous, let first = candidates.first, first.evidence != .searchResult else { return nil }
        return first
    }

    /// Candidates worth showing when there is no single answer: the tied set
    /// for an ambiguous result, otherwise whatever search returned.
    public var choices: [PressingCandidate] {
        guard let top = candidates.first else { return [] }
        return isAmbiguous ? candidates.filter { $0.evidence == top.evidence } : candidates
    }

    public var isEmpty: Bool { candidates.isEmpty }

    public func ownership(for releaseID: ReleaseID) -> OwnershipStatus {
        ownership[releaseID] ?? .unknown
    }
}

/// What happened when the user asked for a lookup.
public enum LookupOutcome: Hashable, Sendable {
    case found(LookupResult)
    /// No connection: the lookup was queued. `local` is the best answer the
    /// device could give on its own, if any.
    case queued(PendingLookup, local: LookupResult?)
}

/// Settings that shape a lookup.
public struct LookupOptions: Sendable, Hashable {
    /// ISO 4217 currency for marketplace stats, for example "GBP".
    public var currency: String
    /// How many search results to fetch full details for. Each one costs a request.
    public var maxDetailFetches: Int
    /// Fetch price suggestions as well as marketplace stats. Costs one request.
    public var includePriceSuggestions: Bool

    public init(currency: String = "GBP", maxDetailFetches: Int = 4, includePriceSuggestions: Bool = true) {
        self.currency = currency
        self.maxDetailFetches = maxDetailFetches
        self.includePriceSuggestions = includePriceSuggestions
    }
}

/// Identifies a pressing: searches Discogs, fetches details for the strongest
/// candidates, matches identifiers, and adds ownership and price information.
/// Falls back to the device cache and the lookup queue when offline.
public struct LookupService: Sendable {
    private let api: DiscogsAPI
    private let cache: LibraryCache
    private let queue: LookupQueue?
    private let now: @Sendable () -> Date

    public init(api: DiscogsAPI, cache: LibraryCache, queue: LookupQueue? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.cache = cache
        self.queue = queue
        self.now = now
    }

    /// The entry point the Scan screen uses. Tries Discogs; if the network is
    /// unavailable, answers from the cache and queues the lookup for later.
    public func lookupOrQueue(_ query: LookupQuery, shopName: String?, options: LookupOptions) async throws -> LookupOutcome {
        do {
            return .found(try await lookup(query, options: options))
        } catch let error as DiscogsError where error.isTransient {
            let local = await localLookup(query)
            guard let queue else { throw error }
            let pending = try await queue.enqueue(query, shopName: shopName)
            return .queued(pending, local: local.isEmpty ? nil : local)
        }
    }

    /// Online lookup. Throws `DiscogsError` on failure.
    public func lookup(_ query: LookupQuery, options: LookupOptions) async throws -> LookupResult {
        let summaries = try await searchCandidates(for: query)

        // First pass on summaries alone decides which candidates deserve a detail fetch.
        let preliminary = PressingMatcher.rank(query, candidates: summaries.map { ($0, nil) })
        var details: [ReleaseID: Release] = [:]
        for candidate in preliminary.prefix(options.maxDetailFetches) {
            try Task.checkCancellation()
            if let cached = await cache.freshRelease(id: candidate.id) {
                details[candidate.id] = cached
                continue
            }
            do {
                details[candidate.id] = try await api.release(id: candidate.id)
            } catch DiscogsError.notFound {
                continue
            }
        }
        try? await cache.store(releases: Array(details.values))

        let ranked = PressingMatcher.rank(query, candidates: summaries.map { ($0, details[$0.id]) })
        let resolution = PressingMatcher.resolve(ranked)

        var prices: [ReleaseID: PriceInfo] = [:]
        if case .unique(let match) = resolution, match.evidence != .searchResult {
            prices[match.id] = try? await priceInfo(for: match.id, options: options)
        }

        return await assemble(query: query, ranked: ranked, resolution: resolution, prices: prices, source: .discogs)
    }

    /// Answers from the device alone.
    public func localLookup(_ query: LookupQuery) async -> LookupResult {
        let candidates = await cache.localCandidates(for: query)
        let ranked = PressingMatcher.rank(query, candidates: candidates)
        let resolution = PressingMatcher.resolve(ranked)
        var prices: [ReleaseID: PriceInfo] = [:]
        for candidate in ranked {
            if let price = await cache.price(for: candidate.id) { prices[candidate.id] = price }
        }
        return await assemble(query: query, ranked: ranked, resolution: resolution, prices: prices, source: .deviceCache)
    }

    /// Price data for one release, from the cache when fresh. Used when the
    /// user picks a pressing from an ambiguous result.
    public func priceInfo(for releaseID: ReleaseID, options: LookupOptions, forceRefresh: Bool = false) async throws -> PriceInfo {
        if !forceRefresh, let cached = await cache.price(for: releaseID), cached.currency == options.currency,
           await cache.isFresh(cached) {
            return cached
        }
        let stats = try await api.marketplaceStats(releaseID: releaseID, currency: options.currency)
        var suggestions: [PricePoint] = []
        if options.includePriceSuggestions {
            do {
                suggestions = try await api.priceSuggestions(releaseID: releaseID)
            } catch let error as DiscogsError where error == .offline {
                throw error
            } catch {
                // Suggestions need seller settings on the user's Discogs account;
                // without them Discogs refuses, which is not worth failing over.
                suggestions = []
            }
        }
        let info = PriceInfo(releaseID: releaseID, currency: options.currency, stats: stats, suggestions: suggestions, fetchedAt: now())
        try? await cache.store(price: info)
        return info
    }

    /// Full details for one release (cache first).
    public func release(id: ReleaseID) async throws -> Release {
        if let cached = await cache.freshRelease(id: id) { return cached }
        let release = try await api.release(id: id)
        try? await cache.store(releases: [release])
        return release
    }

    // MARK: - Internals

    /// Runs the right Discogs searches for the query kind.
    func searchCandidates(for query: LookupQuery) async throws -> [ReleaseSummary] {
        switch query {
        case .barcode(let barcode):
            // Discogs search does not equate UPC-A with EAN-13, so try each form.
            for variant in barcode.searchVariants {
                let results = try await api.searchReleases(.barcode(variant))
                if !results.isEmpty { return results }
            }
            return []
        case .catalogueNumber(let text):
            let results = try await api.searchReleases(.catalogueNumber(text))
            if !results.isEmpty { return results }
            // "GCR012" will not find "GCR 012"; a plain text search often will.
            return try await api.searchReleases(.text(text))
        case .matrix(let text):
            // The Discogs barcode field indexes every identifier on a release,
            // including run-out etchings, so try that before general text search.
            let results = try await api.searchReleases(.barcode(text))
            if !results.isEmpty { return results }
            return try await api.searchReleases(.text(text))
        }
    }

    private func assemble(
        query: LookupQuery,
        ranked: [PressingCandidate],
        resolution: MatchResolution,
        prices: [ReleaseID: PriceInfo],
        source: LookupResult.Source
    ) async -> LookupResult {
        let index = await cache.ownershipIndex()
        var ownership: [ReleaseID: OwnershipStatus] = [:]
        for candidate in ranked {
            ownership[candidate.id] = index.status(for: candidate.summary)
        }
        var distinguishing: [ReleaseID: [String]] = [:]
        if case .ambiguous(let tied) = resolution {
            let releases = tied.compactMap(\.release)
            if releases.count > 1 { distinguishing = PressingMatcher.distinguishingMatrices(among: releases) }
        }
        let isAmbiguous: Bool
        switch resolution {
        case .ambiguous: isAmbiguous = true
        case .unique, .none: isAmbiguous = false
        }
        return LookupResult(
            query: query,
            candidates: Array(ranked.prefix(12)),
            isAmbiguous: isAmbiguous,
            ownership: ownership,
            prices: prices,
            distinguishingMatrices: distinguishing,
            source: source,
            lookedUpAt: now()
        )
    }
}
