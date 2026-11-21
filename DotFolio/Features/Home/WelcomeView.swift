import SwiftUI

/// Full-window welcome, shown until the first project exists: who we are,
/// how to add a project, and why it's safe to hand us secrets.
struct WelcomeView: View {
    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: DS.Space.s) {
                    AppMark(size: 96)
                        .padding(.bottom, DS.Space.m)
                    Text("Welcome to DOTFOLIO")
                        .font(.largeTitle.weight(.bold))
                    Text("Keep every project’s secrets in your Keychain — and remember where each one came from.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                VStack(spacing: DS.Space.s) {
                    Button(action: flow.connectGitHub) {
                        ProviderLabel(brand: .github, title: "Continue with GitHub")
                    }
                    .buttonStyle(.borderedProminent)

                    if FeatureFlags.gitLab {
                        Button(action: flow.connectGitLab) {
                            ProviderLabel(brand: .gitlab, title: "Continue with GitLab")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.extraLarge)
                .buttonBorderShape(.capsule)
                .clickableCursor()
                .frame(width: 320)
                .padding(.top, DS.Space.xxl)

                HStack(spacing: DS.Space.s) {
                    Button("Add project manually") { showNewProject = true }
                        .keyboardShortcut("n")
                    Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                    Button("Import a project folder…") {
                        if let folder = ProjectFolderPicker.choose() { navigation.folderToImport = PendingFolder(url: folder) }
                    }
                    if FeatureFlags.gitLab {
                        Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                        Button("Use self-hosted GitLab", action: flow.showGitLabHost)
                    }
                }
                .buttonStyle(.link)
                .clickableCursor()
                .padding(.top, DS.Space.m)

                HStack(alignment: .top, spacing: DS.Space.xxl) {
                    Promise(symbol: "eye", tint: DS.Palette.blue, motion: .bounce, title: "Read-only repos", detail: "Never pushes or writes to your repos.")
                    Promise(symbol: "key.horizontal", tint: DS.Palette.violet, motion: .wiggle, title: "Secrets stay on this Mac", detail: "Stored in Keychain, never in the database.")
                    Promise(symbol: "touchid", tint: DS.Palette.magenta, motion: .pulse, title: "Touch ID", detail: "Locks itself when you step away.")
                }
                .frame(maxWidth: 640)
                .padding(.top, 44)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Vertically centered when the window is taller than the content.
        .defaultScrollAnchor(.center)
        // Dropping a project folder anywhere on the welcome screen imports it.
        .projectFolderDropTarget(navigation)
    }
}

private struct Promise: View {
    let symbol: String
    var tint: Color = DS.Palette.violet
    let motion: SymbolMotion
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.s) {
            TintedIcon(symbol: symbol, tint: tint, size: 40)
                .symbolMotion(motion, onAppear: true)
            Text(title).fontWeight(.semibold)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ProviderLabel: View {
    let brand: BrandMark
    let title: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            brand.image.resizable().scaledToFit().frame(width: 16, height: 16)
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
