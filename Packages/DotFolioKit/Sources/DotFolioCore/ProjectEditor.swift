import DotFolioModels
import Foundation

/// Editing a project's own details after creation.
public enum ProjectEditor {
    public enum Failure: Error, Equatable {
        case emptyName
        case invalidLink
        case invalidProductionURL
        case insecureProductionURL

        public var message: String {
            switch self {
            case .emptyName: "Enter a project name."
            case .invalidLink: "Enter a web link, e.g. https://github.com/owner/repo"
            case .invalidProductionURL: "Enter the live site’s address, e.g. https://example.com"
            case .insecureProductionURL: "Use an https:// address; macOS blocks uptime checks over plain http."
            }
        }
    }

    /// Updates name, description, link and production URL. A GitHub/GitLab
    /// link also sets the provider and "owner/repo"; any other link (or none)
    /// clears them. `production` nil leaves the production URL as it is; a
    /// new address forgets the last uptime check.
    @MainActor
    public static func update(_ project: Project, name: String, summary: String, link: String,
                              production: String? = nil) throws(Failure) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .emptyName }
        let linkText = link.trimmingCharacters(in: .whitespacesAndNewlines)
        var url: URL?
        if !linkText.isEmpty {
            guard let parsed = InputValidation.webURL(linkText) else { throw .invalidLink }
            url = parsed
        }
        var newProduction: URL??
        if let production { newProduction = .some(try productionURL(production)) }

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
        if let newProduction, newProduction != project.productionURL {
            project.productionURL = newProduction
            project.clearHealth()
        }
        project.updatedAt = .now
    }

    /// The production address as typed: empty means none; bare
    /// "example.com" becomes https; plain http is refused.
    public static func productionURL(_ text: String) throws(Failure) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.lowercased().hasPrefix("http://") { throw .insecureProductionURL }
        guard let url = InputValidation.webURL(text) else { throw .invalidProductionURL }
        return url
    }
}
