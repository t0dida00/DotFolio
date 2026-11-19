import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// Editable .env table for one environment: #, Name, Value, Service, Account, Link.
/// - Name / Link: edit in place, saved on Return or when leaving the cell.
/// - Value: type a new value to replace it (no auth needed to write).
///   Reveal and Copy read the Keychain, so they ask for Touch ID once per session.
/// - Add with the card pinned to the bottom of the column (AddVariableCard);
///   delete with − / Delete key / right-click.
struct EnvEditor: View {
    let environment: ProjectEnvironment

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session
    @Query(sort: \Account.login) private var accounts: [Account]

    @State private var selection: Set<Variable.ID> = []
    /// Plaintext of revealed values, in memory only, hidden again on lock.
    @State private var revealed: [Variable.ID: String] = [:]
    @State private var errorMessage: String?
    @State private var pendingDeletion: [Variable] = []
    @State private var copyNotice: String?

    /// "+" under the table: focus the pinned Add variable card.
    var onAdd: () -> Void = {}

    private var variables: [Variable] { environment.sortedVariables }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            table
            footer
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { revealed.removeAll() }
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete \(pendingDeletion[0].key)?" : "Delete \(pendingDeletion.count) variables?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
        ) {
            Button("Delete", role: .destructive) { delete(pendingDeletion) }
        } message: {
            Text("Stored values are removed from your Keychain. This can’t be undone.")
        }
    }

    // MARK: Table height

    /// Header + one row per variable (at least two rows, so the empty state fits).
    private var tableHeight: CGFloat {
        let header: CGFloat = 28, row: CGFloat = 26, borders: CGFloat = 4
        return header + row * CGFloat(max(variables.count, 2)) + borders
    }

    // MARK: Column widths

    /// Minimum width per column: just wide enough for its widest value (or
    /// its prompt), within limits. Columns have no maximum, so any spare width
    /// is shared out and the table always fills the panel; narrower than the
    /// minimums → the table scrolls sideways.
    private var widths: (name: CGFloat, value: CGFloat, service: CGFloat, account: CGFloat, link: CGFloat) {
        let vars = variables
        let revealedWidest = revealed.values.map { TextWidth.of($0, monospaced: true) }.max() ?? 0
        return (
            name: TextWidth.fit(vars.map(\.key) + ["NAME"], monospaced: true, extra: 20, min: 80, max: 280),
            // Dots (or a revealed value) + the eye and copy buttons.
            value: min(320, max(150, revealedWidest + 70)),
            service: TextWidth.fit(vars.map(\.displayService) + ["e.g. DB, Firebase"], extra: 38, min: 100, max: 200),
            account: TextWidth.fit(vars.map { $0.account?.login ?? "" } + ["email or username"], extra: 38, min: 130, max: 300),
            link: TextWidth.fit(vars.map { $0.sourceURL?.absoluteString ?? "" } + ["https://…"], extra: 40, min: 110, max: 380)
        )
    }

    // MARK: Table

    private var table: some View {
        Table(variables, selection: $selection) {
            TableColumn("#") { v in
                Text("\((variables.firstIndex { $0.id == v.id } ?? 0) + 1)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(24)

            TableColumn("Name") { v in
                CommitField(text: v.key, prompt: "NAME", monospaced: true) { new in
                    attempt { try VariableEditor.rename(v, to: new) }
                }
            }
            .width(min: widths.name, ideal: widths.name)

            TableColumn("Value") { v in
                valueCell(v)
            }
            .width(min: widths.value, ideal: widths.value)

            TableColumn("Service") { v in
                HStack(spacing: 4) {
                    CommitField(text: v.displayService, prompt: "e.g. DB, Firebase") { new in
                        VariableEditor.setService(v, to: new)
                        return true
                    }
                    SuggestionMenu(help: "Choose a service", items: Self.serviceSuggestions) { pick in
                        VariableEditor.setService(v, to: pick)
                    }
                }
            }
            .width(min: widths.service, ideal: widths.service)

            TableColumn("Account") { v in
                HStack(spacing: 4) {
                    CommitField(text: v.account?.login ?? "", prompt: "email or username") { new in
                        VariableEditor.setAccount(v, login: new, context: context)
                        return true
                    }
                    SuggestionMenu(help: "Choose an account", items: accounts.map(\.login)) { pick in
                        VariableEditor.setAccount(v, login: pick, context: context)
                    }
                }
            }
            .width(min: widths.account, ideal: widths.account)

            TableColumn("Link") { v in
                HStack(spacing: 6) {
                    CommitField(text: v.sourceURL?.absoluteString ?? "", prompt: "https://…") { new in
                        attempt { try VariableEditor.setLink(v, to: new) }
                    }
                    if let url = v.sourceURL {
                        Link(destination: url) { Image(systemName: "arrow.up.forward.square") }
                            .help("Open \(url.absoluteString)")
                            .clickableCursor()
                    }
                }
            }
            .width(min: widths.link, ideal: widths.link)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        // Tall enough for every row, so it never scrolls vertically (the
        // surrounding column does); it still scrolls sideways when the
        // content-fit columns are wider than the panel.
        .frame(height: tableHeight)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .contextMenu(forSelectionType: Variable.ID.self) { ids in
            let picked = variables.filter { ids.contains($0.id) }
            if picked.count == 1, let v = picked.first {
                Button("Reveal Value") { reveal(v) }.disabled(!v.hasValue)
                Button("Copy Value") { copy(v) }.disabled(!v.hasValue)
                if let url = v.sourceURL { Link("Open Link", destination: url) }
                Divider()
            }
            if !picked.isEmpty {
                Button(picked.count == 1 ? "Delete Variable…" : "Delete \(picked.count) Variables…", role: .destructive) {
                    pendingDeletion = picked
                }
            }
        }
        .onDeleteCommand {
            let picked = variables.filter { selection.contains($0.id) }
            if !picked.isEmpty { pendingDeletion = picked }
        }
        .overlay {
            if variables.isEmpty {
                Text("No variables in \(environment.name) yet — add one below.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func valueCell(_ v: Variable) -> some View {
        HStack(spacing: 6) {
            if let plain = revealed[v.id] {
                CommitField(text: plain, prompt: "value", monospaced: true) { new in
                    attempt {
                        try VariableEditor.setValue(v, to: new, secrets: secrets)
                        revealed[v.id] = new.isEmpty ? nil : new
                    }
                }
            } else {
                // Typing here replaces the value; the old one is never shown.
                CommitField(text: "", prompt: v.hasValue ? "••••••••" : "Not set", monospaced: true, secure: true, keepsTextAfterCommit: false) { new in
                    guard !new.isEmpty else { return true }
                    return attempt { try VariableEditor.setValue(v, to: new, secrets: secrets) }
                }
            }

            Button {
                if revealed[v.id] != nil { revealed[v.id] = nil } else { reveal(v) }
            } label: {
                Image(systemName: revealed[v.id] != nil ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .disabled(!v.hasValue)
            .help(revealed[v.id] != nil ? "Hide value" : "Reveal value (Touch ID)")
            .clickableCursor()

            Button { copy(v) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .disabled(!v.hasValue)
                .help("Copy value (Touch ID). The clipboard clears after 60 seconds.")
                .clickableCursor()
        }
    }

    // MARK: Add row

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) { Image(systemName: "plus").frame(width: 24, height: 20) }
                .help("Add variable")
                .accessibilityLabel("Add variable")
            Button {
                pendingDeletion = variables.filter { selection.contains($0.id) }
            } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                .disabled(selection.isEmpty)
                .help("Delete selected")
                .accessibilityLabel("Delete selected variables")
            copyMenu
                .padding(.leading, 10)
            Spacer()
            Text(errorMessage ?? copyNotice ?? "Values live in your Keychain. Reveal and Copy ask for Touch ID.")
                .font(.caption)
                .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
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

    // MARK: Actions

    /// Runs an edit; on failure shows the message and returns false so the
    /// cell reverts to the saved value.
    @discardableResult
    private func attempt(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            errorMessage = nil
            return true
        } catch let failure as VariableEditor.Failure {
            errorMessage = failure.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }


    private func delete(_ picked: [Variable]) {
        for v in picked {
            if !attempt({ try VariableEditor.delete(v, context: context, secrets: secrets) }) { break }
            revealed[v.id] = nil
            selection.remove(v.id)
        }
        pendingDeletion = []
    }

    private func reveal(_ v: Variable) {
        withValue(of: v, reason: "reveal \(v.key)") { plain in
            revealed[v.id] = plain
        }
    }

    private func copy(_ v: Variable) {
        withValue(of: v, reason: "copy \(v.key)") { plain in
            SecureClipboard.copy(plain)
            errorMessage = nil
        }
    }

    /// Authenticates once per session (Touch ID / password), then reads.
    private func withValue(of v: Variable, reason: String, _ use: @escaping (String) -> Void) {
        Task {
            do {
                let context = try await session.authenticatedContext(reason: reason)
                if let plain = try VariableEditor.value(of: v, secrets: secrets, context: context) { use(plain) }
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                // User dismissed the prompt; nothing to report.
            } catch let failure as VariableEditor.Failure {
                errorMessage = failure.message
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension EnvEditor {
    /// Common services offered in the Service column's menu.
    static let serviceSuggestions: [String] =
        ServiceType.allCases.filter { $0 != .custom }.map(\.displayName) + ["Database", "Redis", "Email", "Analytics"]
}

/// Small chevron menu that fills a cell from a list of suggestions.
private struct SuggestionMenu: View {
    let help: String
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            if items.isEmpty {
                Text("No suggestions yet")
            } else {
                ForEach(items, id: \.self) { item in
                    Button(item) { onPick(item) }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .clickableCursor()
    }
}

/// Text field that saves on Return or when focus leaves, and reverts to the
/// saved text when `onCommit` returns false.
private struct CommitField: View {
    let text: String
    var prompt: String
    var monospaced = false
    var secure = false
    /// False for "type to replace" fields that should empty after saving.
    var keepsTextAfterCommit = true
    let onCommit: (String) -> Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $draft, prompt: Text(verbatim: prompt))
            } else {
                TextField("", text: $draft, prompt: Text(verbatim: prompt))
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? .system(.body, design: .monospaced) : .body)
        .focused($focused)
        .onAppear { draft = text }
        .onChange(of: text) { _, new in if !focused { draft = new } }
        .onSubmit(commit)
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onExitCommand { draft = text; focused = false }
    }

    private func commit() {
        guard draft != text else { return }
        if onCommit(draft) {
            if !keepsTextAfterCommit { draft = "" }
        } else {
            draft = text
        }
    }
}
