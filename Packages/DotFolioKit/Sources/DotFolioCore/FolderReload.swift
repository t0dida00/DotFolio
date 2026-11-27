import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// "Reload from Folder" for a local project: read its `.env*` files again
/// and show what changed since the import, environment by environment, so
/// the user picks what to apply. Nothing is written until `apply`.
///
/// Files map to environments by name, like the import (`.env.production` →
/// production; `.env` and `.env.local` → development). Example files and
/// names Dotfolio can't place are listed as ignored. An environment with no
/// file is left alone.
public enum FolderReload {
    /// One `.env*` file read from the folder.
    public struct File: Sendable {
        public var path: String
        public var entries: [EnvEntry]

        public init(path: String, entries: [EnvEntry]) {
            self.path = path
            self.entries = entries
        }

        var fileName: String { (path as NSString).lastPathComponent }
    }

    public struct Change {
        public let environment: ProjectEnvironment
        public let files: [String]
        /// Removals included; the sheet leaves them unticked.
        public let plan: EnvFileEdit.Plan
    }

    public struct Result {
        public var changes: [Change] = []
        /// Files not used: examples (names only) and names with no environment.
        public var ignored: [String] = []
        /// Environments a file was found for, even when nothing changed.
        public var checked: [String] = []

        public var isEmpty: Bool { changes.isEmpty }
    }

    /// - Parameter currentValues: the plaintext of the project's stored values
    ///   (read with Touch ID), so an unchanged value isn't reported as changed.
    @MainActor
    public static func compare(_ project: Project, files: [File], currentValues: [UUID: String]) -> Result {
        var result = Result()
        var byEnvironment: [String: [File]] = [:]
        for file in files {
            switch EnvFileImport.kind(forFileName: file.fileName) {
            case .environment(let name): byEnvironment[name, default: []].append(file)
            case .template, .unknown: result.ignored.append(file.path)
            }
        }
        for environment in project.sortedEnvironments {
            guard let files = byEnvironment[environment.name], !files.isEmpty else { continue }
            result.checked.append(environment.name)
            // Later files win, like dotenv loaders (.env.local over .env).
            let merged = FolderImport.merge(files.map { FolderImport.Source(relativePath: $0.path, entries: $0.entries,
                                                                            environment: environment.name) },
                                            environments: [environment.name])
            let entries = (merged.rowsByEnvironment[environment.name] ?? []).map { row in
                EnvEntry(key: row.key, value: row.value,
                         inlineComment: EnvSource(service: row.category, provider: row.service,
                                                  account: row.account, link: row.link).comment)
            }
            var plan = EnvFileEdit.plan(entries: entries, for: environment, currentValues: currentValues)
            // A line without a #Service/Provider/… comment keeps the source the app has.
            for entry in entries where entry.source.isEmpty { plan.sources[entry.key] = nil }
            if !plan.isEmpty {
                result.changes.append(Change(environment: environment, files: files.map(\.path), plan: plan))
            }
        }
        // Names in a file for an environment the project doesn't have.
        let known = Set(project.sortedEnvironments.map(\.name))
        for (name, files) in byEnvironment where !known.contains(name) { result.ignored += files.map(\.path) }
        result.ignored.sort()
        return result
    }

    /// Applies one environment's plan without the removals the user didn't tick.
    @MainActor
    public static func apply(_ change: Change, removing: Set<String>, context: ModelContext,
                             secrets: any SecretStore) throws(EnvFileEdit.Failure) {
        var plan = change.plan
        plan.removed = plan.removed.filter(removing.contains)
        try EnvFileEdit.apply(plan, to: change.environment, context: context, secrets: secrets)
    }
}
