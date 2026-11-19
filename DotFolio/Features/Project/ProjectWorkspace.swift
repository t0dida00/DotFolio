import DotFolioModels
import SwiftData
import SwiftUI

/// Detail stage, laid out like a native Mac database client:
/// sidebar = the environment's variables, detail = the selected variable,
/// toolbar = environment switcher.
struct ProjectWorkspace: View {
    @Environment(AppNavigation.self) private var navigation
    private let opened: Project

    @State private var environmentID: ProjectEnvironment.ID?
    @State private var variableID: Variable.ID?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    init(project: Project) {
        opened = project
    }

    private var project: Project { opened }

    private var environment: ProjectEnvironment? {
        let envs = project.sortedEnvironments
        return envs.first { $0.id == environmentID } ?? envs.first
    }

    private var selectedVariable: Variable? {
        environment?.variables?.first { $0.id == variableID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VariableSidebar(project: project, environment: environment, selection: $variableID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            Group {
                if let variable = selectedVariable, let environment {
                    VariableDetailView(variable: variable, environment: environment)
                } else {
                    NoVariableSelectedView(hasVariables: !(environment?.variables?.isEmpty ?? true))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle(project.name)
        .toolbar { toolbarContent }
        .frame(minWidth: HomeView.minSize.width, minHeight: HomeView.minSize.height)
        .onChange(of: environmentID) { _, _ in variableID = nil }
        .background { shortcuts }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: navigation.goHome) {
                Label("All Projects", systemImage: "chevron.left")
            }
            .help("Back to all projects (⌘[)")
            .clickableCursor()
        }

        ToolbarItemGroup(placement: .principal) {
            Label { Text(project.name) } icon: { ProviderIcon(provider: project.provider) }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 4)

            Menu {
                ForEach(Array(project.sortedEnvironments.enumerated()), id: \.element.id) { index, env in
                    Toggle(isOn: Binding(
                        get: { env.id == environment?.id },
                        set: { if $0 { environmentID = env.id } }
                    )) {
                        Label(env.name, systemImage: env.isProtected ? "lock" : "square.stack.3d.up")
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            } label: {
                Label(environment?.name ?? "No environment", systemImage: environment?.isProtected == true ? "lock" : "square.stack.3d.up")
            }
            .help("Switch environment (⌘1–⌘\(max(project.sortedEnvironments.count, 1)))")
            .clickableCursor()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Needs the Keychain (values) — enabled once signing is set up.
            Button {} label: { Label("Export .env", systemImage: "square.and.arrow.up") }
                .disabled(true)
                .help("Export .env — available once Keychain access is set up")

            Menu {
                if let url = project.repoURL {
                    Link("Open \(project.provider == .none ? "Link" : "Repo")", destination: url)
                    Divider()
                }
                Button("Back to All Projects", action: navigation.goHome)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .clickableCursor()
        }
    }

    /// ⌘[ back home (the env shortcuts live on the menu items above).
    private var shortcuts: some View {
        Button("", action: navigation.goHome)
            .keyboardShortcut("[", modifiers: .command)
            .hidden()
    }
}

// MARK: - Empty detail

private struct NoVariableSelectedView: View {
    let hasVariables: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hasVariables ? "No variable selected" : "No variables yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if hasVariables {
                    ShortcutHint(keys: nil, text: "Click a variable", detail: "to see where it comes from")
                }
                ShortcutHint(keys: "⌘1–3", text: "Switch environment")
                ShortcutHint(keys: "⌘F", text: "Filter variables")
                ShortcutHint(keys: "⌘[", text: "Back to all projects")
            }
        }
        .padding()
    }
}

private struct ShortcutHint: View {
    let keys: String?
    let text: String
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            if let keys {
                Text(keys)
                    .font(.callout.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text(text)
            if let detail { Text(detail).foregroundStyle(.tertiary) }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// GitHub/GitLab mark or a folder, sized for toolbar labels and rows.
struct ProviderIcon: View {
    let provider: RepoProvider

    var body: some View {
        switch provider {
        case .github: BrandMark.github.image.resizable().scaledToFit().frame(width: 15, height: 15)
        case .gitlab: BrandMark.gitlab.image.resizable().scaledToFit().frame(width: 15, height: 15)
        case .none: Image(systemName: "folder")
        }
    }
}
