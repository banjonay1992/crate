import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one thing the Discogs client needs from the network. Tests inject a
/// mock; the app uses `URLSessionTransport`.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `HTTPTransport` backed by `URLSession`.
///
/// Uses a data task wrapped in a continuation rather than the async
/// `data(for:)` API so the same code runs on Linux, where the async API has
/// historically been patchy.
public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    // URLSession is thread-safe; @unchecked because older SDKs do not mark it Sendable.
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// A session suited to shop use: short timeouts so an unreachable network
    /// fails quickly and the lookup is queued, and no cookies.
    public static func makeDefault() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if canImport(Darwin)
        // Fail fast in a shop with no signal so the lookup is queued straight away.
        configuration.waitsForConnectivity = false
        #endif
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), http))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Holds the running task so cancellation can reach it.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func set(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

/// Abstracts waiting so retry and rate-limit logic can be tested without real delays.
public protocol Sleeper: Sendable {
    func sleep(seconds: Double) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
