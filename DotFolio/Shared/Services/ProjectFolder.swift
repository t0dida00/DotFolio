import AppKit
import DotFolioEnv
import DotFolioModels

/// The project's local checkout folder. The app is sandboxed, so the folder
/// is remembered as a security-scoped bookmark (not a secret) and opened
/// only for the moment we write into it.
@MainActor
enum ProjectFolder {
    enum Failure: LocalizedError {
        case folderMissing
        var errorDescription: String? { "The project folder can’t be found. Choose it again." }
    }

    /// Asks the user to pick the folder and remembers it on the project.
    @discardableResult
    static func choose(for project: Project) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the local folder of “\(project.name)”. Dotfolio writes .env files here when you export."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        project.localFolderBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return url
    }

    /// The remembered folder, refreshing a stale bookmark if needed.
    static func resolve(_ project: Project) -> URL? {
        guard let data = project.localFolderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale {
            project.localFolderBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return url
    }

    /// Runs `body` while the sandbox grants access to `folder`.
    static func withAccess<T>(to folder: URL, _ body: () throws -> T) throws -> T {
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: folder.path()) else { throw Failure.folderMissing }
        return try body()
    }

    /// Things worth confirming before writing `fileName` into `folder`.
    static func warnings(writing fileName: String, into folder: URL) -> [String] {
        (try? withAccess(to: folder) {
            var notes: [String] = []
            let file = folder.appending(path: fileName)
            if FileManager.default.fileExists(atPath: file.path()) {
                notes.append("\(fileName) already exists in \(folder.lastPathComponent) and will be replaced.")
            }
            let gitignore = folder.appending(path: ".gitignore")
            let isRepo = FileManager.default.fileExists(atPath: folder.appending(path: ".git").path())
            let ignoreText = (try? String(contentsOf: gitignore, encoding: .utf8)) ?? ""
            if isRepo, !GitignoreCheck.ignores(fileName, gitignore: ignoreText) {
                notes.append("⚠️ \(fileName) is not in .gitignore — it could be committed to git. Add it to .gitignore first.")
            }
            return notes
        }) ?? []
    }

    /// Writes the file readable by the owner only (0600).
    static func write(_ text: String, to file: URL) throws {
        try Data(text.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path())
    }
}
