import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Full-window project list (shown once at least one project exists):
/// toolbar (sort, search) above two columns — the project list (25%, with
/// New Project and repo sign-in at its bottom)
/// and the selected project's details with its .env table (75%).
struct ProjectBrowser: View {
    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(UpdateCenter.self) private var updates
    @Environment(AppNavigation.self) private var navigation
    @Query private var projects: [Project]
    @Query private var accounts: [Account]

    /// Left column shows projects, service accounts, or the key Library.
    enum Mode: String, CaseIterable { case projects = "Projects", accounts = "Accounts", libraries = "Libraries" }
    @State private var mode: Mode = .projects
    @State private var accountSelection: PersistentIdentifier?
    @State private var isCreatingAccount = false
    @State private var accountPendingDeletion: Account?
    @Query(filter: #Predicate<Variable> { $0.inLibrary }) private var libraryKeys: [Variable]
    /// Every project variable: the Library shows them too (one row per environment).
    /// All · Library · development · staging · production (remembered).
    @AppStorage("library.scope") private var libraryScope = "all"
    @Query(filter: #Predicate<Variable> { !$0.inLibrary }) private var projectKeys: [Variable]
    /// Provider shown in the Library (nil = all).
    @State private var libraryProvider: String?
    @State private var libraryFocusRequest = 0

    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool
    @AppStorage("home.sort") private var sort: ProjectSort = .name
    /// All · Git · Local under the Projects tab (remembered; not a secret).
    @AppStorage("home.originFilter") private var originFilter: ProjectOriginFilter = .all
    @AppStorage(RepoConnections.gitHubUserKey) private var gitHubUser = ""
    @AppStorage(RepoConnections.gitLabUserKey) private var gitLabUser = ""
    @State private var query = ""
    @State private var selection: PersistentIdentifier?
    /// Projects open as tabs above the detail column, in opening order.
    /// `selection` is the active tab.
    @State private var openTabs: [PersistentIdentifier] = []
    /// Rows highlighted in the list. ⌘-click / ⇧-click / ⌘A select several
    /// for bulk delete; a single selected row becomes the active tab.
    @State private var listSelection: Set<PersistentIdentifier> = []
    /// Where a ⇧-click range starts (the last plain or ⌘ click).
    @State private var listAnchor: PersistentIdentifier?
    @FocusState private var listFocused: Bool
    @State private var projectsPendingDeletion: [Project] = []
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Width of the list column (brand, mode picker, list, footer).
    static let sidebarWidth: CGFloat = 320

    var body: some View {
        // Library groups are built once per redraw, and only in that mode.
        let library = mode == .libraries ? libraryGroups() : (all: [], shown: [])
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    brandHeader
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
                        // Drop a project folder here to import its .env files.
                        VStack(spacing: 0) {
                            Picker("Source", selection: $originFilter) {
                                ForEach(ProjectOriginFilter.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .controlSize(.small)
                            .padding(.horizontal, DS.Space.m)
                            .padding(.bottom, DS.Space.xs)
                            .help("Show every project, those from GitHub/GitLab, or those linked to a folder on this Mac")
                            .clickableCursor()
                            projectList
                                .frame(maxHeight: .infinity)
                            listFooter
                        }
                        .projectFolderDropTarget(navigation)
                    case .accounts:
                        AccountList(accounts: accounts, query: query, selection: $accountSelection,
                                    onDelete: { accountPendingDeletion = $0 })
                            .frame(maxHeight: .infinity)
                        accountsFooter
                    case .libraries:
                        // Same place as Projects' All · Git · Local.
                        Picker("Show", selection: $libraryScope) {
                            Text("All").tag("all")
                            Text("Library").tag("library")
                            Text("Dev").tag("development")
                            Text("Staging").tag("staging")
                            Text("Prod").tag("production")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .padding(.horizontal, DS.Space.m)
                        .padding(.bottom, DS.Space.xs)
                        .help("Every key, only the Library’s own keys, or the project keys of development, staging or production")
                        .clickableCursor()
                        LibraryProviderList(groups: library.all, total: library.all.reduce(0) { $0 + $1.keys.count },
                                            selection: $libraryProvider)
                            .frame(maxHeight: .infinity)
                        libraryFooter
                    }
                }
                // Fixed width: the list column never stretches or squeezes.
                .frame(width: Self.sidebarWidth)
                Divider()
                VStack(spacing: 0) {
                    switch mode {
                    case .projects:
                        if !openTabs.isEmpty {
                            tabBar
                        }
                        detail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .accounts:
                        accountDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .libraries:
                        LibraryView(groups: library.shown, total: library.all.reduce(0) { $0 + $1.keys.count }, focusRequest: libraryFocusRequest,
                                    scope: libraryScope)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // No auto-open: with no tab open the Overview dashboard is the home view.
        .onChange(of: projects.count) { _, _ in pruneTabs() }
        // A project just imported from a folder: show it.
        .onChange(of: navigation.projectToOpen, initial: true) { _, id in
            guard let id, let project = projects.first(where: { $0.id == id }) else { return }
            mode = .projects
            query = ""
            if !originFilter.matches(project) { originFilter = .all }
            selection = project.persistentModelID
            navigation.projectToOpen = nil
        }
        .onChange(of: selection) { _, id in
            if let id, !openTabs.contains(id) { openTabs.append(id) }
            selectedProject?.lastOpenedAt = .now
            // Keep the list highlight on the active tab, unless several rows
            // are selected for a bulk action.
            if listSelection.count <= 1 { listSelection = id.map { [$0] } ?? [] }
        }
        .onChange(of: listSelection) { _, ids in
            if ids.count == 1, let id = ids.first, id != selection { selection = id }
        }
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
        .onChange(of: accountSelection) { _, _ in isCreatingAccount = false }
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

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Space.s) {
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(ProjectSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 15))
                .frame(width: 52, height: 36)
                .contentShape(.capsule)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .glassEffect(.regular.interactive(), in: .capsule)
            .clickableCursor()
            .symbolMotion(.bounce)
            .help("Sort projects")

            Spacer(minLength: 16)

            SearchField(text: $query, isFocused: $searchFocused)
                .frame(maxWidth: 300)
        }
        .padding(.leading, HomeView.trafficLightInset)
        .padding(.trailing, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        .background {
            // ⌘F focuses search, like most Mac apps.
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }

    // MARK: Bottom of the list column

    private var isSignedIn: Bool { !gitHubUser.isEmpty || !gitLabUser.isEmpty }

    private var listFooter: some View {
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

    // MARK: Brand

    /// Logo, name and slogan, stacked and centered at the top of the left column.
    private var brandHeader: some View {
        VStack(spacing: DS.Space.s) {
            AppMark(size: 64)
                .padding(.bottom, DS.Space.xs)
            Text("DOTFOLIO")
                .font(.title3.weight(.semibold))
            Text("Every .env, safe in your Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(UpdateCenter.versionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            VStack(spacing: DS.Space.xxs) {
                Button("Check for Updates…", action: updates.checkForUpdates)
                Button("What’s New in \(UpdateCenter.currentVersion)") { updates.isShowingWhatsNew = true }
            }
            .buttonStyle(.link)
            .font(.callout)
            .clickableCursor()
            .padding(.top, DS.Space.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.m)
        .accessibilityElement(children: .combine)
    }


    // MARK: Libraries mode

    /// Groups for the right column: search filters keys (metadata only), and
    /// a provider picked on the left narrows to that group.
    /// Library keys plus every project's keys.
    private var libraryRows: [Variable] {
        Library.everything(libraryKeys: libraryKeys, projectVariables: projectKeys)
            .filter(Library.Scope(rawValue: libraryScope).matches)
    }

    private func libraryGroups() -> (all: [LibraryGroup], shown: [LibraryGroup]) {
        let keys = libraryRows
        let all = LibraryGroup.make(from: keys)
        let searched = isSearching ? LibraryGroup.make(from: Library.filter(keys, query: query)) : all
        guard let libraryProvider else { return (all, searched) }
        return (all, searched.filter { $0.id == libraryProvider })
    }

    private var libraryFooter: some View {
        Button {
            libraryProvider = nil
            libraryFocusRequest += 1
        } label: {
            Label("New Key", systemImage: "plus").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .clickableCursor()
        .padding(DS.Space.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Accounts mode

    private var accountsFooter: some View {
        Button {
            accountSelection = nil
            isCreatingAccount = true
        } label: {
            Label("New Account", systemImage: "plus").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .clickableCursor()
        .padding(DS.Space.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var accountDetail: some View {
        if isCreatingAccount {
            NewAccountForm(
                onCreated: { account in
                    isCreatingAccount = false
                    accountSelection = account.persistentModelID
                },
                onCancel: { isCreatingAccount = false }
            )
        } else if let id = accountSelection, let account = accounts.first(where: { $0.persistentModelID == id }) {
            AccountDetailView(
                account: account,
                onOpenProject: { project in
                    mode = .projects
                    selection = project.persistentModelID
                },
                onDelete: { accountPendingDeletion = account }
            )
            .id(account.persistentModelID)
        } else {
            ContentUnavailableView(
                accounts.isEmpty ? "No accounts yet" : "No account selected",
                systemImage: "person.crop.circle",
                description: Text("Accounts are the logins your variables come from — which Firebase, Stripe or AWS login a project uses.")
            )
        }
    }

    // MARK: Left column (25%)

    private var results: [(project: Project, match: ProjectSearch.Match)] {
        let sorted = ProjectSearch.sorted(projects.filter(originFilter.matches), by: sort)
        return isSearching ? ProjectSearch.filter(sorted, query: query) : sorted.map { ($0, .name) }
    }

    private var selectedProject: Project? {
        guard let selection else { return nil }
        return projects.first { $0.persistentModelID == selection }
    }

    @ViewBuilder
    private var projectList: some View {
        let rows = results
        if isSearching && rows.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if projects.isEmpty {
            ContentUnavailableView(
                "No projects",
                systemImage: "folder",
                description: Text(isSignedIn ? "Import a repo from GitHub, drop a project folder here, or create one with New Project."
                                             : "Drop a project folder here, or create one with New Project.")
            )
        } else if rows.isEmpty {
            ContentUnavailableView(
                originFilter == .local ? "No local projects" : "No Git projects",
                systemImage: originFilter == .local ? "laptopcomputer" : "arrow.triangle.branch",
                description: Text(originFilter == .local
                                  ? "Drop a project folder here to import its .env files."
                                  : (isSignedIn ? "Import a repo from GitHub with the menu below." : "Sign in to GitHub to import your repos."))
            )
        } else {
            let order = rows.map(\.project.persistentModelID)
            List {
                ForEach(rows, id: \.project.id) { row in
                    let id = row.project.persistentModelID
                    ProjectListRow(project: row.project, match: row.match)
                        .sidebarRow(isSelected: listSelection.contains(id)) {
                            // A click opens the project as a tab; ⌘/⇧ pick several.
                            listSelection = SidebarSelection.click(id, selection: listSelection, anchor: listAnchor, order: order)
                            if !NSEvent.modifierFlags.contains(.shift) { listAnchor = id }
                            listFocused = true
                        }
                        // Right-click acts on the selection when the row is part
                        // of it, otherwise on that row alone (like Finder).
                        .contextMenu {
                            let picked = listSelection.contains(id) ? projects(for: listSelection, in: rows) : [row.project]
                            if picked.count == 1, let project = picked.first {
                                Button("Delete Project…", role: .destructive) { projectsPendingDeletion = [project] }
                            } else if picked.count > 1 {
                                Button("Open \(picked.count) in Tabs") { openInTabs(picked) }
                                Divider()
                                Button("Delete \(picked.count) Projects…", role: .destructive) { projectsPendingDeletion = picked }
                            }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .sidebarKeyboard(focused: $listFocused) { step in
                let current = listSelection.count == 1 ? listSelection.first : selection
                if let next = SidebarSelection.neighbor(of: current, in: order, step: step) {
                    listSelection = [next]
                    listAnchor = next
                }
            }
            .onDeleteCommand {
                let picked = projects(for: listSelection)
                if !picked.isEmpty { projectsPendingDeletion = picked }
            }
        }
    }

    // MARK: Right column (75%)

    /// Safari-style tab bar: equal-width tabs in one capsule track, the
    /// active tab raised as a white pill.
    private var tabBar: some View {
        let tabs = openTabs.compactMap { id in projects.first { $0.persistentModelID == id } }
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.persistentModelID) { index, project in
                    let id = project.persistentModelID
                    if index > 0 {
                        // Hidden next to the active tab, like Safari.
                        let nextToActive = id == selection || tabs[index - 1].persistentModelID == selection
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1, height: 16)
                            .opacity(nextToActive ? 0 : 1)
                    }
                    ProjectTab(
                        title: project.name,
                        isActive: id == selection,
                        onSelect: { selection = id },
                        onClose: { closeTab(id) }
                    )
                    .contextMenu {
                        Button("Close Tab") { closeTab(id) }
                        Button("Close Other Tabs") { closeOtherTabs(keeping: id) }
                            .disabled(tabs.count < 2)
                        Button("Close Tabs to the Right") { closeTabs(rightOf: id) }
                            .disabled(index == tabs.count - 1)
                        Divider()
                        Button("Close All Tabs") { closeAllTabs() }
                    }
                }
            }
            .padding(DS.Space.xxs)
            .background(.quaternary.opacity(DS.Fill.tile), in: .capsule)

            if tabs.count == 1 {
                // Takes the other half, so a lone tab is at most 50% wide.
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.s)
        .padding(.bottom, DS.Space.xxs)
        .background {
            // ⌘W closes the active tab.
            Button("") { if let selection { closeTab(selection) } }
                .keyboardShortcut("w")
                .hidden()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let project = selectedProject {
            ProjectPreview(
                project: project,
                onDelete: { projectsPendingDeletion = [project] }
            )
            .id(project.persistentModelID)
        } else {
            // No tab open: show what DotFolio is tracking instead of an empty pane.
            OverviewDashboard(
                onOpenProject: { selection = $0.persistentModelID },
                onShowAccounts: { mode = .accounts },
                onOpenAccount: { account in
                    accountSelection = account.persistentModelID
                    mode = .accounts
                }
            )
        }
    }

    // MARK: Actions

    /// In list order, so the dialog and tabs follow what the user sees.
    private func projects(for ids: Set<PersistentIdentifier>, in rows: [(project: Project, match: ProjectSearch.Match)]? = nil) -> [Project] {
        (rows ?? results).map(\.project).filter { ids.contains($0.persistentModelID) }
    }

    private func openInTabs(_ picked: [Project]) {
        for project in picked where !openTabs.contains(project.persistentModelID) {
            openTabs.append(project.persistentModelID)
        }
        selection = picked.first?.persistentModelID
        listSelection = selection.map { [$0] } ?? []
    }

    /// Closes a tab; when it was active, the tab to its right (or left)
    /// becomes active, like Safari.
    private func closeTab(_ id: PersistentIdentifier) {
        guard let index = openTabs.firstIndex(of: id) else { return }
        openTabs.remove(at: index)
        if selection == id {
            selection = openTabs.isEmpty ? nil : openTabs[min(index, openTabs.count - 1)]
        }
    }

    private func closeOtherTabs(keeping id: PersistentIdentifier) {
        openTabs = [id]
        selection = id
    }

    /// Keeps the active tab if it survives; otherwise activates `id`.
    private func closeTabs(rightOf id: PersistentIdentifier) {
        guard let index = openTabs.firstIndex(of: id) else { return }
        openTabs.removeSubrange((index + 1)...)
        if let selection, !openTabs.contains(selection) { self.selection = id }
    }

    private func closeAllTabs() {
        openTabs = []
        selection = nil
    }

    /// Drops tabs whose project no longer exists.
    private func pruneTabs() {
        let ids = Set(projects.map(\.persistentModelID))
        openTabs.removeAll { !ids.contains($0) }
    }

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
                closeTab(id)
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

// MARK: - Pieces

private struct ProjectTab: View {
    let title: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(title)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, DS.Space.xxl)
            .frame(maxWidth: .infinity, minHeight: 26)
            .overlay(alignment: .leading) {
                // X sits on the left; always on the active tab, on hover otherwise.
                if isActive || isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DS.Space.s)
                    .help("Close Tab (⌘W)")
                    .symbolMotion(.bounce)
                    .accessibilityLabel("Close \(title)")
                    .clickableCursor()
                }
            }
            .background {
                if isActive {
                    Capsule()
                        .fill(.background)
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                } else if isHovering {
                    Capsule().fill(.quaternary.opacity(DS.Fill.control))
                }
            }
            .contentShape(.capsule)
            .onTapGesture(perform: onSelect)
            .onHover { isHovering = $0 }
            .clickableCursor()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ProjectListRow: View {
    let project: Project
    let match: ProjectSearch.Match

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ProjectTile(project: project, size: 34)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(project.name).lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.s)
            if let opened = project.lastOpenedAt {
                // Compact age (1m, 5h, 1d…), refreshed every 15 minutes.
                TimelineView(.periodic(from: .now, by: CompactAge.refreshInterval)) { context in
                    Text(CompactAge.string(since: opened, now: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .help("Last opened \(opened.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityLabel("Last opened \(opened.formatted(.relative(presentation: .named)))")
            }
        }
        .padding(.vertical, DS.Space.xs)
        .clickableCursor()
    }

    /// `~/Projects/app`. The sandbox's home is the app container, so the
    /// user's real home folder comes from the account record instead.
    private static func tildePath(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return path }
        let home = String(cString: dir)
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// While searching, say why a project matched; otherwise its repo.
    private var subtitle: String {
        switch match {
        case .variableKey(let key): "Matches \(key)"
        case .account(let login): "Uses \(login)"
        case .service(let name): "Uses \(name)"
        case .name, .repo:
            if project.origin == .local, let folder = ProjectFolder.resolve(project) {
                Self.tildePath(folder)
            } else {
                project.repoFullName.isEmpty ? "No repo" : project.repoFullName
            }
        }
    }
}

/// A project's tile shows where it comes from: a folder on this Mac, GitHub,
/// GitLab, or made by hand. Local stands out, since only local projects can
/// read (and later sync) the .env files of their source code.
struct ProjectTile: View {
    let origin: ProjectOrigin
    var size: CGFloat = 40

    init(project: Project, size: CGFloat = 40) {
        self.origin = project.origin
        self.size = size
    }

    var body: some View {
        // The app's icon style (TintedIcon: logo proportions).
        TintedIcon(tint: tint, size: size) { glyph }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    @ViewBuilder
    private var glyph: some View {
        switch origin {
        case .github: BrandMark.github.image.resizable().scaledToFit()
        case .gitlab: BrandMark.gitlab.image.resizable().scaledToFit()
        case .local: Image(systemName: "laptopcomputer").resizable().scaledToFit().fontWeight(.medium)
        case .manual: Image(systemName: "square.and.pencil").resizable().scaledToFit().fontWeight(.medium)
        }
    }

    private var helpText: String {
        switch origin {
        case .local: "Local project: linked to a folder on this Mac"
        case .github: "Imported from GitHub"
        case .gitlab: "Imported from GitLab"
        case .manual: "Created by hand"
        }
    }

    private var tint: Color {
        switch origin {
        case .local: DS.Palette.aqua
        case .github: DS.Palette.violet
        case .gitlab: DS.Palette.orange
        case .manual: DS.Palette.blue
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search projects, keys, providers, accounts", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .clickableCursor()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}
