import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Home window. One full-window stage at a time:
/// - no projects yet → welcome screen,
/// - projects exist → project list,
/// - New Project form or a GitHub/GitLab sign-in → shown inline instead.
struct HomeView: View {
    @Bindable var model: ConnectionFlowModel
    @Query private var projects: [Project]
    @State private var showNewProject = false

    static let minSize = CGSize(width: 760, height: 560)
    /// Room for the traffic lights on rows that sit in the title bar area.
    static let trafficLightInset: CGFloat = 80

    private enum Stage: Equatable { case welcome, list, newProject, connecting }

    private var stage: Stage {
        if model.step != .idle { return .connecting }
        if showNewProject { return .newProject }
        return projects.isEmpty ? .welcome : .list
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
                ScrollView {
                    ConnectionFlowSteps(model: model)
                        .frame(maxWidth: model.isWideStep ? 760 : 460, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 40)
                        .padding(.top, 72)
                        .padding(.bottom, DS.Space.xxxl)
                }
                .scrollBounceBehavior(.basedOnSize)
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

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            // Brand gradient: violet → blue.
            .fill(LinearGradient(colors: [Color(light: 0x7B6CF0, dark: 0x8F84EC), Color(light: 0x3B5BDB, dark: 0x3F63E0)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolMotion(.bounce, onAppear: true)
            }
            // Two layers, like a macOS app icon: a tight contact shadow and a
            // soft ambient one below. Both scale with the mark.
            .shadow(color: .black.opacity(0.22), radius: size * 0.03, y: size * 0.015)
            .shadow(color: .black.opacity(0.25), radius: size * 0.14, y: size * 0.08)
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
