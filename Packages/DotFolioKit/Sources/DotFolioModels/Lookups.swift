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

    /// Search over metadata only (never values): key, provider, service, account, notes.
    public static func filter(_ keys: [Variable], query: String) -> [Variable] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return keys }
        return keys.filter { v in
            [v.key, v.serviceLabel, v.displayCategory, v.account?.login ?? "", v.notes]
                .contains { !$0.isEmpty && $0.localizedStandardContains(q) }
        }
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

extension Project {
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
