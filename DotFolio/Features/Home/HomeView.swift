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
        // Content runs under the hidden title bar.
        .ignoresSafeArea()
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.smooth(duration: 0.2), value: stage)
        // Starting a sign-in replaces the form; don't bring it back afterwards.
        .onChange(of: model.step) { _, step in if step != .idle { showNewProject = false } }
    }
}

// MARK: - Shared pieces

/// Proposes at most `max` points of width and takes only what the content
/// needs (a `.frame(maxWidth:)` would always take the full `max`), so a short
/// step can be centered by its parent.
struct CappedWidth: Layout {
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = Swift.min(proposal.width ?? max, max)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// GitHub/GitLab mark or a folder, sized for toolbar labels and rows.
struct ProviderIcon: View {
    let provider: RepoProvider

    var body: some View {
        switch provider {
        case .github: BrandMark.github.image.resizable().scaledToFit().frame(width: 15, height: 15)
        case .gitlab: BrandMark.gitlab.image.resizable().scaledToFit().frame(width: 15, height: 15)
        case .none: Image(systemName: "folder")
        }
    }
}


/// App mark used on onboarding. Placeholder until a real app icon exists.
struct AppMark: View {
    var size: CGFloat = 36

    /// Same proportions as the app icon (scripts/render-app-icon.swift): a
    /// squircle with ~22.5% corners and one big glyph filling about three
    /// quarters of it, centered.
    private enum Ratio {
        static let corner: CGFloat = 0.225
        static let glyphWidth: CGFloat = 0.72
        static let glyphHeight: CGFloat = 0.76
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * Ratio.corner, style: .continuous)
    }

    var body: some View {
        tile
            // Brand gradient: lighter violet at the top, deeper at the bottom.
            .fill(LinearGradient(colors: [Color(light: 0x8A7CF4, dark: 0x968BF0), Color(light: 0x5543D0, dark: 0x5A4AD6)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            // Thin light rim, brighter at the top, like a lit edge.
            .overlay(
                tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: max(1, size * 0.012))
            )
            .overlay {
                // One large, light glyph: white fading to a soft lavender.
                Image(systemName: "lock.doc.fill")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .frame(width: size * Ratio.glyphWidth, height: size * Ratio.glyphHeight)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(light: 0xE4DFFF, dark: 0xDCD6FF)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(light: 0x2E2290, dark: 0x1E1660).opacity(0.35), radius: size * 0.02, y: size * 0.012)
                    .symbolMotion(.bounce, onAppear: true)
            }
            // Two layers, like a macOS app icon: a tight contact shadow and a
            // soft ambient one below. Both scale with the mark.
            .shadow(color: .black.opacity(0.18), radius: size * 0.025, y: size * 0.012)
            .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// Brand marks live in the asset catalog as template SVGs.
enum BrandMark: String {
    case github = "github-mark"
    case gitlab = "gitlab-mark"

    var image: Image { Image(rawValue) }
}

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
