import DotFolioModels
import SwiftData
import SwiftUI

/// Shown when no project tab is open: what DotFolio is tracking and what
/// needs attention. Metadata only — no secret value is read here.
struct OverviewDashboard: View {
    @Query private var projects: [Project]
    @Query private var accounts: [Account]
    @Environment(AppNavigation.self) private var navigation
    let onOpenProject: (Project) -> Void
    let onShowAccounts: () -> Void
    let onOpenAccount: (Account) -> Void

    var body: some View {
        let stats = OverviewStats(projects: projects, accounts: accounts)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Overview").font(DS.Font.pageTitle)
                    Text("Select a project to open it in a tab.").foregroundStyle(.secondary)
                }

                kpis(stats)

                health(stats)

                // Side by side, half the width each; both as tall as the taller one.
                HStack(alignment: .top, spacing: DS.Space.l) {
                    Card(title: "Providers in use", subtitle: "Variables per provider, longest bar = most used") {
                        UsageBars(items: stats.services, symbol: ServiceType.symbol(for:), tint: ServiceType.tint(for:),
                                  emptyText: "Set a Provider on your variables to see usage here.", noun: "providers")
                    }
                    Card(title: "Services in use", subtitle: "Variables per service — what they’re for") {
                        UsageBars(items: stats.categories, symbol: ServiceCategory.symbol(for:), tint: ServiceCategory.tint(for:),
                                  emptyText: "Set a Service (Database, Cache…) on your variables to see this.", noun: "services")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DS.Space.l) {
                    Card(title: "Values filled by environment", subtitle: "Variables with a stored value") {
                        EnvironmentMeters(environments: stats.environments)
                    }
                    Card(title: "Accounts", subtitle: "Ranked by projects, then variables",
                         trailing: AnyView(Button("Show All", action: onShowAccounts).buttonStyle(.link).clickableCursor())) {
                        AccountRanking(ranks: stats.accountRanking, onOpen: onOpenAccount)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DS.Space.l) {
                    Card(title: "Needs attention", subtitle: "Projects with the most missing values") {
                        AttentionList(items: stats.attention, onOpen: onOpenProject)
                    }
                    Card(title: "Recently updated", subtitle: "Latest variable changes") {
                        RecentList(variables: stats.recentlyUpdated, onOpen: onOpenProject)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 1100, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: KPI tiles

    private func kpis(_ s: OverviewStats) -> some View {
        HStack(spacing: DS.Space.m) {
            StatTile(symbol: "folder", tint: DS.Palette.violet, value: s.projectCount, label: "Projects tracked",
                     detail: "\(s.repoProjectCount) from repos · \(s.projectCount - s.repoProjectCount) manual")
            StatTile(symbol: "key.horizontal", tint: DS.Palette.blue, value: s.variableCount, label: "Variables",
                     detail: "\(percent(s.valueCoverage)) have a value")
            StatTile(symbol: "square.stack.3d.up", tint: DS.Palette.aqua, value: s.serviceCount, label: "Providers in use",
                     detail: s.services.first.map { "Most used: \($0.name)" } ?? "None linked yet")
            StatTile(symbol: "person.crop.circle", tint: DS.Palette.magenta, value: s.accountCount, label: "Accounts",
                     detail: s.accountRanking.first.map { "\($0.account.login)" } ?? "None yet")
        }
    }

    // MARK: Health

    private func health(_ s: OverviewStats) -> some View {
        HStack(spacing: DS.Space.m) {
            HealthTile(symbol: "exclamationmark.circle", value: s.missingCount, label: "Missing values",
                       detail: "No value stored yet", isWarning: s.missingCount > 0)
            HealthTile(symbol: "questionmark.circle", value: s.noSourceCount, label: "No source",
                       detail: "\(percent(s.sourceCoverage)) have a provider, account or link", isWarning: s.noSourceCount > 0,
                       action: s.noSourceCount > 0 ? ("Suggest…", { navigation.isSuggestingSources = true }) : nil)
            HealthTile(symbol: "clock.arrow.circlepath", value: s.staleCount, label: "Stale values",
                       detail: "Unchanged for 90+ days", isWarning: s.staleCount > 0)
        }
        // Equal heights even when one detail wraps.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Building blocks

/// Headline number (a stat tile, not a chart).
private struct StatTile: View {
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
private struct HealthTile: View {
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

// MARK: - Services chart

/// One series, one hue, sorted. Each row: icon | name | bar | value, so names
/// never overlap bars. Bars scale to the largest value; values sit at the
/// ends, so no legend or axis is needed.
private struct UsageBars: View {
    let items: [OverviewStats.ServiceUsage]
    let symbol: (String) -> String
    let tint: (String) -> Color
    let emptyText: String
    let noun: String

    private var shown: [OverviewStats.ServiceUsage] { Array(items.prefix(8)) }
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

private struct UsageBarRow: View {
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

// MARK: - Environment meters

private struct EnvironmentMeters: View {
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

// MARK: - Account ranking

/// Text-only ranking table spanning the card: #, Account, Projects, Variables.
/// Top 5 accounts; each row opens that account in the Accounts tab.
private struct AccountRanking: View {
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

                ForEach(Array(ranks.prefix(5).enumerated()), id: \.element.id) { index, rank in
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lists

private struct AttentionList: View {
    let items: [OverviewStats.ProjectAttention]
    let onOpen: (Project) -> Void

    var body: some View {
        if items.isEmpty {
            Label("Every variable has a value.", systemImage: "checkmark.circle")
                .foregroundStyle(DS.Status.success)
        } else {
            VStack(spacing: DS.Space.xs) {
                ForEach(items) { item in
                    RowButton(action: { onOpen(item.project) }) {
                        ProjectTile(project: item.project, size: 24)
                        Text(item.project.name).lineLimit(1)
                        Spacer()
                        Label("\(item.missing) of \(item.total) missing", systemImage: "exclamationmark.circle")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(DS.Status.warning)
                    }
                }
            }
        }
    }
}

private struct RecentList: View {
    let variables: [Variable]
    let onOpen: (Project) -> Void

    var body: some View {
        if variables.isEmpty {
            EmptyNote(text: "No variables yet.")
        } else {
            VStack(spacing: DS.Space.xs) {
                ForEach(variables) { v in
                    RowButton(action: { if let p = v.project { onOpen(p) } }) {
                        Image(systemName: v.hasValue ? "key.fill" : "key")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(v.key).font(.callout.monospaced()).lineLimit(1)
                            Text("\(v.project?.name ?? "?") · \(v.environment?.name ?? "?")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(v.updatedAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct RowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) { label }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.s)
                .background(.quaternary.opacity(hovering ? 0.6 : 0), in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickableCursor()
    }
}

private struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
