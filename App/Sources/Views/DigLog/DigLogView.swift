import SwiftUI
import CrateCore

struct DigLogView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: DigLogEntry?
    @State private var adding: DigLogEntry?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.visits) { visit in
                    Section {
                        ForEach(visit.entries) { entry in
                            Button {
                                editing = entry
                            } label: {
                                DigLogRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { visit.entries[$0].id }
                            Task { for id in ids { await model.deleteDigEntry(id) } }
                        }
                    } header: {
                        VisitHeader(visit: visit)
                    }
                }
            }
            .overlay {
                if model.digEntries.isEmpty {
                    ContentUnavailableView(
                        "No digs logged",
                        systemImage: "book.closed",
                        description: Text("Log records you buy or leave behind from the result screen, or add one by hand.")
                    )
                }
            }
            .navigationTitle("Dig Log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let exportURL, !model.digEntries.isEmpty {
                        ShareLink(item: exportURL) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = DigLogEntry(date: Date(), shop: model.settings.currentShop, outcome: .noted)
                    } label: {
                        Label("Add entry", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { entry in
                DigLogEntryEditor(entry: entry, isNew: false)
            }
            .sheet(item: $adding) { entry in
                DigLogEntryEditor(entry: entry, isNew: true)
            }
            .task(id: model.digEntries) {
                exportURL = await model.exportDigLog()
            }
        }
    }
}

private struct VisitHeader: View {
    let visit: DigVisit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(visit.shop)
                .font(.headline)
                .textCase(nil)
            HStack(spacing: 6) {
                Text(visit.day, format: .dateTime.weekday(.abbreviated).day().month().year())
                if visit.boughtCount > 0 {
                    Text("\(visit.boughtCount) bought")
                }
                ForEach(visit.spent.keys.sorted(), id: \.self) { currency in
                    if let amount = visit.spent[currency] {
                        Text(Money(amount: amount, currency: currency).formatted())
                    }
                }
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DigLogRow: View {
    let entry: DigLogEntry

    var body: some View {
        HStack(spacing: 12) {
            SleeveThumbnail(url: entry.release?.thumbURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.outcome.displayName)
                    if entry.wasOnWantlist {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                            .accessibilityLabel("Was on wantlist")
                    }
                    if let paid = entry.pricePaid {
                        Text(paid.formatted())
                    }
                    Text(entry.date, format: .dateTime.hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = entry.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit entry")
    }
}
