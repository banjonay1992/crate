import SwiftUI
import CrateCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tokenText = ""
    @State private var isConnecting = false
    @State private var connectError: String?
    @State private var confirmDisconnect = false
    @State private var confirmDeleteLog = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                accountSection

                if model.isConnected {
                    Section {
                        Button {
                            Task { await model.sync() }
                        } label: {
                            HStack {
                                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if model.isSyncing { ProgressView() }
                            }
                        }
                        .disabled(model.isSyncing || !model.isOnline)
                        if let status = model.syncStatus {
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let note = model.syncNote {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let error = model.syncError {
                            Text(error).font(.footnote).foregroundStyle(.orange)
                        }
                        LabeledContent("Collection", value: "\(model.collection.count)")
                        LabeledContent("Wantlist", value: "\(model.wants.count)")
                        LabeledContent("Release details saved", value: "\(model.cachedReleaseCount)")
                        if let synced = model.lastSynced {
                            LabeledContent("Last synced", value: synced.formatted(.relative(presentation: .named)))
                        }
                        Toggle("Save wantlist details for offline matching", isOn: $settings.prefetchWantlistDetails)
                    } header: {
                        Text("Sync")
                    } footer: {
                        Text("With this on, Crate fetches each wantlist release once so barcodes and run-outs match with no signal. Large wantlists fill in over several syncs to stay inside Discogs rate limits.")
                    }
                }

                Section {
                    Picker("Currency", selection: $settings.currency) {
                        ForEach(AppSettings.supportedCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Fetch price suggestions", isOn: $settings.includePriceSuggestions)
                } header: {
                    Text("Prices")
                } footer: {
                    Text("Suggestions by condition only appear if you have filled in your Discogs seller settings. Each costs one extra request.")
                }

                Section("Offline lookups") {
                    NavigationLink {
                        QueueView()
                    } label: {
                        LabeledContent("Queued and resolved", value: "\(model.pending.count) / \(model.resolved.count)")
                    }
                }

                Section("Data on this phone") {
                    Button("Clear saved Discogs data") {
                        Task { await model.clearCache() }
                    }
                    Button("Delete dig log", role: .destructive) {
                        confirmDeleteLog = true
                    }
                    .disabled(model.digEntries.isEmpty)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    if model.isDemo {
                        Label("Demo mode: invented sample data, kept in memory. Nothing is sent to Discogs.", systemImage: "theatermasks")
                            .font(.footnote)
                    }
                    Text("Crate is open source under the MIT licence. It talks only to Discogs, using your own token, and has no analytics or tracking.")
                        .font(.footnote)
                    Text("This application uses the Discogs API but is not affiliated with, sponsored or endorsed by Discogs. Discogs is a trademark of Zink Media, LLC.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: ReleaseRoute.self) { route in
                PressingDetailView(route: route)
            }
            .confirmationDialog("Disconnect Discogs?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
            } message: {
                Text("Your token and saved Discogs data are removed from this phone. Your dig log is kept.")
            }
            .confirmationDialog("Delete the whole dig log?", isPresented: $confirmDeleteLog, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.deleteAllDigEntries() } }
            } message: {
                Text("This cannot be undone. Export it as CSV first if you want a copy.")
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if model.isConnected {
                LabeledContent("Signed in as", value: model.settings.username ?? "Unknown")
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            } else {
                SecureField("Personal access token", text: $tokenText)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text("Connect")
                        if isConnecting { Spacer(); ProgressView() }
                    }
                }
                .disabled(tokenText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                if let connectError {
                    Text(connectError).font(.footnote).foregroundStyle(.red)
                }
                if let url = URL(string: "https://www.discogs.com/settings/developers") {
                    Link("Get a token from Discogs", destination: url)
                }
            }
        } header: {
            Text("Discogs account")
        } footer: {
            if !model.isConnected {
                Text("On Discogs, go to Settings, Developers and choose Generate new token. Crate stores it in the Keychain on this phone only.")
            }
        }
    }

    private func connect() async {
        isConnecting = true
        connectError = nil
        defer { isConnecting = false }
        do {
            try await model.connect(token: tokenText)
            tokenText = ""
        } catch let error as DiscogsError {
            connectError = error.userMessage
        } catch {
            connectError = error.localizedDescription
        }
    }
}

/// Lookups made offline: waiting, failed, and answered.
struct QueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                if model.pending.isEmpty {
                    Text("Nothing waiting.").foregroundStyle(.secondary)
                }
                ForEach(model.pending) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.query.kind.displayName): \(item.query.displayText)")
                        HStack {
                            if let shop = item.shopName { Text(shop) }
                            Text(item.createdAt.formatted(.relative(presentation: .named)))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let error = item.lastError {
                            Text(error).font(.caption).foregroundStyle(item.hasFailed ? Color.red : Color.orange)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await model.removePending(item.id) } }
                        if item.hasFailed {
                            Button("Retry") { Task { await model.retryPending(item.id) } }
                        }
                    }
                }
            } header: {
                Text("Waiting")
            } footer: {
                Text("These run automatically when your phone is back online.")
            }

            if !model.resolved.isEmpty {
                Section("Answered") {
                    ForEach(model.resolved) { item in
                        NavigationLink {
                            LookupResultView(result: item.result)
                                .navigationTitle(item.pending.query.displayText)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.result.bestMatch?.summary.displayTitle ?? item.pending.query.displayText)
                                Text(resolvedSummary(item.result))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Dismiss") { Task { await model.acknowledge(item.id) } }
                        }
                    }
                    Button("Clear answered lookups") {
                        Task { await model.acknowledgeAll() }
                    }
                }
            }
        }
        .navigationTitle("Offline lookups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Try now") { Task { await model.drainQueue() } }
                    .disabled(model.pending.isEmpty || !model.isOnline || model.isDrainingQueue)
            }
        }
        .refreshable { await model.drainQueue() }
    }

    private func resolvedSummary(_ result: LookupResult) -> String {
        if let match = result.bestMatch {
            return result.ownership(for: match.id).headline.text
        }
        if result.isAmbiguous { return "\(result.choices.count) possible pressings" }
        return result.isEmpty ? "No match" : "No exact match"
    }
}
