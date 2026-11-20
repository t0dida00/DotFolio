import DotFolioCore
import DotFolioModels
import SwiftUI

/// Right column of the project list: project information on top, the
/// selected environment's .env table underneath.
struct ProjectPreview: View {
    let project: Project
    let onDelete: () -> Void

    @State private var environmentID: ProjectEnvironment.ID?
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
            ProjectTile(provider: project.provider, size: 52)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(project.name)
                    .font(DS.Font.pageTitle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if !project.summary.isEmpty {
                    Text(project.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 12)
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
        let all = project.allVariables
        let missing = all.reduce(0) { $0 + ($1.hasValue ? 0 : 1) }
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
                Text(Self.variablesSummary(total: all.count, missing: missing, environments: environmentCount))
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

    private static func variablesSummary(total: Int, missing: Int, environments: Int) -> String {
        guard total > 0 else { return "None yet" }
        let base = "\(total) across \(environments) environments"
        return missing == 0 ? base : "\(base) · \(missing) missing \(missing == 1 ? "value" : "values")"
    }

    // MARK: Bottom: .env table

    private func envSection(environments: [ProjectEnvironment], environment: ProjectEnvironment?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
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

            if let environment, environment.isProtected {
                ProtectedEnvironmentBanner(name: environment.name)
            }

            if let environment {
                HStack(spacing: DS.Space.m) {
                    Picker("View", selection: $viewMode) {
                        Text("Table").tag(EnvViewMode.table)
                        Text("File").tag(EnvViewMode.file)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("See the variables as a table or as a .env file")
                    .clickableCursor()
                    Spacer()
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
                .padding(.top, DS.Space.xs)

                EnvEditor(environment: environment, mode: viewMode, showsValues: $showsValues,
                          isEditing: $editUnlocked, onAdd: { addNameFocused = true })
                    .id(environment.id) // fresh state (revealed values, drafts) per environment
            }
        }
        // Another environment, project or view starts hidden and locked again.
        .onChange(of: environment?.id) { showsValues = false; editUnlocked = false }
        .onChange(of: project.id) { showsValues = false; editUnlocked = false }
        .onChange(of: viewMode) { editUnlocked = false }
        .sheet(isPresented: $isSuggesting) {
            SuggestSourcesSheet(variables: environment?.sortedVariables ?? [])
        }
    }
}
