import Foundation

/// The ⌘K palette and the menu bar panel: one ranked list of projects, keys
/// and app actions for a typed query. Searches metadata only, never values.
public enum CommandPalette {
    /// App commands the palette can run (the app maps them to menu actions).
    public enum Action: String, CaseIterable, Sendable {
        case newProject, importFolder, suggestSources, verifyData, checkForUpdates

        public var title: String {
            switch self {
            case .newProject: "New Project"
            case .importFolder: "Import Project Folder…"
            case .suggestSources: "Suggest Sources…"
            case .verifyData: "Verify Data…"
            case .checkForUpdates: "Check for Updates…"
            }
        }

        public var symbol: String {
            switch self {
            case .newProject: "plus"
            case .importFolder: "folder.badge.plus"
            case .suggestSources: "wand.and.stars"
            case .verifyData: "checkmark.shield"
            case .checkForUpdates: "arrow.down.circle"
            }
        }
    }

    public enum Item: Identifiable {
        case project(Project)
        /// A project key (one per environment) or a Library key.
        case variable(Variable)
        case action(Action)

        public var id: String {
            switch self {
            case .project(let p): "p-\(p.id)"
            case .variable(let v): "v-\(v.id)"
            case .action(let a): "a-\(a.rawValue)"
            }
        }

        public var title: String {
            switch self {
            case .project(let p): p.name
            case .variable(let v): v.key
            case .action(let a): a.title
            }
        }

        /// "Shop · production · Stripe", "Library · OpenAI", "t0dida00/shop".
        public var subtitle: String {
            switch self {
            case .project(let p):
                return p.repoFullName.isEmpty ? "Project" : p.repoFullName
            case .variable(let v):
                let provider = v.displayService
                let place = Library.origin(of: v)
                return provider.isEmpty ? place : "\(place) · \(provider)"
            case .action:
                return "Command"
            }
        }
    }

    /// How well `text` matches `query` (lower is better), nil when it doesn't.
    /// exact (0) < prefix (1) < word prefix (2) < contains (3).
    static func rank(_ text: String, _ query: String) -> Int? {
        let t = text.lowercased(), q = query.lowercased()
        guard !q.isEmpty, !t.isEmpty else { return nil }
        if t == q { return 0 }
        if t.hasPrefix(q) { return 1 }
        let words = t.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(q) }) { return 2 }
        return t.contains(q) ? 3 : nil
    }

    /// Ranked results: by match quality, then projects before keys before
    /// actions, then name. Keys match on name first; provider, service,
    /// account and project name count as a weaker (contains) match.
    public static func results(query rawQuery: String, projects: [Project], variables: [Variable],
                               includeActions: Bool = true, limit: Int = 12) -> [Item] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        // Ties: the same name in several environments stays together, by
        // project, then development → staging → production.
        var scored: [(rank: Int, kind: Int, name: String, place: String, order: Int, item: Item)] = []

        for project in projects {
            let best = [rank(project.name, query), rank(project.repoFullName, query).map { max($0, 2) }]
                .compactMap { $0 }.min()
            if let best { scored.append((best, 0, project.name, "", 0, .project(project))) }
        }
        for v in variables {
            let other = [v.displayService, v.displayCategory, v.account?.login ?? "", v.environment?.project?.name ?? ""]
                .compactMap { rank($0, query) }.min().map { _ in 3 }
            if let best = [rank(v.key, query), other].compactMap({ $0 }).min() {
                scored.append((best, 1, v.key, v.environment?.project?.name ?? "", v.environment?.sortOrder ?? -1, .variable(v)))
            }
        }
        if includeActions {
            for action in Action.allCases {
                if let r = rank(action.title, query) { scored.append((r, 2, action.title, "", 0, .action(action))) }
            }
        }
        return scored
            .sorted {
                ($0.rank, $0.kind, $0.name.lowercased(), $0.place.lowercased(), $0.order)
                    < ($1.rank, $1.kind, $1.name.lowercased(), $1.place.lowercased(), $1.order)
            }
            .prefix(limit)
            .map(\.item)
    }
}
