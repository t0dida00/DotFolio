import SwiftUI

/// Which repo hosts the user has signed in to. Only the display name is kept
/// here (not secret); the OAuth tokens themselves live in the Keychain.
/// Set by the GitHub/GitLab sign-in flow once it is wired up.
enum RepoConnections {
    static let gitHubUserKey = "connections.github.username"
    static let gitLabUserKey = "connections.gitlab.username"
}
