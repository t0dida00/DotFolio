import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// One environment's variables: the shared `VariableTable` plus the
/// environment footer (+, −, Copy to another environment, messages).
/// Variables are added with the card pinned to the bottom of the column.
struct EnvEditor: View {
    let environment: ProjectEnvironment

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session

    @State private var selection: Set<Variable.ID> = []
    @State private var errorMessage: String?
    @State private var pendingDeletion: [Variable] = []
    @State private var copyNotice: String?

    /// Table or File (a .env file, editable after Edit).
    var mode: EnvViewMode = .table
    /// Every value in plain text; the toggle sits above the table.
    @Binding var showsValues: Bool
    /// The Edit switch above the table: off = locked, read-only.
    @Binding var isEditing: Bool
    /// "+" under the table: focus the pinned Add variable card.
    var onAdd: () -> Void = {}

    private var variables: [Variable] { environment.sortedVariables }

    var body: some View {
        // Sorted once per redraw and handed down (each read used to re-sort).
        let variables = self.variables
        let others = otherEnvironments
        VStack(alignment: .leading, spacing: DS.Space.s) {
            switch mode {
            case .table:
                VariableTable(
                    variables: variables,
                    selection: $selection,
                    pendingDeletion: $pendingDeletion,
                    errorMessage: $errorMessage,
                    showsValues: $showsValues,
                    isEditable: isEditing,
                    emptyText: "No variables in \(environment.name) yet — add one below."
                )
            case .file, .compare:
                EnvFileView(environment: environment, variables: variables, errorMessage: $errorMessage, showsValues: $showsValues, isEditing: $isEditing)
            }
            footer(variables: variables, others: others)
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { isEditing = false }
        }
        // A message from the table (e.g. "no value to copy") doesn't belong to the file view.
        .onChange(of: mode) { errorMessage = nil; copyNotice = nil }
    }

    // MARK: Add row

    private func footer(variables: [Variable], others: [ProjectEnvironment]) -> some View {
        HStack(spacing: 0) {
            Button(action: onAdd) { Image(systemName: "plus").frame(width: 24, height: 20) }
                .symbolMotion(.bounce)
                .help("Add variable")
                .accessibilityLabel("Add variable")
            Button {
                pendingDeletion = variables.filter { selection.contains($0.id) }
            } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                .symbolMotion(.bounce)
                .disabled(selection.isEmpty || !isEditing)
                .help(isEditing ? "Delete selected" : "Turn on Edit to delete")
                .accessibilityLabel("Delete selected variables")
            copyMenu(variables: variables, others: others)
                .padding(.leading, DS.Space.s)
            Spacer()
            Text(errorMessage ?? copyNotice ?? (isEditing ? "Values live in your Keychain · showing and copying them ask for Touch ID" : "Double-click a row to copy it as a .env line · turn on Edit to change it"))
                .font(.caption)
                .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
                .lineLimit(2)
        }
        .buttonStyle(.borderless)
        .clickableCursor()
    }

    // MARK: Copy to another environment

    private var otherEnvironments: [ProjectEnvironment] {
        (environment.project?.sortedEnvironments ?? []).filter { $0.id != environment.id }
    }

    /// Selected rows if any, otherwise the whole list.
    private var rowsToCopy: [Variable] {
        let picked = variables.filter { selection.contains($0.id) }
        return picked.isEmpty ? variables : picked
    }

    private func copyMenu(variables: [Variable], others: [ProjectEnvironment]) -> some View {
        Menu {
            let picked = variables.filter { selection.contains($0.id) }.count
            let count = picked == 0 ? variables.count : picked
            Text(selection.isEmpty ? "Copy all \(count) variables to…" : "Copy \(count) selected to…")
            ForEach(others) { target in
                Menu(target.name) {
                    Button("Names Only") { copy(to: target, includeValues: false) }
                    Button("Names and Values (Touch ID)") { copy(to: target, includeValues: true) }
                }
            }
        } label: {
            Label("Copy to", systemImage: "square.on.square")
        }
        .menuStyle(.button)
        .symbolMotion(.bounce)
        .fixedSize()
        .disabled(variables.isEmpty || others.isEmpty)
        .help("Copy these variables to another environment. Existing names there are skipped, never overwritten.")
    }

    private func copy(to target: ProjectEnvironment, includeValues: Bool) {
        let rows = rowsToCopy
        Task {
            do {
                var auth: LAContext?
                if includeValues && rows.contains(where: \.hasValue) {
                    auth = try await session.authenticatedContext(reason: "copy values to \(target.name)")
                }
                let result = try VariableCopier.copy(rows, to: target, includeValues: includeValues,
                                                     context: context, secrets: secrets, authContext: auth)
                errorMessage = nil
                var notice = "Copied \(result.copied) to \(target.name)."
                if !result.skipped.isEmpty {
                    notice += " Skipped \(result.skipped.count) already there: \(result.skipped.prefix(3).joined(separator: ", "))\(result.skipped.count > 3 ? "…" : "")."
                }
                copyNotice = notice
                navigation.show(result.copied == 0
                    ? .nothing("Nothing copied", "Every name is already in \(target.name); existing ones are never overwritten.",
                               groups: [.init(title: "Already there", names: result.skipped)])
                    : .success("Copied to \(target.name)", notice,
                               groups: result.skipped.isEmpty ? [] : [.init(title: "Already there, skipped", names: result.skipped)]))
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                // Prompt dismissed.
            } catch {
                errorMessage = (error as? KeychainError)?.userMessage ?? error.localizedDescription
            }
        }
    }

}
