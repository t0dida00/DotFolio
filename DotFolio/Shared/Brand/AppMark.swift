import SwiftUI

/// App mark used on onboarding. Placeholder until a real app icon exists.
struct AppMark: View {
    var size: CGFloat = 36

    /// Same proportions as the app icon (scripts/render-app-icon.swift): a
    /// squircle with ~22.5% corners and one big glyph filling about three
    /// quarters of it, centered.
    private enum Ratio {
        static let corner: CGFloat = 0.225
        static let glyphWidth: CGFloat = 0.72
        static let glyphHeight: CGFloat = 0.76
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * Ratio.corner, style: .continuous)
    }

    var body: some View {
        tile
            // Brand gradient: lighter violet at the top, deeper at the bottom.
            .fill(LinearGradient(colors: [Color(light: 0x8A7CF4, dark: 0x968BF0), Color(light: 0x5543D0, dark: 0x5A4AD6)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            // Thin light rim, brighter at the top, like a lit edge.
            .overlay(
                tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: max(1, size * 0.012))
            )
            .overlay {
                // One large, light glyph: white fading to a soft lavender.
                Image(systemName: "lock.doc.fill")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .frame(width: size * Ratio.glyphWidth, height: size * Ratio.glyphHeight)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(light: 0xE4DFFF, dark: 0xDCD6FF)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(light: 0x2E2290, dark: 0x1E1660).opacity(0.35), radius: size * 0.02, y: size * 0.012)
                    .symbolMotion(.bounce, onAppear: true)
            }
            // Two layers, like a macOS app icon: a tight contact shadow and a
            // soft ambient one below. Both scale with the mark.
            .shadow(color: .black.opacity(0.18), radius: size * 0.025, y: size * 0.012)
            .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}
