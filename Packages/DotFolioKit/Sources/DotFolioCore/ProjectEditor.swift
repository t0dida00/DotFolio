import DotFolioModels
import Foundation

/// Editing a project's own details after creation.
public enum ProjectEditor {
    public enum Failure: Error, Equatable {
        case emptyName
        case invalidLink

        public var message: String {
            switch self {
            case .emptyName: "Enter a project name."
            case .invalidLink: "Enter a web link, e.g. https://github.com/owner/repo"
            }
        }
    }

    /// Updates name, description and link. A GitHub/GitLab link also sets the
    /// provider and "owner/repo"; any other link (or none) clears them.
    @MainActor
    public static func update(_ project: Project, name: String, summary: String, link: String) throws(Failure) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .emptyName }
        let linkText = link.trimmingCharacters(in: .whitespacesAndNewlines)
        var url: URL?
        if !linkText.isEmpty {
            guard let parsed = InputValidation.webURL(linkText) else { throw .invalidLink }
            url = parsed
        }

        project.name = name
        project.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if url != project.repoURL {
            project.repoURL = url
            if let url, let repo = RepoLink(url: url) {
                project.provider = repo.provider
                project.repoFullName = repo.fullName
            } else {
                project.provider = .none
                project.repoFullName = ""
            }
        }
        project.updatedAt = .now
    }
}
