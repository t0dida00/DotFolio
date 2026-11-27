import SwiftUI

/// Which repo hosts the user has signed in to. Only the display name is kept
/// here (not secret); the OAuth tokens themselves live in the Keychain.
/// Set by the GitHub/GitLab sign-in flow.
enum RepoConnections {
    static let gitHubUserKey = "connections.github.username"
    static let gitLabUserKey = "connections.gitlab.username"
    /// The GitLab instance signed in to ("https://gitlab.com" or self-hosted).
    static let gitLabHostKey = "connections.gitlab.host"

    static var gitLabHost: URL? {
        UserDefaults.standard.string(forKey: gitLabHostKey).flatMap(URL.init(string:))
    }
}
