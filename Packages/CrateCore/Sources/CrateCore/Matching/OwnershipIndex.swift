import Foundation

/// How a release relates to the user's collection and wantlist.
public struct OwnershipStatus: Codable, Hashable, Sendable {
    /// Copies of this exact release in the collection.
    public var ownedCopies: Int
    /// This exact release is on the wantlist.
    public var isWanted: Bool
    /// Other releases of the same album (same master) in the collection.
    public var otherPressingsOwned: [ReleaseSummary]
    /// Other releases of the same album on the wantlist.
    public var otherPressingsWanted: [ReleaseSummary]

    public init(
        ownedCopies: Int = 0,
        isWanted: Bool = false,
        otherPressingsOwned: [ReleaseSummary] = [],
        otherPressingsWanted: [ReleaseSummary] = []
    ) {
        self.ownedCopies = ownedCopies
        self.isWanted = isWanted
        self.otherPressingsOwned = otherPressingsOwned
        self.otherPressingsWanted = otherPressingsWanted
    }

    public static let unknown = OwnershipStatus()

    public var isOwned: Bool { ownedCopies > 0 }

    /// The single most useful thing to tell someone stood at a record bin.
    public var headline: Headline {
        if isWanted { return .wanted }
        if isOwned { return .owned }
        if !otherPressingsWanted.isEmpty { return .wantedOtherPressing }
        if !otherPressingsOwned.isEmpty { return .ownedOtherPressing }
        return .neither
    }

    public enum Headline: String, Codable, Sendable {
        case wanted
        case owned
        case wantedOtherPressing
        case ownedOtherPressing
        case neither

        public var text: String {
            switch self {
            case .wanted: "On your wantlist"
            case .owned: "Already in your collection"
            case .wantedOtherPressing: "You want a different pressing"
            case .ownedOtherPressing: "You own a different pressing"
            case .neither: "Not in your collection or wantlist"
            }
        }
    }
}

/// Fast in-memory lookup over the cached collection and wantlist.
public struct OwnershipIndex: Sendable {
    private var ownedCounts: [ReleaseID: Int] = [:]
    private var wanted: Set<ReleaseID> = []
    private var ownedByMaster: [MasterID: [ReleaseSummary]] = [:]
    private var wantedByMaster: [MasterID: [ReleaseSummary]] = [:]
    private var summariesByCatalogueKey: [String: [ReleaseSummary]] = [:]

    public init(collection: [CollectionItem] = [], wants: [Want] = []) {
        var seenOwned = Set<ReleaseID>()
        for item in collection {
            ownedCounts[item.releaseID, default: 0] += 1
            guard seenOwned.insert(item.releaseID).inserted else { continue }
            if let master = item.release.masterID {
                ownedByMaster[master, default: []].append(item.release)
            }
            index(item.release)
        }
        for want in wants {
            guard wanted.insert(want.releaseID).inserted else { continue }
            if let master = want.release.masterID {
                wantedByMaster[master, default: []].append(want.release)
            }
            if !seenOwned.contains(want.releaseID) { index(want.release) }
        }
    }

    private mutating func index(_ summary: ReleaseSummary) {
        for number in summary.catalogueNumbers {
            let key = IdentifierNormaliser.looseCatalogueKey(number)
            guard !key.isEmpty else { continue }
            summariesByCatalogueKey[key, default: []].append(summary)
        }
    }

    public var isEmpty: Bool { ownedCounts.isEmpty && wanted.isEmpty }

    public func status(releaseID: ReleaseID, masterID: MasterID?) -> OwnershipStatus {
        var status = OwnershipStatus(ownedCopies: ownedCounts[releaseID] ?? 0, isWanted: wanted.contains(releaseID))
        if let masterID {
            status.otherPressingsOwned = (ownedByMaster[masterID] ?? []).filter { $0.id != releaseID }
            status.otherPressingsWanted = (wantedByMaster[masterID] ?? []).filter { $0.id != releaseID }
        }
        return status
    }

    public func status(for summary: ReleaseSummary) -> OwnershipStatus {
        status(releaseID: summary.id, masterID: summary.masterID)
    }

    /// Collection and wantlist releases whose catalogue number matches, ignoring
    /// spacing, punctuation and leading zeros. Works with no network at all.
    public func releases(matchingCatalogueNumber text: String) -> [ReleaseSummary] {
        summariesByCatalogueKey[IdentifierNormaliser.looseCatalogueKey(text)] ?? []
    }
}
