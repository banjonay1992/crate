import SwiftUI
import CrateCore

/// Adds or edits a dig log entry.
struct DigLogEntryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var entry: DigLogEntry
    @State private var priceText: String
    @State private var noteText: String
    private let isNew: Bool

    init(entry: DigLogEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        _priceText = State(initialValue: entry.pricePaid.map { "\($0.amount)" } ?? "")
        _noteText = State(initialValue: entry.note ?? "")
        self.isNew = isNew
    }

    private var parsedPrice: Decimal? {
        let cleaned = priceText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_GB"))
    }

    private var priceIsInvalid: Bool {
        !priceText.trimmingCharacters(in: .whitespaces).isEmpty && parsedPrice == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.title).font(.headline)
                    if let line = entry.release?.pressingLine, !line.isEmpty {
                        Text(line).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Shop or fair", text: $entry.shop)
                        .textInputAutocapitalization(.words)
                    Picker("Outcome", selection: $entry.outcome) {
                        ForEach(DigLogEntry.Outcome.allCases, id: \.self) { outcome in
                            Text(outcome.displayName).tag(outcome)
                        }
                    }
                    DatePicker("When", selection: $entry.date)
                }
                Section {
                    HStack {
                        TextField("Price paid", text: $priceText)
                            .keyboardType(.decimalPad)
                        Text(model.settings.currency).foregroundStyle(.secondary)
                    }
                    if priceIsInvalid {
                        Text("That does not look like a price.").font(.footnote).foregroundStyle(.red)
                    }
                    if let market = entry.marketPriceAtTime {
                        LabeledContent("Lowest on Discogs at the time", value: market.formatted())
                    }
                    Toggle("Was on my wantlist", isOn: $entry.wasOnWantlist)
                }
                Section("Note") {
                    TextField("Condition, sleeve, haggling...", text: $noteText, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(isNew ? "Log record" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(priceIsInvalid)
                }
            }
        }
    }

    private func save() async {
        var final = entry
        final.shop = entry.shop.trimmingCharacters(in: .whitespaces)
        if final.shop.isEmpty { final.shop = "Unnamed shop" }
        final.pricePaid = parsedPrice.map { Money(amount: $0, currency: entry.pricePaid?.currency ?? model.settings.currency) }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        final.note = note.isEmpty ? nil : note
        if isNew {
            await model.addDigEntry(final)
        } else {
            await model.updateDigEntry(final)
        }
        dismiss()
    }
}
