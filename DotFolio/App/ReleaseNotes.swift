/// What's new in each version, newest first. Shipped with the app so it
/// works offline. Add an entry when bumping MARKETING_VERSION.
enum ReleaseNotes {
    struct Entry {
        let version: String
        let highlights: [(symbol: String, title: String, detail: String)]
    }

    static let entries: [Entry] = [
        Entry(version: "0.3.0", highlights: [
            ("square.and.arrow.down", "Import .env files",
             "New Project: pick or drop .env files and the table fills itself. The file name picks the environment — .env.production goes to production, .env and .env.local to development. Example files bring names only."),
            ("books.vertical", "Import into the Library",
             "Drop .env files on the Library, choose a provider, and every key is added with its value in your Keychain. Names already there are never overwritten."),
            ("rectangle.split.3x1", "One table per environment",
             "In New Project, development, staging and production each keep their own variables, and Create Project saves all of them."),
            ("text.below.photo", "Clearer forms",
             "No more grey example text inside fields: a short line under each field explains what goes there."),
        ]),
        Entry(version: "0.2.0", highlights: [
            ("books.vertical", "Libraries",
             "A library for keys you reuse across projects — a personal OpenAI key, a Stripe test key. Grouped by provider, stored in your Keychain, not tied to any project."),
            ("square.and.arrow.down.on.square", "Add to Project",
             "Right-click a library key to add it to any project environment, with or without its value (Touch ID)."),
            ("checkmark.shield", "Safe by default",
             "Names are unique per provider, Verify Data understands library keys, and Erase All Data removes them too."),
            ("gauge.with.dots.needle.67percent", "Smoother tables",
             "Variable tables and project details redraw much faster while you hover, type and reveal values. Copying a value now shows a checkmark."),
        ]),
        Entry(version: "0.1.0", highlights: [
            ("key.horizontal", "Secrets in your Keychain",
             "Values never touch the database. Reveal and copy with Touch ID; the session locks on sleep or screen lock."),
            ("square.and.arrow.down", "Import from GitHub",
             "Sign in with a read-only GitHub App and turn repos into projects, with variables from each .env.example."),
            ("tablecells", "Edit .env per environment",
             "Name, value, service, provider, account and console link — add, edit, delete and copy between environments. Color-coded environments, with a reminder when production is open."),
            ("square.on.square", "Projects in tabs",
             "Open several projects as tabs, edit a project’s name, description, repo link and local folder, and see when you last opened each."),
            ("square.and.arrow.up", "Export .env",
             "To the clipboard (auto-cleared), your project folder (with a .gitignore check) or anywhere."),
            ("person.crop.circle", "Accounts",
             "One login, many providers. Provider projects with Open console, and every project that uses the account."),
            ("chart.bar", "Overview",
             "What you track, missing values, stale secrets, providers and services in use."),
            ("checkmark.shield", "Verify Data",
             "Cross-checks the database against the Keychain and repairs what it safely can."),
            ("arrow.down.circle", "Check for Updates",
             "See when a new version is published on GitHub, and what’s new in each one."),
        ]),
    ]

    static func entry(for version: String) -> Entry? {
        entries.first { $0.version == version }
    }
}
