#if DEBUG
import SwiftUI

/// Simple generated sleeve art for demo releases, so screenshots are not a
/// wall of placeholders. Drawn on the device from the release ID; no images
/// are bundled or fetched. Debug builds only.
struct DemoSleeveArt: View {
    let seed: Int

    private struct Palette {
        var top: Color
        var bottom: Color
        var mark: Color
    }

    private static let palettes: [Palette] = [
        Palette(top: rgb(0x1D3557), bottom: rgb(0x457B9D), mark: rgb(0xF1C453)),
        Palette(top: rgb(0x6D2E46), bottom: rgb(0xA26769), mark: rgb(0xECE2D0)),
        Palette(top: rgb(0x264653), bottom: rgb(0x2A9D8F), mark: rgb(0xE9C46A)),
        Palette(top: rgb(0x3D405B), bottom: rgb(0x81B29A), mark: rgb(0xF2CC8F)),
        Palette(top: rgb(0x22223B), bottom: rgb(0x4A4E69), mark: rgb(0xC9ADA7)),
        Palette(top: rgb(0xBC4B51), bottom: rgb(0xF4A259), mark: rgb(0xF4E285)),
        Palette(top: rgb(0x0B3954), bottom: rgb(0x087E8B), mark: rgb(0xFF5A5F)),
        Palette(top: rgb(0x5F0F40), bottom: rgb(0x9A031E), mark: rgb(0xFB8B24)),
    ]

    private static func rgb(_ hex: Int) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var body: some View {
        let palette = Self.palettes[abs(seed) % Self.palettes.count]
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                motif(side: side, palette: palette)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private func motif(side: CGFloat, palette: Palette) -> some View {
        switch (abs(seed) / Self.palettes.count) % 3 {
        case 0:
            // A low sun over a horizon line.
            ZStack {
                Circle().fill(palette.mark).frame(width: side * 0.5).offset(y: side * 0.08)
                Rectangle().fill(palette.top).frame(height: side * 0.36).offset(y: side * 0.32)
            }
        case 1:
            // Concentric grooves.
            ZStack {
                ForEach(0..<4, id: \.self) { ring in
                    Circle()
                        .stroke(palette.mark.opacity(1 - Double(ring) * 0.2), lineWidth: max(1, side * 0.035))
                        .frame(width: side * (0.78 - CGFloat(ring) * 0.16))
                }
            }
        default:
            // Diagonal bands.
            VStack(spacing: side * 0.07) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(palette.mark).frame(height: side * 0.08)
                }
            }
            .rotationEffect(.degrees(-24))
            .frame(width: side * 1.4)
        }
    }
}
#endif
