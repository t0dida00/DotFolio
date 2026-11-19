import AppKit
import SwiftUI

/// Shared look-and-feel values and building blocks. Use these instead of
/// literal numbers or one-off copies so every screen stays consistent.
enum DS {
    /// Corner radii: three steps only.
    enum Radius {
        /// Icon tiles, small badges, inline rows.
        static let small: CGFloat = 8
        /// Panels, inputs groups, stat tiles, add/edit blocks.
        static let medium: CGFloat = 12
        /// Top-level cards on a page.
        static let large: CGFloat = 14
    }

    /// Native tables that grow to show every row (the page scrolls, the table
    /// only scrolls sideways). One formula for every table in the app.
    enum Table {
        static let headerHeight: CGFloat = 30
        static let rowHeight: CGFloat = 28
        static let borders: CGFloat = 6

        static func height(rows: Int, minimumRows: Int = 1) -> CGFloat {
            headerHeight + rowHeight * CGFloat(max(rows, minimumRows)) + borders
        }
    }
}

// MARK: - Surfaces

extension View {
    /// Inset panel: light fill, medium radius (stat tiles, add blocks, rows).
    func panel(radius: CGFloat = DS.Radius.medium, bordered: Bool = false) -> some View {
        self
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator)
                }
            }
    }
}

/// Top-level page card: title, optional subtitle and trailing accessory.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                trailing
            }
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous).strokeBorder(.separator))
    }
}

// MARK: - Chips

/// Shared chip look: same font, height, padding and capsule for every chip.
struct ChipStyle: ViewModifier {
    var dashed = false

    func body(content: Content) -> some View {
        content
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(dashed ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary.opacity(0.7)), in: Capsule())
            .overlay {
                if dashed {
                    Capsule().strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .foregroundStyle(dashed ? .secondary : .primary)
            .contentShape(Capsule())
    }
}

extension View {
    func chip(dashed: Bool = false) -> some View { modifier(ChipStyle(dashed: dashed)) }
}

// MARK: - Links

/// A web link that always stays on one line, left-aligned, truncated in the
/// middle (SwiftUI's `Link` can wrap and center its label in table cells).
/// Click opens the browser; hover shows the full URL.
struct LinkText: View {
    let url: URL
    var title: String?

    var body: some View {
        Text(title ?? url.absoluteString)
            .foregroundStyle(.link)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { NSWorkspace.shared.open(url) }
            .help(url.absoluteString)
            .clickableCursor()
            .accessibilityAddTraits(.isLink)
            .accessibilityAction { NSWorkspace.shared.open(url) }
    }
}
