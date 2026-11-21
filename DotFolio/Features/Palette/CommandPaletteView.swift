import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// ⌘K: type part of a project or key name and go to it without the mouse.
/// ↑↓ move, ↩ opens, Esc closes. Searches metadata only and
/// never reads a value; copying happens in the tables and the menu bar.
struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigation.self) private var navigation
    @Query private var projects: [Project]
    @Query private var variables: [Variable]

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var items: [CommandPalette.Item] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            // Nothing typed yet: the projects opened most recently.
            return ProjectSearch.recent(projects, limit: 6).map { .project($0) }
        }
        let keys = variables.filter { $0.inLibrary || $0.environment?.project != nil }
        // Projects and keys only: app commands stay in the menus.
        return CommandPalette.results(query: query, projects: projects, variables: keys, includeActions: false)
    }

    var body: some View {
        let items = self.items
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Go to a project or key", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { if items.indices.contains(selected) { run(items[selected]) } }
                    .onKeyPress(.downArrow) { move(+1, count: items.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: items.count); return .handled }
            }
            .padding(DS.Space.l)

            Divider()

            if items.isEmpty {
                Text(query.isEmpty ? "No projects yet." : "Nothing matches “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: DS.Space.xxs) {
                            if query.isEmpty {
                                Text("Recent projects")
                                    .font(DS.Font.label)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, DS.Space.s)
                                    .padding(.top, DS.Space.xs)
                            }
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                PaletteRow(item: item, isSelected: index == selected)
                                    .id(item.id)
                                    .onTapGesture { selected = index; run(item) }
                                    .onHover { if $0 { selected = index } }
                            }
                        }
                        .padding(DS.Space.s)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: selected) { _, index in
                        if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                    }
                }
            }

            Divider()
            HStack(spacing: DS.Space.l) {
                Text("↑↓ Move")
                Text("↩ Open")
                Spacer()
                Text("esc Close")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
        }
        .frame(width: 640)
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
    }

    private func move(_ step: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + step + count) % count
    }

    // MARK: Actions

    private func run(_ item: CommandPalette.Item) {
        switch item {
        case .project(let project):
            navigation.projectToOpen = project.id
            dismiss()
        case .variable(let v):
            if let env = v.environment, let project = env.project {
                navigation.environmentToOpen = env.id
                navigation.projectToOpen = project.id
            } else {
                navigation.libraryProviderToOpen = v.serviceLabel.lowercased()
            }
            dismiss()
        case .action:
            dismiss()
        }
    }
}

/// One result: icon, name and where it lives.
private struct PaletteRow: View {
    let item: CommandPalette.Item
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DS.Space.m) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(isVariable ? .body.monospaced() : .body)
                    .lineLimit(1)
                PaletteSubtitle(item: item)
            }
            Spacer(minLength: DS.Space.s)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .clickableCursor()
    }

    private var isVariable: Bool {
        if case .variable = item { return true }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .project(let project):
            ProjectTile(project: project, size: 28)
        case .variable(let v):
            TintedIcon(symbol: ServiceType.symbol(for: v.displayService), tint: ServiceType.tint(for: v.displayService), size: 28)
        case .action(let action):
            TintedIcon(symbol: action.symbol, tint: DS.Palette.violet, size: 28)
        }
    }
}
