import AppKit
import DotFolioIntegrations
import DotFolioModels
import SwiftUI

/// Lists every repo the signed-in account can read (GitHub App installs, or
/// GitLab projects you're a member of); pick some to import as projects.
struct RepoPickerStep: View {
    @Bindable var model: ConnectionFlowModel

    private var selectable: [GitHubRepo] { model.filteredRepos.filter { !model.isImported($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                StepHeader(
                    title: "Import repositories",
                    subtitle: "\(model.account.map { "Signed in as @\($0.login) · " } ?? "")\(model.repos.count) repositories DOTFOLIO can read"
                )
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshRepos)
                    .labelStyle(.iconOnly)
                    .symbolMotion(.rotate)
                    .buttonStyle(.borderless)
                    .help("Reload the list from \(model.host.name)")
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

                if model.host == .github { installHint }
            }

            HStack {
                Button("Sign Out of \(model.host.name)…", action: model.requestSignOut)
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
            Text("Missing a repo? DOTFOLIO only sees repos where its GitHub App is installed.")
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
            Text(model.host == .github
                 ? "Install DOTFOLIO’s GitHub App on your account or organization and choose which repos it can read, then refresh."
                 : "This account isn’t a member of any project on \(model.host.name) yet. Join one, then refresh.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.host == .github, let url = GitHubConfig.installURL {
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

struct RepoRow: View {
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
