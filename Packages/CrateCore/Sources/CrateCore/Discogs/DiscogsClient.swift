import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How Crate authenticates with Discogs.
public enum DiscogsCredentials: Sendable, Equatable {
    /// A personal access token from discogs.com/settings/developers. Gives
    /// access to the user's own collection and wantlist. This is what Crate uses.
    case personalToken(String)
    /// An application consumer key and secret. Enough for database search and
    /// marketplace stats, but not for a user's collection or wantlist.
    case consumerKey(key: String, secret: String)

    var authorizationHeader: String {
        switch self {
        case .personalToken(let token):
            "Discogs token=\(token)"
        case .consumerKey(let key, let secret):
            "Discogs key=\(key), secret=\(secret)"
        }
    }
}

/// What to search the Discogs database for.
public enum SearchTerm: Hashable, Sendable {
    case barcode(String)
    case catalogueNumber(String)
    /// Free text search across everything, used as a fallback for matrix numbers.
    case text(String)

    var queryItems: [URLQueryItem] {
        switch self {
        case .barcode(let value): [URLQueryItem(name: "barcode", value: value)]
        case .catalogueNumber(let value): [URLQueryItem(name: "catno", value: value)]
        case .text(let value): [URLQueryItem(name: "q", value: value)]
        }
    }
}

/// The Discogs operations Crate uses. `DiscogsClient` is the real
/// implementation; tests and previews can provide their own.
public protocol DiscogsAPI: Sendable {
    func identity() async throws -> UserIdentity
    func search(_ term: SearchTerm, page: Int, perPage: Int) async throws -> Page<ReleaseSummary>
    func release(id: ReleaseID) async throws -> Release
    func marketplaceStats(releaseID: ReleaseID, currency: String) async throws -> MarketplaceStats
    func priceSuggestions(releaseID: ReleaseID) async throws -> [PricePoint]
    func collectionPage(username: String, page: Int, perPage: Int) async throws -> Page<CollectionItem>
    func wantsPage(username: String, page: Int, perPage: Int) async throws -> Page<Want>
}

extension DiscogsAPI {
    /// First page of release results for a search term.
    public func searchReleases(_ term: SearchTerm) async throws -> [ReleaseSummary] {
        try await search(term, page: 1, perPage: 50).items
    }

    /// Fetches every page of the user's collection (folder 0, "All").
    /// `progress` receives (items fetched so far, total).
    public func fullCollection(
        username: String,
        perPage: Int = 100,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [CollectionItem] {
        try await fetchAllPages(progress: progress) { page in
            try await collectionPage(username: username, page: page, perPage: perPage)
        }
    }

    /// Fetches every page of the user's wantlist.
    public func fullWantlist(
        username: String,
        perPage: Int = 100,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [Want] {
        try await fetchAllPages(progress: progress) { page in
            try await wantsPage(username: username, page: page, perPage: perPage)
        }
    }

    private func fetchAllPages<Item: Sendable>(
        progress: (@Sendable (Int, Int) -> Void)?,
        fetch: (Int) async throws -> Page<Item>
    ) async throws -> [Item] {
        var items: [Item] = []
        var pageNumber = 1
        // Hard stop so a misbehaving server cannot loop us forever.
        let maxPages = 500
        while pageNumber <= maxPages {
            try Task.checkCancellation()
            let page = try await fetch(pageNumber)
            items += page.items
            progress?(items.count, page.totalItems)
            guard page.hasNextPage, !page.items.isEmpty else { break }
            pageNumber += 1
        }
        return items
    }
}

/// Discogs REST client.
///
/// Every request goes through the shared `RateLimiter`, carries a proper
/// User-Agent (Discogs rejects requests without one), and is retried with
/// backoff on 429 and 5xx responses. Network failures are reported as
/// `DiscogsError.offline` so callers can queue the lookup.
public struct DiscogsClient: DiscogsAPI {
    public static let defaultBaseURL = URL(string: "https://api.discogs.com")!

    public let baseURL: URL
    public let userAgent: String
    private let credentials: DiscogsCredentials?
    private let transport: HTTPTransport
    private let rateLimiter: RateLimiter
    private let sleeper: Sleeper

    public init(
        credentials: DiscogsCredentials?,
        transport: HTTPTransport = URLSessionTransport.makeDefault(),
        rateLimiter: RateLimiter = RateLimiter(),
        sleeper: Sleeper = TaskSleeper(),
        userAgent: String = "Crate/\(CrateCore.version)",
        baseURL: URL = DiscogsClient.defaultBaseURL
    ) {
        self.credentials = credentials
        self.transport = transport
        self.rateLimiter = rateLimiter
        self.sleeper = sleeper
        self.userAgent = userAgent
        self.baseURL = baseURL
    }

    // MARK: - Endpoints

    public func identity() async throws -> UserIdentity {
        let dto: DiscogsDTO.Identity = try await get("/oauth/identity")
        return UserIdentity(id: dto.id, username: dto.username)
    }

    public func search(_ term: SearchTerm, page: Int = 1, perPage: Int = 50) async throws -> Page<ReleaseSummary> {
        let items = term.queryItems + [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        let dto: DiscogsDTO.SearchPage = try await get("/database/search", query: items)
        let results = dto.results
            .filter { $0.type == nil || $0.type == "release" }
            .map { $0.toDomain() }
        return dto.pagination.page(results)
    }

    public func release(id: ReleaseID) async throws -> Release {
        let dto: DiscogsDTO.Release = try await get("/releases/\(id)")
        return dto.toDomain()
    }

    public func marketplaceStats(releaseID: ReleaseID, currency: String) async throws -> MarketplaceStats {
        let dto: DiscogsDTO.MarketplaceStats = try await get(
            "/marketplace/stats/\(releaseID)",
            query: [URLQueryItem(name: "curr_abbr", value: currency)]
        )
        return dto.toDomain()
    }

    public func priceSuggestions(releaseID: ReleaseID) async throws -> [PricePoint] {
        let data = try await send(path: "/marketplace/price_suggestions/\(releaseID)", query: [])
        do {
            return try DiscogsDTO.priceSuggestions(from: data, decoder: JSONDecoder())
        } catch {
            throw DiscogsError.decoding(String(describing: error))
        }
    }

    public func collectionPage(username: String, page: Int = 1, perPage: Int = 100) async throws -> Page<CollectionItem> {
        let dto: DiscogsDTO.CollectionPage = try await get(
            "/users/\(try pathComponent(username))/collection/folders/0/releases",
            query: pageQuery(page: page, perPage: perPage) + [
                URLQueryItem(name: "sort", value: "added"),
                URLQueryItem(name: "sort_order", value: "desc"),
            ]
        )
        let items = dto.releases.map {
            CollectionItem(
                instanceID: $0.instanceID,
                folderID: $0.folderID ?? 0,
                dateAdded: DiscogsDTO.date($0.dateAdded),
                rating: $0.rating ?? 0,
                release: $0.basicInformation.toDomain()
            )
        }
        return dto.pagination.page(items)
    }

    public func wantsPage(username: String, page: Int = 1, perPage: Int = 100) async throws -> Page<Want> {
        let dto: DiscogsDTO.WantsPage = try await get(
            "/users/\(try pathComponent(username))/wants",
            query: pageQuery(page: page, perPage: perPage)
        )
        let items = dto.wants.map {
            Want(
                release: $0.basicInformation.toDomain(),
                dateAdded: DiscogsDTO.date($0.dateAdded),
                notes: ($0.notes?.isEmpty == false) ? $0.notes : nil,
                rating: $0.rating ?? 0
            )
        }
        return dto.pagination.page(items)
    }

    // MARK: - Request plumbing

    private func pageQuery(page: Int, perPage: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "per_page", value: String(min(max(1, perPage), 100))),
        ]
    }

    private func pathComponent(_ value: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard !value.isEmpty, let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw DiscogsError.missingCredentials
        }
        return encoded
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send(path: path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DiscogsError.decoding(String(describing: error))
        }
    }

    func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard let credentials else { throw DiscogsError.missingCredentials }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DiscogsError.transport("Invalid base URL")
        }
        components.percentEncodedPath = components.percentEncodedPath.trimmingSuffix("/") + path
        components.queryItems = query.isEmpty ? nil : query
        // URLComponents leaves "+" alone in query values, but Discogs reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw DiscogsError.transport("Could not build URL for \(path)") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.discogs.v2.discogs+json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(path: String, query: [URLQueryItem]) async throws -> Data {
        let request = try makeRequest(path: path, query: query)
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let wait = await rateLimiter.reserveSlot()
            if wait > 0 { try await sleeper.sleep(seconds: wait) }

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as DiscogsError {
                throw error
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw DiscogsError.from(transportError: error)
            }

            await rateLimiter.record(headers: Self.headers(of: response))

            switch response.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw DiscogsError.unauthorised(message: Self.message(in: data))
            case 404:
                throw DiscogsError.notFound
            case 429, 500...599:
                guard attempt < rateLimiter.policy.maxRetries else {
                    throw response.statusCode == 429
                        ? DiscogsError.rateLimited
                        : DiscogsError.server(status: response.statusCode, message: Self.message(in: data))
                }
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                // The limiter turns this into a pause that the next reserveSlot() call waits out.
                _ = await rateLimiter.backoff(attempt: attempt, retryAfter: retryAfter)
                attempt += 1
            default:
                throw DiscogsError.server(status: response.statusCode, message: Self.message(in: data))
            }
        }
    }

    private static func headers(of response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String { result[key] = "\(value)" }
        }
        return result
    }

    private static func message(in data: Data) -> String? {
        (try? JSONDecoder().decode(DiscogsDTO.ErrorBody.self, from: data))?.message
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
