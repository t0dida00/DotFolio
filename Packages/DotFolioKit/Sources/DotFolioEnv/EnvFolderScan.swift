import Foundation

/// Finds the `.env*` files of a project folder the user dropped, and the
/// repo it is a checkout of. Read-only: nothing in the folder is changed.
public enum EnvFolderScan {
    /// A dotenv file found in the folder.
    public struct Found: Equatable, Sendable {
        /// Path relative to the dropped folder, e.g. `apps/web/.env.local`.
        public let relativePath: String
        public let url: URL

        public var fileName: String { url.lastPathComponent }
        /// Number of folders between the dropped folder and the file.
        public var depth: Int { relativePath.split(separator: "/").count - 1 }
    }

    /// How deep below the dropped folder to look (`apps/web/config/.env` is 3).
    public static let maxDepth = 3
    /// Stop after this many files: a folder with more is not one project.
    public static let maxFiles = 100

    /// Folders that hold dependencies or build output, never a project's own
    /// settings. Hidden folders (`.git`, `.next`, `.venv`…) are skipped too.
    public static let skippedFolders: Set<String> = [
        "node_modules", "bower_components", "vendor", "Pods", "Carthage",
        "build", "dist", "out", "target", "DerivedData", "coverage",
        "venv", "env", "__pycache__", "site-packages", "tmp",
    ]

    /// `.env`, `.env.local`, `.env.production`, `.env.example`, `production.env`.
    /// Not `.envrc` (direnv script) or `.environment`.
    public static func isEnvFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == ".env" || lower.hasPrefix(".env.") || (lower.hasSuffix(".env") && lower.count > 4)
    }

    public static func isSkippedFolder(_ name: String) -> Bool {
        name.hasPrefix(".") || skippedFolders.contains(name)
    }

    /// Every `.env*` file up to `maxDepth` folders down, sorted so the files
    /// of the dropped folder come first, then by path. Symbolic links are not
    /// followed (they could lead outside the project).
    public static func scan(_ folder: URL, maxDepth: Int = maxDepth, maxFiles: Int = maxFiles) -> [Found] {
        var found: [Found] = []
        visit(folder, prefix: "", depth: 0, maxDepth: maxDepth, maxFiles: maxFiles, into: &found)
        return found.sorted { ($0.depth, $0.relativePath) < ($1.depth, $1.relativePath) }
    }

    private static func visit(_ folder: URL, prefix: String, depth: Int, maxDepth: Int, maxFiles: Int, into found: inout [Found]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var subfolders: [URL] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard found.count < maxFiles else { return }
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            let name = item.lastPathComponent
            if values?.isDirectory == true {
                if depth < maxDepth && !isSkippedFolder(name) { subfolders.append(item) }
            } else if values?.isRegularFile == true, isEnvFileName(name) {
                found.append(Found(relativePath: prefix + name, url: item))
            }
        }
        for sub in subfolders {
            visit(sub, prefix: prefix + sub.lastPathComponent + "/", depth: depth + 1,
                  maxDepth: maxDepth, maxFiles: maxFiles, into: &found)
        }
    }

    // MARK: Git remote

    /// The web address of the folder's `origin` remote, read from `.git/config`
    /// (no git command runs). Nil when the folder isn't a git checkout.
    public static func repoWebURL(in folder: URL) -> URL? {
        let config = folder.appending(path: ".git/config")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        return repoWebURL(gitConfig: text)
    }

    /// `git@github.com:owner/repo.git`, `ssh://git@github.com/owner/repo.git`
    /// and `https://user@github.com/owner/repo.git` all become
    /// `https://github.com/owner/repo`. Prefers `origin`, else the first remote.
    public static func repoWebURL(gitConfig: String) -> URL? {
        var remotes: [(name: String, url: String)] = []
        var current: String?
        for raw in gitConfig.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                // [remote "origin"]
                if line.hasPrefix("[remote "), let open = line.firstIndex(of: "\""), let close = line.lastIndex(of: "\""), open < close {
                    current = String(line[line.index(after: open)..<close])
                } else {
                    current = nil
                }
            } else if let name = current, let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                if key == "url" {
                    remotes.append((name, line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        let remote = remotes.first { $0.name == "origin" } ?? remotes.first
        return remote.flatMap { webURL(fromRemote: $0.url) }
    }

    static func webURL(fromRemote remote: String) -> URL? {
        var host: String
        var path: String
        if let url = URL(string: remote), let scheme = url.scheme, ["https", "http", "ssh", "git"].contains(scheme), let h = url.host() {
            host = h
            path = url.path()
        } else if let at = remote.firstIndex(of: "@"), let colon = remote[at...].firstIndex(of: ":") {
            // scp-like: git@github.com:owner/repo.git
            host = String(remote[remote.index(after: at)..<colon])
            path = String(remote[remote.index(after: colon)...])
        } else {
            return nil
        }
        host = host.lowercased()
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard !host.isEmpty, path.contains("/") else { return nil }
        return URL(string: "https://\(host)/\(path)")
    }
}
