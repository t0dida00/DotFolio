import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Hosts the home window plus app-wide confirmations (Erase All Data, sign-out).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @State private var flow = ConnectionFlowModel()
    @State private var eraseError: String?

    var body: some View {
        @Bindable var navigation = navigation
        HomeView(model: flow)
        .onAppear {
            flow.configure(context: context,
                           tokens: KeychainStore.oauthTokens(bundleID: DotFolioApp.bundleID),
                           secrets: KeychainStore.secrets(bundleID: DotFolioApp.bundleID))
        }
        .confirmationDialog("Erase all DotFolio data?", isPresented: $navigation.isConfirmingErase) {
            Button("Erase All Data", role: .destructive, action: eraseAll)
        } message: {
            Text("This permanently deletes every project, account and variable, and removes all stored values and sign-in tokens from your Keychain. This can’t be undone.")
        }
        .confirmationDialog(
            "Sign out of GitHub?",
            isPresented: Binding(get: { flow.pendingSignOut != nil }, set: { if !$0 { flow.pendingSignOut = nil } }),
            presenting: flow.pendingSignOut
        ) { plan in
            Button(plan.projects.isEmpty ? "Sign Out" : "Sign Out and Delete \(plan.projects.count) Projects", role: .destructive) {
                flow.confirmSignOut()
            }
        } message: { plan in
            Text(signOutMessage(plan))
        }
        .alert("Couldn’t erase data", isPresented: Binding(get: { eraseError != nil }, set: { if !$0 { eraseError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(eraseError ?? "")
        }
    }

    private func signOutMessage(_ plan: ConnectionFlowModel.SignOutPlan) -> String {
        let account = plan.login.isEmpty ? "this account" : "@\(plan.login)"
        guard !plan.projects.isEmpty else {
            return "DotFolio forgets \(account). No projects came from it."
        }
        let values = plan.projects.flatMap(\.allVariables).filter(\.hasValue).count
        let names = plan.projects.prefix(3).map(\.name).joined(separator: ", ") + (plan.projects.count > 3 ? "…" : "")
        var text = "The \(plan.projects.count) projects imported from \(account) (\(names)) are deleted"
        text += values > 0 ? ", along with \(values) stored values in your Keychain." : "."
        return text + " Projects you created by hand are kept. This can’t be undone."
    }

    private func eraseAll() {
        let bundleID = DotFolioApp.bundleID
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
