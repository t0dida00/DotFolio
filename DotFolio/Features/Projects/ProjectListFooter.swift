import SwiftUI

/// Bottom of the project list: New Project, the signed-in accounts (GitHub,
/// GitLab: import, sign out), and one button that lists the repo hosts.
struct ProjectListFooter: View {
    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool
    @AppStorage(RepoConnections.gitHubUserKey) private var gitHubUser = ""
    @AppStorage(RepoConnections.gitLabUserKey) private var gitLabUser = ""
    @AppStorage(RepoConnections.gitLabHostKey) private var gitLabHost = ""

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

            Divider()
            if !gitHubUser.isEmpty {
                accountRow(.github, user: gitHubUser, hostName: "GitHub",
                           importAction: flow.connectGitHub, signOut: flow.requestSignOutGitHub)
            }
            if !gitLabUser.isEmpty {
                accountRow(.gitlab, user: gitLabUser, hostName: gitLabHostName,
                           importAction: flow.connectGitLab, signOut: flow.requestSignOutGitLab)
            }
            if !isSignedIn {
                Text("Sign in to import your repos and their .env.example.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SourceHostButton(flow: flow, gitHubUser: gitHubUser, gitLabUser: gitLabUser, gitLabHostName: gitLabHostName)
        }
        .padding(DS.Space.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// "gitlab.com" or the self-hosted server's name.
    private var gitLabHostName: String {
        URL(string: gitLabHost)?.host() ?? "gitlab.com"
    }

    private func accountRow(_ brand: BrandMark, user: String, hostName: String,
                            importAction: @escaping () -> Void, signOut: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Space.s) {
            brand.image.resizable().scaledToFit().frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
            Text("@\(user)").lineLimit(1).truncationMode(.middle)
                .help("Signed in to \(hostName) as @\(user)")
            Spacer(minLength: 4)
            Menu {
                Button("Import Repositories…", action: importAction)
                Divider()
                Button("Sign Out of \(hostName)…", role: .destructive, action: signOut)
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
    }
}

/// "Connect Repositories…" (nothing signed in) or "Import Repositories…":
/// opens the list of repo hosts. A signed-in host imports straight away;
/// the others start their sign-in. GitLab rows need `FeatureFlags.gitLab`.
private struct SourceHostButton: View {
    let flow: ConnectionFlowModel
    let gitHubUser: String
    let gitLabUser: String
    let gitLabHostName: String
    @State private var isOpen = false

    private var isSignedIn: Bool { !gitHubUser.isEmpty || !gitLabUser.isEmpty }

    var body: some View {
        Button { isOpen.toggle() } label: {
            Label(isSignedIn ? "Import Repositories…" : "Connect Repositories…",
                  systemImage: isSignedIn ? "square.and.arrow.down" : "arrow.triangle.branch")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .help(isSignedIn ? "Import repos as projects" : "Sign in to a repo host to import repos")
        .clickableCursor()
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Source control").font(DS.Font.panelTitle)
                    .padding(.horizontal, DS.Space.s)
                    .padding(.bottom, DS.Space.xxs)
                row(.github, "GitHub",
                    gitHubUser.isEmpty ? "github.com · read-only access" : "Signed in as @\(gitHubUser)",
                    tint: DS.Palette.violet, action: flow.connectGitHub)
                if FeatureFlags.gitLab {
                    row(.gitlab, gitLabUser.isEmpty ? "GitLab" : "GitLab · \(gitLabHostName)",
                        gitLabUser.isEmpty ? "gitlab.com · read-only token" : "Signed in as @\(gitLabUser)",
                        tint: DS.Palette.orange, action: flow.connectGitLab)
                    // One GitLab account at a time: sign out to switch servers.
                    if gitLabUser.isEmpty {
                        row(.gitlab, "Self-hosted GitLab…", "Your company’s or client’s server",
                            tint: DS.Palette.orange, action: flow.showGitLabHost)
                    }
                }
            }
            .padding(DS.Space.m)
            .frame(width: 300)
        }
    }

    private func row(_ brand: BrandMark, _ title: String, _ detail: String, tint: Color, action: @escaping () -> Void) -> some View {
        SourceHostRow(brand: brand, title: title, detail: detail, tint: tint) {
            isOpen = false
            action()
        }
    }
}

private struct SourceHostRow: View {
    let brand: BrandMark
    let title: String
    let detail: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                TintedIcon(tint: tint, size: 32) { brand.image.resizable().scaledToFit() }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: DS.Space.s)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(DS.Space.s)
            .background(.quaternary.opacity(hovering ? DS.Fill.control : 0),
                        in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickableCursor()
    }
}
