import DotFolioCore
import DotFolioModels
import SwiftUI

/// Right column of the project list: project information on top, the
/// selected environment's .env table underneath.
struct ProjectPreview: View {
    let project: Project
    let onDelete: () -> Void

    @State private var environmentID: ProjectEnvironment.ID?
    @Environment(AppNavigation.self) private var navigation
    @FocusState private var addNameFocused: Bool
    @State private var isEditing = false
    /// Table or File, remembered across projects and launches (not a secret).
    @AppStorage("envViewMode") private var viewMode: EnvViewMode = .table
    /// Show Values above the table; off again when the view or environment changes.
    @State private var showsValues = false
    /// The Edit switch: off = the table/file is locked (read-only).
    @State private var editUnlocked = false
    /// Suggest Sources for the environment shown (only while Edit is on).
    @State private var isSuggesting = false
    /// Local folder whose .env files are being reloaded (sheet).
    @State private var folderToReload: URL?

    var body: some View {
        // Sorted once per redraw and handed down (each read used to re-sort).
        let environments = project.sortedEnvironments
        let environment = environments.first { $0.id == environmentID } ?? environments.first
        // The whole detail column scrolls; the .env table inside grows to fit
        // every row instead of scrolling on its own.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    header
                    infoGrid(environmentCount: environments.count)
                    Divider()
                    envSection(environments: environments, environment: environment)
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Pinned to the bottom, like New Project in the list column.
            if let environment {
                AddVariableCard(target: .environment(environment), nameFocused: $addNameFocused)
                    .id(environment.id)
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.vertical, DS.Space.m)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .sheet(item: Binding(get: { folderToReload.map(ReloadTarget.init) },
                             set: { folderToReload = $0?.url })) { target in
            FolderReloadSheet(project: project, folder: target.url)
        }
    }

    /// Identifiable wrapper for the reload sheet.
    private struct ReloadTarget: Identifiable {
        let url: URL
        var id: URL { url }
    }

    // MARK: Top: project information

    @ViewBuilder
    private var header: some View {
        if isEditing {
            ProjectInfoEditor(project: project, onDone: { isEditing = false })
        } else {
            readOnlyHeader
        }
    }

    private var readOnlyHeader: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            ProjectTile(project: project, size: 52)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(project.name)
                    .font(DS.Font.pageTitle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                ProductionStatusLine(project: project)
                if !project.summary.isEmpty {
                    Text(project.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 12)
            // Local projects: the import was a snapshot, so read the folder's .env files again.
            if let folder = ProjectFolder.resolve(project) {
                Button { folderToReload = folder } label: {
                    Image(systemName: "arrow.clockwise")
                }
                    .symbolMotion(.bounce)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .help("Reload from Folder: read the .env files again and review what changed")
                    .accessibilityLabel("Reload from Folder")
                    .clickableCursor()
            }
            Button { isEditing = true } label: {
                Image(systemName: "pencil")
            }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .help("Edit project details")
                .accessibilityLabel("Edit project details")
                .clickableCursor()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(DS.Status.danger)
            }
                .symbolMotion(.wiggle)
                .buttonStyle(.bordered)
                .tint(DS.Status.danger)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .help("Delete project…")
                .accessibilityLabel("Delete project")
                .clickableCursor()
        }
    }

    @ViewBuilder
    private func infoGrid(environmentCount: Int) -> some View {
        // Count names, not per-environment copies: DATABASE_URL in development,
        // staging and production is one variable. A name is missing a value
        // when any of its environments has none.
        let all = project.allVariables
        let names = Set(all.map(\.key)).count
        let missing = Set(all.filter { !$0.hasValue }.map(\.key)).count
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.s) {
            if let url = project.repoURL {
                GridRow {
                    label(project.provider == .none ? "Link" : "Repository")
                    HStack(spacing: DS.Space.s) {
                        ProviderIcon(provider: project.provider).foregroundStyle(.secondary)
                        LinkText(url: url, title: project.repoFullName.isEmpty ? (url.host() ?? url.absoluteString) : project.repoFullName)
                            .fixedSize()
                    }
                }
            }
            if let folder = ProjectFolder.resolve(project) {
                GridRow {
                    label("Local folder")
                    Text(folder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(folder.path(percentEncoded: false))
                }
            }
            GridRow {
                label("Variables")
                Text(Self.variablesSummary(names: names, missing: missing, environments: environmentCount))
                    .foregroundStyle(missing > 0 ? AnyShapeStyle(DS.Status.warning) : AnyShapeStyle(.primary))
            }
            GridRow {
                label("Created")
                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    /// "13 in 3 environments · 5 missing a value" (distinct names).
    private static func variablesSummary(names: Int, missing: Int, environments: Int) -> String {
        guard names > 0 else { return "None yet" }
        let base = "\(names) in \(environments) environments"
        return missing == 0 ? base : "\(base) · \(missing) missing a value"
    }

    // MARK: Bottom: .env table

    private func envSection(environments: [ProjectEnvironment], environment: ProjectEnvironment?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            // Export and the environment picker act on one environment; Compare shows them all.
            if viewMode != .compare {
            HStack {
                if let environment {
                    ExportMenu(project: project, environment: environment)
                        .id(environment.id)
                }
                Spacer()
                EnvironmentPicker(
                    environments: environments,
                    selection: Binding(get: { environment?.id }, set: { environmentID = $0 })
                )
            }
            }

            if viewMode != .compare, let environment, environment.isProtected {
                ProtectedEnvironmentBanner(name: environment.name)
            }

            if let environment {
                HStack(spacing: DS.Space.m) {
                    Picker("View", selection: $viewMode) {
                        Text("Table").tag(EnvViewMode.table)
                        Text("File").tag(EnvViewMode.file)
                        Text("Compare").tag(EnvViewMode.compare)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("See the variables as a table, as a .env file, or every environment side by side")
                    .clickableCursor()
                    Spacer()
                    if viewMode != .compare {
                    if editUnlocked {
                        Button {
                            isSuggesting = true
                        } label: {
                            Label("Suggest Sources", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderless)
                        .help("Guess Service and Provider for the empty ones in \(environment.name)")
                        .clickableCursor()
                    }
                    ShowValuesButton(isOn: $showsValues,
                                     isEnabled: (environment.variables ?? []).contains(where: \.hasValue))
                    EditSwitch(isOn: $editUnlocked)
                    }
                }
                .padding(.top, DS.Space.xs)

                if viewMode == .compare {
                    EnvCompareView(project: project) { env in
                        environmentID = env.id
                        viewMode = .table
                    }
                } else {
                    EnvEditor(environment: environment, mode: viewMode, showsValues: $showsValues,
                              isEditing: $editUnlocked, onAdd: { addNameFocused = true })
                        .id(environment.id) // fresh state (revealed values, drafts) per environment
                }
            }
        }
        // Another environment, project or view starts hidden and locked again.
        .onChange(of: environment?.id) { showsValues = false; editUnlocked = false }
        .onChange(of: project.id) { showsValues = false; editUnlocked = false }
        .onChange(of: viewMode) { editUnlocked = false }
        // A key picked in the ⌘K palette or the menu bar: show its environment.
        .onChange(of: navigation.environmentToOpen, initial: true) { _, id in
            guard let id, environments.contains(where: { $0.id == id }) else { return }
            environmentID = id
            if viewMode == .compare { viewMode = .table }
            navigation.environmentToOpen = nil
        }
        .sheet(isPresented: $isSuggesting) {
            SuggestSourcesSheet(variables: environment?.sortedVariables ?? [])
        }
    }
}
