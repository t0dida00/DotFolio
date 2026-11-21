import AppKit
import DotFolioModels
import SwiftData
import SwiftUI

/// Left column in Projects mode: the All · Git · Local filter, the project
/// list (⌘/⇧-click to pick several) and its footer. A project folder dropped
/// here is imported.
struct ProjectSidebar: View {
    let projects: [Project]
    /// Rows after filter, sort and search (the browser computes them once).
    let rows: [(project: Project, match: ProjectSearch.Match)]
    let query: String
    let flow: ConnectionFlowModel
    @Binding var originFilter: ProjectOriginFilter
    @Binding var listSelection: Set<PersistentIdentifier>
    @Binding var listAnchor: PersistentIdentifier?
    @Binding var showNewProject: Bool
    /// The active tab, used by ↑/↓ when no single row is selected.
    let activeTab: PersistentIdentifier?
    let onOpenInTabs: ([Project]) -> Void
    let onDelete: ([Project]) -> Void

    @Environment(AppNavigation.self) private var navigation
    @AppStorage(RepoConnections.gitHubUserKey) private var gitHubUser = ""
    @AppStorage(RepoConnections.gitLabUserKey) private var gitLabUser = ""
    @FocusState private var listFocused: Bool

    private var isSignedIn: Bool { !gitHubUser.isEmpty || !gitLabUser.isEmpty }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Drop a project folder here to import its .env files.
        VStack(spacing: 0) {
            EqualSegmentedPicker(options: ProjectOriginFilter.allCases.map { ($0.title, $0) },
                                 selection: $originFilter, controlSize: .small)
                .accessibilityLabel("Source")
                .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.xs)
            .help("Show every project, those from GitHub/GitLab, or those linked to a folder on this Mac")
            .clickableCursor()
            projectList
                .frame(maxHeight: .infinity)
            ProjectListFooter(flow: flow, showNewProject: $showNewProject)
        }
        .projectFolderDropTarget(navigation)
    }

    /// In list order, so the dialog and tabs follow what the user sees.
    private func projects(for ids: Set<PersistentIdentifier>) -> [Project] {
        rows.map(\.project).filter { ids.contains($0.persistentModelID) }
    }

    @ViewBuilder
    private var projectList: some View {
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
                            let picked = listSelection.contains(id) ? projects(for: listSelection) : [row.project]
                            if picked.count == 1, let project = picked.first {
                                Button("Delete Project…", role: .destructive) { onDelete([project]) }
                            } else if picked.count > 1 {
                                Button("Open \(picked.count) in Tabs") { onOpenInTabs(picked) }
                                Divider()
                                Button("Delete \(picked.count) Projects…", role: .destructive) { onDelete(picked) }
                            }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .sidebarKeyboard(focused: $listFocused) { step in
                let current = listSelection.count == 1 ? listSelection.first : activeTab
                if let next = SidebarSelection.neighbor(of: current, in: order, step: step) {
                    listSelection = [next]
                    listAnchor = next
                }
            }
            .onDeleteCommand {
                let picked = projects(for: listSelection)
                if !picked.isEmpty { onDelete(picked) }
            }
        }
    }
}
