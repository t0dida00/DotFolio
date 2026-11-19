import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

@main
struct DotFolioApp: App {
    private let container: ModelContainer
    @State private var navigation = AppNavigation()
    @State private var session = SessionLock()

    init() {
        do {
            container = try DotFolioSchema.makeContainer()
        } catch {
            // Metadata store unreadable: fail loudly rather than silently starting empty
            // (an empty store would look like data loss to the user).
            fatalError("Could not open the DotFolio database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(navigation)
                .environment(session)
                .task {
                    // Auto-lock: drop the Touch ID session after inactivity.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15))
                        session.lockIfExpired()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(container)
        .environment(\.secretStore, KeychainStore.secrets(bundleID: Self.bundleID))
        .commands {
            // After "About DotFolio": always present (the app has no Settings
            // scene yet, so an .appSettings anchor may not exist).
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Erase All Data…") { navigation.isConfirmingErase = true }
            }
        }
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "app.dotfolio.DotFolio" }
}
