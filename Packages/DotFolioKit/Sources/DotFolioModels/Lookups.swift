import Foundation
import SwiftData

/// The full schema, shared by the app, the menu bar extra and (later) the CLI.
public enum DotFolioSchema {
    public static let models: [any PersistentModel.Type] = [
        Account.self, ServiceProject.self, Project.self, ProjectEnvironment.self, Variable.self,
    ]

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: config)
    }
}

// MARK: - Library

public enum Library {
    /// Every library key, sorted by provider then name.
    @MainActor
    public static func keys(context: ModelContext) -> [Variable] {
        let all = (try? context.fetch(FetchDescriptor<Variable>(predicate: #Predicate { $0.inLibrary }))) ?? []
        return all.sorted {
            $0.serviceLabel.lowercased() == $1.serviceLabel.lowercased()
                ? $0.key.localizedStandardCompare($1.key) == .orderedAscending
                : $0.serviceLabel.localizedStandardCompare($1.serviceLabel) == .orderedAscending
        }
    }

    /// Library keys of one provider (case-insensitive; "" = no provider).
    @MainActor
    public static func keys(provider: String, context: ModelContext) -> [Variable] {
        keys(context: context).filter { $0.serviceLabel.caseInsensitiveCompare(provider) == .orderedSame }
    }

    /// Search over metadata only (never values): key, provider, service,
    /// account, notes, and the project a project key belongs to.
    public static func filter(_ keys: [Variable], query: String) -> [Variable] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return keys }
        return keys.filter { v in
            [v.key, v.serviceLabel, v.displayCategory, v.account?.login ?? "", v.notes, v.environment?.project?.name ?? ""]
                .contains { !$0.isEmpty && $0.localizedStandardContains(q) }
        }
    }

    // MARK: Library view (Library keys + every project's keys)

    /// What the Library shows: its own keys plus every project variable, one
    /// row per environment. Project keys are not copies — they are the
    /// project's variables, so deleting a project removes them here too and
    /// a Library key with the same name is never touched.
    public static func everything(libraryKeys: [Variable], projectVariables: [Variable]) -> [Variable] {
        (libraryKeys.filter(\.inLibrary) + projectVariables.filter { !$0.inLibrary && $0.environment?.project != nil })
            .sorted(by: displayOrder)
    }

    /// Inside a provider: Library keys first, then project keys; each by
    /// name, then project, then environment order (development → production).
    public static func displayOrder(_ a: Variable, _ b: Variable) -> Bool {
        if a.inLibrary != b.inLibrary { return a.inLibrary }
        let byKey = a.key.localizedStandardCompare(b.key)
        if byKey != .orderedSame { return byKey == .orderedAscending }
        let pa = a.environment?.project?.name ?? "", pb = b.environment?.project?.name ?? ""
        let byProject = pa.localizedStandardCompare(pb)
        if byProject != .orderedSame { return byProject == .orderedAscending }
        return (a.environment?.sortOrder ?? 0) < (b.environment?.sortOrder ?? 0)
    }

    /// "Library" or "Shop · production".
    public static func origin(of v: Variable) -> String {
        guard !v.inLibrary, let env = v.environment else { return "Library" }
        return "\(env.project?.name ?? "Project") · \(env.name)"
    }
}

// MARK: - Variable linking

extension Variable {
    /// Links this variable to a source while keeping the account/serviceProject
    /// invariant. Passing a service project implies its account.
    public func link(account: Account?, serviceProject: ServiceProject?) {
        if let serviceProject {
            self.serviceProject = serviceProject
            self.account = serviceProject.account ?? account
        } else {
            self.serviceProject = nil
            self.account = account
        }
        updatedAt = .now
    }

    public var project: Project? { environment?.project }

    /// What the Service column shows: the chosen category, else one guessed
    /// from the provider ("Redis" → Cache), else "".
    public var displayCategory: String {
        if !serviceCategory.isEmpty { return serviceCategory }
        return ServiceCategory.suggested(forProvider: displayService)?.displayName ?? ""
    }

    /// What the Provider column shows: the typed provider, else the
    /// service project's / single-service account's provider.
    public var displayService: String {
        if !serviceLabel.isEmpty { return serviceLabel }
        if let sp = serviceProject, !sp.serviceName.isEmpty { return sp.serviceName }
        // Only unambiguous when the account has a single service.
        if let services = account?.services, services.count == 1 { return services[0] }
        return ""
    }
}

// MARK: - "Which account / service project does Project A use?"

/// One source (account + optional service project) used by a project, with the
/// variables that come from it, grouped across environments.
public struct SourceUsage: Identifiable {
    public let account: Account
    public let serviceProject: ServiceProject?
    public let variables: [Variable]

    public var id: String {
        "\(account.id.uuidString)/\(serviceProject?.id.uuidString ?? "-")"
    }
}

/// Where a project comes from, shown as its tile. Only `.local` projects have
/// a folder on this Mac whose .env files DOTFOLIO can read (and later sync).
public enum ProjectOrigin: Sendable {
    /// Linked to a folder on this Mac (dropped, or chosen as Local folder).
    case local
    case github
    case gitlab
    /// Made by hand, no repo and no folder.
    case manual
}

extension Project {
    /// `importedFrom` of projects created from a dropped folder. Sign-out of a
    /// repo host never removes them, even when their repo is on that host.
    public static let folderImportTag = "folder"

    public var origin: ProjectOrigin {
        if localFolderBookmark != nil { return .local }
        switch provider {
        case .github: return .github
        case .gitlab: return .gitlab
        case .none: return .manual
        }
    }

    public var allVariables: [Variable] {
        (environments ?? []).flatMap { $0.variables ?? [] }
    }

    /// Sources used by this project, grouped by (account, serviceProject).
    public var sourceUsages: [SourceUsage] {
        var groups: [String: (Account, ServiceProject?, [Variable])] = [:]
        var order: [String] = []
        for variable in allVariables {
            guard let account = variable.account ?? variable.serviceProject?.account else { continue }
            let key = "\(account.id.uuidString)/\(variable.serviceProject?.id.uuidString ?? "-")"
            if groups[key] == nil {
                groups[key] = (account, variable.serviceProject, [])
                order.append(key)
            }
            groups[key]!.2.append(variable)
        }
        return order.map { key in
            let (account, serviceProject, variables) = groups[key]!
            return SourceUsage(account: account, serviceProject: serviceProject, variables: variables)
        }
    }

    public var linkedAccounts: [Account] {
        uniqued(sourceUsages.map(\.account))
    }
}

// MARK: - "Which of my projects use this account?"

extension Account {
    /// Variables linked to this account directly or through one of its service projects.
    public var allLinkedVariables: [Variable] {
        let direct = variables ?? []
        let viaServiceProjects = (serviceProjects ?? []).flatMap { $0.variables ?? [] }
        return uniqued(direct + viaServiceProjects)
    }

    public var linkedProjects: [Project] {
        uniqued(allLinkedVariables.compactMap(\.project))
    }
}

extension ServiceProject {
    public var linkedProjects: [Project] {
        uniqued((variables ?? []).compactMap(\.project))
    }
}

private func uniqued<T: PersistentModel>(_ items: [T]) -> [T] {
    var seen = Set<PersistentIdentifier>()
    return items.filter { seen.insert($0.persistentModelID).inserted }
}

/// Every key that uses an account (directly or through one of its provider
/// projects): per project (name order) and environment (environment order),
/// then the Library keys. Keys are sorted by name.
@MainActor
public struct AccountKeys {
    public struct EnvironmentKeys: Identifiable {
        public let environment: ProjectEnvironment
        public let keys: [Variable]
        public var id: PersistentIdentifier { environment.persistentModelID }
    }

    public struct ProjectKeys: Identifiable {
        public let project: Project
        public let environments: [EnvironmentKeys]
        public var id: PersistentIdentifier { project.persistentModelID }
        public var count: Int { environments.reduce(0) { $0 + $1.keys.count } }
    }

    public let projects: [ProjectKeys]
    public let library: [Variable]

    public var isEmpty: Bool { projects.isEmpty && library.isEmpty }
    public var count: Int { projects.reduce(0) { $0 + $1.count } + library.count }

    public init(account: Account) {
        let keys = account.allLinkedVariables.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        library = keys.filter(\.inLibrary)

        var byEnvironment: [PersistentIdentifier: [Variable]] = [:]
        var projectsByID: [PersistentIdentifier: Project] = [:]
        for key in keys where !key.inLibrary {
            guard let environment = key.environment, let project = environment.project else { continue }
            byEnvironment[environment.persistentModelID, default: []].append(key)
            projectsByID[project.persistentModelID] = project
        }
        projects = projectsByID.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { project in
                ProjectKeys(project: project, environments: project.sortedEnvironments.compactMap { env in
                    byEnvironment[env.persistentModelID].map { EnvironmentKeys(environment: env, keys: $0) }
                })
            }
    }
}

/// The All · Git · Local switch under Projects.
public enum ProjectOriginFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    /// Imported from GitHub or GitLab (no folder on this Mac).
    case git
    /// Linked to a folder on this Mac.
    case local

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .git: "Git"
        case .local: "Local"
        }
    }

    public func matches(_ project: Project) -> Bool {
        switch self {
        case .all: true
        case .git: project.origin == .github || project.origin == .gitlab
        case .local: project.origin == .local
        }
    }
}
