import SwiftUI

/// Icon on a soft tile of its own hue — the app's one icon-tile style.
/// Icon tile in the app's one icon style — the same proportions as the
/// logo (AppMark): ~22.5% continuous corners and a glyph filling ~60% of the
/// tile, centered; soft tint background with a same-hue glyph and rim.
/// Give `icon` a resizable image (`.resizable().scaledToFit()`) so it fills
/// the glyph box at any size.
struct TintedIcon<Icon: View>: View {
    let tint: Color
    var size: CGFloat = 28
    @ViewBuilder let icon: Icon

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * DS.IconTile.corner, style: .continuous)
        icon
            .frame(width: size * DS.IconTile.glyph, height: size * DS.IconTile.glyph)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: shape)
            .overlay(shape.strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

extension TintedIcon where Icon == AnyView {
    init(symbol: String, tint: Color, size: CGFloat = 28) {
        self.tint = tint
        self.size = size
        self.icon = AnyView(Image(systemName: symbol).resizable().scaledToFit().fontWeight(.medium))
    }
}
