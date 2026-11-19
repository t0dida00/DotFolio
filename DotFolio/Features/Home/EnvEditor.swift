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
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session

    @State private var selection: Set<Variable.ID> = []
    @State private var errorMessage: String?
    @State private var pendingDeletion: [Variable] = []
    @State private var copyNotice: String?

    /// "+" under the table: focus the pinned Add variable card.
    var onAdd: () -> Void = {}

    private var variables: [Variable] { environment.sortedVariables }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            VariableTable(
                variables: variables,
                selection: $selection,
                pendingDeletion: $pendingDeletion,
                errorMessage: $errorMessage,
                emptyText: "No variables in \(environment.name) yet — add one below."
            )
            footer
        }
    }

    // MARK: Add row

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) { Image(systemName: "plus").frame(width: 24, height: 20) }
                .symbolMotion(.bounce)
                .help("Add variable")
                .accessibilityLabel("Add variable")
            Button {
                pendingDeletion = variables.filter { selection.contains($0.id) }
            } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                .symbolMotion(.bounce)
                .disabled(selection.isEmpty)
                .help("Delete selected")
                .accessibilityLabel("Delete selected variables")
            copyMenu
                .padding(.leading, DS.Space.s)
            Spacer()
            Text(errorMessage ?? copyNotice ?? "Values live in your Keychain · reveal and copy ask for Touch ID")
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

    private var copyMenu: some View {
        Menu {
            let count = rowsToCopy.count
            Text(selection.isEmpty ? "Copy all \(count) variables to…" : "Copy \(count) selected to…")
            ForEach(otherEnvironments) { target in
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
        .disabled(variables.isEmpty || otherEnvironments.isEmpty)
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
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                // Prompt dismissed.
            } catch {
                errorMessage = (error as? KeychainError)?.userMessage ?? error.localizedDescription
            }
        }
    }

}
