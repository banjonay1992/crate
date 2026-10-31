import SwiftUI
import CrateCore

/// One pressing: what it is, whether you have or want it, and what it sells for.
struct PressingDetailView: View {
    let route: ReleaseRoute
    var initialOwnership: OwnershipStatus?
    var initialPrice: PriceInfo?
    var fromDeviceCache = false

    @Environment(AppModel.self) private var model
    @State private var release: Release?
    @State private var ownership: OwnershipStatus?
    @State private var price: PriceInfo?
    @State private var priceError: String?
    @State private var isLoadingPrice = false
    @State private var logDraft: DigLogEntry?

    private var summary: ReleaseSummary { release?.summary ?? route.summary }

    var body: some View {
        List {
            Section {
                header
                if let ownership {
                    OwnershipBadge(status: ownership)
                }
                if let evidence = route.evidence {
                    EvidenceBadge(evidence: evidence)
                }
                if fromDeviceCache {
                    Label("Matched from data saved on this phone.", systemImage: "internaldrive")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let ownership, !ownership.otherPressingsWanted.isEmpty || !ownership.otherPressingsOwned.isEmpty {
                Section("Other pressings of this album") {
                    ForEach(ownership.otherPressingsWanted) { other in
                        ReleaseRow(summary: other, trailing: "Wanted")
                    }
                    ForEach(ownership.otherPressingsOwned) { other in
                        ReleaseRow(summary: other, trailing: "Owned")
                    }
                }
            }

            priceSection

            Section {
                Button {
                    logDraft = draft(outcome: .bought)
                } label: {
                    Label("Log as bought", systemImage: "bag")
                }
                Button {
                    logDraft = draft(outcome: .passed)
                } label: {
                    Label("Log as left in the rack", systemImage: "arrow.uturn.left")
                }
                if let url = release?.webURL ?? URL(string: "https://www.discogs.com/release/\(summary.id)") {
                    Link(destination: url) {
                        Label("Open on Discogs", systemImage: "safari")
                    }
                }
            }

            identifiersSection

            if let tracks = release?.tracklist, !tracks.isEmpty {
                Section("Tracklist") {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                        HStack {
                            Text(track.position).monospacedDigit().foregroundStyle(.secondary)
                            Text(track.title)
                            Spacer()
                            if let duration = track.duration {
                                Text(duration).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section { DiscogsAttribution() }
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logDraft) { entry in
            DigLogEntryEditor(entry: entry, isNew: true)
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            SleeveThumbnail(url: summary.thumbURL, size: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title).font(.title3.weight(.semibold))
                Text(summary.artist).foregroundStyle(.secondary)
                Text(summary.pressingLine).font(.footnote)
                if let format = summary.formats.first {
                    Text(format.displayText).font(.footnote).foregroundStyle(.secondary)
                }
                if let community = release?.community {
                    Text("\(community.have) have, \(community.want) want on Discogs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var priceSection: some View {
        Section {
            if let price, !price.isEmpty {
                if let lowest = price.stats?.lowestPrice {
                    LabeledContent("Lowest for sale now", value: lowest.formatted())
                }
                if let count = price.stats?.numForSale {
                    LabeledContent("Copies for sale", value: "\(count)")
                }
                ForEach(price.suggestions, id: \.condition) { point in
                    LabeledContent("Suggested, \(point.condition.shortLabel)", value: point.price.formatted())
                        .accessibilityLabel("Suggested price in \(point.condition.rawValue) condition: \(point.price.formatted())")
                }
            } else if isLoadingPrice {
                ProgressView()
            } else if let priceError {
                Text(priceError).foregroundStyle(.secondary)
            } else if price != nil {
                Text("Nobody is selling this pressing on Discogs right now.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No price data saved.").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Price")
                Spacer()
                if model.isOnline && model.isConnected {
                    Button("Refresh") { Task { await loadPrice(force: true) } }
                        .font(.caption)
                        .disabled(isLoadingPrice)
                }
            }
        } footer: {
            if let price {
                Text("Discogs marketplace, \(price.fetchedAt.formatted(.relative(presentation: .named))). Suggestions use your Discogs seller settings and appear only if those are filled in.")
            }
        }
    }

    @ViewBuilder
    private var identifiersSection: some View {
        let barcodes = release?.barcodes ?? summary.barcodes.filter { Barcode($0) != nil }
        let matrices = release?.matrices ?? []
        if !barcodes.isEmpty || !matrices.isEmpty || !summary.catalogueNumbers.isEmpty {
            Section("Identifiers") {
                ForEach(summary.labels, id: \.self) { label in
                    LabeledContent(label.name, value: label.catalogueNumber)
                }
                ForEach(barcodes, id: \.self) { barcode in
                    identifierRow(title: "Barcode", value: barcode, detail: nil)
                }
                ForEach(matrices, id: \.self) { matrix in
                    identifierRow(title: "Run-out", value: matrix.value, detail: matrix.detail)
                }
            }
        }
    }

    private func identifierRow(title: String, value: String, detail: String?) -> some View {
        let isMatch = value == route.matchedIdentifier
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if isMatch {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMatch ? "Matches what you looked up" : "")
    }

    private func draft(outcome: DigLogEntry.Outcome) -> DigLogEntry {
        DigLogEntry(
            date: Date(),
            shop: model.settings.currentShop,
            outcome: outcome,
            release: summary,
            query: route.query,
            marketPriceAtTime: price?.stats?.lowestPrice,
            wasOnWantlist: ownership?.isWanted ?? false
        )
    }

    private func load() async {
        if release == nil { release = route.release }
        if ownership == nil { ownership = initialOwnership }
        if price == nil { price = initialPrice }

        if ownership == nil {
            ownership = await model.ownership(for: route.summary)
        }
        if release == nil, model.isConnected || !model.isOnline {
            release = try? await model.release(id: route.summary.id)
        }
        if price == nil {
            price = await model.cachedPrice(for: route.summary.id)
            if model.isOnline && model.isConnected {
                await loadPrice(force: false)
            }
        }
    }

    private func loadPrice(force: Bool) async {
        isLoadingPrice = true
        defer { isLoadingPrice = false }
        do {
            price = try await model.priceInfo(for: route.summary.id, forceRefresh: force)
            priceError = nil
        } catch let error as DiscogsError {
            if price == nil { priceError = error.userMessage }
        } catch {
            if price == nil { priceError = error.localizedDescription }
        }
    }
}
