import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// One row of the .env table in the New Project sheet.
public struct EnvDraftRow: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var key = ""
    public var value = ""
    public var service = ""
    public var account = ""
    public var link = ""
    public var isRevealed = false

    public init(key: String = "", value: String = "", service: String = "", account: String = "", link: String = "") {
        self.key = key
        self.value = value
        self.service = service
        self.account = account
        self.link = link
    }

    public var isBlank: Bool {
        [key, service, account, link].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } && value.isEmpty
    }
}

/// Everything the New Project sheet collected.
public struct ProjectDraft {
    public var name = ""
    public var summary = ""
    public var link = ""
    public var environmentName = "development"
    public var rows: [EnvDraftRow] = [EnvDraftRow()]

    public init() {}

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var filledRows: [EnvDraftRow] { rows.filter { !$0.isBlank } }

    // MARK: Validation (drives the inline messages and the Create button)

    public var linkIsInvalid: Bool {
        !link.trimmingCharacters(in: .whitespaces).isEmpty && InputValidation.webURL(link) == nil
    }

    public func keyIssue(for row: EnvDraftRow) -> String? {
        let key = row.key.trimmingCharacters(in: .whitespaces)
        if row.isBlank { return nil }
        if key.isEmpty { return "Name is required" }
        if !InputValidation.isValidEnvKey(key) { return "Use letters, digits and _ (not starting with a digit)" }
        if duplicateKeys.contains(key) { return "Duplicate name" }
        return nil
    }

    public func linkIssue(for row: EnvDraftRow) -> String? {
        let link = row.link.trimmingCharacters(in: .whitespaces)
        return !link.isEmpty && InputValidation.webURL(link) == nil ? "Not a valid web link" : nil
    }

    public var duplicateKeys: Set<String> {
        InputValidation.duplicateKeys(filledRows.map { $0.key.trimmingCharacters(in: .whitespaces) })
    }

    public var canCreate: Bool {
        !trimmedName.isEmpty && !linkIsInvalid
            && filledRows.allSatisfy { keyIssue(for: $0) == nil && linkIssue(for: $0) == nil }
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
        let rows = draft.filledRows
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
        let environment = project.sortedEnvironments.first { $0.name == draft.environmentName }
            ?? project.sortedEnvironments.first

        for row in rows {
            let variable = Variable(key: row.key.trimmingCharacters(in: .whitespaces), environment: environment)
            variable.sourceURL = InputValidation.webURL(row.link)
            variable.serviceLabel = row.service.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ref = refs[row.id] {
                variable.secretRef = ref
                variable.hasValue = true
            }
            context.insert(variable)
            variable.account = VariableEditor.findOrCreateAccount(login: row.account, service: variable.serviceLabel, context: context)
        }
        project.lastOpenedAt = .now
        return project
    }
}
