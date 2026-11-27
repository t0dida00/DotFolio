import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// "Erase All Data": removes every secret and every piece of metadata.
public enum DataEraser {
    public enum Failure: Error {
        /// Keychain items could not be removed; the database was left intact
        /// so the references to those items are not lost.
        case keychain(Error)
    }

    /// SECURITY: secrets are removed FIRST. If that fails we stop, because
    /// deleting the metadata would orphan Keychain items we could no longer
    /// find or remove.
    @MainActor
    public static func eraseAll(context: ModelContext, secretStores: [any SecretStore]) throws {
        do {
            for store in secretStores { try store.deleteAll() }
        } catch {
            throw Failure.keychain(error)
        }

        // Children before parents, so no cascade ordering surprises.
        try context.fetch(FetchDescriptor<Variable>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ProjectEnvironment>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Project>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ServiceProject>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Account>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<AppNotification>()).forEach(context.delete)
        try context.save()
    }
}
