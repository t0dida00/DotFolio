import AppKit
import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

// MARK: - Detail (right column)

/// One account: login details, its services (each with its projects and
/// Open console), and the projects / variables that use it.
struct AccountDetailView: View {
    let account: Account
    let onOpenProject: (Project) -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @State private var draft: AccountDraft
    @State private var error: String?
    /// "Used by" sections that are open (project IDs, or `libraryID`).
    /// Collapsed by default, unless there is a single section.
    @State private var expanded: Set<String> = []
    /// A lone section starts open; this remembers that it was closed.
    @State private var collapsedSingles: Set<String> = []
    private static let libraryID = "library"

    init(account: Account, onOpenProject: @escaping (Project) -> Void, onDelete: @escaping () -> Void) {
        self.account = account
        self.onOpenProject = onOpenProject
        self.onDelete = onDelete
        _draft = State(initialValue: AccountDraft(account))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                AccountFields(draft: $draft)
                if draft != AccountDraft(account) || error != nil {
                    HStack {
                        if let error { Text(error).font(.callout).foregroundStyle(DS.Status.danger) }
                        Spacer()
                        Button("Revert") { draft = AccountDraft(account); error = nil }
                            .buttonStyle(.bordered)
                        Button("Save Changes", action: save)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
                }
                Divider()
                ServicesSection(account: account)
                Divider()
                usedBy
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Services can also change from elsewhere (e.g. adding a project here
        // or typing a service in a variable); keep the draft's list in sync.
        .onChange(of: account.services) { _, services in draft.services = services }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            AccountTile(services: account.services, size: 52)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(account.login).font(DS.Font.pageTitle).textSelection(.enabled).lineLimit(2)
                Text(account.displayName.isEmpty ? account.usageSummary : "\(account.displayName) · \(account.usageSummary)")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(DS.Status.danger)
            }
            .buttonStyle(.bordered)
            .tint(DS.Status.danger)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .help("Delete account…")
            .accessibilityLabel("Delete account")
            .clickableCursor()
        }
    }

    /// Every key that uses this login, as the same editable table as a
    /// project's: one collapsible section per project (a table per
    /// environment), then the Library keys.
    private var usedBy: some View {
        let keys = AccountKeys(account: account)
        let sectionIDs = keys.projects.map { Self.sectionID($0.project) } + (keys.library.isEmpty ? [] : [Self.libraryID])
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Used by").font(DS.Font.sectionTitle)
                if !keys.isEmpty {
                    Text("\(keys.count) \(keys.count == 1 ? "key" : "keys")").foregroundStyle(.secondary)
                }
                Spacer()
                if sectionIDs.count > 1 {
                    let allOpen = sectionIDs.allSatisfy(expanded.contains)
                    Button(allOpen ? "Collapse All" : "Expand All") {
                        withAnimation(.smooth(duration: 0.2)) { expanded = allOpen ? [] : Set(sectionIDs) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .clickableCursor()
                }
            }
            if keys.isEmpty {
                Text("No keys use this account yet. Set it in a key’s Account column.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: DS.Space.s) {
                    ForEach(keys.projects) { group in
                        AccountKeysSection(
                            title: group.project.name,
                            count: group.count,
                            icon: AnyView(ProjectTile(project: group.project, size: 28)),
                            isExpanded: binding(for: Self.sectionID(group.project), single: sectionIDs.count == 1),
                            onOpen: { onOpenProject(group.project) }
                        ) {
                            ForEach(group.environments) { env in
                                VStack(alignment: .leading, spacing: DS.Space.xs) {
                                    EnvLabel(name: env.environment.name).font(DS.Font.panelTitle)
                                    AccountKeysTable(keys: env.keys)
                                }
                            }
                        }
                    }
                    if !keys.library.isEmpty {
                        AccountKeysSection(
                            title: "Library",
                            count: keys.library.count,
                            icon: AnyView(TintedIcon(symbol: "books.vertical", tint: DS.Palette.violet, size: 28)),
                            isExpanded: binding(for: Self.libraryID, single: sectionIDs.count == 1),
                            onOpen: nil
                        ) {
                            AccountKeysTable(keys: keys.library)
                        }
                    }
                }
            }
        }
    }

    private static func sectionID(_ project: Project) -> String { "\(project.persistentModelID.hashValue)" }

    private func binding(for id: String, single: Bool) -> Binding<Bool> {
        Binding(
            get: { single ? !collapsedSingles.contains(id) : expanded.contains(id) },
            set: { open in
                withAnimation(.smooth(duration: 0.2)) {
                    if single {
                        if open { collapsedSingles.remove(id) } else { collapsedSingles.insert(id) }
                    } else {
                        if open { expanded.insert(id) } else { expanded.remove(id) }
                    }
                }
            }
        )
    }

    private func save() {
        do {
            try AccountEditor.update(account, services: draft.services, login: draft.login,
                                     displayName: draft.displayName, notes: draft.notes, context: context)
            draft = AccountDraft(account)
            error = nil
            navigation.show(.success("Account saved", "\(account.login) was updated."))
        } catch {
            self.error = error.message
            navigation.show(.failed("Couldn’t save the account", error.message))
        }
    }
}

// MARK: - Services and their projects

/// One block per service of the account, each listing its projects
/// (e.g. Firebase project IDs) with Open console.
private struct ServicesSection: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Projects by provider").font(DS.Font.sectionTitle)
            Text("The projects inside each provider — e.g. a Firebase project ID. Open the console straight from here.")
                .font(.callout).foregroundStyle(.secondary)

            if account.services.isEmpty {
                Text("Add a provider above to list its projects.")
                    .foregroundStyle(.secondary)
            }
            ForEach(account.services, id: \.self) { service in
                ServiceProjectsBlock(account: account, service: service)
            }
        }
    }
}
