import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Editing an environment as .env text (File view → Edit). The text is the
/// whole truth for that environment: keys missing from it are deleted, new
/// keys added, values and `#Service/Provider/Account/Link` comments applied.
/// Notes are not part of the text and are kept as they are.
public enum EnvFileEdit {
    public enum Failure: Error, Equatable {
        case invalidLink(key: String)
        case variable(key: String, VariableEditor.Failure)

        public var message: String {
            switch self {
            case .invalidLink(let key): "\(key): the link after the third “/” isn’t a web link."
            case .variable(let key, let failure): "\(key): \(failure.message)"
            }
        }
    }

    /// What saving the text would change. Keys only, so it can be shown in
    /// a confirmation before anything is written.
    public struct Plan: Equatable, Sendable {
        public var added: [EnvEntry] = []
        /// Key → new value ("" clears it).
        public var values: [String: String] = [:]
        public var sources: [String: EnvSource] = [:]
        /// Keys whose variables (and Keychain items) will be deleted.
        public var removed: [String] = []

        public var isEmpty: Bool { added.isEmpty && values.isEmpty && sources.isEmpty && removed.isEmpty }
    }

    /// The text the editor starts with: one line per variable, real values.
    @MainActor
    public static func text(for variables: [Variable], values: [UUID: String]) -> String {
        variables.map { variable in
            var line = "\(variable.key)=\(EnvExporter.quote(values[variable.id] ?? ""))"
            let source = EnvFileLines.source(of: variable).comment
            if !source.isEmpty { line += " #\(source)" }
            return line
        }.joined(separator: "\n") + (variables.isEmpty ? "" : "\n")
    }

    /// - Parameter currentValues: plaintext of the variables that have one,
    ///   read when editing started. A variable with a value that is missing
    ///   here is only changed when the text gives it a non-empty value.
    @MainActor
    public static func plan(_ text: String, for environment: ProjectEnvironment, currentValues: [UUID: String]) -> Plan {
        plan(entries: EnvParser.parse(text), for: environment, currentValues: currentValues)
    }

    /// Same as `plan(_:for:currentValues:)` for entries already parsed
    /// (e.g. several files merged for one environment).
    @MainActor
    public static func plan(entries: [EnvEntry], for environment: ProjectEnvironment, currentValues: [UUID: String]) -> Plan {
        let current = environment.sortedVariables
        let byKey = Dictionary(current.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var plan = Plan()

        for entry in entries {
            guard let variable = byKey[entry.key] else {
                plan.added.append(entry)
                continue
            }
            let old = currentValues[variable.id] ?? (variable.hasValue ? nil : "")
            if let old {
                if old != entry.value { plan.values[entry.key] = entry.value }
            } else if !entry.value.isEmpty {
                // Stored value we couldn't read: only replace, never clear.
                plan.values[entry.key] = entry.value
            }
            if entry.source != EnvFileLines.source(of: variable) {
                plan.sources[entry.key] = entry.source
            }
        }
        let kept = Set(entries.map(\.key))
        plan.removed = current.map(\.key).filter { !kept.contains($0) }
        return plan
    }

    /// Writes the plan. Links are checked first so a bad one changes nothing;
    /// deletions go last and remove the Keychain item before the metadata.
    @MainActor
    public static func apply(_ plan: Plan, to environment: ProjectEnvironment,
                             context: ModelContext, secrets: any SecretStore) throws(Failure) {
        for entry in plan.added where !entry.source.link.isEmpty && InputValidation.webURL(entry.source.link) == nil {
            throw .invalidLink(key: entry.key)
        }
        for (key, source) in plan.sources where !source.link.isEmpty && InputValidation.webURL(source.link) == nil {
            throw .invalidLink(key: key)
        }

        let byKey = Dictionary((environment.variables ?? []).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in plan.added {
            let s = entry.source
            do {
                try VariableEditor.add(key: entry.key, value: entry.value, category: s.service, service: s.provider,
                                       account: s.account, link: s.link, to: environment, context: context, secrets: secrets)
            } catch { throw .variable(key: entry.key, error) }
        }
        for (key, value) in plan.values.sorted(by: { $0.key < $1.key }) {
            guard let variable = byKey[key] else { continue }
            do { try VariableEditor.setValue(variable, to: value, secrets: secrets) }
            catch { throw .variable(key: key, error) }
        }
        for (key, source) in plan.sources.sorted(by: { $0.key < $1.key }) {
            guard let variable = byKey[key] else { continue }
            VariableEditor.setCategory(variable, to: source.service)
            VariableEditor.setService(variable, to: source.provider)
            VariableEditor.setAccount(variable, login: source.account, context: context)
            do { try VariableEditor.setLink(variable, to: source.link) }
            catch { throw .variable(key: key, error) }
        }
        for key in plan.removed {
            guard let variable = byKey[key] else { continue }
            do { try VariableEditor.delete(variable, context: context, secrets: secrets) }
            catch { throw .variable(key: key, error) }
        }
    }
}
