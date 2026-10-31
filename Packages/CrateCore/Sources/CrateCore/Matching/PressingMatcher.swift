import Foundation

/// Why a release was put forward as the record in the user's hands.
/// Ordered from strongest to weakest.
public enum MatchEvidence: String, Codable, Hashable, Sendable, Comparable {
    /// The barcode matches one printed on the release.
    case barcode
    /// The full matrix / run-out string matches.
    case matrixExact
    /// The catalogue number matches exactly (ignoring spacing and punctuation).
    case catalogueNumber
    /// Part of a matrix string matches, or most of its tokens do.
    case matrixPartial
    /// The catalogue number matches once leading zeros are ignored.
    case catalogueNumberLoose
    /// Discogs returned it for the search but no identifier lines up.
    case searchResult

    public var score: Int {
        switch self {
        case .barcode: 100
        case .matrixExact: 95
        case .catalogueNumber: 70
        case .matrixPartial: 60
        case .catalogueNumberLoose: 40
        case .searchResult: 10
        }
    }

    public var explanation: String {
        switch self {
        case .barcode: "Barcode matches"
        case .matrixExact: "Matrix / run-out matches"
        case .catalogueNumber: "Catalogue number matches"
        case .matrixPartial: "Matrix / run-out partly matches"
        case .catalogueNumberLoose: "Catalogue number is similar"
        case .searchResult: "Found by Discogs search"
        }
    }

    public static func < (lhs: MatchEvidence, rhs: MatchEvidence) -> Bool {
        lhs.score < rhs.score
    }
}

/// A release that might be the pressing being looked at.
public struct PressingCandidate: Codable, Hashable, Sendable, Identifiable {
    public var summary: ReleaseSummary
    /// Full details, when they have been fetched or were cached.
    public var release: Release?
    public var evidence: MatchEvidence
    /// The identifier on the release that produced the match, as Discogs prints it.
    public var matchedIdentifier: String?

    public var id: ReleaseID { summary.id }

    public init(summary: ReleaseSummary, release: Release? = nil, evidence: MatchEvidence, matchedIdentifier: String? = nil) {
        self.summary = summary
        self.release = release
        self.evidence = evidence
        self.matchedIdentifier = matchedIdentifier
    }
}

/// The outcome of matching a query against a set of candidates.
public enum MatchResolution: Hashable, Sendable {
    /// One release clearly fits better than the rest.
    case unique(PressingCandidate)
    /// Several releases fit equally well, typically an original and a reissue
    /// sharing a catalogue number. The user picks, helped by the run-out.
    case ambiguous([PressingCandidate])
    case none

    public var candidates: [PressingCandidate] {
        switch self {
        case .unique(let candidate): [candidate]
        case .ambiguous(let candidates): candidates
        case .none: []
        }
    }
}

/// Decides which release, out of a handful, is the pressing being looked at.
public enum PressingMatcher {
    /// Minimum key length for substring matching of matrix strings; shorter
    /// fragments like "A1" match far too much.
    static let minimumPartialMatrixLength = 5

    /// Compares one release against the query.
    public static func evaluate(_ query: LookupQuery, summary: ReleaseSummary, release: Release?) -> (MatchEvidence, String?) {
        switch query {
        case .barcode(let barcode):
            let target = barcode.canonical
            let printed = release?.barcodes ?? summary.barcodes
            if let hit = printed.first(where: { Barcode.canonicalKey(for: $0) == target }) {
                return (.barcode, hit)
            }
            return (.searchResult, nil)

        case .catalogueNumber(let text):
            let numbers = release?.catalogueNumbers ?? summary.catalogueNumbers
            let strict = IdentifierNormaliser.catalogueKey(text)
            if let hit = numbers.first(where: { IdentifierNormaliser.catalogueKey($0) == strict }) {
                return (.catalogueNumber, hit)
            }
            let loose = IdentifierNormaliser.looseCatalogueKey(text)
            if let hit = numbers.first(where: { IdentifierNormaliser.looseCatalogueKey($0) == loose }) {
                return (.catalogueNumberLoose, hit)
            }
            return (.searchResult, nil)

        case .matrix(let text):
            // Search results put matrix strings in their "barcode" list, so use
            // those when full details have not been fetched.
            let strings = release.map { $0.matrices.map(\.value) } ?? summary.barcodes.filter { Barcode($0) == nil }
            return matchMatrix(text, against: strings)
        }
    }

    static func matchMatrix(_ query: String, against strings: [String]) -> (MatchEvidence, String?) {
        let queryKey = IdentifierNormaliser.matrixKey(query)
        guard !queryKey.isEmpty else { return (.searchResult, nil) }
        var best: (MatchEvidence, String?) = (.searchResult, nil)
        for value in strings {
            let key = IdentifierNormaliser.matrixKey(value)
            guard !key.isEmpty else { continue }
            if key == queryKey { return (.matrixExact, value) }
            if best.0 < .matrixPartial, matrixPartiallyMatches(query: query, queryKey: queryKey, value: value, valueKey: key) {
                best = (.matrixPartial, value)
            }
        }
        return best
    }

    /// Run-out etchings are transcribed inconsistently: one contributor writes
    /// "GCR 012 A-1 PORKY", the user types "GCR012 A1". Containment of the
    /// reduced key, or sharing most tokens, counts as a partial match.
    static func matrixPartiallyMatches(query: String, queryKey: String, value: String, valueKey: String) -> Bool {
        let shorter = min(queryKey.count, valueKey.count)
        if shorter >= minimumPartialMatrixLength, valueKey.contains(queryKey) || queryKey.contains(valueKey) {
            return true
        }
        let queryTokens = Set(IdentifierNormaliser.matrixTokens(query))
        let valueTokens = Set(IdentifierNormaliser.matrixTokens(value))
        guard queryTokens.count >= 2, !valueTokens.isEmpty else { return false }
        let shared = queryTokens.intersection(valueTokens)
        // Shared tokens must carry real content, not just "A" and "1".
        let sharedLength = shared.reduce(0) { $0 + $1.count }
        let overlap = Double(shared.count) / Double(queryTokens.count)
        return overlap >= 0.75 && sharedLength >= minimumPartialMatrixLength
    }

    /// Scores every candidate and sorts them strongest first. Ties keep the
    /// order Discogs returned, which is already relevance-ranked.
    public static func rank(_ query: LookupQuery, candidates: [(summary: ReleaseSummary, release: Release?)]) -> [PressingCandidate] {
        var seen = Set<ReleaseID>()
        let scored = candidates.enumerated().compactMap { index, pair -> (Int, PressingCandidate)? in
            guard seen.insert(pair.summary.id).inserted else { return nil }
            let (evidence, identifier) = evaluate(query, summary: pair.summary, release: pair.release)
            return (index, PressingCandidate(summary: pair.release?.summary ?? pair.summary, release: pair.release, evidence: evidence, matchedIdentifier: identifier))
        }
        return scored
            .sorted { lhs, rhs in
                lhs.1.evidence != rhs.1.evidence ? lhs.1.evidence > rhs.1.evidence : lhs.0 < rhs.0
            }
            .map(\.1)
    }

    /// Turns a ranked list into a decision.
    public static func resolve(_ ranked: [PressingCandidate]) -> MatchResolution {
        guard let top = ranked.first else { return .none }
        let tied = ranked.filter { $0.evidence == top.evidence }
        if tied.count == 1 { return .unique(top) }
        return .ambiguous(tied)
    }

    /// Convenience: rank then resolve.
    public static func match(_ query: LookupQuery, candidates: [(summary: ReleaseSummary, release: Release?)]) -> MatchResolution {
        resolve(rank(query, candidates: candidates))
    }

    /// For each release, the matrix strings that none of the others share.
    /// When an original and a reissue share a catalogue number, these are what
    /// the user should look for in the run-out groove to tell them apart.
    public static func distinguishingMatrices(among releases: [Release]) -> [ReleaseID: [String]] {
        var result: [ReleaseID: [String]] = [:]
        for release in releases {
            let otherKeys = Set(
                releases
                    .filter { $0.id != release.id }
                    .flatMap { $0.matrices.map { IdentifierNormaliser.matrixKey($0.value) } }
            )
            result[release.id] = release.matrices
                .map(\.value)
                .filter { !otherKeys.contains(IdentifierNormaliser.matrixKey($0)) }
        }
        return result
    }
}
