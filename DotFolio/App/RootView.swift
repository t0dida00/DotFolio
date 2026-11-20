import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Hosts the home window plus app-wide confirmations (Erase All Data, sign-out).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(UpdateCenter.self) private var updates
    @State private var flow = ConnectionFlowModel()
    @State private var eraseError: String?
    /// Suggest Sources opens by itself once, the first time this version runs.
    @AppStorage("didReviewSourceSuggestions") private var didReviewSources = false

    var body: some View {
        @Bindable var navigation = navigation
        HomeView(model: flow)
        .onAppear {
            // Category words typed as providers before Service/Provider were split.
            ServiceCategoryMigration.run(context: context)
            flow.configure(context: context,
                           tokens: KeychainStore.oauthTokens(bundleID: DotFolioApp.bundleID),
                           secrets: KeychainStore.secrets(bundleID: DotFolioApp.bundleID))
            offerSourceSuggestionsOnce()
        }
        .sheet(isPresented: $navigation.isVerifyingData) { VerifyDataSheet() }
        .sheet(isPresented: $navigation.isSuggestingSources) { SuggestSourcesSheet() }
        .sheet(isPresented: Binding(get: { updates.isShowingResult }, set: { updates.isShowingResult = $0 })) {
            UpdateResultSheet(center: updates)
        }
        .sheet(isPresented: Binding(get: { updates.isShowingWhatsNew }, set: { updates.isShowingWhatsNew = $0 })) {
            WhatsNewSheet(center: updates)
        }
        .confirmationDialog("Erase all DOTFOLIO data?", isPresented: $navigation.isConfirmingErase) {
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

    /// First launch with this feature: if anything can be filled, show the
    /// review once. Marked done either way, so it never comes back by itself.
    private func offerSourceSuggestionsOnce() {
        guard !didReviewSources else { return }
        didReviewSources = true
        guard !SourceSuggester.reviewAll(context: context).isEmpty else { return }
        Task {
            try? await Task.sleep(for: .seconds(1)) // let the window settle first
            if !navigation.isVerifyingData && !updates.isShowingWhatsNew && !updates.isShowingResult {
                navigation.isSuggestingSources = true
            }
        }
    }

    private func signOutMessage(_ plan: ConnectionFlowModel.SignOutPlan) -> String {
        let account = plan.login.isEmpty ? "this account" : "@\(plan.login)"
        guard !plan.projects.isEmpty else {
            return "DOTFOLIO forgets \(account). No projects came from it."
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
        .environment(UpdateCenter())
}
