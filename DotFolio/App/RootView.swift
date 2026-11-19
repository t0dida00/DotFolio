import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Switches the main window between the home screen and a project's detail
/// stage (opened by double-clicking a project). Also hosts "Erase All Data".
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @State private var flow = ConnectionFlowModel()
    @State private var eraseError: String?

    var body: some View {
        @Bindable var navigation = navigation
        Group {
            if let project = openProject {
                ProjectWorkspace(project: project)
                    .id(project.persistentModelID)
            } else {
                HomeView(model: flow)
            }
        }
        .animation(.smooth(duration: 0.2), value: navigation.openProjectID)
        .onAppear {
            flow.configure(context: context, tokens: KeychainStore.oauthTokens(bundleID: DotFolioApp.bundleID))
        }
        .confirmationDialog("Erase all DotFolio data?", isPresented: $navigation.isConfirmingErase) {
            Button("Erase All Data", role: .destructive, action: eraseAll)
        } message: {
            Text("This permanently deletes every project, group, account and variable, and removes all stored values and sign-in tokens from your Keychain. This can’t be undone.")
        }
        .alert("Couldn’t erase data", isPresented: Binding(get: { eraseError != nil }, set: { if !$0 { eraseError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(eraseError ?? "")
        }
    }

    /// Nil when nothing is open, or when the open project was deleted.
    private var openProject: Project? {
        guard let id = navigation.openProjectID,
              let project = context.registeredModel(for: id) as Project?,
              !project.isDeleted
        else { return nil }
        return project
    }

    private func eraseAll() {
        let bundleID = DotFolioApp.bundleID
        navigation.goHome()
        flow.cancel()
        do {
            try DataEraser.eraseAll(context: context, secretStores: [
                KeychainStore.secrets(bundleID: bundleID),
                KeychainStore.oauthTokens(bundleID: bundleID),
            ])
            for key in ["home.sort", "workspace.variableSort", RepoConnections.gitHubUserKey, RepoConnections.gitLabUserKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        } catch DataEraser.Failure.keychain(let error) {
            let detail = (error as? KeychainError)?.userMessage ?? error.localizedDescription
            eraseError = "Values in the Keychain couldn’t be removed, so nothing was deleted. \(detail)"
        } catch {
            eraseError = error.localizedDescription
        }
    }
}

#Preview {
    RootView()
        .modelContainer(try! DotFolioSchema.makeContainer(inMemory: true))
        .environment(AppNavigation())
        .environment(SessionLock())
}
