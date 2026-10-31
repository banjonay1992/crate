import SwiftUI
import CrateCore

/// Sleeve thumbnail with a neutral placeholder. Decorative for VoiceOver,
/// since the row text already says what the record is.
struct SleeveThumbnail: View {
    let url: URL?
    var size: CGFloat = 52

    var body: some View {
        artwork
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        #if DEBUG
        if let url, url.scheme == DemoLibrary.artScheme {
            DemoSleeveArt(seed: Int(url.lastPathComponent) ?? 0)
        } else {
            remoteImage
        }
        #else
        remoteImage
        #endif
    }

    private var remoteImage: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "record.circle")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ReleaseRow: View {
    let summary: ReleaseSummary
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            SleeveThumbnail(url: summary.thumbURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if !summary.artist.isEmpty {
                    Text(summary.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(summary.pressingLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
