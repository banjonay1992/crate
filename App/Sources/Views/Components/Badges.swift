import SwiftUI
import CrateCore

/// The headline answer at a record bin: wanted, owned, or neither.
struct OwnershipBadge: View {
    let status: OwnershipStatus

    var body: some View {
        Label(status.headline.text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
    }

    private var symbol: String {
        switch status.headline {
        case .wanted: "heart.fill"
        case .owned: "checkmark.circle.fill"
        case .wantedOtherPressing: "heart"
        case .ownedOtherPressing: "checkmark.circle"
        case .neither: "circle.dashed"
        }
    }

    private var foreground: Color {
        switch status.headline {
        case .wanted, .owned: .white
        default: .primary
        }
    }

    private var background: Color {
        switch status.headline {
        case .wanted: .pink
        case .owned: .green
        case .wantedOtherPressing: .pink.opacity(0.18)
        case .ownedOtherPressing: .green.opacity(0.18)
        case .neither: .secondary.opacity(0.15)
        }
    }

    private var accessibilityText: String {
        var text = status.headline.text
        if status.ownedCopies > 1 { text += ", \(status.ownedCopies) copies" }
        return text
    }
}

/// Why a candidate was matched.
struct EvidenceBadge: View {
    let evidence: MatchEvidence

    var body: some View {
        Label(evidence.explanation, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(evidence.score >= MatchEvidence.catalogueNumber.score ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Match: \(evidence.explanation)")
    }

    private var symbol: String {
        switch evidence {
        case .barcode: "barcode"
        case .matrixExact, .matrixPartial: "record.circle"
        case .catalogueNumber, .catalogueNumberLoose: "number"
        case .searchResult: "magnifyingglass"
        }
    }
}

/// Offline banner shown on screens that talk to Discogs.
struct OfflineBanner: View {
    var body: some View {
        Label("Offline. Lookups are saved and run when you are back online.", systemImage: "wifi.slash")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Required attribution for Discogs data.
struct DiscogsAttribution: View {
    var body: some View {
        Text("Data provided by Discogs. Crate is not affiliated with, sponsored or endorsed by Discogs.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
