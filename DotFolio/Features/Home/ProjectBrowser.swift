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
    @Query private var projects: [Project]
    @Query private var accounts: [Account]

    /// Left column shows projects or service accounts.
    enum Mode: String, CaseIterable { case projects = "Projects", accounts = "Accounts" }
    @State private var mode: Mode = .projects
    @State private var accountSelection: PersistentIdentifier?
    @State private var isCreatingAccount = false
    @State private var accountPendingDeletion: Account?

    let flow: ConnectionFlowModel
    @Binding var showNewProject: Bool
    @AppStorage("home.sort") private var sort: ProjectSort = .name
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
    @State private var projectsPendingDeletion: [Project] = []
    @State private var deleteError: String?
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Picker("Show", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .clickableCursor()

                        switch mode {
                        case .projects:
                            projectList
                                .frame(maxHeight: .infinity)
                            listFooter
                        case .accounts:
                            AccountList(accounts: accounts, query: query, selection: $accountSelection,
                                        onDelete: { accountPendingDeletion = $0 })
                                .frame(maxHeight: .infinity)
                            accountsFooter
                        }
                    }
                    .frame(width: proxy.size.width * 0.25)
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
                        }
                    }
                }
            }
        }
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: projects.count) { _, _ in
            pruneTabs()
            selectFirstIfNeeded()
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
                    AccountEditor.delete(account, context: context)
                }
                accountPendingDeletion = nil
            }
        } message: {
            let used = accountPendingDeletion?.allLinkedVariables.count ?? 0
            Text(used == 0
                 ? "Its service projects are deleted too. This can’t be undone."
                 : "\(used) \(used == 1 ? "variable keeps" : "variables keep") existing but lose this source link. Its service projects are deleted too. This can’t be undone.")
        }
        .alert("Couldn’t delete all projects", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(ProjectSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
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
        .padding(.trailing, 16)
        .padding(.vertical, 8)
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
        VStack(spacing: 10) {
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
                HStack(spacing: 8) {
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

            // Shown until a GitHub or GitLab account is linked.
            if !isSignedIn {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to GitHub or GitLab to import your repos and their .env.example.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        Button(action: flow.connectGitHub) {
                            Label { Text("GitHub") } icon: { BrandMark.github.image.resizable().scaledToFit().frame(width: 13, height: 13) }
                                .frame(maxWidth: .infinity)
                        }
                        Button(action: flow.connectGitLab) {
                            Label { Text("GitLab") } icon: { BrandMark.gitlab.image.resizable().scaledToFit().frame(width: 13, height: 13) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
                    Button("Self-hosted GitLab…", action: flow.showGitLabHost)
                        .buttonStyle(.link)
                        .font(.callout)
                        .clickableCursor()
                }
            }
        }
        .padding(12)
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
        .padding(12)
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
                description: Text("Accounts are the service logins your variables come from — which Firebase, Stripe or AWS login a project uses.")
            )
        }
    }

    // MARK: Left column (25%)

    private var results: [(project: Project, match: ProjectSearch.Match)] {
        let sorted = ProjectSearch.sorted(projects, by: sort)
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
        } else {
            List(selection: $listSelection) {
                ForEach(rows, id: \.project.id) { row in
                    ProjectListRow(project: row.project, match: row.match)
                        .tag(row.project.persistentModelID)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            // Right-click menu. A click opens the project as a tab.
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                let picked = projects(for: ids)
                if picked.count == 1, let project = picked.first {
                    Button("Delete Project…", role: .destructive) { projectsPendingDeletion = [project] }
                } else if picked.count > 1 {
                    Button("Open \(picked.count) in Tabs") { openInTabs(picked) }
                    Divider()
                    Button("Delete \(picked.count) Projects…", role: .destructive) { projectsPendingDeletion = picked }
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
            .padding(2)
            .background(.quaternary.opacity(0.8), in: .capsule)

            if tabs.count == 1 {
                // Takes the other half, so a lone tab is at most 50% wide.
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
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
            ContentUnavailableView(
                "No project open",
                systemImage: "sidebar.right",
                description: Text("Select a project in the list to open it in a tab.")
            )
        }
    }

    // MARK: Actions

    /// In list order, so the dialog and tabs follow what the user sees.
    private func projects(for ids: Set<PersistentIdentifier>) -> [Project] {
        results.map(\.project).filter { ids.contains($0.persistentModelID) }
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

    private func selectFirstIfNeeded() {
        if selectedProject == nil && openTabs.isEmpty {
            selection = ProjectSearch.sorted(projects, by: sort).first?.persistentModelID
        }
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
        for project in picked {
            let id = project.persistentModelID
            let name = project.name
            do {
                try ProjectDeleter.delete(project, context: context, secrets: secrets)
                closeTab(id)
                listSelection.remove(id)
            } catch ProjectDeleter.Failure.keychain(let error) {
                let detail = (error as? KeychainError)?.userMessage ?? error.localizedDescription
                failures.append("“\(name)” was kept: stored values couldn’t be removed from the Keychain. \(detail)")
            } catch {
                failures.append("“\(name)”: \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { deleteError = failures.joined(separator: "\n") }
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
            .padding(.horizontal, 28)
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
                    .padding(.leading, 8)
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
                    Capsule().fill(.quaternary.opacity(0.6))
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
        HStack(spacing: 10) {
            ProjectTile(provider: project.provider, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
        .clickableCursor()
    }

    /// While searching, say why a project matched; otherwise its repo.
    private var subtitle: String {
        switch match {
        case .variableKey(let key): "Matches \(key)"
        case .account(let login): "Uses \(login)"
        case .service(let name): "Uses \(name)"
        case .name, .repo: project.repoFullName.isEmpty ? "No repo" : project.repoFullName
        }
    }
}

struct ProjectTile: View {
    let provider: RepoProvider
    var size: CGFloat = 40

    var body: some View {
        Group {
            switch provider {
            case .github: BrandMark.github.image.resizable().scaledToFit().frame(width: size * 0.5, height: size * 0.5)
            case .gitlab: BrandMark.gitlab.image.resizable().scaledToFit().frame(width: size * 0.5, height: size * 0.5)
            case .none: Image(systemName: "folder").font(.system(size: size * 0.42))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search projects, keys, accounts", text: $text)
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
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}
