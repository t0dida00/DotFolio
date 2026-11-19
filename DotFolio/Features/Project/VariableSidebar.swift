import DotFolioModels
import SwiftUI

/// Sidebar: "Variables | Sources" tabs, a filter field, sectioned list, and a
/// footer with the repo link and variable count.
struct VariableSidebar: View {
    enum Tab: String, CaseIterable, Identifiable {
        case variables = "Variables"
        case sources = "Sources"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name"
        case recentlyUpdated = "Recently Updated"
        var id: String { rawValue }
    }

    let project: Project
    let environment: ProjectEnvironment?
    @Binding var selection: Variable.ID?

    @State private var tab: Tab = .variables
    @State private var filter = ""
    @AppStorage("workspace.variableSort") private var sort: SortOrder = .name
    @FocusState private var filterFocused: Bool

    private var variables: [Variable] {
        let all = environment?.variables ?? []
        let q = filter.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? all : all.filter {
            $0.key.localizedStandardContains(q)
                || ($0.account?.login.localizedStandardContains(q) ?? false)
                || ($0.account?.serviceName.localizedStandardContains(q) ?? false)
        }
        switch sort {
        case .name: return filtered.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        case .recentlyUpdated: return filtered.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            list.frame(maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background {
            Button("") { filterFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .clickableCursor()

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.plain)
                        .focused($filterFocused)
                        .onExitCommand { filter = "" }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.quaternary.opacity(0.6), in: Capsule())

                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort variables")
                .clickableCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let rows = variables
        if (environment?.variables ?? []).isEmpty {
            ContentUnavailableView("No variables", systemImage: "list.bullet.rectangle",
                                   description: Text("\(environment?.name.capitalized ?? "This environment") has no variables yet."))
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: filter)
        } else {
            List(selection: $selection) {
                switch tab {
                case .variables: byStatus(rows)
                case .sources: bySource(rows)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func byStatus(_ rows: [Variable]) -> some View {
        let set = rows.filter(\.hasValue)
        let missing = rows.filter { !$0.hasValue }
        if !set.isEmpty {
            Section("Variables") { ForEach(set) { VariableRow(variable: $0).tag($0.id) } }
        }
        if !missing.isEmpty {
            Section("Missing Values") { ForEach(missing) { VariableRow(variable: $0).tag($0.id) } }
        }
    }

    @ViewBuilder
    private func bySource(_ rows: [Variable]) -> some View {
        let groups = Dictionary(grouping: rows) { $0.account?.persistentModelID }
        let accounts = rows.compactMap(\.account)
            .reduce(into: [Account]()) { list, a in if !list.contains(where: { $0.persistentModelID == a.persistentModelID }) { list.append(a) } }
            .sorted { $0.serviceName.localizedStandardCompare($1.serviceName) == .orderedAscending }

        ForEach(accounts) { account in
            Section("\(account.serviceName) · \(account.login)") {
                ForEach(groups[account.persistentModelID] ?? []) { VariableRow(variable: $0).tag($0.id) }
            }
        }
        if let unlinked = groups[nil], !unlinked.isEmpty {
            Section("No Source Linked") { ForEach(unlinked) { VariableRow(variable: $0).tag($0.id) } }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let url = project.repoURL {
                Link(project.provider == .none ? "Open link" : "Open repo", destination: url)
                    .font(.callout)
                    .clickableCursor()
                    .help(url.absoluteString)
            }
            Spacer()
            let count = environment?.variables?.count ?? 0
            Text("\(count) \(count == 1 ? "variable" : "variables")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct VariableRow: View {
    let variable: Variable

    var body: some View {
        Label {
            Text(variable.key)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: variable.hasValue ? "key.fill" : "key")
                .foregroundStyle(variable.hasValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .help(variable.hasValue ? variable.key : "\(variable.key) — no value yet")
    }
}
