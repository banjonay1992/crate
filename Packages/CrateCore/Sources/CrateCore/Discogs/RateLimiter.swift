import Foundation

/// Keeps Crate inside the Discogs rate limit.
///
/// Discogs allows 60 authenticated requests per minute over a moving window
/// and reports the state in `X-Discogs-Ratelimit` and
/// `X-Discogs-Ratelimit-Remaining` headers. The limiter does three things:
///
/// 1. Reserves a slot for every request in a local sliding window, keeping a
///    small reserve free, so a long sync never hits the limit on its own.
/// 2. Reads the headers on every response and pauses briefly when Discogs says
///    the allowance is nearly used (another device may be using the same token).
/// 3. Works out exponential backoff with jitter after a 429, honouring
///    `Retry-After` when it is present.
///
/// Slots are reserved before any waiting happens, so concurrent callers queue
/// in order instead of all waking at once.
public actor RateLimiter {
    public struct Policy: Sendable {
        public var window: TimeInterval
        public var defaultLimit: Int
        /// Requests kept spare inside each window.
        public var reserve: Int
        public var maxRetries: Int
        public var baseBackoff: TimeInterval
        public var maxBackoff: TimeInterval
        /// Proportion of random extra delay added to backoff, 0...1.
        public var jitter: Double

        public init(
            window: TimeInterval = 60,
            defaultLimit: Int = 60,
            reserve: Int = 2,
            maxRetries: Int = 4,
            baseBackoff: TimeInterval = 2,
            maxBackoff: TimeInterval = 60,
            jitter: Double = 0.25
        ) {
            self.window = window
            self.defaultLimit = defaultLimit
            self.reserve = reserve
            self.maxRetries = maxRetries
            self.baseBackoff = baseBackoff
            self.maxBackoff = maxBackoff
            self.jitter = jitter
        }
    }

    public nonisolated let policy: Policy
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double

    private var limit: Int
    private var slots: [Date] = []
    private var pausedUntil: Date?

    public init(
        policy: Policy = Policy(),
        now: @escaping @Sendable () -> Date = { Date() },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.policy = policy
        self.now = now
        self.random = random
        self.limit = policy.defaultLimit
    }

    /// Reserves a request slot and returns how long the caller must wait before sending.
    public func reserveSlot() -> TimeInterval {
        let current = now()
        slots.removeAll { $0 <= current.addingTimeInterval(-policy.window) }

        var start = current
        if let pausedUntil, pausedUntil > start { start = pausedUntil }

        let capacity = max(1, limit - policy.reserve)
        if slots.count >= capacity {
            // The slot that must leave the window before this request can go.
            let blocking = slots[slots.count - capacity]
            start = max(start, blocking.addingTimeInterval(policy.window))
        }
        slots.append(start)
        slots.sort()
        return max(0, start.timeIntervalSince(current))
    }

    /// Feeds response headers back in. Header names are matched case-insensitively.
    public func record(headers: [String: String]) {
        let lowered = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        if let value = lowered["x-discogs-ratelimit"].flatMap({ Int($0) }), value > 0 {
            limit = value
        }
        if let remaining = lowered["x-discogs-ratelimit-remaining"].flatMap({ Int($0) }), remaining <= policy.reserve {
            // Space the next few requests out by roughly one window share each.
            let perRequest = policy.window / Double(max(limit, 1))
            let pause = perRequest * Double(policy.reserve - remaining + 1)
            extendPause(until: now().addingTimeInterval(pause))
        }
    }

    /// Delay before retry number `attempt` (0-based) after a 429 or a 5xx.
    /// Also pauses every other caller for the same period.
    public func backoff(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let delay: TimeInterval
        if let retryAfter, retryAfter > 0 {
            delay = min(retryAfter, policy.maxBackoff)
        } else {
            let exponential = policy.baseBackoff * pow(2, Double(max(0, attempt)))
            let jittered = exponential * (1 + policy.jitter * random())
            delay = min(jittered, policy.maxBackoff)
        }
        extendPause(until: now().addingTimeInterval(delay))
        return delay
    }

    /// Current known limit, for diagnostics and tests.
    public var currentLimit: Int { limit }

    private func extendPause(until date: Date) {
        if let pausedUntil, pausedUntil >= date { return }
        pausedUntil = date
    }
}
