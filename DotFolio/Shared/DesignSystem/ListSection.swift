import SwiftUI

/// Section with a small gray header, like "Recent" / "Connections".
struct ListSection<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            header
                .font(DS.Font.panelTitle)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DS.Space.xs) { content }
                .padding(.leading, DS.Space.m)
        }
    }
}

extension ListSection where Header == Text {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.header = Text(title)
        self.content = content()
    }
}

/// Icon tile + title + secondary line.
struct ListRow: View {
    enum Tile { case symbol(String), brand(BrandMark) }

    let tile: Tile
    let title: Text
    let subtitle: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            TintedIcon(tint: DS.Palette.violet, size: 40) {
                switch tile {
                case .symbol(let name): Image(systemName: name).resizable().scaledToFit().fontWeight(.medium).symbolMotion(.bounce)
                case .brand(let mark): mark.image.resizable().scaledToFit()
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                title.font(.body).lineLimit(1)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, DS.Space.s)
        .accessibilityElement(children: .combine)
    }
}
