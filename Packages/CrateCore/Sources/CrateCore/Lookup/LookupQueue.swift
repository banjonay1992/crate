import Foundation

/// A lookup made with no signal, waiting to be sent to Discogs.
public struct PendingLookup: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var query: LookupQuery
    public var shopName: String?
    public var createdAt: Date
    public var attempts: Int
    public var lastError: String?
    /// Set once `maxAttempts` is reached; the user can retry or delete it.
    public var hasFailed: Bool

    public init(id: UUID = UUID(), query: LookupQuery, shopName: String?, createdAt: Date, attempts: Int = 0, lastError: String? = nil, hasFailed: Bool = false) {
        self.id = id
        self.query = query
        self.shopName = shopName
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
        self.hasFailed = hasFailed
    }
}

/// A queued lookup that has now been answered, kept until the user has seen it.
public struct ResolvedLookup: Codable, Hashable, Sendable, Identifiable {
    public var pending: PendingLookup
    public var result: LookupResult
    public var resolvedAt: Date

    public var id: UUID { pending.id }
}

/// Summary of one pass through the queue.
public struct DrainReport: Hashable, Sendable {
    public var resolved: Int
    public var failed: Int
    public var remaining: Int
    /// Why the pass stopped early, if it did.
    public var stoppedBecause: DiscogsError?

    public init(resolved: Int = 0, failed: Int = 0, remaining: Int = 0, stoppedBecause: DiscogsError? = nil) {
        self.resolved = resolved
        self.failed = failed
        self.remaining = remaining
        self.stoppedBecause = stoppedBecause
    }
}

/// Persistent first-in, first-out queue of lookups made offline.
///
/// When the connection returns, `drain` works through the queue in order. It
/// stops at the first network or rate-limit failure (there is no point
/// hammering a dead connection) and at an authorisation failure (every later
/// request would fail the same way). Other failures count against the item,
/// which is marked failed after `maxAttempts`.
public actor LookupQueue {
    static let pendingKey = "lookup-queue"
    static let resolvedKey = "lookup-queue-resolved"

    public nonisolated let maxAttempts: Int
    private let storage: CodableStorage
    private let now: @Sendable () -> Date
    private var items: [PendingLookup]
    private var resolvedItems: [ResolvedLookup]
    private var isDraining = false

    public init(store: KeyValueStore, maxAttempts: Int = 5, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = CodableStorage(store: store)
        self.maxAttempts = maxAttempts
        self.now = now
        self.items = storage.load([PendingLookup].self, key: Self.pendingKey) ?? []
        self.resolvedItems = storage.load([ResolvedLookup].self, key: Self.resolvedKey) ?? []
    }

    public var pending: [PendingLookup] { items }
    public var resolved: [ResolvedLookup] { resolvedItems }
    /// Items still to try (not failed).
    public var activeCount: Int { items.filter { !$0.hasFailed }.count }

    /// Adds a lookup. Asking for the same thing twice before it resolves keeps one entry.
    @discardableResult
    public func enqueue(_ query: LookupQuery, shopName: String?) throws -> PendingLookup {
        if let existing = items.first(where: { $0.query == query && !$0.hasFailed }) {
            return existing
        }
        let item = PendingLookup(query: query, shopName: shopName, createdAt: now())
        items.append(item)
        try persist()
        return item
    }

    public func remove(id: UUID) throws {
        items.removeAll { $0.id == id }
        try persist()
    }

    /// Puts a failed item back in line.
    public func retry(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].hasFailed = false
        items[index].attempts = 0
        items[index].lastError = nil
        try persist()
    }

    /// The user has seen a resolved lookup.
    public func acknowledge(id: UUID) throws {
        resolvedItems.removeAll { $0.id == id }
        try persist()
    }

    public func acknowledgeAll() throws {
        resolvedItems.removeAll()
        try persist()
    }

    /// Works through the queue with `perform`, normally `LookupService.lookup`.
    public func drain(using perform: @Sendable (LookupQuery) async throws -> LookupResult) async -> DrainReport {
        guard !isDraining else { return DrainReport(remaining: activeCount) }
        isDraining = true
        defer { isDraining = false }

        var report = DrainReport()
        // Snapshot ids so items enqueued during the drain wait for the next pass.
        let ids = items.filter { !$0.hasFailed }.map(\.id)
        for id in ids {
            if Task.isCancelled { break }
            guard let item = items.first(where: { $0.id == id }) else { continue }
            do {
                let result = try await perform(item.query)
                items.removeAll { $0.id == id }
                resolvedItems.append(ResolvedLookup(pending: item, result: result, resolvedAt: now()))
                report.resolved += 1
                try? persist()
            } catch {
                let discogsError = error as? DiscogsError ?? .transport(String(describing: error))
                if discogsError.isTransient || discogsError == .missingCredentials || isUnauthorised(discogsError) {
                    report.stoppedBecause = discogsError
                    if !discogsError.isTransient { recordFailure(id: id, error: discogsError, countsTowardsLimit: false) }
                    break
                }
                if recordFailure(id: id, error: discogsError, countsTowardsLimit: true) { report.failed += 1 }
            }
        }
        report.remaining = activeCount
        try? persist()
        return report
    }

    private func isUnauthorised(_ error: DiscogsError) -> Bool {
        if case .unauthorised = error { return true }
        return false
    }

    /// Returns true if this failure tipped the item into the failed state.
    @discardableResult
    private func recordFailure(id: UUID, error: DiscogsError, countsTowardsLimit: Bool) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].lastError = error.userMessage
        guard countsTowardsLimit else { return false }
        items[index].attempts += 1
        if items[index].attempts >= maxAttempts {
            items[index].hasFailed = true
            return true
        }
        return false
    }

    private func persist() throws {
        try storage.save(items, key: Self.pendingKey, now: now())
        try storage.save(resolvedItems, key: Self.resolvedKey, now: now())
    }
}
