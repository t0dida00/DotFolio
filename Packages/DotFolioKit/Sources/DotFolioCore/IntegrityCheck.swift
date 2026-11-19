import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Cross-checks the database against the Keychain and the model's own rules.
/// Reads Keychain attributes only (never values), so no Touch ID is needed.
public enum IntegrityCheck {
    public struct DuplicateKey: Hashable, Sendable {
        public let project: String
        public let environment: String
        public let key: String
    }

    public struct Report {
        /// Marked "has value" but the Keychain item is gone.
        public var missingSecrets: [Variable] = []
        /// Keychain items no variable points at (left behind by a crash or bug).
        public var orphanedSecretRefs: [String] = []
        /// Same name twice in one environment (shown, not auto-fixed).
        public var duplicateKeys: [DuplicateKey] = []
        /// Variables without an environment, environments without a project.
        public var orphanVariables: [Variable] = []
        public var orphanEnvironments: [ProjectEnvironment] = []
        /// Provider projects whose account is gone.
        public var orphanServiceProjects: [ServiceProject] = []
        /// Accounts listing a service category ("Database") as a provider.
        public var accountsWithCategoryWords: [Account] = []

        /// Issues `repair` can fix.
        public var fixableCount: Int {
            missingSecrets.count + orphanedSecretRefs.count + orphanVariables.count
                + orphanEnvironments.count + orphanServiceProjects.count + accountsWithCategoryWords.count
        }
        public var issueCount: Int { fixableCount + duplicateKeys.count }
        public var isClean: Bool { issueCount == 0 }
    }

    @MainActor
    public static func run(context: ModelContext, secrets: any SecretStore) throws -> Report {
        var report = Report()
        let variables = try context.fetch(FetchDescriptor<Variable>())
        let environments = try context.fetch(FetchDescriptor<ProjectEnvironment>())
        let serviceProjects = try context.fetch(FetchDescriptor<ServiceProject>())
        let accounts = try context.fetch(FetchDescriptor<Account>())

        let stored = Set(try secrets.allRefs())
        let referenced = Set(variables.filter(\.hasValue).map(\.secretRef.uuidString))
        report.missingSecrets = variables.filter { $0.hasValue && !stored.contains($0.secretRef.uuidString) }
        report.orphanedSecretRefs = stored.subtracting(referenced).sorted()

        for env in environments {
            var seen = Set<String>()
            for v in env.variables ?? [] where !seen.insert(v.key).inserted {
                report.duplicateKeys.append(.init(project: env.project?.name ?? "?", environment: env.name, key: v.key))
            }
        }
        report.duplicateKeys = Array(Set(report.duplicateKeys)).sorted { ($0.project, $0.environment, $0.key) < ($1.project, $1.environment, $1.key) }

        report.orphanVariables = variables.filter { $0.environment == nil }
        report.orphanEnvironments = environments.filter { $0.project == nil }
        report.orphanServiceProjects = serviceProjects.filter { $0.account == nil }
        report.accountsWithCategoryWords = accounts.filter { account in
            account.services.contains { ServiceType(matching: $0) == nil && ServiceCategory(matching: $0) != nil }
        }
        return report
    }

    /// Fixes what can be fixed safely and returns how many issues were fixed.
    /// SECURITY: orphaned Keychain items are deleted; orphan variables lose
    /// their Keychain item before their metadata. Duplicate names are left
    /// for the user (which one is right is their call).
    @MainActor
    @discardableResult
    public static func repair(_ report: Report, context: ModelContext, secrets: any SecretStore) throws -> Int {
        var fixed = 0
        for v in report.missingSecrets { v.hasValue = false; fixed += 1 }
        for ref in report.orphanedSecretRefs { try secrets.delete(ref); fixed += 1 }
        for v in report.orphanVariables {
            if v.hasValue { try secrets.delete(v.secretRef.uuidString) }
            context.delete(v)
            fixed += 1
        }
        for env in report.orphanEnvironments {
            for v in env.variables ?? [] where v.hasValue { try secrets.delete(v.secretRef.uuidString) }
            context.delete(env)
            fixed += 1
        }
        for sp in report.orphanServiceProjects { context.delete(sp); fixed += 1 }
        if !report.accountsWithCategoryWords.isEmpty {
            ServiceCategoryMigration.run(context: context)
            fixed += report.accountsWithCategoryWords.count
        }
        try context.save()
        return fixed
    }
}
