import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

@main
struct DotFolioApp: App {
    private let container: ModelContainer
    @State private var navigation: AppNavigation
    @State private var session = SessionLock()
    @State private var updates = UpdateCenter()
    @State private var autoLock: SessionAutoLock?
    /// Production uptime checks; runs from launch, window open or not.
    @State private var health: HealthMonitor
    /// "Show in Menu Bar" (Dotfolio menu); not a secret.
    @AppStorage("menuBarExtra") private var showsMenuBarExtra = true

    init() {
        do {
            container = try DotFolioSchema.makeContainer()
        } catch {
            // Metadata store unreadable: fail loudly rather than silently starting empty
            // (an empty store would look like data loss to the user).
            fatalError("Could not open the Dotfolio database: \(error)")
        }
        let navigation = AppNavigation()
        _navigation = State(initialValue: navigation)
        let health = HealthMonitor(container: container, navigation: navigation)
        health.start()
        _health = State(initialValue: health)
    }

    var body: some Scene {
        // "main": the menu bar panel's Open Dotfolio reopens it by this id.
        WindowGroup(id: "main") {
            RootView()
                .environment(navigation)
                .environment(session)
                .environment(updates)
                .environment(health)
                .task { await runAutoLock() }
                .modifier(OpensMainWindow(health: health))
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
                Button("What’s New in Dotfolio") { updates.isShowingWhatsNew = true }
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
        MenuBarExtra(isInserted: $showsMenuBarExtra) {
            MenuBarPanel()
                .environment(health)
                .modifier(OpensMainWindow(health: health))
                .environment(navigation)
                .environment(session)
                .environment(updates)
                .modelContainer(container)
                .environment(\.secretStore, KeychainStore.secrets(bundleID: Self.bundleID))
                // Keeps the session's auto-lock running even with the main window closed.
                .task { await runAutoLock() }
        } label: {
            // A site down shows in the menu bar too, with its own symbol.
            Label("Dotfolio", systemImage: health.downProjects.isEmpty ? "lock.doc" : "exclamationmark.triangle.fill")
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

/// Hands the scene's `openWindow` to the health monitor, so a notification
/// clicked with the window closed can open it again.
private struct OpensMainWindow: ViewModifier {
    let health: HealthMonitor
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { health.openMainWindow = { openWindow(id: "main") } }
    }
}
