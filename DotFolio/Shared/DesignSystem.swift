import AppKit
import SwiftUI

/// Shared look-and-feel values and building blocks. Use these instead of
/// literal numbers or one-off copies so every screen stays consistent.
enum DS {
    /// Spacing and padding: a 4pt grid. Layout-specific insets (window
    /// chrome, hero spacing ≥ 40) may stay literal.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    /// Type scale: one role, one style.
    enum Font {
        /// Top of a screen or full-window step (project name, Overview, New Project).
        static let pageTitle = SwiftUI.Font.title2.weight(.semibold)
        /// Top of a sheet (Verify Data, updates).
        static let sheetTitle = SwiftUI.Font.title3.weight(.semibold)
        /// Heading of a card or section inside a page ("Used by").
        static let sectionTitle = SwiftUI.Font.headline
        /// Heading inside a panel ("Add variable", a provider block).
        static let panelTitle = SwiftUI.Font.callout.weight(.semibold)
        /// Column headers, small badges.
        static let label = SwiftUI.Font.caption.weight(.medium)
    }

    /// Brand + categorical hues (validated set: distinct for color-blind
    /// viewers in light and dark). Used for icon tiles and identity accents —
    /// never alone to carry meaning; a label or symbol always goes with it.
    enum Palette {
        static let violet = Color(light: 0x6250D6, dark: 0x8F84EC)
        static let blue = Color(light: 0x2A78D6, dark: 0x3987E5)
        static let aqua = Color(light: 0x1BAF7A, dark: 0x199E70)
        static let orange = Color(light: 0xEB6834, dark: 0xD95926)
        static let magenta = Color(light: 0xE87BA4, dark: 0xD55181)
        static let green = Color(light: 0x008300, dark: 0x0CA30C)
        static let yellow = Color(light: 0xEDA100, dark: 0xC98500)
        static let red = Color(light: 0xE34948, dark: 0xE66767)
        static let neutral = Color.secondary
    }

    /// The developer convention: development calm, staging caution,
    /// production hot. Validated as a trio in both modes (CVD ΔE ≥ 8.3).
    enum Env {
        static let development = Color(light: 0x1BAF7A, dark: 0x199E70)
        static let staging = Color(light: 0xEDA100, dark: 0xB38B00)
        static let production = Color(light: 0xE34948, dark: 0xEA5B78)

        static func color(for name: String) -> Color {
            switch name.lowercased() {
            case "development", "dev", "local": development
            case "staging", "stage", "preview", "qa", "test": staging
            case "production", "prod", "live": production
            default: Palette.violet
            }
        }
    }

    /// Status colors — always paired with an icon or text, never color alone.
    enum Status {
        static let danger = Color.red
        static let warning = Color.orange
        static let success = Color.green
    }

    /// Opacity of the `.quaternary` fill, by role.
    enum Fill {
        /// Panels and inset blocks.
        static let subtle = 0.35
        /// Inputs, hover states, search fields.
        static let control = 0.6
        /// Icon tiles, chips, tab tracks.
        static let tile = 0.7
    }

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

// MARK: - Colors

extension Color {
    /// A color that switches with the appearance (light / dark).
    init(light: UInt32, dark: UInt32) {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

/// Icon on a soft tile of its own hue — the app's one icon-tile style.
struct TintedIcon<Icon: View>: View {
    let tint: Color
    var size: CGFloat = 28
    @ViewBuilder let icon: Icon

    var body: some View {
        icon
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: max(DS.Radius.small, size * 0.24), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: max(DS.Radius.small, size * 0.24), style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

extension TintedIcon where Icon == AnyView {
    init(symbol: String, tint: Color, size: CGFloat = 28) {
        self.tint = tint
        self.size = size
        self.icon = AnyView(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .medium)))
    }
}

/// Colored dot + environment name.
struct EnvLabel: View {
    let name: String
    var body: some View {
        HStack(spacing: DS.Space.xs + 2) {
            Circle().fill(DS.Env.color(for: name)).frame(width: 8, height: 8)
            Text(name)
        }
    }
}

// MARK: - Surfaces

extension View {
    /// Inset panel: light fill, medium radius (stat tiles, add blocks, rows).
    func panel(radius: CGFloat = DS.Radius.medium, bordered: Bool = false) -> some View {
        self
            .background(.quaternary.opacity(DS.Fill.subtle), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                trailing
            }
            content
            Spacer(minLength: 0)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous).strokeBorder(.separator))
    }
}

// MARK: - Form fields

extension View {
    /// The app's way to explain an input: a small caption line under the
    /// field. Inputs never carry placeholder text.
    func fieldHint(_ text: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            self
            Text(text)
                .font(.caption)
                .foregroundStyle(isError ? AnyShapeStyle(DS.Status.danger) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Chips

/// Shared chip look: same font, height, padding and capsule for every chip.
struct ChipStyle: ViewModifier {
    var dashed = false

    func body(content: Content) -> some View {
        content
            .font(.callout)
            .padding(.horizontal, DS.Space.m)
            .frame(height: 26)
            .background(dashed ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary.opacity(DS.Fill.tile)), in: Capsule())
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


// MARK: - Field titles

extension Text {
    /// A form field's title. Required fields end with a red asterisk, optional
    /// ones with "(optional)"; everything else is plain.
    static func fieldTitle(_ title: String, required: Bool = false, optional: Bool = false) -> Text {
        if required {
            return Text(title) + Text(" *").foregroundStyle(DS.Status.danger)
        }
        if optional {
            return Text(title) + Text(" (optional)").foregroundStyle(.tertiary)
        }
        return Text(title)
    }
}
