import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

@main
struct DotFolioApp: App {
    private let container: ModelContainer
    @State private var navigation = AppNavigation()
    @State private var session = SessionLock()
    @State private var updates = UpdateCenter()
    @State private var autoLock: SessionAutoLock?

    init() {
        do {
            container = try DotFolioSchema.makeContainer()
        } catch {
            // Metadata store unreadable: fail loudly rather than silently starting empty
            // (an empty store would look like data loss to the user).
            fatalError("Could not open the DOTFOLIO database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(navigation)
                .environment(session)
                .environment(updates)
                .task {
                    // Lock on sleep / screen lock / screensaver.
                    if autoLock == nil { autoLock = SessionAutoLock(session: session) }
                    // Auto-lock: drop the Touch ID session after inactivity.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15))
                        session.lockIfExpired()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .modelContainer(container)
        .environment(\.secretStore, KeychainStore.secrets(bundleID: Self.bundleID))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Project Folder…") {
                    if let folder = ProjectFolderPicker.choose() { navigation.folderToImport = PendingFolder(url: folder) }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            // After "About DotFolio": always present (the app has no Settings
            // scene yet, so an .appSettings anchor may not exist).
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updates.checkForUpdates)
                Button("What’s New in DOTFOLIO") { updates.isShowingWhatsNew = true }
                Divider()
                Button("Suggest Sources…") { navigation.isSuggestingSources = true }
                Button("Verify Data…") { navigation.isVerifyingData = true }
                Button("Erase All Data…") { navigation.isConfirmingErase = true }
            }
        }
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "app.dotfolio.DotFolio" }
}
