import SwiftUI

/// Full-window welcome, shown until the first project exists: who we are,
/// how to add a project, and why it's safe to hand us secrets.
struct WelcomeView: View {
    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    AppMark(size: 96)
                        .padding(.bottom, 12)
                    Text("Welcome to DotFolio")
                        .font(.largeTitle.weight(.bold))
                    Text("Keep every project’s secrets in your Keychain — and remember where each one came from.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                VStack(spacing: 10) {
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
                .padding(.top, 28)

                HStack(spacing: 10) {
                    Button("Add project manually") { showNewProject = true }
                        .keyboardShortcut("n")
                    if FeatureFlags.gitLab {
                        Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                        Button("Use self-hosted GitLab", action: flow.showGitLabHost)
                    }
                }
                .buttonStyle(.link)
                .clickableCursor()
                .padding(.top, 14)

                HStack(alignment: .top, spacing: 28) {
                    Promise(symbol: "eye", motion: .bounce, title: "Read-only repos", detail: "Never pushes or writes to your repos.")
                    Promise(symbol: "key.horizontal", motion: .wiggle, title: "Secrets stay on this Mac", detail: "Stored in Keychain, never in the database.")
                    Promise(symbol: "touchid", motion: .pulse, title: "Touch ID", detail: "Locks itself when you step away.")
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
    }
}

private struct Promise: View {
    let symbol: String
    let motion: SymbolMotion
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
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
        HStack(spacing: 8) {
            brand.image.resizable().scaledToFit().frame(width: 16, height: 16)
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
