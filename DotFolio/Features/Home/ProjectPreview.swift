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

    private var environments: [ProjectEnvironment] { project.sortedEnvironments }
    private var environment: ProjectEnvironment? {
        environments.first { $0.id == environmentID } ?? environments.first
    }

    var body: some View {
        // The whole detail column scrolls; the .env table inside grows to fit
        // every row instead of scrolling on its own.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    header
                    infoGrid
                    Divider()
                    envSection
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

    private var infoGrid: some View {
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
                Text(variablesSummary)
                    .foregroundStyle(missingCount > 0 ? AnyShapeStyle(DS.Status.warning) : AnyShapeStyle(.primary))
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

    private var allVariables: [Variable] { project.allVariables }
    private var missingCount: Int { allVariables.filter { !$0.hasValue }.count }

    private var variablesSummary: String {
        let total = allVariables.count
        guard total > 0 else { return "None yet" }
        let base = "\(total) across \(environments.count) environments"
        return missingCount == 0 ? base : "\(base) · \(missingCount) missing \(missingCount == 1 ? "value" : "values")"
    }

    // MARK: Bottom: .env table

    private var envSection: some View {
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
                EnvEditor(environment: environment, onAdd: { addNameFocused = true })
                    .id(environment.id) // fresh state (revealed values, drafts) per environment
            }
        }
    }
}
