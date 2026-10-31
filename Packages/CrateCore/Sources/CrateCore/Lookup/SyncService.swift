import Foundation

/// Progress updates during a sync.
public enum SyncProgress: Hashable, Sendable {
    case collection(fetched: Int, total: Int)
    case wantlist(fetched: Int, total: Int)
    case releaseDetails(fetched: Int, total: Int)

    public var description: String {
        switch self {
        case .collection(let fetched, let total): "Collection \(fetched) of \(total)"
        case .wantlist(let fetched, let total): "Wantlist \(fetched) of \(total)"
        case .releaseDetails(let fetched, let total): "Wantlist details \(fetched) of \(total)"
        }
    }
}

public struct SyncReport: Hashable, Sendable {
    public var collectionCount: Int
    public var wantCount: Int
    public var detailsFetched: Int
    /// Details still missing because the pass hit its cap or lost the connection.
    public var detailsOutstanding: Int
    public var finishedAt: Date
}

/// Downloads the collection and wantlist into the cache. Optionally also
/// fetches full release details for wantlist items, which is what makes
/// offline barcode and matrix matching against the wantlist possible
/// (collection and wantlist listings do not include identifiers).
public struct SyncService: Sendable {
    private let api: DiscogsAPI
    private let cache: LibraryCache
    private let now: @Sendable () -> Date

    public init(api: DiscogsAPI, cache: LibraryCache, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.cache = cache
        self.now = now
    }

    /// - Parameters:
    ///   - prefetchWantlistDetails: fetch identifiers for wantlist releases not already cached.
    ///   - maxDetailFetches: cap per sync, so a 2,000-item wantlist fills in over several syncs
    ///     instead of tying up the rate limit for half an hour.
    public func sync(
        username: String,
        prefetchWantlistDetails: Bool,
        maxDetailFetches: Int = 150,
        progress: (@Sendable (SyncProgress) -> Void)? = nil
    ) async throws -> SyncReport {
        let collection = try await api.fullCollection(username: username) { fetched, total in
            progress?(.collection(fetched: fetched, total: total))
        }
        let wants = try await api.fullWantlist(username: username) { fetched, total in
            progress?(.wantlist(fetched: fetched, total: total))
        }
        try await cache.save(snapshot: LibrarySnapshot(username: username, collection: collection, wants: wants, syncedAt: now()))

        var fetched = 0
        var outstanding = 0
        if prefetchWantlistDetails {
            var missing: [ReleaseID] = []
            for want in wants where await !cache.hasRelease(id: want.releaseID) {
                missing.append(want.releaseID)
            }
            let batch = Array(missing.prefix(maxDetailFetches))
            outstanding = missing.count
            var buffer: [Release] = []
            progress?(.releaseDetails(fetched: 0, total: batch.count))
            for id in batch {
                if Task.isCancelled { break }
                do {
                    buffer.append(try await api.release(id: id))
                    fetched += 1
                    outstanding -= 1
                    progress?(.releaseDetails(fetched: fetched, total: batch.count))
                } catch let error as DiscogsError where error.isTransient {
                    // Keep what we have; the rest comes next sync.
                    break
                } catch DiscogsError.notFound {
                    outstanding -= 1
                    continue
                }
                // Save in chunks so an interrupted sync keeps its progress.
                if buffer.count >= 25 {
                    try await cache.store(releases: buffer)
                    buffer.removeAll()
                }
            }
            try await cache.store(releases: buffer)
        }

        return SyncReport(
            collectionCount: collection.count,
            wantCount: wants.count,
            detailsFetched: fetched,
            detailsOutstanding: outstanding,
            finishedAt: now()
        )
    }
}
