import AppKit
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// The menu bar panel: find a key and copy it without opening the main
/// window. Click copies the value, ⌥-click the `.env` line (Touch ID, shared
/// with the main window's session). A project opens it in the main window.
/// Values are never shown here.
struct MenuBarPanel: View {
    @Environment(\.secretStore) private var secrets
    @Environment(\.openWindow) private var openWindow
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionLock.self) private var session
    @Query private var projects: [Project]
    @Query private var variables: [Variable]

    @State private var query = ""
    @State private var copiedID: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    private var items: [CommandPalette.Item] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return ProjectSearch.recent(projects, limit: 5).map { .project($0) }
        }
        let keys = variables.filter { $0.inLibrary || $0.environment?.project != nil }
        return CommandPalette.results(query: query, projects: projects, variables: keys, includeActions: false, limit: 10)
    }

    var body: some View {
        let items = self.items
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search keys and projects", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
            }
            .padding(DS.Space.m)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    if query.isEmpty {
                        Text("Recent projects")
                            .font(DS.Font.label)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DS.Space.s)
                            .padding(.top, DS.Space.xs)
                    }
                    if items.isEmpty {
                        Text(query.isEmpty ? "No projects yet." : "Nothing matches “\(query)”.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(items) { item in
                        MenuBarRow(item: item, didCopy: copiedID == item.id) { activate(item) }
                    }
                }
                .padding(DS.Space.s)
            }
            .frame(height: 340)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DS.Status.danger)
                    .padding(.horizontal, DS.Space.m)
                    .padding(.bottom, DS.Space.xs)
            }

            Divider()
            HStack {
                Text("Click copies the value · ⌥-click the .env line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open DOTFOLIO") { openMainWindow() }
                    .controlSize(.small)
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
            }
            .padding(DS.Space.m)
        }
        .frame(width: 380)
        .onAppear { focused = true }
    }

    private func activate(_ item: CommandPalette.Item) {
        switch item {
        case .project(let project):
            navigation.projectToOpen = project.id
            openMainWindow()
        case .variable(let v):
            let what: KeyCopier.What = NSEvent.modifierFlags.contains(.option) ? .line : .value
            let id = item.id
            Task {
                do {
                    if try await KeyCopier.copy(v, as: what, session: session, secrets: secrets) {
                        error = nil
                        withAnimation(.snappy) { copiedID = id }
                        try? await Task.sleep(for: .seconds(1.5))
                        if copiedID == id { withAnimation(.snappy) { copiedID = nil } }
                    }
                } catch {
                    self.error = ResultReport.describe(error)
                }
            }
        case .action:
            break
        }
    }

    /// Brings the main window forward, opening it if it was closed.
    private func openMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

private struct MenuBarRow: View {
    let item: CommandPalette.Item
    let didCopy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(isVariable ? .callout.monospaced() : .callout)
                        .lineLimit(1)
                    PaletteSubtitle(item: item)
                }
                Spacer(minLength: DS.Space.s)
                if didCopy {
                    Image(systemName: "checkmark").foregroundStyle(DS.Status.success)
                } else if isVariable && hovering {
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isVariable ? "Copy the value (⌥: copy the .env line)" : "Open in DOTFOLIO")
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
            ProjectTile(project: project, size: 24)
        case .variable(let v):
            TintedIcon(symbol: ServiceType.symbol(for: v.displayService), tint: ServiceType.tint(for: v.displayService), size: 24)
        case .action(let action):
            TintedIcon(symbol: action.symbol, tint: DS.Palette.violet, size: 24)
        }
    }
}
