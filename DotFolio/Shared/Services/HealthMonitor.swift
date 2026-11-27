import AppKit
import DotFolioIntegrations
import DotFolioModels
import Network
import Observation
import SwiftData
import SwiftUI
import UserNotifications

/// Checks every project's production URL every 10 minutes while Dotfolio
/// runs (the menu bar extra keeps it running with the window closed), once
/// more when the Mac wakes, and on Check Now. A site that changes state
/// (down, back up) posts a notification; clicking it opens the project.
/// Without a network nothing is checked: the last results stay, no false
/// "down", and everything is checked again as soon as the Mac is back online.
@Observable
@MainActor
final class HealthMonitor {
    /// Seconds between rounds of checks.
    static let interval: TimeInterval = 600
    /// At most this many sites are asked at once.
    private static let parallelChecks = 4

    /// Projects being checked right now (their chip says "Checking…").
    private(set) var checking: Set<UUID> = []
    /// Names of projects whose site is down; drives the menu bar icon.
    private(set) var downProjects: [String] = []
    /// This Mac has a network path. Off: checks wait, chips say "Offline".
    private(set) var isOnline = true

    /// What Check Now found.
    enum Outcome {
        case checked(HealthResult)
        /// No network on this Mac; nothing was recorded.
        case offline
        /// No URL, already checking, or the URL changed meanwhile.
        case skipped
    }

    /// Opens the main window when a notification is clicked with it closed.
    /// Set by whichever scene appeared last.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let navigation: AppNavigation
    @ObservationIgnored private let checker = HealthChecker()
    /// macOS's own timer for periodic background work: it wakes the app on
    /// schedule even when App Nap would stretch a plain `Task.sleep` loop
    /// (window closed, app only in the menu bar).
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var wakeToken: NSObjectProtocol?
    @ObservationIgnored private var saveToken: NSObjectProtocol?
    @ObservationIgnored private let notifications = NotificationRouter()
    @ObservationIgnored private let path = NWPathMonitor()

    init(container: ModelContainer, navigation: AppNavigation) {
        context = container.mainContext
        self.navigation = navigation
        notifications.onOpen = { [weak self] id in self?.open(projectID: id) }
        UNUserNotificationCenter.current().delegate = notifications
    }

    /// Starts the 10-minute loop. Safe to call more than once.
    func start() {
        guard scheduler == nil else { return }
        refreshDownList()
        // First round shortly after launch; then every 10 minutes.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await self?.checkAll()
        }
        let scheduler = NSBackgroundActivityScheduler(identifier: "app.dotfolio.DotFolio.health")
        scheduler.repeats = true
        scheduler.interval = Self.interval
        scheduler.tolerance = 30
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.checkAll()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
        // After sleep the network takes a moment to come back.
        // Any save (project deleted, production URL changed or removed, Erase
        // All Data, autosave after an edit) refreshes the down list, so the
        // menu bar warning never outlives the site it was about.
        saveToken = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDownList() }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                await self?.checkAll()
            }
        }
        path.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        path.start(queue: DispatchQueue(label: "app.dotfolio.health.network"))
        if monitoredProjects().isEmpty == false { requestNotificationPermission() }
    }

    private func networkChanged(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        // Back online: don't wait up to 10 minutes. A short pause lets DNS settle.
        if online {
            Task {
                try? await Task.sleep(for: .seconds(3))
                await checkAll()
            }
        }
    }

    func isChecking(_ project: Project) -> Bool { checking.contains(project.id) }

    /// Check Now, or right after the production URL was saved.
    @discardableResult
    func check(_ project: Project) async -> Outcome {
        guard isOnline else { return .offline }
        guard let url = project.productionURL, !checking.contains(project.id) else { return .skipped }
        checking.insert(project.id)
        defer { checking.remove(project.id) }
        let answer = await checker.check(url)
        if answer.isOffline { return .offline }
        return record(answer, url: url, projectID: project.id).map(Outcome.checked) ?? .skipped
    }

    func checkAll() async {
        guard isOnline else { return }
        // Only Sendable values (id, URL) cross into the parallel requests;
        // results are written back here on the main actor.
        let targets = monitoredProjects()
            .filter { !checking.contains($0.id) }
            .compactMap { project in project.productionURL.map { (id: project.id, url: $0) } }
        guard !targets.isEmpty else { return }
        checking.formUnion(targets.map(\.id))
        let checker = self.checker
        for start in stride(from: 0, to: targets.count, by: Self.parallelChecks) {
            let batch = targets[start..<min(start + Self.parallelChecks, targets.count)]
            await withTaskGroup(of: (UUID, URL, HealthChecker.Answer).self) { group in
                for target in batch {
                    group.addTask { (target.id, target.url, await checker.check(target.url)) }
                }
                for await (id, url, answer) in group {
                    checking.remove(id)
                    record(answer, url: url, projectID: id)
                }
            }
        }
    }

    /// Stores an answer unless the project or its URL changed meanwhile, or
    /// the network dropped mid-check (that says nothing about the site).
    @discardableResult
    private func record(_ answer: HealthChecker.Answer, url: URL, projectID: UUID) -> HealthResult? {
        guard !answer.isOffline, let project = monitoredProjects().first(where: { $0.id == projectID }),
              project.productionURL == url else { return nil }
        let result = HealthResult(statusCode: answer.statusCode, responseTime: answer.responseTime, error: answer.error)
        apply(result, to: project)
        return result
    }

    func requestNotificationPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    // MARK: Private

    private func monitoredProjects() -> [Project] {
        let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return all.filter { $0.productionURL != nil }
    }

    private func apply(_ result: HealthResult, to project: Project) {
        if let event = project.recordHealth(result) { notify(event, project: project) }
        try? context.save()
        refreshDownList()
    }

    private func refreshDownList() {
        let names = monitoredProjects().filter { $0.health == .down }.map(\.name).sorted()
        // Saves are frequent; only redraw the menu bar icon when it changes.
        if names != downProjects { downProjects = names }
    }

    private func notify(_ event: HealthEvent, project: Project) {
        let site = project.productionDisplayName ?? project.name
        let content = UNMutableNotificationContent()
        switch event {
        case .wentDown(let reason):
            content.title = "\(project.name) is down"
            content.body = "\(site) · \(reason)"
            content.sound = .default
        case .recovered(let downtime):
            content.title = "\(project.name) is back up"
            content.body = "\(site) was down for \(DowntimeText.string(downtime))."
        }
        content.userInfo = ["projectID": project.id.uuidString]
        // Also kept under the toolbar bell, so a missed banner isn't lost.
        let kind: AppNotification.Kind = if case .wentDown = event { .siteDown } else { .siteRecovered }
        NotificationFeed.post(kind, title: content.title, body: content.body, projectID: project.id, context: context)
        let request = UNNotificationRequest(identifier: "health-\(project.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func open(projectID: UUID) {
        navigation.projectToOpen = projectID
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}

/// Shows banners while Dotfolio is in front, and opens the project on click.
private final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    @MainActor var onOpen: ((UUID) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["projectID"] as? String,
              let id = UUID(uuidString: text) else { return }
        await MainActor.run { onOpen?(id) }
    }
}

// MARK: - Formatting

enum HealthText {
    /// "240 ms", "1.4 s"
    static func responseTime(_ seconds: Double) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.1f s", seconds)
    }

    /// "14:20" today, "26 Nov, 14:20" before.
    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
