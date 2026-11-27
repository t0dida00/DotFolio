import AppKit
import DotFolioIntegrations
import DotFolioModels
import SwiftUI

struct WaitingStep: View {
    let model: ConnectionFlowModel
    let code: ConnectionFlowModel.DeviceCode
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            StepHeader(title: "Enter this code on GitHub", subtitle: "The code is copied. Your browser will open the confirmation page.")

            HStack(spacing: DS.Space.m) {
                Text(code.userCode)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .clickableCursor()
                .foregroundStyle(.secondary)
                .help("Copy code")
                .symbolMotion(.bounce)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
            .background(.quaternary.opacity(DS.Fill.control), in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))

            HStack(spacing: DS.Space.s) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to confirm… Code expires in ") + Text(timerInterval: Date.now...max(code.expiresAt, .now), countsDown: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            HStack(spacing: DS.Space.s) {
                Button(action: model.openVerificationPage) {
                    Label("Open \(code.verificationURL.host() ?? "")\(code.verificationURL.path())", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .clickableCursor()
                .symbolMotion(.bounceUp)
                Button("Cancel", action: model.cancel)
                    .buttonStyle(.bordered)
                    .clickableCursor()
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }
}

struct ConnectedStep: View {
    let model: ConnectionFlowModel
    let account: ConnectionFlowModel.ConnectedAccount

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            StepHeader(title: "Connected to \(account.provider.displayName)", subtitle: "Next, choose the repos to turn into projects.")

            ListSection(title: "Account") {
                HStack(spacing: DS.Space.m) {
                    AccountAvatar(name: account.username, url: account.avatarURL)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.s) {
                            Text(account.username).font(.body.weight(.medium)).lineLimit(1)
                            Label("Read-only", systemImage: "checkmark")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Status.success)
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, DS.Space.xxs)
                                .background(DS.Status.success.opacity(0.12), in: Capsule())
                        }
                        Text(accountDetail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.vertical, DS.Space.s)
            }

            HStack(spacing: DS.Space.s) {
                Button("Choose Repos…", action: model.chooseRepos)
                    .buttonStyle(.borderedProminent)
                    .clickableCursor()
                    .keyboardShortcut(.defaultAction)
                Button("Later", action: model.dismiss)
                    .buttonStyle(.bordered)
                    .clickableCursor()
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }

    private var accountDetail: String {
        let repos = "\(account.repoCount) repos readable (\(account.privateRepoCount) private)"
        guard let email = account.email else { return repos }
        return "\(email) · \(repos)"
    }
}

struct FailedStep: View {
    let model: ConnectionFlowModel
    let failure: ConnectionFlowModel.Failure

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            StepHeader(title: failure == .notConfigured ? "GitHub sign-in needs setup" : "\(model.host.name) isn’t connected yet", subtitle: nil)

            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.Status.danger)
                    .symbolMotion(.wiggle, onAppear: true)
                (Text(failure.title).fontWeight(.semibold) + Text(" ") + Text(failure.message))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Status.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))

            HStack(spacing: DS.Space.s) {
                Button(failure.retryTitle, action: model.retry)
                    .buttonStyle(.borderedProminent)
                    .clickableCursor()
                    .keyboardShortcut(.defaultAction)
                Button("Back", action: model.cancel)
                    .buttonStyle(.bordered)
                    .clickableCursor()
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }
}

/// GitLab sign-in: the instance's address and a personal access token with
/// the read-only `read_api` scope. gitlab.com is filled in; self-hosted
/// starts empty.
struct GitLabHostStep: View {
    @Bindable var model: ConnectionFlowModel
    @FocusState private var focus: Field?

    private enum Field { case host, token }

    private var hostURL: URL? { ConnectionFlowModel.validatedGitLabHost(model.gitLabHost) }
    private var showsHostError: Bool { !model.gitLabHost.isEmpty && hostURL == nil }
    private var hasToken: Bool { !model.gitLabToken.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isSelfHosted: Bool { hostURL.map { $0.host() != GitLabClient.gitLabCom.host() } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            StepHeader(title: isSelfHosted ? "Sign in to your GitLab" : "Sign in to GitLab",
                       subtitle: "Dotfolio reads your projects’ .env.example with a read-only token. It never writes to GitLab.")

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text.fieldTitle("GitLab address", required: true).font(.callout.weight(.medium))
                TextField("", text: $model.gitLabHost)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(maxWidth: 360)
                    .focused($focus, equals: .host)
                    .onSubmit { focus = .token }
                    .fieldHint(showsHostError ? "The address must start with https://"
                                              : "https://gitlab.com, or your company’s server. Only https is supported.",
                               isError: showsHostError)
            }

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text.fieldTitle("Personal access token", required: true).font(.callout.weight(.medium))
                SecureField("", text: $model.gitLabToken)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(maxWidth: 360)
                    .focused($focus, equals: .token)
                    .onSubmit(model.signInToGitLab)
                    .fieldHint("Create one with only the read_api scope. It’s kept in your Keychain.")
                if let hostURL {
                    Link(destination: GitLabClient.tokenPage(for: hostURL)) {
                        Label("Create a token on \(hostURL.host() ?? "GitLab")", systemImage: "arrow.up.forward.square")
                    }
                    .font(.callout)
                    .clickableCursor()
                }
            }

            HStack(spacing: DS.Space.s) {
                Button(action: model.signInToGitLab) {
                    Label { Text("Sign In") } icon: { BrandMark.gitlab.image }
                }
                .buttonStyle(.borderedProminent)
                .clickableCursor()
                .keyboardShortcut(.defaultAction)
                .disabled(hostURL == nil || !hasToken)
                Button("Back", action: model.cancel)
                    .buttonStyle(.bordered)
                    .clickableCursor()
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .onAppear { focus = model.gitLabHost.isEmpty ? .host : .token }
    }
}

struct StepHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title).font(DS.Font.pageTitle)
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProgressStep: View {
    let title: String
    var detail: String?
    var progress: Double?
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                if progress == nil { ProgressView().controlSize(.small) }
                Text(title).font(DS.Font.pageTitle)
            }
            if let progress { ProgressView(value: progress) }
            if let detail { Text(detail).foregroundStyle(.secondary) }
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.cancelAction)
                .clickableCursor()
        }
    }
}
