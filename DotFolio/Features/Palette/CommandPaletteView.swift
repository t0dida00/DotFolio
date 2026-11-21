import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// ⌘K: type part of a project, key or command and act on it without the
/// mouse. ↑↓ move, ↩ opens (or runs), ⌘C copies a key's value, ⇧⌘C its
/// `.env` line, Esc closes. Searches metadata only; values are read with
/// Touch ID only when copied.
struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.secretStore) private var secrets
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionLock.self) private var session
    @Environment(UpdateCenter.self) private var updates
    @Query private var projects: [Project]
    @Query private var variables: [Variable]

    @State private var query = ""
    @State private var selected = 0
    @State private var copiedID: String?
    @FocusState private var focused: Bool

    private var items: [CommandPalette.Item] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            // Nothing typed yet: the projects opened most recently.
            return ProjectSearch.recent(projects, limit: 6).map { .project($0) }
        }
        let keys = variables.filter { $0.inLibrary || $0.environment?.project != nil }
        return CommandPalette.results(query: query, projects: projects, variables: keys)
    }

    var body: some View {
        let items = self.items
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Go to a project, key or command", text: $query)
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
                                PaletteRow(item: item, isSelected: index == selected, didCopy: copiedID == item.id)
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
                Text("↩ Open")
                Text("⌘C Copy value")
                Text("⇧⌘C Copy .env line")
                Spacer()
                Text("esc Close")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
        }
        .frame(width: 640)
        .background {
            // Copy shortcuts act on the selected key; they win over Edit ▸ Copy
            // because the palette's own buttons handle them first.
            Group {
                Button("") { copySelected(.value, items: items) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("") { copySelected(.line, items: items) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .hidden()
        }
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
        case .action(let action):
            dismiss()
            perform(action)
        }
    }

    /// Runs after the palette has closed, so sheets the action opens can show.
    private func perform(_ action: CommandPalette.Action) {
        let navigation = navigation, updates = updates
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            switch action {
            case .newProject: navigation.isRequestingNewProject = true
            case .importFolder:
                if let folder = ProjectFolderPicker.choose() { navigation.folderToImport = PendingFolder(url: folder) }
            case .suggestSources: navigation.isSuggestingSources = true
            case .verifyData: navigation.isVerifyingData = true
            case .checkForUpdates: updates.checkForUpdates()
            }
        }
    }

    private func copySelected(_ what: KeyCopier.What, items: [CommandPalette.Item]) {
        guard items.indices.contains(selected), case .variable(let v) = items[selected] else { return }
        let id = items[selected].id
        Task {
            do {
                if try await KeyCopier.copy(v, as: what, session: session, secrets: secrets) {
                    withAnimation(.snappy) { copiedID = id }
                    try? await Task.sleep(for: .seconds(1.5))
                    if copiedID == id { withAnimation(.snappy) { copiedID = nil } }
                }
            } catch {
                navigation.show(.failed("Couldn’t copy \(v.key)", ResultReport.describe(error)))
            }
        }
    }
}

/// One result: icon, name, where it lives, and a tick right after a copy.
private struct PaletteRow: View {
    let item: CommandPalette.Item
    let isSelected: Bool
    let didCopy: Bool

    var body: some View {
        HStack(spacing: DS.Space.m) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(isVariable ? .body.monospaced() : .body)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s)
            if didCopy {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(DS.Status.success)
                    .transition(.opacity)
            }
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
