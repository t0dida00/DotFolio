import SwiftUI

/// Bottom of the project list: New Project, then the GitHub account (import,
/// sign out) or, before sign-in, the sign-in buttons.
struct ProjectListFooter: View {
    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool
    @AppStorage(RepoConnections.gitHubUserKey) private var gitHubUser = ""
    @AppStorage(RepoConnections.gitLabUserKey) private var gitLabUser = ""

    private var isSignedIn: Bool { !gitHubUser.isEmpty || !gitLabUser.isEmpty }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Button { showNewProject = true } label: {
                Label("New Project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .keyboardShortcut("n")
            .help("New Project (⌘N)")
            .clickableCursor()
            .symbolMotion(.bounce)

            if !gitHubUser.isEmpty {
                Divider()
                HStack(spacing: DS.Space.s) {
                    BrandMark.github.image.resizable().scaledToFit().frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                    Text("@\(gitHubUser)").lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Menu {
                        Button("Import Repositories…", action: flow.connectGitHub)
                        Divider()
                        Button("Sign Out of GitHub…", role: .destructive, action: flow.requestSignOutGitHub)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .symbolMotion(.bounce)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .clickableCursor()
                }
                .font(.callout)
                Button(action: flow.connectGitHub) {
                    Label("Import from GitHub", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .symbolMotion(.bounceDown)
                .buttonBorderShape(.capsule)
                .clickableCursor()
            }

            // Shown until a GitHub (or, once supported, GitLab) account is linked.
            if !isSignedIn {
                Divider()
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(FeatureFlags.gitLab
                         ? "Sign in to GitHub or GitLab to import your repos and their .env.example."
                         : "Sign in to GitHub to import your repos and their .env.example.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: DS.Space.s) {
                        Button(action: flow.connectGitHub) {
                            Label { Text("GitHub") } icon: { BrandMark.github.image.resizable().scaledToFit().frame(width: 13, height: 13) }
                                .frame(maxWidth: .infinity)
                        }
                        if FeatureFlags.gitLab {
                            Button(action: flow.connectGitLab) {
                                Label { Text("GitLab") } icon: { BrandMark.gitlab.image.resizable().scaledToFit().frame(width: 13, height: 13) }
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
                    if FeatureFlags.gitLab {
                        Button("Self-hosted GitLab…", action: flow.showGitLabHost)
                            .buttonStyle(.link)
                            .font(.callout)
                            .clickableCursor()
                    }
                }
            }
        }
        .padding(DS.Space.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
