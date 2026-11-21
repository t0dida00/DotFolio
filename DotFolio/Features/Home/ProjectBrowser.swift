import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Full-window browser (shown once anything exists): toolbar (sort, search)
/// above two columns — a fixed list column (brand, Projects · Accounts ·
/// Libraries, that mode's list and footer) and the detail column.
///
/// This view only holds what the modes share: the mode, the search, the
/// open project tabs and selection, and the delete confirmations. Each
/// column's content is its own view.
struct ProjectBrowser: View {
    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(AppNavigation.self) private var navigation
    @Query private var projects: [Project]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Variable> { $0.inLibrary }) private var libraryKeys: [Variable]
    /// Every project variable: the Library shows them too (one row per environment).
    @Query(filter: #Predicate<Variable> { !$0.inLibrary }) private var projectKeys: [Variable]

    /// Left column shows projects, service accounts, or the key Library.
    enum Mode: String, CaseIterable { case projects = "Projects", accounts = "Accounts", libraries = "Libraries" }
    @State private var mode: Mode = .projects

    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool

    // Search and sort (toolbar), project filter.
    @State private var query = ""
    @AppStorage("home.sort") private var sort: ProjectSort = .name
    /// All · Git · Local under the Projects tab (remembered; not a secret).
    @AppStorage("home.originFilter") private var originFilter: ProjectOriginFilter = .all

    // Projects: open tabs (the active one is the selected project) and the
    // rows highlighted in the list (⌘/⇧-click pick several for bulk actions).
    @State private var tabs = TabStrip<PersistentIdentifier>()
    @State private var listSelection: Set<PersistentIdentifier> = []
    /// Where a ⇧-click range starts (the last plain or ⌘ click).
    @State private var listAnchor: PersistentIdentifier?
    @State private var projectsPendingDeletion: [Project] = []

    // Accounts (kept here so the Overview can open one).
    @State private var accountSelection: PersistentIdentifier?
    @State private var isCreatingAccount = false
    @State private var accountPendingDeletion: Account?

    // Library.
    /// All · Library · development · staging · production (remembered).
    @AppStorage("library.scope") private var libraryScope = "all"
    /// Provider shown in the Library (nil = all).
    @State private var libraryProvider: String?
    @State private var libraryFocusRequest = 0

    /// Width of the list column (brand, mode picker, list, footer).
    static let sidebarWidth: CGFloat = 320

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Library groups are built once per redraw, and only in that mode.
        let library = mode == .libraries ? libraryGroups() : (all: [], shown: [])
        VStack(spacing: 0) {
            BrowserToolbar(sort: $sort, query: $query)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    BrandHeader()
                    Divider()
                        .padding(.horizontal, DS.Space.m)
                    Picker("Show", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, DS.Space.m)
                    .padding(.vertical, DS.Space.s)
                    .clickableCursor()

                    switch mode {
                    case .projects:
                        ProjectSidebar(
                            projects: projects, rows: results, query: query, flow: flow,
                            originFilter: $originFilter, listSelection: $listSelection, listAnchor: $listAnchor,
                            showNewProject: $showNewProject, activeTab: tabs.active,
                            onOpenInTabs: openInTabs,
                            onDelete: { projectsPendingDeletion = $0 }
                        )
                    case .accounts:
                        AccountList(accounts: accounts, query: query, selection: $accountSelection,
                                    onDelete: { accountPendingDeletion = $0 })
                            .frame(maxHeight: .infinity)
                        SidebarFooterButton(title: "New Account") {
                            accountSelection = nil
                            isCreatingAccount = true
                        }
                    case .libraries:
                        LibrarySidebar(groups: library.all, scope: $libraryScope,
                                       provider: $libraryProvider, focusRequest: $libraryFocusRequest)
                    }
                }
                // Fixed width: the list column never stretches or squeezes.
                .frame(width: Self.sidebarWidth)
                Divider()
                VStack(spacing: 0) {
                    switch mode {
                    case .projects:
                        if !tabs.isEmpty {
                            ProjectTabBar(tabs: openProjects, strip: $tabs)
                        }
                        projectDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .accounts:
                        AccountsDetailColumn(
                            accounts: accounts, selection: $accountSelection, isCreating: $isCreatingAccount,
                            onOpenProject: { project in
                                mode = .projects
                                tabs.active = project.persistentModelID
                            },
                            onDelete: { accountPendingDeletion = $0 }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .libraries:
                        LibraryView(groups: library.shown, total: library.all.reduce(0) { $0 + $1.keys.count },
                                    focusRequest: libraryFocusRequest, scope: libraryScope,
                                    nothingSelected: !library.all.isEmpty && libraryProvider != nil
                                        && !library.all.contains { $0.id == libraryProvider })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // No auto-open: with no tab open the Overview dashboard is the home view.
        .onChange(of: projects.count) { _, _ in tabs.prune(keeping: Set(projects.map(\.persistentModelID))) }
        // A project just imported from a folder: show it.
        .onChange(of: navigation.projectToOpen, initial: true) { _, id in
            guard let id, let project = projects.first(where: { $0.id == id }) else { return }
            mode = .projects
            query = ""
            if !originFilter.matches(project) { originFilter = .all }
            tabs.active = project.persistentModelID
            navigation.projectToOpen = nil
        }
        .onChange(of: tabs.active) { _, id in
            if let id { tabs.add(id) }
            selectedProject?.lastOpenedAt = .now
            // Keep the list highlight on the active tab, unless several rows
            // are selected for a bulk action.
            if listSelection.count <= 1 { listSelection = id.map { [$0] } ?? [] }
        }
        .onChange(of: listSelection) { _, ids in
            if ids.count == 1, let id = ids.first, id != tabs.active { tabs.active = id }
        }
        .onChange(of: accountSelection) { _, _ in isCreatingAccount = false }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { !projectsPendingDeletion.isEmpty }, set: { if !$0 { projectsPendingDeletion = [] } })
        ) {
            Button(projectsPendingDeletion.count == 1 ? "Delete Project" : "Delete \(projectsPendingDeletion.count) Projects", role: .destructive) {
                delete(projectsPendingDeletion)
                projectsPendingDeletion = []
            }
        } message: {
            Text(deletionMessage)
        }
        .confirmationDialog(
            "Delete “\(accountPendingDeletion?.login ?? "")”?",
            isPresented: Binding(get: { accountPendingDeletion != nil }, set: { if !$0 { accountPendingDeletion = nil } })
        ) {
            Button("Delete Account", role: .destructive) {
                if let account = accountPendingDeletion {
                    if accountSelection == account.persistentModelID { accountSelection = nil }
                    let login = account.login
                    AccountEditor.delete(account, context: context)
                    navigation.show(.success("Account deleted", "\(login) was removed. Variables that used it keep their values."))
                }
                accountPendingDeletion = nil
            }
        } message: {
            let used = accountPendingDeletion?.allLinkedVariables.count ?? 0
            Text(used == 0
                 ? "Its provider projects (e.g. Firebase projects) are deleted too. This can’t be undone."
                 : "\(used) \(used == 1 ? "variable keeps" : "variables keep") existing but lose this source link. Its provider projects (e.g. Firebase projects) are deleted too. This can’t be undone.")
        }
    }

    // MARK: Projects

    private var results: [(project: Project, match: ProjectSearch.Match)] {
        let sorted = ProjectSearch.sorted(projects.filter(originFilter.matches), by: sort)
        return isSearching ? ProjectSearch.filter(sorted, query: query) : sorted.map { ($0, .name) }
    }

    private var selectedProject: Project? {
        guard let active = tabs.active else { return nil }
        return projects.first { $0.persistentModelID == active }
    }

    private var openProjects: [Project] {
        tabs.ids.compactMap { id in projects.first { $0.persistentModelID == id } }
    }

    @ViewBuilder
    private var projectDetail: some View {
        if let project = selectedProject {
            ProjectPreview(
                project: project,
                onDelete: { projectsPendingDeletion = [project] }
            )
            .id(project.persistentModelID)
        } else {
            // No tab open: show what DotFolio is tracking instead of an empty pane.
            OverviewDashboard(
                onOpenProject: { tabs.active = $0.persistentModelID },
                onShowAccounts: { mode = .accounts },
                onOpenAccount: { account in
                    accountSelection = account.persistentModelID
                    mode = .accounts
                }
            )
        }
    }

    private func openInTabs(_ picked: [Project]) {
        tabs.open(picked.map(\.persistentModelID))
        listSelection = tabs.active.map { [$0] } ?? []
    }

    // MARK: Library

    /// Groups for the right column: search filters keys (metadata only), and
    /// a provider picked on the left narrows to that group.
    private func libraryGroups() -> (all: [LibraryGroup], shown: [LibraryGroup]) {
        let keys = Library.everything(libraryKeys: libraryKeys, projectVariables: projectKeys)
            .filter(Library.Scope(rawValue: libraryScope).matches)
        let all = LibraryGroup.make(from: keys)
        let searched = isSearching ? LibraryGroup.make(from: Library.filter(keys, query: query)) : all
        guard let libraryProvider else { return (all, searched) }
        return (all, searched.filter { $0.id == libraryProvider })
    }

    // MARK: Deleting projects

    private var deletionTitle: String {
        let picked = projectsPendingDeletion
        return picked.count == 1 ? "Delete “\(picked[0].name)”?" : "Delete \(picked.count) projects?"
    }

    private var deletionMessage: String {
        let picked = projectsPendingDeletion
        let stored = picked.reduce(0) { $0 + $1.allVariables.filter(\.hasValue).count }
        let values = stored == 0 ? "" : " \(stored) stored \(stored == 1 ? "value is" : "values are") removed from your Keychain."
        let names = picked.count > 1 ? picked.prefix(5).map(\.name).joined(separator: ", ") + (picked.count > 5 ? " and \(picked.count - 5) more" : "") + ". " : ""
        let subject = picked.count == 1 ? "Its" : "Their"
        return "\(names)\(subject) environments and variables are deleted.\(values) This can’t be undone."
    }

    /// SECURITY: goes through ProjectDeleter so Keychain items are removed
    /// first and never left behind. Each project is deleted on its own: one
    /// that fails is kept (with its Keychain items) and the rest still go.
    private func delete(_ picked: [Project]) {
        var failures: [String] = []
        var deleted: [String] = []
        for project in picked {
            let id = project.persistentModelID
            let name = project.name
            do {
                try ProjectDeleter.delete(project, context: context, secrets: secrets)
                deleted.append(name)
                tabs.close(id)
                listSelection.remove(id)
            } catch ProjectDeleter.Failure.keychain(let error) {
                let detail = (error as? KeychainError)?.userMessage ?? error.localizedDescription
                failures.append("“\(name)” was kept: stored values couldn’t be removed from the Keychain. \(detail)")
            } catch {
                failures.append("“\(name)”: \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            navigation.show(.success(deleted.count == 1 ? "Project deleted" : "\(deleted.count) projects deleted",
                                     "Their variables and the values in your Keychain were removed.",
                                     groups: [.init(title: "Deleted", names: deleted)]))
        } else {
            navigation.show(.failed(deleted.isEmpty ? "Couldn’t delete the project" : "Some projects couldn’t be deleted",
                                    failures.joined(separator: "\n")
                                    + (deleted.isEmpty ? "" : "\nDeleted: \(deleted.joined(separator: ", ")).")))
        }
    }
}
