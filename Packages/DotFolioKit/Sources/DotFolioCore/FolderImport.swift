import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Turning the `.env*` files of a dropped project folder into a project (or
/// into the project already linked to that folder).
public enum FolderImport {
    /// One file the user ticked in the import sheet.
    public struct Source: Sendable {
        public var relativePath: String
        public var entries: [EnvEntry]
        /// Environment the values go to; nil = names only, in every environment
        /// (what `.env.example` is for).
        public var environment: String?

        public init(relativePath: String, entries: [EnvEntry], environment: String?) {
            self.relativePath = relativePath
            self.entries = entries
            self.environment = environment
        }
    }

    /// A name set to different values by two files of the same environment.
    public struct Conflict: Equatable, Sendable {
        public let environment: String
        public let key: String
        /// The file whose value is kept (the later one).
        public let keptFrom: String
    }

    public struct Merged {
        public var rowsByEnvironment: [String: [EnvDraftRow]] = [:]
        public var conflicts: [Conflict] = []

        /// Distinct names over every environment.
        public var nameCount: Int { Set(rowsByEnvironment.values.flatMap { $0.map(\.key) }).count }
    }

    /// Merges the files in the order given (the sheet's order: the dropped
    /// folder first, then by path). A later file wins for a value — `.env.local`
    /// overrides `.env`, like dotenv loaders do. Source fields
    /// (`#Service/Provider/Account/Link`) fill in what is still empty. Names-only
    /// files add their names to every environment without a value.
    public static func merge(_ sources: [Source], environments: [String] = ProjectEnvironment.defaultNames) -> Merged {
        var merged = Merged()
        for source in sources {
            let targets = source.environment.map { [$0] } ?? environments
            for env in targets {
                var rows = merged.rowsByEnvironment[env] ?? []
                for entry in source.entries {
                    let value = source.environment == nil ? "" : entry.value
                    let s = entry.source
                    // A link that isn't a web address is dropped rather than blocking the import.
                    let link = InputValidation.webURL(s.link) == nil ? "" : s.link
                    if let i = rows.firstIndex(where: { $0.key == entry.key }) {
                        if !value.isEmpty {
                            if !rows[i].value.isEmpty, rows[i].value != value {
                                merged.conflicts.removeAll { $0.environment == env && $0.key == entry.key }
                                merged.conflicts.append(Conflict(environment: env, key: entry.key, keptFrom: source.relativePath))
                            }
                            rows[i].value = value
                        }
                        fillEmpty(&rows[i].category, s.service)
                        fillEmpty(&rows[i].service, s.provider)
                        fillEmpty(&rows[i].account, s.account)
                        fillEmpty(&rows[i].link, link)
                    } else {
                        rows.append(EnvDraftRow(key: entry.key, value: value, category: s.service,
                                                service: s.provider, account: s.account, link: link))
                    }
                }
                merged.rowsByEnvironment[env] = rows
            }
        }
        return merged
    }

    private static func fillEmpty(_ field: inout String, _ new: String) {
        if field.trimmingCharacters(in: .whitespaces).isEmpty, !new.isEmpty { field = new }
    }

    /// The New Project draft for `merged`; `ProjectCreator.create` saves it
    /// (values to the Keychain first).
    public static func draft(name: String, link: URL?, merged: Merged) -> ProjectDraft {
        var draft = ProjectDraft()
        draft.name = name
        draft.link = link?.absoluteString ?? ""
        draft.rowsByEnvironment = merged.rowsByEnvironment
        return draft
    }

    /// Creates the project from a folder (values to the Keychain first) and
    /// tags it as a folder import, so signing out of GitHub never deletes it.
    @MainActor
    @discardableResult
    public static func createProject(name: String, link: URL?, merged: Merged, folderBookmark: Data?,
                                     context: ModelContext, secrets: any SecretStore) throws -> Project {
        let project = try ProjectCreator.create(draft(name: name, link: link, merged: merged), includeValues: true,
                                                context: context, secrets: secrets)
        project.importedFrom = Project.folderImportTag
        project.localFolderBookmark = folderBookmark
        return project
    }

    /// Names that would stop `ProjectCreator.create` (invalid env names, bad links).
    public static func problems(in merged: Merged) -> [String] {
        var draft = ProjectDraft()
        draft.name = "x"
        draft.rowsByEnvironment = merged.rowsByEnvironment
        var out: [String] = []
        for env in draft.environmentsWithRows {
            for row in draft.filledRows(in: env) {
                if let issue = draft.keyIssue(for: row, in: env) { out.append("\(row.key): \(issue)") }
                else if let issue = draft.linkIssue(for: row) { out.append("\(row.key): \(issue)") }
            }
        }
        return Array(Set(out)).sorted()
    }

    // MARK: Files dropped on one environment

    /// One dropped `.env` file. Templates (`.env.example`) bring names only.
    public struct DroppedFile: Sendable {
        public var name: String
        public var entries: [EnvEntry]
        public var isTemplate: Bool

        public init(name: String, entries: [EnvEntry], isTemplate: Bool) {
            self.name = name
            self.entries = entries
            self.isTemplate = isTemplate
        }
    }

    /// Adds dropped files to one environment, whatever their names say (the
    /// user dropped them there). Later files win; nothing already in the
    /// environment is overwritten — see `add(_:to:context:secrets:)`.
    @MainActor
    @discardableResult
    public static func add(_ files: [DroppedFile], to environment: ProjectEnvironment, context: ModelContext,
                           secrets: any SecretStore) throws(VariableEditor.Failure) -> AddResult {
        guard let project = environment.project else { return AddResult() }
        let merged = merge(files.map { Source(relativePath: $0.name, entries: $0.entries,
                                              environment: $0.isTemplate ? nil : environment.name) },
                           environments: [environment.name])
        return try add(merged, to: project, context: context, secrets: secrets)
    }

    // MARK: Into an existing project

    public struct AddResult: Equatable, Sendable {
        /// Names of new variables, in file order.
        public var addedKeys: [String] = []
        /// Existing variables that got a value or source they didn't have.
        public var filledKeys: [String] = []
        /// Already there with nothing to fill: left as they were.
        public var unchangedKeys: [String] = []

        public init(addedKeys: [String] = [], filledKeys: [String] = [], unchangedKeys: [String] = []) {
            self.addedKeys = addedKeys
            self.filledKeys = filledKeys
            self.unchangedKeys = unchangedKeys
        }

        public var added: Int { addedKeys.count }
        public var filled: Int { filledKeys.count }
        /// Nothing was added or filled.
        public var changedNothing: Bool { addedKeys.isEmpty && filledKeys.isEmpty }
    }

    /// Adds the files to a project that already exists. Never overwrites: a
    /// name already there only gets an empty value or empty source fields
    /// filled. Environments the project doesn't have are skipped.
    @MainActor
    @discardableResult
    public static func add(_ merged: Merged, to project: Project, context: ModelContext,
                           secrets: any SecretStore) throws(VariableEditor.Failure) -> AddResult {
        var result = AddResult()
        for environment in project.sortedEnvironments {
            for row in merged.rowsByEnvironment[environment.name] ?? [] where !row.isBlank {
                if let variable = (environment.variables ?? []).first(where: { $0.key == row.key }) {
                    var changed = false
                    if !variable.hasValue, !row.value.isEmpty {
                        try VariableEditor.setValue(variable, to: row.value, secrets: secrets)
                        changed = true
                    }
                    if variable.serviceCategory.isEmpty, !row.category.isEmpty {
                        VariableEditor.setCategory(variable, to: row.category); changed = true
                    }
                    if variable.serviceLabel.isEmpty, !row.service.isEmpty {
                        VariableEditor.setService(variable, to: row.service); changed = true
                    }
                    if variable.account == nil, !row.account.isEmpty {
                        VariableEditor.setAccount(variable, login: row.account, context: context); changed = true
                    }
                    if variable.sourceURL == nil, !row.link.isEmpty, InputValidation.webURL(row.link) != nil {
                        try VariableEditor.setLink(variable, to: row.link); changed = true
                    }
                    if changed { result.filledKeys.append(row.key) } else { result.unchangedKeys.append(row.key) }
                } else {
                    let link = InputValidation.webURL(row.link) == nil ? "" : row.link
                    try VariableEditor.add(key: row.key, value: row.value, category: row.category, service: row.service,
                                           account: row.account, link: link, to: environment, context: context, secrets: secrets)
                    result.addedKeys.append(row.key)
                }
            }
        }
        return result
    }
}
