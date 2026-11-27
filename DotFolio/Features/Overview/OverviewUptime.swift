import DotFolioModels
import SwiftUI

/// Overview card: how many production sites are up or down, and for how
/// long. Durations count from the first check that saw the current state,
/// so they only cover the time DOTFOLIO was running.
struct UptimeCard: View {
    let summary: UptimeSummary
    let onOpen: (Project) -> Void
    @Environment(HealthMonitor.self) private var monitor
    @State private var filter: UptimeSummary.Filter = .all

    /// Falls back to All when the chosen status has no project any more.
    private var activeFilter: UptimeSummary.Filter {
        summary.availableFilters.contains(filter) ? filter : .all
    }

    var body: some View {
        Card(title: "Production uptime", subtitle: subtitle, trailing: summary.total == 0 ? nil : AnyView(filters)) {
            if summary.total == 0 {
                EmptyNote(text: "Add a Production URL to a project (✎ in its header) to see here whether it’s up.")
            } else {
                // Refreshes the "for 23 min" durations once a minute.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: DS.Space.xs) {
                        ForEach(summary.projects(activeFilter)) { project in
                            RowButton(action: { onOpen(project) }) {
                                UptimeRow(project: project, now: context.date)
                            }
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        monitor.isOnline
            ? "Checked every 10 minutes while DOTFOLIO is open"
            : "This Mac is offline: showing the last results"
    }

    /// "All 5 · ● Down 2 · ● Slow 1 · ● Up 1 · ● Not checked 1": a status
    /// with no project is left out. The chosen one is violet with white text.
    private var filters: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(summary.availableFilters) { option in
                let selected = option == activeFilter
                Button { filter = option } label: {
                    HStack(spacing: DS.Space.xs + 2) {
                        if let status = option.status {
                            Circle().fill(status.color).frame(width: 8, height: 8)
                        }
                        Text(option.title)
                        Text(summary.count(option), format: .number)
                            .monospacedDigit()
                            .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    }
                    .fontWeight(selected ? .semibold : .regular)
                    .chip(selected: selected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .clickableCursor()
            }
        }
    }
}

private struct UptimeRow: View {
    let project: Project
    let now: Date

    var body: some View {
        Circle().fill(project.health.color).frame(width: 8, height: 8)
            .accessibilityHidden(true)
        ProjectTile(project: project, size: 24)
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(project.name).lineLimit(1)
            Text(project.productionDisplayName ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        Spacer(minLength: DS.Space.m)
        VStack(alignment: .trailing, spacing: DS.Space.xxs) {
            Text(state)
                .font(.callout.monospacedDigit())
                .foregroundStyle(project.health == .down ? AnyShapeStyle(DS.Status.danger) : AnyShapeStyle(.primary))
                .lineLimit(1)
            if let checked = project.healthCheckedAt {
                Text("Checked \(checked.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// "Up for 2 d 4 h · 240 ms", "Slow for 1 h · 4.1 s", "Down for 23 min · HTTP 503", "Not checked yet".
    private var state: String {
        let duration = project.healthDuration(now: now).map(DowntimeText.string)
        switch project.health {
        case .unknown:
            return "Not checked yet"
        case .up:
            let time = project.healthResponseTime.map(HealthText.responseTime)
            return [duration.map { "Up for \($0)" } ?? "Up", time].compactMap { $0 }.joined(separator: " · ")
        case .slow:
            // The clock is the up time; "slow" is about the last answer only.
            let time = project.healthResponseTime.map(HealthText.responseTime)
            return ["Slow", time, duration.map { "up for \($0)" }].compactMap { $0 }.joined(separator: " · ")
        case .down:
            return [duration.map { "Down for \($0)" } ?? "Down", project.healthError].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
