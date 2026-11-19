import DotFolioModels
import DotFolioSecurity
import Foundation
import LocalAuthentication
import SwiftData

/// Copies variables from one environment to another (e.g. development → staging).
public enum VariableCopier {
    public struct Result: Equatable, Sendable {
        public var copied: Int
        /// Keys that already existed in the target; never overwritten.
        public var skipped: [String]
    }

    /// - Parameters:
    ///   - includeValues: also copy stored values. Reading them needs an
    ///     authenticated context (Touch ID); each copy gets its own new
    ///     Keychain item, so editing one environment never affects the other.
    /// SECURITY: all values are read and written before any metadata is
    /// inserted; on failure the new Keychain items are removed and nothing
    /// is created.
    @MainActor
    @discardableResult
    public static func copy(
        _ variables: [Variable], to target: ProjectEnvironment, includeValues: Bool,
        context: ModelContext, secrets: any SecretStore, authContext: LAContext? = nil
    ) throws -> Result {
        let existing = Set((target.variables ?? []).map(\.key))
        let toCopy = variables.filter { !existing.contains($0.key) && $0.environment?.persistentModelID != target.persistentModelID }
        let skipped = variables.map(\.key).filter(existing.contains)

        var newRefs: [Variable.ID: UUID] = [:]
        if includeValues {
            var written: [UUID] = []
            do {
                for source in toCopy where source.hasValue {
                    guard let value = try secrets.string(for: source.secretRef.uuidString, context: authContext) else { continue }
                    let ref = UUID()
                    try secrets.setString(value, for: ref.uuidString)
                    written.append(ref)
                    newRefs[source.id] = ref
                }
            } catch {
                for ref in written { try? secrets.delete(ref.uuidString) }
                throw error
            }
        }

        for source in toCopy {
            let copy = Variable(key: source.key, notes: source.notes, environment: nil)
            copy.sourceURL = source.sourceURL
            copy.serviceLabel = source.serviceLabel
            if let ref = newRefs[source.id] {
                copy.secretRef = ref
                copy.hasValue = true
            }
            context.insert(copy)
            copy.environment = target
            copy.link(account: source.account, serviceProject: source.serviceProject)
        }
        if !toCopy.isEmpty { target.project?.updatedAt = .now }
        return Result(copied: toCopy.count, skipped: skipped)
    }
}
