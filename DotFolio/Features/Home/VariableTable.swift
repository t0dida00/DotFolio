import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// The editable variables table shared by a project environment and the
/// Library: #, Name, Value, Service, Provider, Account, Link.
/// - Name / Link / Service / Provider / Account: edit in place, saved on
///   Return or when leaving the cell.
/// - Value: type a new value to replace it (no auth needed to write).
///   Reveal and Copy read the Keychain, so they ask for Touch ID once per session.
/// - Delete with the Delete key / right-click (confirmed, Keychain first).
/// The parent owns selection, the pending deletion and the error line, so
/// its own footer (− button, Copy to…, messages) can use them.
struct VariableTable: View {
    let variables: [Variable]
    @Binding var selection: Set<Variable.ID>
    @Binding var pendingDeletion: [Variable]
    @Binding var errorMessage: String?
    var emptyText: String = "No variables yet — add one below."
    /// Extra right-click items for a single variable (e.g. "Add to Project").
    var extraMenu: ((Variable) -> AnyView)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session
    @Query(sort: \Account.login) private var accounts: [Account]

    /// Plaintext of revealed values, in memory only, hidden again on lock.
    @State private var revealed: [Variable.ID: String] = [:]
    /// Row whose value was just copied: its copy icon shows a tick briefly.
    @State private var copiedID: Variable.ID?

    var body: some View {
        // Computed once per redraw and shared by every column and row (reading a
        // computed property per column re-measured all the text six times).
        let widths = columnWidths
        let rowNumber = Dictionary(uniqueKeysWithValues: variables.enumerated().map { ($1.id, $0 + 1) })
        Table(variables, selection: $selection) {
            TableColumn("#") { v in
                Text("\(rowNumber[v.id] ?? 0)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(24)

            TableColumn("Name") { v in
                CommitField(text: v.key, prompt: "", monospaced: true) { new in
                    attempt { try VariableEditor.rename(v, to: new) }
                }
            }
            .width(min: widths.name, ideal: widths.name)

            TableColumn("Value") { v in
                valueCell(v)
            }
            .width(min: widths.value, ideal: widths.value)

            // What the value is for. No example placeholders; only a real guess
            // from the provider (Redis → Cache) shows, dimmed, until one is chosen.
            TableColumn("Service") { v in
                HStack(spacing: DS.Space.xs) {
                    CommitField(text: v.serviceCategory, prompt: v.displayCategory) { new in
                        VariableEditor.setCategory(v, to: new)
                        return true
                    }
                    SuggestionMenu(help: "Choose what this value is for", items: Self.categorySuggestions) { pick in
                        VariableEditor.setCategory(v, to: pick)
                    }
                }
            }
            .width(min: widths.category, ideal: widths.category)

            // Who provides it.
            TableColumn("Provider") { v in
                HStack(spacing: DS.Space.xs) {
                    CommitField(text: v.displayService, prompt: "") { new in
                        setProvider(v, to: new)
                    }
                    SuggestionMenu(help: "Choose a provider", items: Self.serviceSuggestions) { pick in
                        setProvider(v, to: pick)
                    }
                }
            }
            .width(min: widths.service, ideal: widths.service)

            TableColumn("Account") { v in
                HStack(spacing: DS.Space.xs) {
                    CommitField(text: v.account?.login ?? "", prompt: "") { new in
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
                HStack(spacing: DS.Space.s) {
                    CommitField(text: v.sourceURL?.absoluteString ?? "", prompt: "") { new in
                        attempt { try VariableEditor.setLink(v, to: new) }
                    }
                    if let url = v.sourceURL {
                        Link(destination: url) { Image(systemName: "arrow.up.forward.square") }
                            .symbolMotion(.bounceUp)
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
        .frame(height: DS.Table.height(rows: variables.count, minimumRows: 2))
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .contextMenu(forSelectionType: Variable.ID.self) { ids in
            let picked = variables.filter { ids.contains($0.id) }
            if picked.count == 1, let v = picked.first {
                Button("Reveal Value") { reveal(v) }.disabled(!v.hasValue)
                Button("Copy Value") { copy(v) }.disabled(!v.hasValue)
                if let url = v.sourceURL { Link("Open Link", destination: url) }
                if let extraMenu { extraMenu(v) }
                Divider()
            }
            if !picked.isEmpty {
                Button(picked.count == 1 ? "Delete…" : "Delete \(picked.count) Items…", role: .destructive) {
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
                Text(emptyText).foregroundStyle(.secondary)
            }
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { revealed.removeAll() }
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete \(pendingDeletion.first?.key ?? "")?" : "Delete \(pendingDeletion.count) items?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
        ) {
            Button("Delete", role: .destructive) { delete(pendingDeletion) }
        } message: {
            Text("Stored values are removed from your Keychain. This can’t be undone.")
        }
    }

    // MARK: Column widths

    private var columnWidths: (name: CGFloat, value: CGFloat, category: CGFloat, service: CGFloat, account: CGFloat, link: CGFloat) {
        let vars = variables
        let revealedWidest = revealed.values.map { TextWidth.of($0, monospaced: true, cached: false) }.max() ?? 0
        return (
            name: TextWidth.fit(vars.map(\.key) + ["Name"], monospaced: true, extra: 20, min: 80, max: 280),
            // Dots (or a revealed value) + the eye and copy buttons.
            value: min(320, max(150, revealedWidest + 70)),
            category: TextWidth.fit(vars.map(\.displayCategory) + ["Service"], extra: 38, min: 90, max: 160),
            service: TextWidth.fit(vars.map(\.displayService) + ["Provider"], extra: 38, min: 90, max: 200),
            account: TextWidth.fit(vars.map { $0.account?.login ?? "" } + ["Account"], extra: 38, min: 100, max: 300),
            link: TextWidth.fit(vars.map { $0.sourceURL?.absoluteString ?? "" } + ["Link"], extra: 40, min: 90, max: 380)
        )
    }


    @ViewBuilder
    private func valueCell(_ v: Variable) -> some View {
        HStack(spacing: DS.Space.s) {
            if let plain = revealed[v.id] {
                CommitField(text: plain, prompt: "", monospaced: true) { new in
                    attempt {
                        try VariableEditor.setValue(v, to: new, secrets: secrets)
                        revealed[v.id] = new.isEmpty ? nil : new
                    }
                }
            } else {
                // Typing here replaces the value; the old one is never shown.
                CommitField(text: "", prompt: v.hasValue ? "••••••••" : "", monospaced: true, secure: true, keepsTextAfterCommit: false) { new in
                    guard !new.isEmpty else { return true }
                    return attempt { try VariableEditor.setValue(v, to: new, secrets: secrets) }
                }
            }

            Button {
                if revealed[v.id] != nil { revealed[v.id] = nil } else { reveal(v) }
            } label: {
                Image(systemName: revealed[v.id] != nil ? "eye.slash" : "eye")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .symbolMotion(.bounce)
            .disabled(!v.hasValue)
            .help(revealed[v.id] != nil ? "Hide value" : "Reveal value (Touch ID)")
            .clickableCursor()

            Button { copy(v) } label: {
                Image(systemName: copiedID == v.id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedID == v.id ? AnyShapeStyle(DS.Status.success) : AnyShapeStyle(.primary))
                    .contentTransition(.symbolEffect(.replace))
            }
                .buttonStyle(.borderless)
                .symbolMotion(.bounce)
                .disabled(!v.hasValue)
                .help("Copy value (Touch ID). The clipboard clears after 60 seconds.")
                .clickableCursor()
        }
    }

    // MARK: Actions

    /// Library keys stay unique per provider when moved; project variables
    /// just take the new provider.
    private func setProvider(_ v: Variable, to text: String) -> Bool {
        if v.inLibrary {
            return attempt { try VariableEditor.setLibraryProvider(v, to: text, context: context) }
        }
        VariableEditor.setService(v, to: text)
        return true
    }

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
            copiedID = v.id
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedID == v.id { copiedID = nil }
            }
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

extension VariableTable {
    /// Common providers offered in the Provider column's menu.
    static let serviceSuggestions: [String] =
        ServiceType.allCases.filter { $0 != .custom }.map(\.displayName) + ["Redis", "Postgres", "Resend", "Sentry", "OpenAI"]

    /// Service categories offered in the Service column's menu.
    static let categorySuggestions: [String] = ServiceCategory.allCases.map(\.displayName)
}

/// Small chevron menu that fills a cell from a list of suggestions.
struct SuggestionMenu: View {
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
        .symbolMotion(.bounceDown)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .clickableCursor()
    }
}

/// Text field that saves on Return or when focus leaves, and reverts to the
/// saved text when `onCommit` returns false.
struct CommitField: View {
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
