import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Home window. One full-window stage at a time:
/// - nothing yet (no projects, not signed in, no accounts or Library keys)
///   → welcome screen,
/// - otherwise → project list (an empty one says "No projects"),
/// - New Project form or a GitHub/GitLab sign-in → shown inline instead.
struct HomeView: View {
    @Bindable var model: ConnectionFlowModel
    @Query private var projects: [Project]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Variable> { $0.inLibrary }) private var libraryKeys: [Variable]
    @AppStorage(RepoConnections.gitHubUserKey) private var gitHubUser = ""
    @AppStorage(RepoConnections.gitLabUserKey) private var gitLabUser = ""
    @State private var showNewProject = false

    /// The layout is not responsive: below this size it would squeeze tiles,
    /// tabs and tables, so the window can't get smaller (it can grow).
    static let minSize = CGSize(width: 1200, height: 760)
    /// Room for the traffic lights on rows that sit in the title bar area.
    static let trafficLightInset: CGFloat = 80

    private enum Stage: Equatable { case welcome, list, newProject, connecting }

    private var stage: Stage {
        if model.step != .idle { return .connecting }
        if showNewProject { return .newProject }
        return isFirstRun ? .welcome : .list
    }

    /// Deleting the last project keeps the list when anything else is still
    /// there (a sign-in, accounts, Library keys) so those stay reachable.
    private var isFirstRun: Bool {
        projects.isEmpty && accounts.isEmpty && libraryKeys.isEmpty && gitHubUser.isEmpty && gitLabUser.isEmpty
    }

    var body: some View {
        Group {
            switch stage {
            case .welcome:
                WelcomeView(flow: model, showNewProject: $showNewProject)
            case .list:
                ProjectBrowser(flow: model, showNewProject: $showNewProject)
            case .newProject:
                NewProjectForm(onClose: { showNewProject = false })
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity)
            case .connecting:
                // Every step (code, loading, connected, repo picker, import)
                // sits in the middle of the window, both ways. A narrow step is
                // only as wide as its content, so short text isn't pushed left.
                GeometryReader { viewport in
                    ScrollView {
                        CappedWidth(max: model.isWideStep ? 760 : 460) {
                            ConnectionFlowSteps(model: model)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 56)
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Full-window steps run under the hidden title bar. The project list
        // has a real toolbar (sort, search) there, so it starts below it.
        .ignoresSafeArea(edges: stage == .list ? [] : .all)
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.smooth(duration: 0.2), value: stage)
        // Starting a sign-in replaces the form; don't bring it back afterwards.
        .onChange(of: model.step) { _, step in if step != .idle { showNewProject = false } }
    }
}

// MARK: - Shared pieces

#Preview("Home") {
    HomeView(model: ConnectionFlowModel())
        .modelContainer(try! DotFolioSchema.makeContainer(inMemory: true))
        .environment(AppNavigation())
        .environment(SessionLock())
        .environment(UpdateCenter())
}

#Preview("Failed") {
    HomeView(model: ConnectionFlowModel(step: .failed(.codeExpired)))
        .modelContainer(try! DotFolioSchema.makeContainer(inMemory: true))
        .environment(AppNavigation())
        .environment(SessionLock())
        .environment(UpdateCenter())
}

#Preview("Self-hosted GitLab") {
    HomeView(model: ConnectionFlowModel(step: .gitLabHost))
        .modelContainer(try! DotFolioSchema.makeContainer(inMemory: true))
        .environment(AppNavigation())
        .environment(SessionLock())
        .environment(UpdateCenter())
}

#Preview("Dark") {
    HomeView(model: ConnectionFlowModel())
        .modelContainer(try! DotFolioSchema.makeContainer(inMemory: true))
        .environment(AppNavigation())
        .environment(SessionLock())
        .environment(UpdateCenter())
        .preferredColorScheme(.dark)
}
