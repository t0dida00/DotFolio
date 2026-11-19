import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Deletes a project together with the Keychain items of its variables.
public enum ProjectDeleter {
    public enum Failure: Error {
        /// Some values could not be removed; the project was kept so those
        /// items remain findable (and deletable on a retry).
        case keychain(Error)
    }

    /// SECURITY: Keychain items go first. If any removal fails we keep the
    /// project, otherwise its secrets would become orphans nobody can find.
    @MainActor
    public static func delete(_ project: Project, context: ModelContext, secrets: any SecretStore) throws {
        do {
            for variable in project.allVariables where variable.hasValue {
                try secrets.delete(variable.secretRef.uuidString)
                variable.hasValue = false
            }
        } catch {
            throw Failure.keychain(error)
        }
        context.delete(project) // cascades to environments and variables
        try context.save()
    }
}
