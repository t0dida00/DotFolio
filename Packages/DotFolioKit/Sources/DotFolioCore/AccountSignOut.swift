import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Signing out of a repo host removes the projects that came from it.
public enum AccountSignOut {
    /// "github:octocat"
    public static func source(provider: RepoProvider, login: String) -> String {
        "\(provider.rawValue):\(login.lowercased())"
    }

    /// Projects belonging to the account: tagged as imported from it, or
    /// (for projects imported before tagging existed) pointing at one of the
    /// account's repos. Hand-made projects without such a link, and projects
    /// linked to a folder on this Mac, are never included by that fallback.
    @MainActor
    public static func projects(provider: RepoProvider, login: String, repoFullNames: Set<String>, context: ModelContext) -> [Project] {
        let tag = source(provider: provider, login: login)
        let names = Set(repoFullNames.map { $0.lowercased() })
        let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return all.filter { project in
            guard project.provider == provider else { return false }
            if project.importedFrom == tag { return true }
            // A project linked to a folder on this Mac is the user's own checkout.
            return project.importedFrom == nil && project.localFolderBookmark == nil
                && names.contains(project.repoFullName.lowercased())
        }
    }

    /// Deletes the projects (Keychain values first, via ProjectDeleter).
    /// Stops at the first Keychain failure so no secret is orphaned.
    @MainActor
    public static func deleteProjects(_ projects: [Project], context: ModelContext, secrets: any SecretStore) throws {
        for project in projects {
            try ProjectDeleter.delete(project, context: context, secrets: secrets)
        }
    }
}
