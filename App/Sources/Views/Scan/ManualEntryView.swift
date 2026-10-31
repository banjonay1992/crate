import SwiftUI
import CrateCore

/// Typed lookup, for damaged barcodes, records with no barcode (most before
/// the early 1980s), or identifying the exact pressing by its run-out.
struct ManualEntryView: View {
    let onSubmit: (LookupQuery) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: LookupQuery.Kind
    @State private var text: String
    @FocusState private var focused: Bool

    /// `prefill` sets the starting type and text, for example in demo mode.
    init(prefill: LookupQuery? = nil, onSubmit: @escaping (LookupQuery) -> Void) {
        self.onSubmit = onSubmit
        _kind = State(initialValue: prefill?.kind ?? .catalogueNumber)
        _text = State(initialValue: prefill?.displayText ?? "")
    }

    private var query: LookupQuery? {
        LookupQuery.make(kind: kind, text: text)
    }

    private var warning: String? {
        guard !text.isEmpty else { return nil }
        switch kind {
        case .barcode:
            guard let barcode = Barcode(text) else { return "Barcodes are 8, 12 or 13 digits." }
            return barcode.hasValidCheckDigit ? nil : "The check digit does not add up. Look up anyway, or check for a typo."
        case .catalogueNumber:
            return query == nil ? "Too short to search for." : nil
        case .matrix:
            return query == nil ? "Type at least a few characters from the run-out." : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(LookupQuery.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    TextField(placeholder, text: $text)
                        .keyboardType(kind == .barcode ? .numberPad : .asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(submit)
                        .accessibilityLabel(kind.displayName)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let warning {
                            Text(warning).foregroundStyle(.orange)
                        }
                        Text(help)
                    }
                }
            }
            .navigationTitle("Look up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Look up", action: submit)
                        .disabled(query == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var placeholder: String {
        switch kind {
        case .barcode: "5012345600123"
        case .catalogueNumber: "e.g. SHVL 804"
        case .matrix: "e.g. A-1 PORKY"
        }
    }

    private var help: String {
        switch kind {
        case .barcode:
            "The digits under the barcode on the back of the sleeve."
        case .catalogueNumber:
            "Usually on the spine and the label. Several pressings often share one, so Crate may ask you to check the run-out."
        case .matrix:
            "Etched or stamped in the run-out groove near the label. Type what you can read; spacing and punctuation do not matter."
        }
    }

    private func submit() {
        guard let query else { return }
        onSubmit(query)
    }
}
