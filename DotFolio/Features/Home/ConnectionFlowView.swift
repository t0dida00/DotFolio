import AppKit
import DotFolioIntegrations
import DotFolioModels
import SwiftUI

/// The current step of a GitHub/GitLab sign-in.
struct ConnectionFlowSteps: View {
    @Bindable var model: ConnectionFlowModel

    var body: some View {
        switch model.step {
        case .idle: EmptyView()
        case .gitLabHost: GitLabHostStep(model: model)
        case .waitingForGitHub(let code): WaitingStep(model: model, code: code)
        case .connected(let account): ConnectedStep(model: model, account: account)
        case .failed(let failure): FailedStep(model: model, failure: failure)
        case .loading(let message): ProgressStep(title: message, onCancel: model.cancel)
        case .choosingRepos: RepoPickerStep(model: model)
        case .importing(let done, let total): ImportProgressView(model: model, done: done, total: total)
        case .importFinished(let summary): ImportFinishedView(model: model, summary: summary)
        }
    }
}

// MARK: - Flow steps

private struct WaitingStep: View {
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

private struct ConnectedStep: View {
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

private struct FailedStep: View {
    let model: ConnectionFlowModel
    let failure: ConnectionFlowModel.Failure

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            StepHeader(title: failure == .notConfigured ? "GitHub sign-in needs setup" : "GitHub isn’t connected yet", subtitle: nil)

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

private struct GitLabHostStep: View {
    @Bindable var model: ConnectionFlowModel
    @FocusState private var focused: Bool

    private var isValid: Bool { ConnectionFlowModel.validatedGitLabHost(model.gitLabHost) != nil }
    private var showsError: Bool { !model.gitLabHost.isEmpty && !isValid }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            StepHeader(title: "Self-hosted GitLab", subtitle: "Enter the address of your company’s or client’s GitLab.")

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("GitLab address").font(.callout.weight(.medium))
                TextField("https://gitlab.example.com", text: $model.gitLabHost)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(maxWidth: 360)
                    .focused($focused)
                    .onSubmit(model.connectSelfHostedGitLab)
                Text(showsError ? "The address must start with https://" : "Only https is supported, so your sign-in code can’t be intercepted.")
                    .font(.caption)
                    .foregroundStyle(showsError ? AnyShapeStyle(DS.Status.danger) : AnyShapeStyle(.secondary))
            }

            HStack(spacing: DS.Space.s) {
                Button(action: model.connectSelfHostedGitLab) {
                    Label { Text("Continue") } icon: { BrandMark.gitlab.image }
                }
                .buttonStyle(.borderedProminent)
                .clickableCursor()
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                Button("Back", action: model.cancel)
                    .buttonStyle(.bordered)
                    .clickableCursor()
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Building blocks

/// Section with a small gray header, like "Recent" / "Connections".
struct ListSection<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            header
                .font(DS.Font.panelTitle)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DS.Space.xs) { content }
                .padding(.leading, DS.Space.m)
        }
    }
}

extension ListSection where Header == Text {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.header = Text(title)
        self.content = content()
    }
}

/// Icon tile + title + secondary line.
struct ListRow: View {
    enum Tile { case symbol(String), brand(BrandMark) }

    let tile: Tile
    let title: Text
    let subtitle: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            TintedIcon(tint: DS.Palette.violet, size: 40) {
                switch tile {
                case .symbol(let name): Image(systemName: name).font(.system(size: 16, weight: .medium)).symbolMotion(.bounce)
                case .brand(let mark): mark.image.resizable().scaledToFit().frame(width: 18, height: 18)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                title.font(.body).lineLimit(1)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, DS.Space.s)
        .accessibilityElement(children: .combine)
    }
}

private struct StepHeader: View {
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

struct AccountAvatar: View {
    let name: String
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(initials)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor)
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Loading / importing

private struct ProgressStep: View {
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

// MARK: - Repo picker

/// Lists every repo the GitHub App can read; pick some to import as projects.
private struct RepoPickerStep: View {
    @Bindable var model: ConnectionFlowModel

    private var selectable: [GitHubRepo] { model.filteredRepos.filter { !model.isImported($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                StepHeader(
                    title: "Import repositories",
                    subtitle: "\(model.account.map { "Signed in as @\($0.login) · " } ?? "")\(model.repos.count) repositories DotFolio can read"
                )
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshRepos)
                    .labelStyle(.iconOnly)
                    .symbolMotion(.rotate)
                    .buttonStyle(.borderless)
                    .help("Reload the list from GitHub")
                    .clickableCursor()
            }

            if model.repos.isEmpty {
                noRepos
            } else {
                HStack(spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter repositories", text: $model.repoFilter).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: 30)
                    .background(.quaternary.opacity(DS.Fill.control), in: Capsule())

                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected { model.selectedRepoIDs.subtract(selectable.map(\.id)) }
                        else { model.selectedRepoIDs.formUnion(selectable.map(\.id)) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectable.isEmpty)
                    .clickableCursor()
                }

                List {
                    ForEach(model.filteredRepos) { repo in
                        RepoRow(repo: repo, imported: model.isImported(repo), isOn: Binding(
                            get: { model.selectedRepoIDs.contains(repo.id) },
                            set: { if $0 { model.selectedRepoIDs.insert(repo.id) } else { model.selectedRepoIDs.remove(repo.id) } }
                        ))
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 260, maxHeight: 420)

                installHint
            }

            HStack {
                Button("Sign Out of GitHub…", action: model.requestSignOutGitHub)
                    .buttonStyle(.link)
                    .clickableCursor()
                Spacer()
                Button("Cancel", action: model.cancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Import \(model.selectedRepoIDs.count == 0 ? "" : "\(model.selectedRepoIDs.count) ")Repositories", action: model.importSelected)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedRepoIDs.isEmpty)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
    }

    private var allSelected: Bool {
        !selectable.isEmpty && selectable.allSatisfy { model.selectedRepoIDs.contains($0.id) }
    }

    /// GitHub Apps only see repos where they're installed.
    @ViewBuilder
    private var installHint: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Missing a repo? DotFolio only sees repos where its GitHub App is installed.")
                .foregroundStyle(.secondary)
            if let url = GitHubConfig.installURL {
                Link("Manage access", destination: url).clickableCursor()
            }
        }
        .font(.callout)
    }

    private var noRepos: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("No repositories yet").font(DS.Font.sectionTitle)
            Text("Install DotFolio’s GitHub App on your account or organization and choose which repos it can read, then refresh.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = GitHubConfig.installURL {
                Link(destination: url) { Label("Install on GitHub", systemImage: "arrow.up.forward.square") }
                    .clickableCursor()
                    .symbolMotion(.bounceUp)
            }
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(DS.Fill.subtle), in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
    }
}

private struct RepoRow: View {
    let repo: GitHubRepo
    let imported: Bool
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(imported)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.s) {
                    Text(repo.fullName).fontWeight(.medium).lineLimit(1)
                    if repo.isPrivate {
                        Label("Private", systemImage: "lock.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Private repository")
                    }
                }
                if let description = repo.description, !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if imported {
                Text("Added").font(DS.Font.label).foregroundStyle(.secondary)
            } else if let updated = repo.updatedAt {
                Text(updated.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .contentShape(Rectangle())
        .onTapGesture { if !imported { isOn.toggle() } }
        .clickableCursor()
        .opacity(imported ? 0.6 : 1)
    }
}
