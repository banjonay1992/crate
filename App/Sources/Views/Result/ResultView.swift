import SwiftUI
import CrateCore

/// Runs a lookup and shows the outcome.
struct ResultView: View {
    let query: LookupQuery

    @Environment(AppModel.self) private var model
    @State private var state: LookupState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Looking up \(query.displayText) on Discogs")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            case .found(let result):
                LookupResultView(result: result)
            case .queued(let pending, let local):
                QueuedResultView(pending: pending, local: local)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Lookup failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await run() } }
                }
            }
        }
        .navigationTitle(query.displayText)
        .navigationBarTitleDisplayMode(.inline)
        .task { await run() }
    }

    private func run() async {
        state = .loading
        state = await model.lookup(query)
    }
}

/// Shows a finished lookup: one pressing, a choice of pressings, or nothing.
/// Also used for queued lookups that resolved later.
struct LookupResultView: View {
    let result: LookupResult

    var body: some View {
        if let match = result.bestMatch {
            PressingDetailView(
                route: ReleaseRoute(candidate: match, query: result.query),
                initialOwnership: result.ownership(for: match.id),
                initialPrice: result.prices[match.id],
                fromDeviceCache: result.source == .deviceCache
            )
        } else if result.isEmpty {
            ContentUnavailableView {
                Label("No match on Discogs", systemImage: "questionmark.circle")
            } description: {
                Text(emptyAdvice)
            }
        } else {
            CandidateListView(result: result)
        }
    }

    private var emptyAdvice: String {
        switch result.query {
        case .barcode:
            "Discogs has no release with that barcode. Try the catalogue number from the spine or label."
        case .catalogueNumber:
            "Nothing with that catalogue number. Check for a letter O typed as a zero, or try the run-out."
        case .matrix:
            "No run-out matched. Try fewer characters, just the part before any engineer's initials."
        }
    }
}

/// Several possible pressings. Explains how to tell them apart.
struct CandidateListView: View {
    let result: LookupResult

    var body: some View {
        List {
            Section {
                if result.source == .deviceCache {
                    Label("From your saved data. Discogs will be checked when you are online.", systemImage: "internaldrive")
                        .font(.footnote)
                }
                Text(intro)
                    .font(.callout)
            }
            ForEach(result.choices) { candidate in
                Section {
                    NavigationLink(value: ReleaseRoute(candidate: candidate, query: result.query)) {
                        VStack(alignment: .leading, spacing: 8) {
                            ReleaseRow(summary: candidate.summary)
                            HStack {
                                OwnershipBadge(status: result.ownership(for: candidate.id))
                                Spacer()
                            }
                            EvidenceBadge(evidence: candidate.evidence)
                            if let matrices = result.distinguishingMatrices[candidate.id], !matrices.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Run-out to look for")
                                        .font(.caption.weight(.semibold))
                                    ForEach(matrices, id: \.self) { matrix in
                                        Text(matrix)
                                            .font(.caption.monospaced())
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section { DiscogsAttribution() }
        }
    }

    private var intro: String {
        if result.isAmbiguous {
            return "\(result.choices.count) pressings match equally well. Check the run-out groove and pick the one in your hands."
        }
        return "No exact identifier match. These are the closest Discogs results."
    }
}

/// Shown when there was no connection and the lookup was queued.
struct QueuedResultView: View {
    let pending: PendingLookup
    let local: LookupResult?

    var body: some View {
        VStack(spacing: 0) {
            Label("Saved for later. Crate will look this up as soon as you have a connection, and it will appear under Settings > Offline lookups.", systemImage: "tray.and.arrow.down")
                .font(.footnote)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.2))
            if let local {
                LookupResultView(result: local)
            } else {
                ContentUnavailableView(
                    "Nothing saved on this phone matches",
                    systemImage: "wifi.slash",
                    description: Text("Sync with Wantlist details turned on to make offline matches more likely.")
                )
            }
        }
    }
}
