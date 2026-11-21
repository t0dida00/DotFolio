import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// One provider: header (chevron, provider tile, name, count) and its keys.
struct LibrarySection: View {
    let group: LibraryGroup
    @Binding var isExpanded: Bool

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selection: Set<Variable.ID> = []
    @State private var pendingDeletion: [Variable] = []
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var hovering = false
    @State private var showsValues = false
    /// The Edit switch: off = read-only (double-click a row copies it).
    @State private var editUnlocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    VariableTable(
                        variables: group.keys,
                        selection: $selection,
                        pendingDeletion: $pendingDeletion,
                        errorMessage: $errorMessage,
                        showsValues: $showsValues,
                        isEditable: editUnlocked,
                        showsOrigin: true,
                        emptyText: "No keys",
                        extraMenu: { v in AnyView(addToProjectMenu(v)) }
                    )
                    footer
                }
                .padding(DS.Space.m)
                .transition(.opacity)
            }
        }
        .panel(radius: DS.Radius.medium, bordered: true)
        // Collapsing or the session locking puts the table back to read-only.
        .onChange(of: isExpanded) { _, open in if !open { editUnlocked = false } }
        .onChange(of: session.isUnlocked) { _, unlocked in if !unlocked { editUnlocked = false } }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 16)
            TintedIcon(symbol: ServiceType.symbol(for: group.provider),
                       tint: group.provider.isEmpty ? DS.Palette.neutral : ServiceType.tint(for: group.provider), size: 28)
            Text(group.title).font(DS.Font.sectionTitle)
            Text("\(group.keys.count) \(group.keys.count == 1 ? "key" : "keys")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if isExpanded {
                ShowValuesButton(isOn: $showsValues, isEnabled: group.keys.contains(where: \.hasValue))
                EditSwitch(isOn: $editUnlocked)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .contentShape(Rectangle())
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(DS.Fill.control)) : AnyShapeStyle(Color.clear))
        .onHover { hovering = $0 }
        .onTapGesture { isExpanded.toggle() }
        .clickableCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAction { isExpanded.toggle() }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                pendingDeletion = group.keys.filter { selection.contains($0.id) }
            } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty || !editUnlocked)
                .help(editUnlocked ? "Delete selected" : "Turn on Edit to delete keys")
                .accessibilityLabel("Delete selected keys")
                .clickableCursor()
            Spacer()
            Text(errorMessage ?? notice ?? (editUnlocked
                ? "Right-click a key to add it to a project"
                : "Double-click a key to copy it as a .env line · right-click to add it to a project · turn on Edit to change it"))
                .font(.caption)
                .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
                .lineLimit(2)
        }
    }

    /// Add to Project ▸ project ▸ environment ▸ name only / name and value.
    @ViewBuilder
    private func addToProjectMenu(_ key: Variable) -> some View {
        Menu("Add to Project") {
            if projects.isEmpty {
                Text("No projects yet")
            }
            ForEach(projects) { project in
                Menu(project.name) {
                    ForEach(project.sortedEnvironments) { env in
                        Menu(env.name) {
                            Button("Name Only") { add(key, to: env, includeValue: false) }
                            Button("Name and Value (Touch ID)") { add(key, to: env, includeValue: true) }
                                .disabled(!key.hasValue)
                        }
                    }
                }
            }
        }
    }

    private func add(_ key: Variable, to env: ProjectEnvironment, includeValue: Bool) {
        Task {
            do {
                var auth: LAContext?
                if includeValue && key.hasValue {
                    auth = try await session.authenticatedContext(reason: "add \(key.key) to \(env.project?.name ?? "the project")")
                }
                let result = try VariableCopier.copy([key], to: env, includeValues: includeValue,
                                                     context: context, secrets: secrets, authContext: auth)
                errorMessage = nil
                let place = "\(env.project?.name ?? "") · \(env.name)"
                notice = result.copied == 1 ? "Added \(key.key) to \(place)." : "\(key.key) already exists in \(place) — skipped."
                navigation.show(result.copied == 1
                    ? .success("Added to project", "\(key.key) was added to \(place)" + (includeValue ? " with its value." : ", name only."))
                    : .nothing("Already there", "\(key.key) already exists in \(place). It was left as it was."))
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                // Prompt dismissed.
            } catch {
                errorMessage = (error as? KeychainError)?.userMessage ?? error.localizedDescription
            }
        }
    }
}
