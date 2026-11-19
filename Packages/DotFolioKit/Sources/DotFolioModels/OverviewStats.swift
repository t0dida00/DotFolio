import Foundation

/// Numbers for the Overview dashboard, computed from metadata only
/// (never from secret values).
public struct OverviewStats {
    public struct ServiceUsage: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let variables: Int
        public let projects: Int
    }

    public struct EnvironmentCompleteness: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let withValue: Int
        public let total: Int
        public var fraction: Double { total == 0 ? 1 : Double(withValue) / Double(total) }
    }

    public struct AccountRank: Identifiable {
        public var id: String { account.login }
        public let account: Account
        public let services: Int
        public let projects: Int
        public let variables: Int
    }

    public struct ProjectAttention: Identifiable {
        public var id: String { project.id.uuidString }
        public let project: Project
        public let missing: Int
        public let total: Int
    }

    public let projectCount: Int
    public let repoProjectCount: Int
    public let variableCount: Int
    public let withValueCount: Int
    public var missingCount: Int { variableCount - withValueCount }
    /// No service, account, service project or link: "where does this come from?" unanswered.
    public let noSourceCount: Int
    /// Stored values not updated for `staleAfter` days: candidates for rotation.
    public let staleCount: Int
    public let accountCount: Int
    /// Distinct services across variables and accounts.
    public let serviceCount: Int
    /// Usage by provider (Supabase, Redis…).
    public let services: [ServiceUsage]
    /// Usage by service category (Database, Cache…), incl. guesses from the provider.
    public let categories: [ServiceUsage]
    public let environments: [EnvironmentCompleteness]
    public let accountRanking: [AccountRank]
    public let attention: [ProjectAttention]
    public let recentlyUpdated: [Variable]

    public var valueCoverage: Double { variableCount == 0 ? 1 : Double(withValueCount) / Double(variableCount) }
    public var sourceCoverage: Double { variableCount == 0 ? 1 : Double(variableCount - noSourceCount) / Double(variableCount) }

    public init(projects: [Project], accounts: [Account], now: Date = .now, staleAfterDays: Int = 90) {
        let variables = projects.flatMap(\.allVariables)
        projectCount = projects.count
        repoProjectCount = projects.filter { $0.provider != .none }.count
        variableCount = variables.count
        withValueCount = variables.filter(\.hasValue).count
        noSourceCount = variables.filter {
            $0.displayService.isEmpty && $0.account == nil && $0.serviceProject == nil && $0.sourceURL == nil
        }.count
        let cutoff = now.addingTimeInterval(-Double(staleAfterDays) * 86_400)
        staleCount = variables.filter { $0.hasValue && $0.updatedAt < cutoff }.count
        accountCount = accounts.count

        // Services: usage by variables (case-insensitive), plus services only listed on accounts.
        var byService: [String: (name: String, vars: Int, projects: Set<UUID>)] = [:]
        for v in variables {
            let name = v.displayService
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            var entry = byService[key] ?? (name, 0, [])
            entry.vars += 1
            if let p = v.project { entry.projects.insert(p.id) }
            byService[key] = entry
        }
        var allServiceKeys = Set(byService.keys)
        for a in accounts { a.services.forEach { allServiceKeys.insert($0.lowercased()) } }
        serviceCount = allServiceKeys.count
        services = byService.values
            .map { ServiceUsage(name: $0.name, variables: $0.vars, projects: $0.projects.count) }
            .sorted { ($0.variables, $1.name) > ($1.variables, $0.name) }

        var byCategory: [String: (name: String, vars: Int, projects: Set<UUID>)] = [:]
        for v in variables {
            let name = v.displayCategory
            guard !name.isEmpty else { continue }
            var entry = byCategory[name.lowercased()] ?? (name, 0, [])
            entry.vars += 1
            if let p = v.project { entry.projects.insert(p.id) }
            byCategory[name.lowercased()] = entry
        }
        categories = byCategory.values
            .map { ServiceUsage(name: $0.name, variables: $0.vars, projects: $0.projects.count) }
            .sorted { ($0.variables, $1.name) > ($1.variables, $0.name) }

        // Environments grouped by name, standard ones first.
        var byEnv: [String: (set: Int, total: Int)] = [:]
        for v in variables {
            guard let name = v.environment?.name else { continue }
            var e = byEnv[name] ?? (0, 0)
            e.total += 1
            if v.hasValue { e.set += 1 }
            byEnv[name] = e
        }
        let order = ProjectEnvironment.defaultNames
        environments = byEnv
            .map { EnvironmentCompleteness(name: $0.key, withValue: $0.value.set, total: $0.value.total) }
            .sorted { a, b in
                let ia = order.firstIndex(of: a.name) ?? order.count, ib = order.firstIndex(of: b.name) ?? order.count
                return ia == ib ? a.name < b.name : ia < ib
            }

        accountRanking = accounts
            .map { AccountRank(account: $0, services: $0.services.count, projects: $0.linkedProjects.count,
                               variables: $0.allLinkedVariables.count) }
            .sorted { ($0.services, $0.projects, $0.variables) > ($1.services, $1.projects, $1.variables) }

        attention = projects
            .map { p in ProjectAttention(project: p, missing: p.allVariables.filter { !$0.hasValue }.count, total: p.allVariables.count) }
            .filter { $0.missing > 0 }
            .sorted { $0.missing > $1.missing }
            .prefix(5).map { $0 }

        recentlyUpdated = Array(variables.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }
}
