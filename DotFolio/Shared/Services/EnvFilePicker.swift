import AppKit
import DotFolioEnv

/// Picks and reads `.env*` files for New Project and the Library.
/// The app is sandboxed: files the user picks or drops are readable for the
/// moment we read them. Nothing is logged; values stay in memory until the
/// caller writes them to the Keychain.
@MainActor
enum EnvFilePicker {
    struct File {
        let name: String
        let kind: EnvFileKind
        let entries: [EnvEntry]
    }

    /// Open panel that shows hidden files, since `.env` files start with a dot.
    static func choose(message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.prompt = "Import"
        panel.message = message
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// Reads every URL; the first failure is reported with the file's name.
    static func read(_ urls: [URL]) throws -> [File] {
        try urls.map { url in
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                return File(name: name, kind: EnvFileImport.kind(forFileName: name), entries: try EnvFileImport.entries(from: data))
            } catch EnvFileImport.Failure.tooLarge {
                throw ReadError(message: "\(name) is too large to be a .env file.")
            } catch EnvFileImport.Failure.notText {
                throw ReadError(message: "\(name) isn’t a text file.")
            } catch {
                throw ReadError(message: "\(name) couldn’t be read.")
            }
        }
    }

    struct ReadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
