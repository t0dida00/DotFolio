import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import AppKit
import LocalAuthentication
import SwiftData
import SwiftUI

/// How a project's variables are shown: the editable table, or the .env
/// file a developer would write.
enum EnvViewMode: String {
    case table, file
}

/// One environment as a .env file: line numbers and one line per variable,
/// `KEY=value #Service/Provider/Account/Link`. Values stay dots until
/// "Show Values" (Touch ID); they live in memory only and are dropped on
/// lock, on Hide, or when the view goes away. Read-only text isn't
/// selectable, so values only leave through the clipboard's auto-clear.
///
/// Edit (Touch ID) turns it into a text editor with the real values; Save
/// applies the text to the environment (see `EnvFileEdit`), asking first
/// when keys were removed.
struct EnvFileView: View {
    let environment: ProjectEnvironment
    let variables: [Variable]
    @Binding var errorMessage: String?
    /// Shared with the table's Show Values button above the view.
    @Binding var showsValues: Bool
    /// The Edit switch above the view: on opens the editor, off discards it.
    @Binding var isEditing: Bool

    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation

    @State private var revealed: [Variable.ID: String] = [:]
    @State private var isRevealing = false
    /// Text being edited; nil when not editing. Holds plaintext values.
    @State private var draft: String?
    /// Values read when editing started, to tell what changed.
    @State private var editValues: [Variable.ID: String] = [:]
    /// A save that deletes variables, waiting for confirmation.
    @State private var pendingPlan: EnvFileEdit.Plan?

    var body: some View {
        let lines = EnvFileLines.lines(for: variables, revealed: revealed)
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            if let draft {
                EnvTextEditor(text: Binding(get: { draft }, set: { self.draft = $0 }))
                    .frame(height: EnvTextEditor.height(lines: draft.components(separatedBy: "\n").count))
            } else if lines.isEmpty {
                Text("No variables in \(environment.name) yet — add one below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(DS.Space.m)
            } else {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            row(number: index + 1, line: line)
                        }
                    }
                    .padding(.vertical, DS.Space.s)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(bordered: true)
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { endEditing() }
        }
        .onChange(of: showsValues) { _, show in
            if show { revealAll() } else { revealed.removeAll() }
        }
        .onAppear {
            if showsValues { revealAll() }
            if isEditing { startEditing() }
        }
        .onChange(of: isEditing) { _, editing in
            if editing { startEditing() } else { endEditing() }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingPlan != nil }, set: { if !$0 { pendingPlan = nil } })
        ) {
            Button("Delete and Save", role: .destructive) {
                if let plan = pendingPlan { apply(plan) }
            }
        } message: {
            Text("\((pendingPlan?.removed ?? []).joined(separator: ", ")) \((pendingPlan?.removed.count ?? 0) == 1 ? "is" : "are") no longer in the file. Stored values are removed from your Keychain. This can’t be undone.")
        }
    }

    private var deleteTitle: String {
        let removed = pendingPlan?.removed ?? []
        return removed.count == 1 ? "Delete \(removed[0])?" : "Delete \(removed.count) variables?"
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "doc.plaintext").foregroundStyle(.secondary)
            Text(EnvExport.fileName(for: environment))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            // The line format, always shown so the file reads the same way it's edited.
            Text("· KEY=value #Service/Provider/Account/Link")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if draft != nil {
                Button("Cancel") { isEditing = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .clickableCursor()
                Button("Save", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Apply this file to \(environment.name) (⌘S)")
                    .clickableCursor()
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
    }

    // MARK: Lines

    private func row(number: Int, line: EnvFileLines.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text("\(number)")
                .foregroundStyle(.tertiary)
                .frame(minWidth: 24, alignment: .trailing)
            Text(attributed(line))
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.xxs)
    }

    private func attributed(_ line: EnvFileLines.Line) -> AttributedString {
        func part(_ text: String, _ color: Color) -> AttributedString {
            var a = AttributedString(text)
            a.foregroundColor = color
            return a
        }
        var result = part(line.key, DS.Palette.violet) + part("=", .secondary)
        switch line.value {
        case .missing: break
        case .hidden: result += part("••••••••", .secondary)
        case .plain(let text): result += part(text, .primary)
        }
        if !line.source.isEmpty { result += part(" #\(line.source)", .secondary) }
        return result
    }

    // MARK: Reveal

    private func revealAll() {
        readValues(reason: "show the values in \(environment.name)", onCancel: { showsValues = false }) { values in
            if showsValues { revealed = values }
        }
    }

    // MARK: Edit

    private func startEditing() {
        guard draft == nil else { return }
        readValues(reason: "edit \(environment.name)", onCancel: { isEditing = false }) { values in
            guard isEditing else { return }
            editValues = values
            draft = EnvFileEdit.text(for: variables, values: values)
        }
    }

    private func endEditing() {
        draft = nil
        editValues = [:]
        revealed = [:]
        showsValues = false
        pendingPlan = nil
        if isEditing { isEditing = false }
    }

    private func save() {
        guard let draft else { return }
        let plan = EnvFileEdit.plan(draft, for: environment, currentValues: editValues)
        if plan.isEmpty {
            endEditing()
            navigation.show(.nothing("No changes", "The file is the same as before, so nothing was saved."))
        } else if !plan.removed.isEmpty {
            pendingPlan = plan
        } else {
            apply(plan)
        }
    }

    private func apply(_ plan: EnvFileEdit.Plan) {
        pendingPlan = nil
        do {
            try EnvFileEdit.apply(plan, to: environment, context: context, secrets: secrets)
            try? context.save()
            errorMessage = nil
            endEditing()
            var groups: [ResultReport.Group] = []
            if !plan.added.isEmpty { groups.append(.init(title: "Added", names: plan.added.map(\.key))) }
            let changed = Set(plan.values.keys).union(plan.sources.keys).subtracting(plan.added.map(\.key)).sorted()
            if !changed.isEmpty { groups.append(.init(title: "Changed", names: changed)) }
            if !plan.removed.isEmpty { groups.append(.init(title: "Deleted", names: plan.removed)) }
            navigation.show(.success("Saved \(environment.name)", "Your edits to the file were saved; values are in your Keychain.", groups: groups))
        } catch {
            // Stay in the editor so the text can be fixed.
            errorMessage = error.message
            navigation.show(.failed("Couldn’t save the file", "Nothing was changed. \(error.message)"))
        }
    }

    /// One Touch ID prompt per session, then every stored value is read.
    private func readValues(reason: String, onCancel: @escaping () -> Void = {}, _ use: @escaping ([Variable.ID: String]) -> Void) {
        let withValues = variables.filter(\.hasValue)
        isRevealing = true
        Task {
            defer { isRevealing = false }
            do {
                var values: [Variable.ID: String] = [:]
                if !withValues.isEmpty {
                    let context = try await session.authenticatedContext(reason: reason)
                    for v in withValues {
                        if let plain = try VariableEditor.value(of: v, secrets: secrets, context: context) {
                            values[v.id] = plain
                        }
                    }
                }
                use(values)
                errorMessage = nil
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                onCancel() // Prompt dismissed.
            } catch let failure as VariableEditor.Failure {
                onCancel()
                errorMessage = failure.message
            } catch {
                onCancel()
                errorMessage = error.localizedDescription
            }
        }
    }
}
