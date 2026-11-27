import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// One row of the .env table in the New Project sheet.
public struct EnvDraftRow: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var key = ""
    public var value = ""
    public var category = ""
    public var service = ""
    public var account = ""
    public var link = ""
    public var isRevealed = false

    public init(key: String = "", value: String = "", category: String = "", service: String = "", account: String = "", link: String = "") {
        self.key = key
        self.value = value
        self.category = category
        self.service = service
        self.account = account
        self.link = link
    }

    public var isBlank: Bool {
        [key, category, service, account, link].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } && value.isEmpty
    }
}

/// Everything the New Project sheet collected. Each environment has its own
/// rows; `rows` is the table of the environment currently shown.
public struct ProjectDraft {
    public var name = ""
    public var summary = ""
    public var link = ""
    /// The live site, checked for uptime (see `ProjectEditor.productionURL`).
    public var production = ""
    /// The environment whose rows the table shows and edits.
    public var environmentName = "development"
    public var rowsByEnvironment: [String: [EnvDraftRow]] = [:]

    public init() {}

    public var rows: [EnvDraftRow] {
        get { rowsByEnvironment[environmentName] ?? [EnvDraftRow()] }
        set { rowsByEnvironment[environmentName] = newValue }
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var filledRows: [EnvDraftRow] { filledRows(in: environmentName) }

    public func filledRows(in environment: String) -> [EnvDraftRow] {
        (rowsByEnvironment[environment] ?? []).filter { !$0.isBlank }
    }

    /// Environments that have at least one filled row, default ones first.
    public var environmentsWithRows: [String] {
        let names = rowsByEnvironment.keys.filter { !filledRows(in: $0).isEmpty }
        let order = ProjectEnvironment.defaultNames
        return names.sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
    }

    /// Environments (other than the shown one) with a row that blocks Create.
    public var otherEnvironmentsWithIssues: [String] {
        environmentsWithRows.filter { env in
            env != environmentName && filledRows(in: env).contains { keyIssue(for: $0, in: env) != nil || linkIssue(for: $0) != nil }
        }
    }

    // MARK: Validation (drives the inline messages and the Create button)

    public var linkIsInvalid: Bool {
        !link.trimmingCharacters(in: .whitespaces).isEmpty && InputValidation.webURL(link) == nil
    }

    public func keyIssue(for row: EnvDraftRow, in environment: String? = nil) -> String? {
        let key = row.key.trimmingCharacters(in: .whitespaces)
        if row.isBlank { return nil }
        if key.isEmpty { return "Name is required" }
        if !InputValidation.isValidEnvKey(key) { return "Use letters, digits and _ (not starting with a digit)" }
        if duplicateKeys(in: environment ?? environmentName).contains(key) { return "Duplicate name" }
        return nil
    }

    public func linkIssue(for row: EnvDraftRow) -> String? {
        let link = row.link.trimmingCharacters(in: .whitespaces)
        return !link.isEmpty && InputValidation.webURL(link) == nil ? "Not a valid web link" : nil
    }

    public var duplicateKeys: Set<String> { duplicateKeys(in: environmentName) }

    public func duplicateKeys(in environment: String) -> Set<String> {
        InputValidation.duplicateKeys(filledRows(in: environment).map { $0.key.trimmingCharacters(in: .whitespaces) })
    }

    /// Why the production address can't be used, nil when fine or empty.
    public var productionIssue: ProjectEditor.Failure? {
        do { _ = try ProjectEditor.productionURL(production); return nil } catch { return error }
    }

    public var canCreate: Bool {
        !trimmedName.isEmpty && !linkIsInvalid && productionIssue == nil
            && environmentsWithRows.allSatisfy { env in
                filledRows(in: env).allSatisfy { keyIssue(for: $0, in: env) == nil && linkIssue(for: $0) == nil }
            }
    }

    // MARK: Importing .env files

    public struct ImportResult: Equatable, Sendable {
        /// New rows.
        public var added = 0
        /// Existing rows whose empty value or source fields were filled from the file.
        public var filled = 0
        /// Names already in the table with nothing left to fill; what was typed is kept.
        public var skipped: [String] = []
    }

    /// Adds a file's entries to one environment's table. Service, provider,
    /// account and link come from each line's `#Service/Provider/Account/Link`
    /// comment. Names already there are never overwritten: only empty cells
    /// are filled in.
    /// - Parameter includeValues: false for templates (`.env.example`), whose
    ///   values are placeholders.
    @discardableResult
    public mutating func importEntries(_ entries: [EnvEntry], into environment: String, includeValues: Bool) -> ImportResult {
        var result = ImportResult()
        var table = (rowsByEnvironment[environment] ?? []).filter { !$0.isBlank }
        for entry in entries {
            let value = includeValues ? entry.value : ""
            let source = entry.source
            if let i = table.firstIndex(where: { $0.key.trimmingCharacters(in: .whitespaces) == entry.key }) {
                var changed = false
                func fill(_ field: WritableKeyPath<EnvDraftRow, String>, _ new: String) {
                    guard table[i][keyPath: field].trimmingCharacters(in: .whitespaces).isEmpty, !new.isEmpty else { return }
                    table[i][keyPath: field] = new
                    changed = true
                }
                fill(\.value, value)
                fill(\.category, source.service)
                fill(\.service, source.provider)
                fill(\.account, source.account)
                fill(\.link, source.link)
                if changed { result.filled += 1 } else { result.skipped.append(entry.key) }
            } else {
                table.append(EnvDraftRow(key: entry.key, value: value, category: source.service,
                                         service: source.provider, account: source.account, link: source.link))
                result.added += 1
            }
        }
        table.append(EnvDraftRow()) // spreadsheet feel: a fresh row to type in
        rowsByEnvironment[environment] = table
        return result
    }
}

public enum ProjectCreator {
    public enum Failure: Error {
        /// Values could not be stored; nothing was created.
        case keychain(KeychainError)
    }

    /// Creates the project. SECURITY: values go to the secret store FIRST; only
    /// if every write succeeds is the metadata inserted. On any failure the
    /// already-written items are removed, so no orphaned secrets remain and no
    /// value ever reaches the database.
    @MainActor
    @discardableResult
    public static func create(_ draft: ProjectDraft, includeValues: Bool, context: ModelContext, secrets: any SecretStore) throws -> Project {
        let tables = draft.environmentsWithRows.map { (environment: $0, rows: draft.filledRows(in: $0)) }
        let rows = tables.flatMap(\.rows)
        var refs: [UUID: UUID] = [:] // row.id -> secretRef
        var written: [UUID] = []

        if includeValues {
            do {
                for row in rows where !row.value.isEmpty {
                    let ref = UUID()
                    try secrets.setString(row.value, for: ref.uuidString)
                    written.append(ref)
                    refs[row.id] = ref
                }
            } catch {
                for ref in written { try? secrets.delete(ref.uuidString) }
                throw Failure.keychain(error as? KeychainError ?? .unexpectedStatus(-1))
            }
        }

        let project = Project.create(
            name: draft.trimmedName,
            summary: draft.summary,
            link: InputValidation.webURL(draft.link),
            in: context
        )
        project.productionURL = try? ProjectEditor.productionURL(draft.production)
        let history = SourceHistory(context: context)
        for table in tables {
            let environment = project.sortedEnvironments.first { $0.name == table.environment }
                ?? project.sortedEnvironments.first
            for row in table.rows {
                insert(row, into: environment, refs: refs, history: history, context: context)
            }
        }
        project.lastOpenedAt = .now
        return project
    }

    @MainActor
    private static func insert(_ row: EnvDraftRow, into environment: ProjectEnvironment?, refs: [UUID: UUID],
                               history: SourceHistory, context: ModelContext) {
        let variable = Variable(key: row.key.trimmingCharacters(in: .whitespaces), environment: environment)
        variable.sourceURL = InputValidation.webURL(row.link)
        variable.serviceLabel = row.service.trimmingCharacters(in: .whitespacesAndNewlines)
        variable.serviceCategory = VariableEditor.normalizedCategory(row.category)
        if let ref = refs[row.id] {
            variable.secretRef = ref
            variable.hasValue = true
        }
        context.insert(variable)
        variable.account = VariableEditor.findOrCreateAccount(login: row.account, service: variable.serviceLabel, context: context)
        VariableEditor.fillMissingSource(variable, value: row.value, context: context, history: history)
    }
}
