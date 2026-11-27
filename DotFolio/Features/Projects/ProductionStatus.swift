import DotFolioModels
import SwiftUI

/// Under the project name: the live site's link and whether it's up.
/// Clicking the status opens the details and Check Now.
struct ProductionStatusLine: View {
    let project: Project
    @Environment(HealthMonitor.self) private var monitor
    @State private var showsDetails = false

    var body: some View {
        if let url = project.productionURL {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                LinkText(url: url, title: project.productionDisplayName)
                    .fixedSize()
                Button { showsDetails = true } label: {
                    HealthChip(project: project, isChecking: monitor.isChecking(project), isOffline: !monitor.isOnline)
                }
                .buttonStyle(.plain)
                .help("Production status: click for details")
                .clickableCursor()
                .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                    HealthDetails(project: project, close: { showsDetails = false })
                }
            }
        }
    }
}

/// "● Up · 240 ms", "✕ Down · HTTP 503 · since 14:20": icon and text, never color alone.
struct HealthChip: View {
    let project: Project
    let isChecking: Bool
    /// This Mac has no network: the last result is shown as stale.
    var isOffline = false

    var body: some View {
        HStack(spacing: DS.Space.xs + 2) {
            if isOffline {
                Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                Text(project.healthCheckedAt.map { "Offline · last checked \(HealthText.time($0))" } ?? "Offline · not checked yet")
                    .foregroundStyle(.secondary)
            } else if isChecking && project.health == .unknown {
                ProgressView().controlSize(.mini)
                Text("Checking…").foregroundStyle(.secondary)
            } else {
                Image(systemName: symbol).foregroundStyle(color)
                Text(text).foregroundStyle(project.health == .down ? AnyShapeStyle(DS.Status.danger) : AnyShapeStyle(.primary))
            }
        }
        .lineLimit(1)
        .chip()
    }

    private var symbol: String {
        switch project.health {
        case .unknown: "circle.dashed"
        case .up: "checkmark.circle.fill"
        case .slow: "tortoise.fill"
        case .down: "xmark.octagon.fill"
        }
    }

    private var color: Color { project.health.color }

    private var text: String {
        switch project.health {
        case .unknown:
            return "Not checked yet"
        case .up:
            return project.healthResponseTime.map { "Up · \(HealthText.responseTime($0))" } ?? "Up"
        case .slow:
            return project.healthResponseTime.map { "Slow · \(HealthText.responseTime($0))" } ?? "Slow"
        case .down:
            let reason = project.healthError ?? "No response"
            return project.healthDownSince.map { "Down · \(reason) · since \(HealthText.time($0))" } ?? "Down · \(reason)"
        }
    }
}

/// Popover behind the status chip: the last check, and Check Now.
private struct HealthDetails: View {
    let project: Project
    let close: () -> Void
    @Environment(HealthMonitor.self) private var monitor
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Text("Production").font(DS.Font.panelTitle)
                Spacer(minLength: DS.Space.m)
                HealthChip(project: project, isChecking: monitor.isChecking(project), isOffline: !monitor.isOnline)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.xs) {
                if let url = project.productionURL {
                    row("Address") { LinkText(url: url).frame(maxWidth: 280) }
                }
                row("Last checked") {
                    if let checked = project.healthCheckedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("\(HealthText.time(checked)) (\(checked.formatted(.relative(presentation: .named, unitsStyle: .wide))))")
                        }
                    } else {
                        Text("Not yet").foregroundStyle(.secondary)
                    }
                }
                if let response = responseLine {
                    row("Response") { Text(response) }
                }
                if let since = project.healthDownSince {
                    row("Down since") {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("\(HealthText.time(since)) · \(DowntimeText.string(context.date.timeIntervalSince(since)))")
                                .foregroundStyle(DS.Status.danger)
                        }
                    }
                }
            }
            Text(monitor.isOnline
                 ? "Checked every 10 minutes while DOTFOLIO is open (also from the menu bar). You get a notification when the site goes down or comes back."
                 : "This Mac is offline, so checks are paused and the last result is kept. They resume as soon as the network is back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(action: checkNow) {
                    Label(monitor.isChecking(project) ? "Checking…" : "Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(monitor.isChecking(project) || !monitor.isOnline)
                .clickableCursor()
            }
        }
        .padding(DS.Space.l)
        .frame(width: 400)
    }

    private var responseLine: String? {
        let code = project.healthStatusCode.map { "HTTP \($0)" }
        let time = project.healthResponseTime.map(HealthText.responseTime)
        let protected = project.healthStatusCode.map(HealthStatus.protectedCodes.contains) ?? false
        switch (code, time) {
        case let (code?, time?) where protected: return "\(code) in \(time) (login or firewall; the server is up)"
        case let (code?, time?): return "\(code) in \(time)"
        case let (code?, nil): return code
        default: return project.healthError
        }
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            content()
        }
    }

    private func checkNow() {
        Task {
            let site = project.productionDisplayName ?? project.name
            let result: HealthResult
            switch await monitor.check(project) {
            case .checked(let checked): result = checked
            case .skipped: return
            case .offline:
                close()
                navigation.show(.nothing("Couldn’t check \(site)", "This Mac is offline. The last result was kept; checks resume when the network is back."))
                return
            }
            close()
            if result.isUp {
                let detail = [result.statusCode.map { "HTTP \($0)" }, result.responseTime.map(HealthText.responseTime)]
                    .compactMap { $0 }.joined(separator: " in ")
                if project.health == .slow {
                    navigation.show(.nothing("\(site) is slow", "It answered with \(detail), over the \(Int(HealthStatus.slowThreshold)) s limit."))
                } else {
                    navigation.show(.success("\(site) is up", "It answered with \(detail)."))
                }
            } else {
                navigation.show(.failed("\(site) is down", project.healthError ?? "No response."))
            }
        }
    }
}

extension HealthStatus {
    /// One color per state everywhere (chip icon, list dot, Overview):
    /// green up, yellow slow, red down, gray not checked yet.
    var color: Color {
        switch self {
        case .up: DS.Status.success
        case .slow: DS.Palette.yellow
        case .down: DS.Status.danger
        case .unknown: .secondary
        }
    }
}
