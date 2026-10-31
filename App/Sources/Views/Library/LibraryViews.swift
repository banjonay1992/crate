import SwiftUI
import CrateCore

/// Filters releases by artist, title, label or catalogue number.
private func matches(_ summary: ReleaseSummary, _ search: String) -> Bool {
    let needle = search.trimmingCharacters(in: .whitespaces)
    guard !needle.isEmpty else { return true }
    if summary.title.localizedCaseInsensitiveContains(needle) || summary.artist.localizedCaseInsensitiveContains(needle) {
        return true
    }
    let key = IdentifierNormaliser.catalogueKey(needle)
    return summary.labels.contains { label in
        label.name.localizedCaseInsensitiveContains(needle)
            || (!key.isEmpty && IdentifierNormaliser.catalogueKey(label.catalogueNumber).contains(key))
    }
}

struct WantlistView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    private var filtered: [Want] {
        model.wants.filter { matches($0.release, search) }
    }

    var body: some View {
        NavigationStack {
            LibraryList(
                isEmpty: model.wants.isEmpty,
                emptyTitle: "No wantlist yet",
                emptyText: model.isConnected
                    ? "Pull down to sync, or add records to your wantlist on Discogs."
                    : "Connect your Discogs account in Settings to see your wantlist here, even offline."
            ) {
                ForEach(filtered) { want in
                    NavigationLink(value: ReleaseRoute(summary: want.release)) {
                        VStack(alignment: .leading, spacing: 4) {
                            ReleaseRow(summary: want.release)
                            if let notes = want.notes {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Artist, title or cat. no.")
            .navigationTitle("Wantlist")
            .navigationDestination(for: ReleaseRoute.self) { route in
                PressingDetailView(route: route)
            }
            .toolbar { SyncStatusToolbar(isSyncing: model.isSyncing, status: model.syncStatus) }
        }
    }
}

struct CollectionView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    private struct CopyGroup: Identifiable {
        var summary: ReleaseSummary
        var copies: Int
        var id: ReleaseID { summary.id }
    }

    /// One row per release, with a copy count, rather than one per copy.
    private var grouped: [CopyGroup] {
        var order: [ReleaseID] = []
        var groups: [ReleaseID: CopyGroup] = [:]
        for item in model.collection where matches(item.release, search) {
            if groups[item.releaseID] == nil {
                order.append(item.releaseID)
                groups[item.releaseID] = CopyGroup(summary: item.release, copies: 0)
            }
            groups[item.releaseID]?.copies += 1
        }
        return order.compactMap { groups[$0] }
    }

    var body: some View {
        NavigationStack {
            LibraryList(
                isEmpty: model.collection.isEmpty,
                emptyTitle: "No collection yet",
                emptyText: model.isConnected
                    ? "Pull down to sync your Discogs collection."
                    : "Connect your Discogs account in Settings to see your collection here, even offline."
            ) {
                ForEach(grouped) { entry in
                    NavigationLink(value: ReleaseRoute(summary: entry.summary)) {
                        ReleaseRow(summary: entry.summary, trailing: entry.copies > 1 ? "\(entry.copies) copies" : nil)
                    }
                }
            }
            .searchable(text: $search, prompt: "Artist, title or cat. no.")
            .navigationTitle("Collection")
            .navigationDestination(for: ReleaseRoute.self) { route in
                PressingDetailView(route: route)
            }
            .toolbar { SyncStatusToolbar(isSyncing: model.isSyncing, status: model.syncStatus) }
        }
    }
}

/// Shared list chrome: empty state, pull to refresh, last-synced footer.
private struct LibraryList<Rows: View>: View {
    @Environment(AppModel.self) private var model
    let isEmpty: Bool
    let emptyTitle: String
    let emptyText: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        List {
            if let error = model.syncError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            rows()
            if let synced = model.lastSynced {
                Text("Last synced \(synced.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .overlay {
            if isEmpty && !model.isSyncing {
                ContentUnavailableView(emptyTitle, systemImage: "opticaldisc", description: Text(emptyText))
            }
        }
        .refreshable { await model.sync() }
    }
}

private struct SyncStatusToolbar: ToolbarContent {
    let isSyncing: Bool
    let status: String?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isSyncing {
                ProgressView()
                    .accessibilityLabel(status ?? "Syncing")
            }
        }
    }
}
