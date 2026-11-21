/// What's new in each version, newest first. Shipped with the app so it
/// works offline. Add an entry when bumping MARKETING_VERSION.
enum ReleaseNotes {
    struct Entry {
        let version: String
        let highlights: [(symbol: String, title: String, detail: String)]
    }

    static let entries: [Entry] = [
        Entry(version: "0.7.1", highlights: [
            ("chevron.left.forwardslash.chevron.right", "Open source",
             "DOTFOLIO is now open source under the MIT License, with a full README on GitHub covering features, the security model, building from source and contributing."),
        ]),
        Entry(version: "0.7.0", highlights: [
            ("wand.and.stars", "Smarter sources",
             "DOTFOLIO now recognizes over 150 providers — Groq, xAI, Clerk, Convex, Railway, Contentful, LaunchDarkly, Open-Meteo and more — plus well-known names like KV_REST_API_URL and AUTH_SECRET and more key formats. Suggest Sources opens once to fill the empty ones you already have."),
            ("square.grid.2x2", "Four new services",
             "Messaging (Twilio, Slack, OneSignal), CMS (Contentful, Sanity), Feature flags (LaunchDarkly, Statsig) and Data API (Open-Meteo, OpenWeather)."),
            ("sparkles", "Icons for every provider",
             "A provider without its own icon shows the icon and color of what it’s for — Hugging Face gets AI’s sparkles."),
        ]),
        Entry(version: "0.6.3", highlights: [
            ("square.grid.2x2", "One icon style",
             "Every icon tile — accounts, providers, the Overview, dialogs and sign-in — now has the app icon’s proportions: the same rounded corners and a larger symbol."),
        ]),
        Entry(version: "0.6.2", highlights: [
            ("square.grid.2x2", "Clearer project icons",
             "Project icons follow the app icon’s proportions: rounder corners and a larger GitHub, GitLab, local or hand-made mark."),
        ]),
        Entry(version: "0.6.1", highlights: [
            ("line.3.horizontal.decrease.circle", "Filter the Library",
             "Under Libraries, pick All, Library, Dev, Staging or Prod to see every key, only the Library’s own, or the project keys of one environment."),
            ("cursorarrow.rays", "Row hover",
             "Variable tables highlight the row under the pointer."),
            ("lock", "Used by opens read-only",
             "An account’s Used by tables are locked until you turn on Edit, like projects and the Library; double-click a key to copy it as a .env line."),
            ("chevron.down", "Fixes",
             "A Library or Used by section can be collapsed even when it’s the only one, and the From column no longer cuts off “production”."),
        ]),
        Entry(version: "0.6.0", highlights: [
            ("books.vertical", "Every key in the Library",
             "The Library now lists the keys of all your projects next to its own, one row per environment, with a From column. Import a project and its keys appear; delete it and they go. Keys you added to the Library yourself always stay."),
            ("lock", "Library opens read-only",
             "Library tables are locked until you turn on Edit. Double-click a key to copy it as a .env line."),
        ]),
        Entry(version: "0.5.4", highlights: [
            ("app.badge", "A real app icon",
             "DOTFOLIO has its own icon in the Dock, Finder and Launchpad, and the logo inside the app matches it."),
        ]),
        Entry(version: "0.5.3", highlights: [
            ("chart.bar", "Top 5 in the Overview",
             "Providers in use, Services in use and Accounts list their top 5, with a count of the rest underneath."),
        ]),
        Entry(version: "0.5.2", highlights: [
            ("person.crop.circle", "Simpler Accounts ranking",
             "The Overview’s Accounts card drops the Providers column and ranks accounts by the projects, then the variables, that use them."),
        ]),
        Entry(version: "0.5.1", highlights: [
            ("rectangle.center.inset.filled", "Centered sign-in and import",
             "Signing in to GitHub, the loading steps, choosing repositories and the import summary now sit in the middle of the window."),
        ]),
        Entry(version: "0.5.0", highlights: [
            ("folder.badge.plus", "Import a project folder",
             "Drop a project folder on the project list — or choose File ▸ Import Project Folder… — and DOTFOLIO finds its .env files, up to three folders deep, skipping node_modules and build output. Tick the ones to import and pick each one’s environment."),
            ("laptopcomputer", "Local projects",
             "Projects linked to a folder on this Mac get their own tile and show their path. Filter the list by All, Git or Local. Signing out of GitHub never deletes a local project."),
            ("arrow.down.doc", "Drop .env files on Add variable",
             "Add variable has a drop zone: the files’ names, values and #Service/Provider/Account/Link comments go to the environment shown. Values already there are kept."),
            ("doc.on.doc", "Copy a whole line",
             "The copy button, now after Link, copies KEY=value #Service/Provider/Account/Link — so does double-clicking a row. The icon shows a tick when it’s done."),
            ("square.and.pencil", "Edit long values",
             "With Edit on, click a value to edit it in a larger editor that wraps long text. The eye inside Add variable’s Value field shows what you typed."),
            ("checkmark.circle", "Clear results",
             "Adding, saving, deleting, importing and signing in end with a short dialog — green when it worked, amber when nothing changed, red when it didn’t. Required fields are marked with *."),
        ]),
        Entry(version: "0.4.1", highlights: [
            ("number", "Variables counted once",
             "A name in development, staging and production is one variable. The project page and the Overview — totals, missing values, no source, providers, services, accounts, Needs attention and Recently updated — now count it once, so the numbers agree."),
            ("lock.open", "Smoother Edit switch",
             "Turning Edit on or off no longer stutters on long tables."),
        ]),
        Entry(version: "0.4.0", highlights: [
            ("wand.and.stars", "Smart sources",
             "New variables get their Service and Provider from the name — DATABASE_URL is Database, FIREBASE_AUTH_DOMAIN is Auth on Firebase, NUXT_HF_MODEL is AI on Hugging Face — or from what you chose for the same name before. Suggest Sources… fills the empty ones you already have, after you check them."),
            ("doc.plaintext", "See it as a .env file",
             "Switch a project between Table and File. File shows one line per variable, KEY=value #Service/Provider/Account/Link, and Export .env writes exactly that."),
            ("lock", "Locked until you edit",
             "Tables open read-only: double-click a row to copy its value. Turn on Edit to change names, values and sources, or to edit the whole file as text. Show Values reveals every value at once."),
            ("text.bubble", "Source comments in .env",
             "Write #Service/Provider/Account/Link after a value — e.g. KEY='…' #AI/OpenAI/me@example.com — and importing fills those columns."),
            ("books.vertical", "One-step Library import",
             "Dropping .env files on the Library no longer asks for a provider: each key goes under the provider in its comment, the rest under Other."),
            ("person.crop.circle", "Every key of an account",
             "An account’s Used by now lists each key that uses it — per project and environment, plus the Library — in the same editable table as a project."),
            ("textformat.size.larger", "DOTFOLIO",
             "The app now goes by DOTFOLIO everywhere. Your projects, accounts and Keychain values carry over."),
            ("list.bullet.rectangle", "Calmer selection",
             "Projects, Accounts and Libraries mark the selected row in gray instead of a bright fill. ⌘-click and ⇧-click still pick several projects."),
        ]),
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
