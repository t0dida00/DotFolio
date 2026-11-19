/// What's new in each version, newest first. Shipped with the app so it
/// works offline. Add an entry when bumping MARKETING_VERSION.
enum ReleaseNotes {
    struct Entry {
        let version: String
        let highlights: [(symbol: String, title: String, detail: String)]
    }

    static let entries: [Entry] = [
        Entry(version: "0.1.0", highlights: [
            ("key.horizontal", "Secrets in your Keychain",
             "Values never touch the database. Reveal and copy with Touch ID; the session locks on sleep or screen lock."),
            ("square.and.arrow.down", "Import from GitHub",
             "Sign in with a read-only GitHub App and turn repos into projects, with variables from each .env.example."),
            ("tablecells", "Edit .env per environment",
             "Name, value, service, provider, account and console link — add, edit, delete and copy between environments."),
            ("square.and.arrow.up", "Export .env",
             "To the clipboard (auto-cleared), your project folder (with a .gitignore check) or anywhere."),
            ("person.crop.circle", "Accounts",
             "One login, many providers. Provider projects with Open console, and every project that uses the account."),
            ("chart.bar", "Overview",
             "What you track, missing values, stale secrets, providers and services in use."),
            ("checkmark.shield", "Verify Data",
             "Cross-checks the database against the Keychain and repairs what it safely can."),
        ]),
    ]

    static func entry(for version: String) -> Entry? {
        entries.first { $0.version == version }
    }
}
