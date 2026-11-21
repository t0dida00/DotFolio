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
    /// "Show in Menu Bar" (DOTFOLIO menu); not a secret.
    @AppStorage("menuBarExtra") private var showsMenuBarExtra = true

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
        // "main": the menu bar panel's Open DOTFOLIO reopens it by this id.
        WindowGroup(id: "main") {
            RootView()
                .environment(navigation)
                .environment(session)
                .environment(updates)
                .task { await runAutoLock() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .modelContainer(container)
        .environment(\.secretStore, KeychainStore.secrets(bundleID: Self.bundleID))
        .commands {
            CommandGroup(after: .appInfo) {
                Toggle("Show in Menu Bar", isOn: $showsMenuBarExtra)
            }
            CommandGroup(after: .newItem) {
                Button("Go to…") { navigation.isShowingPalette = true }
                    .keyboardShortcut("k")
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

        menuBarExtra
    }

    /// Quick access from the menu bar: search and copy keys without the main
    /// window. Same database, Keychain and Touch ID session as the window.
    @SceneBuilder
    private var menuBarExtra: some Scene {
        MenuBarExtra("DOTFOLIO", systemImage: "lock.doc", isInserted: $showsMenuBarExtra) {
            MenuBarPanel()
                .environment(navigation)
                .environment(session)
                .environment(updates)
                .modelContainer(container)
                .environment(\.secretStore, KeychainStore.secrets(bundleID: Self.bundleID))
                // Keeps the session's auto-lock running even with the main window closed.
                .task { await runAutoLock() }
        }
        .menuBarExtraStyle(.window)
    }

    /// Lock on sleep / screen lock / screensaver, and drop the Touch ID
    /// session after inactivity. Safe to run from several scenes.
    private func runAutoLock() async {
        if autoLock == nil { autoLock = SessionAutoLock(session: session) }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            session.lockIfExpired()
        }
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "app.dotfolio.DotFolio" }
}
