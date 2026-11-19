import Foundation
import SwiftData

/// How the home screen orders projects.
public enum ProjectSort: String, CaseIterable, Identifiable, Sendable {
    case name
    case recentlyOpened
    case dateAdded

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: "Name"
        case .recentlyOpened: "Recently Opened"
        case .dateAdded: "Date Added"
        }
    }
}

/// Global search over metadata only. SECURITY: secret values are never
/// searched; they live in the Keychain and are not loaded here.
public enum ProjectSearch {
    /// Why a project matched, so the UI can say e.g. "Matches FIREBASE_API_KEY".
    public enum Match: Equatable, Sendable {
        case name
        case repo(String)
        case variableKey(String)
        case account(String)
        case service(String)
    }

    /// Returns the first (most relevant) reason `project` matches `query`, or
    /// nil. Case- and diacritic-insensitive. An empty query matches by name.
    public static func match(_ project: Project, query: String) -> Match? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .name }
        func hit(_ text: String) -> Bool { !text.isEmpty && text.localizedStandardContains(q) }

        if hit(project.name) { return .name }
        if hit(project.repoFullName) { return .repo(project.repoFullName) }

        let variables = project.allVariables
        if let v = variables.first(where: { hit($0.key) }) { return .variableKey(v.key) }
        if let v = variables.first(where: { hit($0.serviceLabel) }) { return .service(v.serviceLabel) }
        if let v = variables.first(where: { hit($0.serviceCategory) }) { return .service(v.serviceCategory) }

        for usage in project.sourceUsages {
            let account = usage.account
            if hit(account.login) { return .account(account.login) }
            if hit(account.displayName) { return .account(account.displayName) }
            if let service = account.services.first(where: hit) { return .service(service) }
            if let sp = usage.serviceProject {
                if hit(sp.name) { return .service(sp.name) }
                if hit(sp.externalID) { return .service(sp.externalID) }
            }
        }
        return nil
    }

    public static func filter(_ projects: [Project], query: String) -> [(project: Project, match: Match)] {
        projects.compactMap { p in match(p, query: query).map { (p, $0) } }
    }

    public static func sorted(_ projects: [Project], by sort: ProjectSort) -> [Project] {
        projects.sorted { a, b in
            switch sort {
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .recentlyOpened:
                // Never-opened projects go last, then by name.
                switch (a.lastOpenedAt, b.lastOpenedAt) {
                case let (x?, y?): return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            case .dateAdded:
                return a.createdAt > b.createdAt
            }
        }
    }

    /// Up to `limit` most recently opened projects.
    public static func recent(_ projects: [Project], limit: Int = 3) -> [Project] {
        Array(sorted(projects.filter { $0.lastOpenedAt != nil }, by: .recentlyOpened).prefix(limit))
    }
}

extension Project {
    /// Creates a project with the three standard environments; production is
    /// protected (asks for confirmation on export).
    @discardableResult
    public static func create(name: String, summary: String = "", link: URL? = nil, in context: ModelContext) -> Project {
        let project = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        project.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        project.repoURL = link
        if let link, let repo = RepoLink(url: link) {
            project.provider = repo.provider
            project.repoFullName = repo.fullName
        }
        context.insert(project)
        for (index, envName) in ProjectEnvironment.defaultNames.enumerated() {
            let env = ProjectEnvironment(name: envName, sortOrder: index, isProtected: envName == "production", project: project)
            context.insert(env)
        }
        return project
    }

    /// True when deleting would leave Keychain items behind unless they are
    /// removed first (the caller must go through the secret store).
    public var hasStoredSecrets: Bool {
        allVariables.contains { $0.hasValue }
    }
}
