import DotFolioModels
import SwiftData
import SwiftUI

/// Headline number (a stat tile, not a chart).
struct OverviewStatTile: View {
    let symbol: String
    var tint: Color = DS.Palette.violet
    let value: Int
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                TintedIcon(symbol: symbol, tint: tint, size: 34)
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
            Text(value, format: .number)
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: Double(value)))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: DS.Radius.medium)
        .accessibilityElement(children: .combine)
    }
}

/// Status tile: warning state always carries an icon + label, never color alone.
struct HealthTile: View {
    let symbol: String
    let value: Int
    let label: String
    let detail: String
    let isWarning: Bool
    /// Optional button at the trailing edge (e.g. "Suggest…").
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            TintedIcon(symbol: isWarning ? symbol : "checkmark.circle",
                       tint: isWarning ? DS.Status.warning : DS.Status.success, size: 34)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(value, format: .number).font(.title3.weight(.semibold).monospacedDigit())
                    Text(label).font(.callout).lineLimit(1)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.run)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Guess Service and Provider from variable names")
                    .clickableCursor()
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel(radius: DS.Radius.medium)
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}
