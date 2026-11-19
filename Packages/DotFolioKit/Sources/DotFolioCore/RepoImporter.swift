import DotFolioEnv
import DotFolioModels
import Foundation
import SwiftData

/// Turns a remote repository (+ its .env.example, if any) into a Project.
public enum RepoImporter {
    public struct RepoInfo: Sendable {
        public var provider: RepoProvider
        public var fullName: String
        public var url: URL
        public var defaultBranch: String
        public var description: String?

        public init(provider: RepoProvider, fullName: String, url: URL, defaultBranch: String, description: String?) {
            self.provider = provider
            self.fullName = fullName
            self.url = url
            self.defaultBranch = defaultBranch
            self.description = description
        }
    }

    /// The project already imported for this repo, if any.
    @MainActor
    public static func existingProject(for fullName: String, provider: RepoProvider, context: ModelContext) -> Project? {
        let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return all.first { $0.provider == provider && $0.repoFullName.caseInsensitiveCompare(fullName) == .orderedSame }
    }

    /// Creates the project, or refreshes `.env.example` keys of an existing one.
    /// Keys from `.env.example` are added to every environment WITHOUT values:
    /// example values are placeholders, never treated as secrets to store.
    @MainActor
    @discardableResult
    public static func importRepo(_ repo: RepoInfo, envExample: String?, envExampleSHA: String?, context: ModelContext) -> Project {
        let project = existingProject(for: repo.fullName, provider: repo.provider, context: context)
            ?? Project.create(name: repo.fullName.split(separator: "/").last.map(String.init) ?? repo.fullName,
                              summary: repo.description ?? "", link: repo.url, in: context)
        project.provider = repo.provider
        project.repoFullName = repo.fullName
        project.repoURL = repo.url
        project.defaultBranch = repo.defaultBranch

        if let envExample {
            let entries = EnvParser.parse(envExample)
            project.envExampleKeys = entries.map(\.key)
            project.envExampleSHA = envExampleSHA
            for environment in project.sortedEnvironments {
                let existing = Set((environment.variables ?? []).map(\.key))
                for entry in entries where !existing.contains(entry.key) {
                    let variable = Variable(key: entry.key, notes: entry.comment, environment: nil)
                    context.insert(variable)
                    variable.environment = environment
                }
            }
        }
        project.updatedAt = .now
        return project
    }
}
