import DotFolioModels
import SwiftData
import SwiftUI

/// One series, one hue, sorted. Each row: icon | name | bar | value, so names
/// never overlap bars. Bars scale to the largest value; values sit at the
/// ends, so no legend or axis is needed.
struct UsageBars: View {
    let items: [OverviewStats.ServiceUsage]
    let symbol: (String) -> String
    let tint: (String) -> Color
    let emptyText: String
    let noun: String

    private var shown: [OverviewStats.ServiceUsage] { Array(items.prefix(OverviewDashboard.topCount)) }
    private var maxValue: Int { max(shown.map(\.variables).max() ?? 1, 1) }
    private var labelWidth: CGFloat { TextWidth.fit(shown.map(\.name), extra: 8, min: 60, max: 160) }

    var body: some View {
        if items.isEmpty {
            EmptyNote(text: emptyText)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(shown) { item in
                    UsageBarRow(item: item, symbol: symbol(item.name), tint: tint(item.name),
                                fraction: Double(item.variables) / Double(maxValue), labelWidth: labelWidth)
                }
                if items.count > shown.count {
                    Text("+ \(items.count - shown.count) more \(noun)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

struct UsageBarRow: View {
    let item: OverviewStats.ServiceUsage
    let symbol: String
    let tint: Color
    let fraction: Double
    let labelWidth: CGFloat
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            // Fixed icon column so every name starts at the same x.
            TintedIcon(symbol: symbol, tint: tint, size: 22)
            Text(item.name)
                .font(.callout)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            GeometryReader { proxy in
                // 4px rounded data end, anchored at the baseline (left).
                UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                    .fill(Color.accentColor.opacity(hovering ? 0.75 : 1))
                    .frame(width: max(4, proxy.size.width * fraction), height: 12)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)
            Text(hovering ? "\(item.variables) in \(item.projects) \(item.projects == 1 ? "project" : "projects")" : "\(item.variables)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(item.name): \(item.variables) variables in \(item.projects) projects")
        .accessibilityElement(children: .combine)
    }
}

struct EnvironmentMeters: View {
    let environments: [OverviewStats.EnvironmentCompleteness]

    var body: some View {
        if environments.isEmpty {
            EmptyNote(text: "No variables yet.")
        } else {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                ForEach(environments) { env in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack {
                            EnvLabel(name: env.name).font(.callout.weight(.medium))
                            Spacer()
                            Text("\(env.withValue) / \(env.total)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(env.fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(DS.Env.color(for: env.name))
                                    .frame(width: max(env.fraction > 0 ? 6 : 0, proxy.size.width * env.fraction))
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .combine)
                    .help("\(env.withValue) of \(env.total) variables in \(env.name) have a value")
                }
            }
        }
    }
}

/// Text-only ranking table spanning the card: #, Account, Projects, Variables.
/// Top 5 accounts; each row opens that account in the Accounts tab.
struct AccountRanking: View {
    let ranks: [OverviewStats.AccountRank]
    let onOpen: (Account) -> Void

    private enum Width {
        static let index: CGFloat = 20
        static let projects: CGFloat = 64
        static let variables: CGFloat = 70
        static let chevron: CGFloat = 10
    }

    var body: some View {
        if ranks.isEmpty {
            EmptyNote(text: "Add accounts in the Accounts tab, or type an email in a variable’s Account column.")
        } else {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.s) {
                    Text("#").frame(width: Width.index, alignment: .leading)
                    Text("Account").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Projects").frame(width: Width.projects, alignment: .trailing)
                    Text("Variables").frame(width: Width.variables, alignment: .trailing)
                    Color.clear.frame(width: Width.chevron, height: 1)
                }
                .font(DS.Font.label)
                .foregroundStyle(.secondary)
                // Same inset as the rows' hover background.
                .padding(.horizontal, DS.Space.s)

                Divider()

                ForEach(Array(ranks.prefix(OverviewDashboard.topCount).enumerated()), id: \.element.id) { index, rank in
                    RowButton(action: { onOpen(rank.account) }) {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: Width.index, alignment: .leading)
                        Text(rank.account.login)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(rank.projects)").monospacedDigit()
                            .frame(width: Width.projects, alignment: .trailing)
                        Text("\(rank.variables)").monospacedDigit()
                            .frame(width: Width.variables, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: Width.chevron)
                    }
                    .help("Open \(rank.account.login)")
                }
                if ranks.count > OverviewDashboard.topCount {
                    Text("+ \(ranks.count - OverviewDashboard.topCount) more accounts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
