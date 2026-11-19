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
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets
    @Query private var projects: [Project]

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
    @State private var projectPendingDeletion: Project?
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
                        projectList
                            .frame(maxHeight: .infinity)
                        listFooter
                    }
                    .frame(width: proxy.size.width * 0.25)
                    Divider()
                    VStack(spacing: 0) {
                        if !openTabs.isEmpty {
                            tabBar
                        }
                        detail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .confirmationDialog(
            "Delete “\(projectPendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { projectPendingDeletion != nil }, set: { if !$0 { projectPendingDeletion = nil } })
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = projectPendingDeletion { delete(project) }
                projectPendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
        .alert("Couldn’t delete project", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
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
                        Button("Sign Out of GitHub", role: .destructive, action: flow.signOutGitHub)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
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
            List(selection: $selection) {
                ForEach(rows, id: \.project.id) { row in
                    ProjectListRow(project: row.project, match: row.match)
                        .tag(row.project.persistentModelID)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            // Right-click menu; double-click / Return opens (primaryAction).
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                if let project = project(for: ids) {
                    Button("Open") { open(project) }
                    Divider()
                    Button("Delete Project…", role: .destructive) { projectPendingDeletion = project }
                }
            } primaryAction: { ids in
                if let project = project(for: ids) { open(project) }
            }
            .onDeleteCommand {
                if let project = selectedProject { projectPendingDeletion = project }
            }
        }
    }

    // MARK: Right column (75%)

    /// Safari-style tab bar: equal-width tabs in one capsule track, the
    /// active tab raised as a white pill, and + beside it for a new project.
    private var tabBar: some View {
        let tabs = openTabs.compactMap { id in projects.first { $0.persistentModelID == id } }
        return HStack(spacing: 8) {
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
                }
            }
            .padding(2)
            .background(.quaternary.opacity(0.8), in: .capsule)

            Button { showNewProject = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(.quaternary.opacity(0.8), in: .circle)
            .help("New Project (⌘N)")
            .accessibilityLabel("New Project")
            .clickableCursor()
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
                onDelete: { projectPendingDeletion = project }
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

    private func project(for ids: Set<PersistentIdentifier>) -> Project? {
        guard let id = ids.first else { return nil }
        return projects.first { $0.persistentModelID == id }
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

    private func open(_ project: Project) {
        project.lastOpenedAt = .now
        navigation.open(project.persistentModelID)
    }

    private var deletionMessage: String {
        let stored = projectPendingDeletion?.allVariables.filter(\.hasValue).count ?? 0
        let values = stored == 0 ? "" : " \(stored) stored \(stored == 1 ? "value is" : "values are") removed from your Keychain."
        return "Its environments and variables are deleted.\(values) This can’t be undone."
    }

    /// SECURITY: goes through ProjectDeleter so Keychain items are removed
    /// first and never left behind.
    private func delete(_ project: Project) {
        closeTab(project.persistentModelID)
        do {
            try ProjectDeleter.delete(project, context: context, secrets: secrets)
        } catch ProjectDeleter.Failure.keychain(let error) {
            let detail = (error as? KeychainError)?.userMessage ?? error.localizedDescription
            deleteError = "Stored values couldn’t be removed from the Keychain, so the project was kept. \(detail)"
        } catch {
            deleteError = error.localizedDescription
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
