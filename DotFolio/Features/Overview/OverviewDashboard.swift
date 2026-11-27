import DotFolioModels
import SwiftData
import SwiftUI

/// Shown when no project tab is open: what DotFolio is tracking and what
/// needs attention. Metadata only — no secret value is read here.
struct OverviewDashboard: View {
    /// Charts and rankings list the top 5; the rest is counted below them.
    static let topCount = 5

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

                UptimeCard(summary: UptimeSummary(projects: projects), onOpen: onOpenProject)

                // Side by side, half the width each; both as tall as the taller one.
                HStack(alignment: .top, spacing: DS.Space.l) {
                    Card(title: "Providers in use", subtitle: "Top 5 by variables, longest bar = most used") {
                        UsageBars(items: stats.services, symbol: ServiceType.symbol(for:), tint: ServiceType.tint(for:),
                                  emptyText: "Set a Provider on your variables to see usage here.", noun: "providers")
                    }
                    Card(title: "Services in use", subtitle: "Top 5 by variables — what they’re for") {
                        UsageBars(items: stats.categories, symbol: ServiceCategory.symbol(for:), tint: ServiceCategory.tint(for:),
                                  emptyText: "Set a Service (Database, Cache…) on your variables to see this.", noun: "services")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DS.Space.l) {
                    Card(title: "Values filled by environment", subtitle: "Variables with a stored value") {
                        EnvironmentMeters(environments: stats.environments)
                    }
                    Card(title: "Accounts", subtitle: "Top 5 by projects, then variables",
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
            OverviewStatTile(symbol: "folder", tint: DS.Palette.violet, value: s.projectCount, label: "Projects tracked",
                     detail: "\(s.repoProjectCount) from repos · \(s.projectCount - s.repoProjectCount) manual")
            OverviewStatTile(symbol: "key.horizontal", tint: DS.Palette.blue, value: s.variableCount, label: "Variables",
                     detail: "\(percent(s.valueCoverage)) have a value")
            OverviewStatTile(symbol: "square.stack.3d.up", tint: DS.Palette.aqua, value: s.serviceCount, label: "Providers in use",
                     detail: s.services.first.map { "Most used: \($0.name)" } ?? "None linked yet")
            OverviewStatTile(symbol: "person.crop.circle", tint: DS.Palette.magenta, value: s.accountCount, label: "Accounts",
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
