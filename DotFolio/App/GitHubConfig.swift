import Foundation

/// GitHub App used for sign-in. Neither value is a secret (device flow needs
/// no client secret), so they can live in source control.
///
/// Create the App at https://github.com/settings/apps/new with:
/// - Repository permissions: Contents → Read-only, Metadata → Read-only
/// - "Enable Device Flow" checked
/// - "Expire user authorization tokens" UNchecked (refreshing needs the
///   client secret, which a desktop app can't keep)
/// - Callback URL / Webhook: not needed (uncheck "Active" under Webhook)
enum GitHubConfig {
    /// "Client ID" on the App's settings page, e.g. "Iv23li…".
    static let clientID = "Iv23liJDNl3uU08eMptg"
    /// The App's URL name (github.com/apps/<slug>), used for "Install on GitHub".
    static let appSlug = "dotfolio-khoa"

    static var installURL: URL? {
        appSlug.isEmpty ? nil : URL(string: "https://github.com/apps/\(appSlug)/installations/new")
    }
}
