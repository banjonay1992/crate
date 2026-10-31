import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CrateCore

/// A scripted HTTP transport. Routes match on the URL path; each route can
/// hold a queue of responses so tests can script "429, then 200".
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: Data
        var headers: [String: String]

        static func json(_ fixture: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            Response(status: status, body: Fixture.data(fixture), headers: headers)
        }

        static func status(_ status: Int, body: String = "{}", headers: [String: String] = [:]) -> Response {
            Response(status: status, body: Data(body.utf8), headers: headers)
        }
    }

    enum Outcome {
        case respond(Response)
        case fail(Error)
    }

    private let lock = NSLock()
    private var routes: [String: [Outcome]] = [:]
    private var fallback: Outcome = .respond(.status(404, body: #"{"message":"Not found in mock"}"#))
    private(set) var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    /// Requests whose path matches exactly.
    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    /// Adds responses for a path. The last response for a path repeats once the queue runs down to it.
    func on(_ path: String, _ outcomes: Outcome...) {
        lock.lock(); defer { lock.unlock() }
        routes[path, default: []].append(contentsOf: outcomes)
    }

    func on(_ path: String, _ responses: Response...) {
        lock.lock(); defer { lock.unlock() }
        routes[path, default: []].append(contentsOf: responses.map { .respond($0) })
    }

    /// Makes every unscripted path fail, for example with an offline error.
    func failEverything(with error: Error) {
        lock.lock(); defer { lock.unlock() }
        routes.removeAll()
        fallback = .fail(error)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        routes.removeAll()
        fallback = .respond(.status(404, body: #"{"message":"Not found in mock"}"#))
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let outcome: Outcome = withLock {
            _requests.append(request)
            let path = request.url?.path ?? ""
            guard var queue = routes[path], !queue.isEmpty else { return fallback }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[path] = queue
            return next
        }
        switch outcome {
        case .fail(let error):
            throw error
        case .respond(let response):
            let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
            return (response.body, http)
        }
    }
}

/// Records requested sleeps instead of sleeping.
final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var _sleeps: [Double] = []

    var sleeps: [Double] {
        lock.lock(); defer { lock.unlock() }
        return _sleeps
    }

    func sleep(seconds: Double) async throws {
        record(seconds)
    }

    private func record(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        _sleeps.append(seconds)
    }
}

/// A clock that only moves when told to.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

extension DiscogsClient {
    /// A client wired to a mock transport with no real waiting.
    static func test(
        transport: MockTransport,
        sleeper: RecordingSleeper = RecordingSleeper(),
        credentials: DiscogsCredentials? = .personalToken("test-token-not-real"),
        policy: RateLimiter.Policy = RateLimiter.Policy(jitter: 0)
    ) -> DiscogsClient {
        DiscogsClient(
            credentials: credentials,
            transport: transport,
            rateLimiter: RateLimiter(policy: policy, random: { 0 }),
            sleeper: sleeper,
            userAgent: "CrateTests/1.0"
        )
    }
}
