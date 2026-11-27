import Foundation

/// Whether a project's production site answers, from the last check.
public enum HealthStatus: Equatable, Sendable {
    /// No production URL, or not checked yet.
    case unknown
    case up
    /// Answers, but slower than `slowThreshold`. Still counts as up.
    case slow
    case down

    /// Seconds after which an answer counts as slow.
    public static let slowThreshold: Double = 3

    /// 401 (login), 403 (Cloudflare and other firewalls block unknown
    /// clients), 429 (rate limited): the server is up, just not for us.
    public static let protectedCodes: Set<Int> = [401, 403, 429]

    public static func isAnswering(_ code: Int) -> Bool {
        (200..<400).contains(code) || protectedCodes.contains(code)
    }
}

/// What one check of a production URL found (from `HealthChecker`).
public struct HealthResult: Equatable, Sendable {
    /// HTTP status, nil when nothing answered (timeout, DNS, TLS…).
    public var statusCode: Int?
    /// Seconds until the response arrived, nil without one.
    public var responseTime: Double?
    /// Why the site counts as down: "Timed out", "HTTP 503"… Nil when up.
    public var error: String?

    public init(statusCode: Int?, responseTime: Double?, error: String?) {
        self.statusCode = statusCode
        self.responseTime = responseTime
        self.error = error
    }

    /// 2xx/3xx, or a server that answers but won't show the page (login,
    /// firewall, rate limit). 404, 5xx or no answer is down.
    public var isUp: Bool { statusCode.map(HealthStatus.isAnswering) ?? false }
}

/// A change worth a notification. Repeated results of the same state say nothing.
public enum HealthEvent: Equatable, Sendable {
    case wentDown(reason: String)
    /// Back up after being down for `downtime` seconds.
    case recovered(downtime: TimeInterval)
}

extension Project {
    public var health: HealthStatus {
        guard productionURL != nil, healthCheckedAt != nil else { return .unknown }
        if healthDownSince != nil { return .down }
        if let time = healthResponseTime, time > HealthStatus.slowThreshold { return .slow }
        return .up
    }

    /// Stores a check's result and says whether the site changed state.
    /// The first check of a URL never announces "recovered"; a first check
    /// that fails does announce "down".
    @discardableResult
    public func recordHealth(_ result: HealthResult, at date: Date = .now) -> HealthEvent? {
        let wasDown = healthDownSince
        healthCheckedAt = date
        healthStatusCode = result.statusCode
        healthResponseTime = result.responseTime
        healthError = result.isUp ? nil : (result.error ?? result.statusCode.map { "HTTP \($0)" } ?? "No response")

        if result.isUp {
            if healthUpSince == nil || wasDown != nil { healthUpSince = date }
            healthDownSince = nil
            return wasDown.map { .recovered(downtime: date.timeIntervalSince($0)) }
        }
        guard wasDown == nil else { return nil }
        healthUpSince = nil
        healthDownSince = date
        return .wentDown(reason: healthError ?? "No response")
    }

    /// Forgets the last check (the URL changed or was removed).
    public func clearHealth() {
        healthCheckedAt = nil
        healthStatusCode = nil
        healthResponseTime = nil
        healthError = nil
        healthDownSince = nil
        healthUpSince = nil
    }

    /// How long the current state has lasted (up or down), nil when unknown.
    public func healthDuration(now: Date = .now) -> TimeInterval? {
        switch health {
        case .up, .slow: healthUpSince.map { now.timeIntervalSince($0) }
        case .down: healthDownSince.map { now.timeIntervalSince($0) }
        case .unknown: nil
        }
    }

    /// "liabeauty.com" or "liabeauty.com/shop": what the header shows.
    public var productionDisplayName: String? {
        guard let url = productionURL, let host = url.host() else { return nil }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path()
        return path.isEmpty || path == "/" ? bareHost : bareHost + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }
}

/// "23 min", "2 h 5 min", "3 d 4 h": how long a site was down.
public enum DowntimeText {
    public static func string(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, restMinutes = minutes % 60
        if hours < 24 { return restMinutes == 0 ? "\(hours) h" : "\(hours) h \(restMinutes) min" }
        let days = hours / 24, restHours = hours % 24
        return restHours == 0 ? "\(days) d" : "\(days) d \(restHours) h"
    }
}

/// Overview's "Production uptime": counts and one row per monitored project,
/// down first (longest outage on top), then slow, not checked, up.
public struct UptimeSummary {
    public let up: Int
    public let slow: Int
    public let down: Int
    public let unchecked: Int
    public let projects: [Project]

    @MainActor
    public init(projects all: [Project]) {
        let monitored = all.filter { $0.productionURL != nil }
        up = monitored.count { $0.health == .up }
        slow = monitored.count { $0.health == .slow }
        down = monitored.count { $0.health == .down }
        unchecked = monitored.count { $0.health == .unknown }
        func rank(_ p: Project) -> Int {
            switch p.health { case .down: 0; case .slow: 1; case .unknown: 2; case .up: 3 }
        }
        projects = monitored.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.health == .down, let x = a.healthDownSince, let y = b.healthDownSince, x != y { return x < y }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    public var total: Int { projects.count }

    /// Status filter above the list ("All", "Down"…).
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all, down, slow, up, unchecked
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: "All"
            case .down: "Down"
            case .slow: "Slow"
            case .up: "Up"
            case .unchecked: "Not checked"
            }
        }

        public var status: HealthStatus? {
            switch self {
            case .all: nil
            case .down: .down
            case .slow: .slow
            case .up: .up
            case .unchecked: .unknown
            }
        }
    }

    public func count(_ filter: Filter) -> Int {
        switch filter {
        case .all: total
        case .down: down
        case .slow: slow
        case .up: up
        case .unchecked: unchecked
        }
    }

    /// Filters that have something to show: always "All", then each
    /// status with at least one project.
    public var availableFilters: [Filter] {
        Filter.allCases.filter { $0 == .all || count($0) > 0 }
    }

    @MainActor
    public func projects(_ filter: Filter) -> [Project] {
        guard let status = filter.status else { return projects }
        return projects.filter { $0.health == status }
    }
}
