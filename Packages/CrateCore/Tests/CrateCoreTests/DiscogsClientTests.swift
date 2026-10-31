import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CrateCore

final class DiscogsClientTests: XCTestCase {
    func testRequestsCarryUserAgentAuthorisationAndAccept() async throws {
        let transport = MockTransport()
        transport.on("/oauth/identity", .json("identity"))
        let client = DiscogsClient.test(transport: transport)

        let identity = try await client.identity()

        XCTAssertEqual(identity, UserIdentity(id: 1234567, username: "example_digger"))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "CrateTests/1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Discogs token=test-token-not-real")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.discogs.v2.discogs+json")
        XCTAssertEqual(request.url?.host, "api.discogs.com")
    }

    func testConsumerKeyAuthorisationHeader() {
        XCTAssertEqual(
            DiscogsCredentials.consumerKey(key: "k", secret: "s").authorizationHeader,
            "Discogs key=k, secret=s"
        )
    }

    func testMissingCredentialsFailsWithoutTouchingTheNetwork() async {
        let transport = MockTransport()
        let client = DiscogsClient.test(transport: transport, credentials: nil)
        do {
            _ = try await client.identity()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .missingCredentials)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testBarcodeSearchBuildsQueryAndFiltersToReleases() async throws {
        let transport = MockTransport()
        transport.on("/database/search", .json("search_barcode"))
        let client = DiscogsClient.test(transport: transport)

        let results = try await client.searchReleases(.barcode("5012345600291"))

        XCTAssertEqual(results.map(\.id), [4000002])
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["barcode"], "5012345600291")
        XCTAssertEqual(items["type"], "release")
    }

    func testPlusSignsInQueriesAreEncoded() throws {
        let client = DiscogsClient.test(transport: MockTransport())
        let request = try client.makeRequest(path: "/database/search", query: [URLQueryItem(name: "q", value: "A+B side")])
        XCTAssertEqual(request.url?.query, "q=A%2BB%20side")
    }

    func testReleaseAndMarketplaceEndpoints() async throws {
        let transport = MockTransport()
        transport.on("/releases/4000001", .json("release_4000001"))
        transport.on("/marketplace/stats/4000001", .json("marketplace_stats_4000001"))
        transport.on("/marketplace/price_suggestions/4000001", .json("price_suggestions_4000001"))
        let client = DiscogsClient.test(transport: transport)

        let release = try await client.release(id: 4000001)
        let stats = try await client.marketplaceStats(releaseID: 4000001, currency: "GBP")
        let suggestions = try await client.priceSuggestions(releaseID: 4000001)

        XCTAssertEqual(release.title, "Harbour Lights")
        XCTAssertEqual(stats.lowestPrice?.currency, "GBP")
        XCTAssertEqual(suggestions.count, 8)
        XCTAssertEqual(transport.requests(to: "/marketplace/stats/4000001").first?.url?.query, "curr_abbr=GBP")
    }

    func testCollectionPaginationFetchesEveryPage() async throws {
        let transport = MockTransport()
        transport.on("/users/example_digger/collection/folders/0/releases", .json("collection_page1"), .json("collection_page2"))
        let client = DiscogsClient.test(transport: transport)
        let progress = ProgressRecorder()

        let items = try await client.fullCollection(username: "example_digger", perPage: 2) { done, total in
            progress.record(done, total)
        }

        XCTAssertEqual(items.map(\.instanceID), [880001, 880002, 880003])
        XCTAssertEqual(progress.values.map(\.0), [2, 3])
        XCTAssertEqual(progress.values.last?.1, 3)
        let pages = transport.requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value }
        XCTAssertEqual(pages, ["1", "2"])
    }

    func testWantlistFetch() async throws {
        let transport = MockTransport()
        transport.on("/users/example_digger/wants", .json("wants_page1"))
        let client = DiscogsClient.test(transport: transport)

        let wants = try await client.fullWantlist(username: "example_digger")

        XCTAssertEqual(wants.map(\.releaseID), [4000003, 4000004])
        XCTAssertNil(wants[1].notes, "empty notes become nil")
        XCTAssertNil(wants[1].release.masterID)
    }

    func testUsernameIsPercentEncodedInPath() throws {
        let client = DiscogsClient.test(transport: MockTransport())
        let path = "/users/\("dj%20kernow")/wants"
        let request = try client.makeRequest(path: path, query: [])
        XCTAssertEqual(request.url?.absoluteString, "https://api.discogs.com/users/dj%20kernow/wants")
    }

    func testUnauthorisedCarriesServerMessage() async {
        let transport = MockTransport()
        transport.on("/oauth/identity", .json("error_401", status: 401))
        let client = DiscogsClient.test(transport: transport)
        do {
            _ = try await client.identity()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .unauthorised(message: "You must authenticate to access this resource."))
        }
    }

    func testNotFound() async {
        let transport = MockTransport()
        let client = DiscogsClient.test(transport: transport)
        do {
            _ = try await client.release(id: 1)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .notFound)
        }
    }

    func testRetriesAfter429WithExponentialBackoff() async throws {
        let transport = MockTransport()
        transport.on(
            "/releases/4000001",
            .json("error_429", status: 429),
            .json("error_429", status: 429),
            .json("release_4000001")
        )
        let sleeper = RecordingSleeper()
        let client = DiscogsClient.test(transport: transport, sleeper: sleeper)

        let release = try await client.release(id: 4000001)

        XCTAssertEqual(release.id, 4000001)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(sleeper.sleeps.count, 2)
        XCTAssertEqual(sleeper.sleeps[0], 2, accuracy: 0.1)
        XCTAssertEqual(sleeper.sleeps[1], 4, accuracy: 0.1)
    }

    func testHonoursRetryAfterHeader() async throws {
        let transport = MockTransport()
        transport.on(
            "/releases/4000001",
            .json("error_429", status: 429, headers: ["Retry-After": "7"]),
            .json("release_4000001")
        )
        let sleeper = RecordingSleeper()
        let client = DiscogsClient.test(transport: transport, sleeper: sleeper)

        _ = try await client.release(id: 4000001)

        XCTAssertEqual(sleeper.sleeps.first ?? 0, 7, accuracy: 0.1)
    }

    func testGivesUpAfterMaxRetries() async {
        let transport = MockTransport()
        transport.on("/releases/4000001", .json("error_429", status: 429))
        let sleeper = RecordingSleeper()
        let client = DiscogsClient.test(
            transport: transport,
            sleeper: sleeper,
            policy: RateLimiter.Policy(maxRetries: 2, jitter: 0)
        )
        do {
            _ = try await client.release(id: 4000001)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .rateLimited)
            XCTAssertTrue((error as? DiscogsError)?.isTransient ?? false)
        }
        XCTAssertEqual(transport.requests.count, 3, "one try plus two retries")
    }

    func testRetriesServerErrorsThenReportsThem() async {
        let transport = MockTransport()
        transport.on("/releases/4000001", .status(503, body: #"{"message":"Maintenance"}"#))
        let client = DiscogsClient.test(transport: transport, policy: RateLimiter.Policy(maxRetries: 1, jitter: 0))
        do {
            _ = try await client.release(id: 4000001)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .server(status: 503, message: "Maintenance"))
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testOfflineTransportErrorsMapToOffline() async {
        let transport = MockTransport()
        transport.failEverything(with: URLError(.notConnectedToInternet))
        let client = DiscogsClient.test(transport: transport)
        do {
            _ = try await client.identity()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DiscogsError, .offline)
        }
    }

    func testOtherTransportErrorsAreTransient() async {
        let transport = MockTransport()
        transport.failEverything(with: URLError(.badServerResponse))
        let client = DiscogsClient.test(transport: transport)
        do {
            _ = try await client.identity()
            XCTFail("Expected an error")
        } catch {
            guard case .transport = error as? DiscogsError else { return XCTFail("Got \(error)") }
        }
    }

    func testDecodingErrorsAreReported() async {
        let transport = MockTransport()
        transport.on("/oauth/identity", .status(200, body: "not json"))
        let client = DiscogsClient.test(transport: transport)
        do {
            _ = try await client.identity()
            XCTFail("Expected an error")
        } catch {
            guard case .decoding = error as? DiscogsError else { return XCTFail("Got \(error)") }
        }
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [(Int, Int)] = []
    var values: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return _values }
    func record(_ done: Int, _ total: Int) { lock.lock(); _values.append((done, total)); lock.unlock() }
}
