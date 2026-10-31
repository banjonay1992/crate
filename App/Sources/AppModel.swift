import Foundation
import Observation
import CrateCore

/// What the Result screen shows for a lookup.
enum LookupState: Equatable {
    case loading
    case found(LookupResult)
    case queued(PendingLookup, local: LookupResult?)
    case failed(String)
}

/// A lookup the user has asked for. Identifiable so it can drive navigation.
struct LookupRequest: Hashable, Identifiable {
    let id = UUID()
    let query: LookupQuery
}

/// A release to show in detail, from a lookup or from the collection / wantlist.
struct ReleaseRoute: Hashable {
    var summary: ReleaseSummary
    var release: Release?
    var evidence: MatchEvidence?
    var matchedIdentifier: String?
    var query: LookupQuery?

    init(candidate: PressingCandidate, query: LookupQuery?) {
        summary = candidate.summary
        release = candidate.release
        evidence = candidate.evidence
        matchedIdentifier = candidate.matchedIdentifier
        self.query = query
    }

    init(summary: ReleaseSummary) {
        self.summary = summary
    }
}

/// App-wide state and the bridge between SwiftUI and CrateCore.
@MainActor
@Observable
final class AppModel {
    // MARK: Dependencies

    // Constants are not tracked by Observation, so they need no annotation.
    let settings: AppSettings
    /// Demo mode (Debug builds only): invented data, no network, no Keychain.
    let isDemo: Bool
    private let cache: LibraryCache
    private let queue: LookupQueue
    private let digLog: DigLogStore
    private let rateLimiter = RateLimiter()
    private let tokenStore = KeychainTokenStore()
    private let connectivity = ConnectivityMonitor()
    @ObservationIgnored private var token: String?
    /// The screen requested with `-CrateScreen`, until a view takes it.
    @ObservationIgnored private var startScreen: StartScreen?

    // MARK: Observed state

    private(set) var isConnected = false
    private(set) var collection: [CollectionItem] = []
    private(set) var wants: [Want] = []
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false
    private(set) var syncStatus: String?
    /// Left over after a sync finishes, for example when details are still outstanding.
    private(set) var syncNote: String?
    private(set) var syncError: String?
    private(set) var cachedReleaseCount = 0

    private(set) var pending: [PendingLookup] = []
    private(set) var resolved: [ResolvedLookup] = []
    private(set) var isDrainingQueue = false

    private(set) var digEntries: [DigLogEntry] = []
    private(set) var visits: [DigVisit] = []
    private(set) var recentShops: [String] = []

    private(set) var isOnline = true
    /// True once saved data has been loaded at launch.
    private(set) var hasStarted = false
    private(set) var storageWarning: String?

    init(demo: Bool = LaunchOptions.isDemo) {
        isDemo = demo
        startScreen = demo ? LaunchOptions.startScreen : nil
        settings = demo ? Self.demoSettings() : AppSettings()
        var warning: String?
        func store(_ name: String, excludeFromBackup: Bool) -> KeyValueStore {
            // Demo data lives in memory only, so it never mixes with real data.
            if demo { return InMemoryStore() }
            do {
                return try FileStore.applicationSupport(named: name, excludeFromBackup: excludeFromBackup)
            } catch {
                warning = "Crate could not open its storage, so nothing will be saved this session."
                return InMemoryStore()
            }
        }
        // Discogs data can be re-downloaded, so it stays out of iCloud backups.
        // The dig log is the user's own record and is backed up.
        cache = LibraryCache(store: store("DiscogsCache", excludeFromBackup: true))
        queue = LookupQueue(store: store("LookupQueue", excludeFromBackup: false))
        digLog = DigLogStore(store: store("DigLog", excludeFromBackup: false))
        storageWarning = warning
        if demo {
            // Signed in as the invented demo user; the Keychain is never read.
            isConnected = true
        } else {
            token = Self.initialToken(from: tokenStore)
            isConnected = token != nil
        }
    }

    /// Settings for demo mode, in their own UserDefaults suite that is reset
    /// on every launch, so the real settings are left alone.
    private static func demoSettings() -> AppSettings {
        let suite = "uk.co.nayproductions.crate.demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #if DEBUG
        settings.currency = DemoLibrary.currency
        settings.currentShop = DemoLibrary.currentShop
        settings.username = DemoLibrary.username
        #endif
        return settings
    }

    /// Returns the launch screen once; later calls get nil.
    func takeStartScreen(_ screens: Set<StartScreen>) -> StartScreen? {
        guard let startScreen, screens.contains(startScreen) else { return nil }
        self.startScreen = nil
        return startScreen
    }

    /// The tab demo mode should open on, without consuming the request.
    var initialStartScreen: StartScreen? { startScreen }

    /// Keychain first. In Debug builds only, fall back to DISCOGS_TOKEN from
    /// the git-ignored Config/Secrets.xcconfig for convenience.
    private static func initialToken(from store: KeychainTokenStore) -> String? {
        if let saved = store.read(), !saved.isEmpty { return saved }
        #if DEBUG
        if let dev = Bundle.main.object(forInfoDictionaryKey: "CrateDevelopmentToken") as? String,
           !dev.isEmpty, !dev.hasPrefix("$(") {
            return dev
        }
        #endif
        return nil
    }

    // MARK: Lifecycle

    func start() async {
        guard !hasStarted else { return }
        if isDemo {
            await startDemo()
            hasStarted = true
            return
        }
        await reloadLibrary()
        await reloadQueue()
        await reloadDigLog()
        hasStarted = true
        connectivity.start { [weak self] online in
            guard let self else { return }
            let cameBack = online && !self.isOnline
            self.isOnline = online
            if cameBack { Task { await self.drainQueue() } }
        }
        if isConnected {
            await drainQueue()
            if lastSynced == nil { await sync() }
        }
    }

    /// Seeds the in-memory stores with invented data and runs one queued
    /// lookup through the demo API so Offline lookups has an answer to show.
    /// The connectivity monitor is not started, so the app always looks online.
    private func startDemo() async {
        #if DEBUG
        try? await DemoLibrary.seed(cache: cache, digLog: digLog)
        _ = try? await queue.enqueue(.matrix("SW 1986-A"), shopName: DemoLibrary.currentShop)
        let service = lookupService
        let options = lookupOptions
        _ = await queue.drain { query in try await service.lookup(query, options: options) }
        #endif
        await reloadLibrary()
        await reloadQueue()
        await reloadDigLog()
    }

    // MARK: Discogs services

    private var credentials: DiscogsCredentials? {
        token.map { DiscogsCredentials.personalToken($0) }
    }

    private func makeClient(token override: String? = nil) -> any DiscogsAPI {
        #if DEBUG
        if isDemo { return DemoDiscogsAPI() }
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? CrateCoreInfo.version
        return DiscogsClient(
            credentials: override.map { DiscogsCredentials.personalToken($0) } ?? credentials,
            rateLimiter: rateLimiter,
            userAgent: "Crate/\(version) (iOS; open source)"
        )
    }

    private var lookupService: LookupService {
        LookupService(api: makeClient(), cache: cache, queue: queue)
    }

    var lookupOptions: LookupOptions {
        LookupOptions(currency: settings.currency, includePriceSuggestions: settings.includePriceSuggestions)
    }

    // MARK: Account

    /// Checks the token with Discogs, stores it in the Keychain and syncs.
    func connect(token newToken: String) async throws {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DiscogsError.missingCredentials }
        let identity = try await makeClient(token: trimmed).identity()
        if !isDemo { try tokenStore.save(trimmed) }
        token = trimmed
        settings.username = identity.username
        isConnected = true
        await sync()
    }

    /// Forgets the token and all cached Discogs data. The dig log is kept.
    func disconnect() async {
        if !isDemo { tokenStore.delete() }
        token = nil
        isConnected = false
        settings.username = nil
        try? await cache.clear()
        await reloadLibrary()
    }

    // MARK: Sync

    func sync() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncNote = nil
        syncStatus = "Starting sync"
        defer {
            isSyncing = false
            syncStatus = nil
        }
        do {
            let username = try await resolveUsername()
            let service = SyncService(api: makeClient(), cache: cache)
            let report = try await service.sync(
                username: username,
                prefetchWantlistDetails: settings.prefetchWantlistDetails
            ) { progress in
                Task { @MainActor [weak self] in self?.syncStatus = progress.description }
            }
            if report.detailsOutstanding > 0 {
                syncNote = "\(report.detailsOutstanding) wantlist items still need details. They will be fetched on the next sync."
            }
        } catch let error as DiscogsError {
            syncError = error.userMessage
        } catch {
            syncError = error.localizedDescription
        }
        await reloadLibrary()
    }

    private func resolveUsername() async throws -> String {
        if let username = settings.username, !username.isEmpty { return username }
        let username = try await makeClient().identity().username
        settings.username = username
        return username
    }

    private func reloadLibrary() async {
        let snapshot = await cache.snapshot
        collection = snapshot?.collection ?? []
        wants = snapshot?.wants ?? []
        lastSynced = snapshot?.syncedAt
        cachedReleaseCount = await cache.cachedReleaseCount
    }

    func clearCache() async {
        try? await cache.clear()
        await reloadLibrary()
    }

    // MARK: Lookup

    func lookup(_ query: LookupQuery) async -> LookupState {
        guard isConnected else {
            // Without a token Discogs cannot be asked, but the cache may still help.
            let local = await LookupService(api: makeClient(), cache: cache).localLookup(query)
            if local.isEmpty { return .failed(DiscogsError.missingCredentials.userMessage) }
            return .found(local)
        }
        do {
            let outcome = try await lookupService.lookupOrQueue(query, shopName: currentShopOrNil, options: lookupOptions)
            await reloadQueue()
            switch outcome {
            case .found(let result): return .found(result)
            case .queued(let pending, let local): return .queued(pending, local: local)
            }
        } catch let error as DiscogsError {
            return .failed(error.userMessage)
        } catch is CancellationError {
            return .failed("Cancelled.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func priceInfo(for releaseID: ReleaseID, forceRefresh: Bool = false) async throws -> PriceInfo {
        try await lookupService.priceInfo(for: releaseID, options: lookupOptions, forceRefresh: forceRefresh)
    }

    /// Cached price, without touching the network.
    func cachedPrice(for releaseID: ReleaseID) async -> PriceInfo? {
        await cache.price(for: releaseID)
    }

    func release(id: ReleaseID) async throws -> Release {
        if !isOnline, let cached = await cache.release(id: id)?.release { return cached }
        return try await lookupService.release(id: id)
    }

    func ownership(for summary: ReleaseSummary) async -> OwnershipStatus {
        await cache.ownershipIndex().status(for: summary)
    }

    private var currentShopOrNil: String? {
        let shop = settings.currentShop.trimmingCharacters(in: .whitespaces)
        return shop.isEmpty ? nil : shop
    }

    // MARK: Queue

    func drainQueue() async {
        guard isConnected, isOnline, !isDrainingQueue else { return }
        isDrainingQueue = true
        defer { isDrainingQueue = false }
        let service = lookupService
        let options = lookupOptions
        _ = await queue.drain { query in
            try await service.lookup(query, options: options)
        }
        await reloadQueue()
    }

    func removePending(_ id: UUID) async {
        try? await queue.remove(id: id)
        await reloadQueue()
    }

    func retryPending(_ id: UUID) async {
        try? await queue.retry(id: id)
        await reloadQueue()
        await drainQueue()
    }

    func acknowledge(_ id: UUID) async {
        try? await queue.acknowledge(id: id)
        await reloadQueue()
    }

    func acknowledgeAll() async {
        try? await queue.acknowledgeAll()
        await reloadQueue()
    }

    private func reloadQueue() async {
        pending = await queue.pending
        resolved = await queue.resolved
    }

    // MARK: Dig log

    func addDigEntry(_ entry: DigLogEntry) async {
        try? await digLog.add(entry)
        let shop = entry.shop.trimmingCharacters(in: .whitespaces)
        if !shop.isEmpty { settings.currentShop = shop }
        await reloadDigLog()
    }

    func updateDigEntry(_ entry: DigLogEntry) async {
        try? await digLog.update(entry)
        await reloadDigLog()
    }

    func deleteDigEntry(_ id: UUID) async {
        try? await digLog.delete(id: id)
        await reloadDigLog()
    }

    func deleteAllDigEntries() async {
        try? await digLog.deleteAll()
        await reloadDigLog()
    }

    /// Writes the dig log to a temporary CSV file for the share sheet.
    func exportDigLog() async -> URL? {
        let csv = await digLog.csv()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Crate dig log.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func reloadDigLog() async {
        digEntries = await digLog.entries
        visits = await digLog.visits()
        recentShops = await digLog.recentShops()
    }
}
