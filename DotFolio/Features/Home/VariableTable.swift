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
///   Show Values (one button for the whole table, owned by the parent's
///   footer) and Copy read the Keychain, so they ask for Touch ID once per session.
/// - Delete with the Delete key / right-click (confirmed, Keychain first).
/// - Locked (`isEditable == false`): plain text; double-click a row to copy
///   its value.
/// The parent owns selection, the pending deletion and the error line, so
/// its own footer (− button, Copy to…, messages) can use them.
struct VariableTable: View {
    let variables: [Variable]
    @Binding var selection: Set<Variable.ID>
    @Binding var pendingDeletion: [Variable]
    @Binding var errorMessage: String?
    /// Every value shown in plain text (the footer's Show Values button).
    @Binding var showsValues: Bool
    /// False = locked: cells are plain text and rows can't be deleted.
    var isEditable = true
    var emptyText: String = "No variables yet — add one below."
    /// Extra right-click items for a single variable (e.g. "Add to Project").
    var extraMenu: ((Variable) -> AnyView)? = nil

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session
    @Query(sort: \Account.login) private var accounts: [Account]

    /// Plaintext of revealed values, in memory only, hidden again on lock.
    @State private var revealed: [Variable.ID: String] = [:]
    /// Row whose value is open in the multi-line editor (Edit on).
    @State private var editingValueID: Variable.ID?
    /// Which row's copy icon shows the tick (button, double-click, menu).
    @State private var copyFeedback = CopyFeedback()

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
                if isEditable {
                    CommitField(text: v.key, prompt: "", monospaced: true) { new in
                        attempt { try VariableEditor.rename(v, to: new) }
                    }
                } else {
                    Text(v.key).monospaced().lineLimit(1)
                }
            }
            .width(min: widths.name, ideal: widths.name)

            TableColumn("Value") { v in
                valueCell(v)
            }
            .width(min: widths.value, ideal: widths.value)

            // What the value is for. Cells never show placeholder text.
            TableColumn("Service") { v in
                if !isEditable {
                    Text(v.displayCategory).lineLimit(1)
                } else { HStack(spacing: DS.Space.xs) {
                    CommitField(text: v.serviceCategory, prompt: "") { new in
                        VariableEditor.setCategory(v, to: new)
                        return true
                    }
                    SuggestionMenu(help: "Choose what this value is for", items: Self.categorySuggestions) { pick in
                        VariableEditor.setCategory(v, to: pick)
                    }
                } }
            }
            .width(min: widths.category, ideal: widths.category)

            // Who provides it.
            TableColumn("Provider") { v in
                if !isEditable {
                    Text(v.displayService).lineLimit(1)
                } else { HStack(spacing: DS.Space.xs) {
                    CommitField(text: v.displayService, prompt: "") { new in
                        setProvider(v, to: new)
                    }
                    SuggestionMenu(help: "Choose a provider", items: Self.serviceSuggestions) { pick in
                        setProvider(v, to: pick)
                    }
                } }
            }
            .width(min: widths.service, ideal: widths.service)

            TableColumn("Account") { v in
                if !isEditable {
                    Text(v.account?.login ?? "").lineLimit(1).truncationMode(.middle)
                } else { HStack(spacing: DS.Space.xs) {
                    CommitField(text: v.account?.login ?? "", prompt: "") { new in
                        VariableEditor.setAccount(v, login: new, context: context)
                        return true
                    }
                    SuggestionMenu(help: "Choose an account", items: accounts.map(\.login)) { pick in
                        VariableEditor.setAccount(v, login: pick, context: context)
                    }
                } }
            }
            .width(min: widths.account, ideal: widths.account)

            TableColumn("Link") { v in
                if !isEditable {
                    if let url = v.sourceURL { LinkText(url: url) }
                } else { HStack(spacing: DS.Space.s) {
                    CommitField(text: v.sourceURL?.absoluteString ?? "", prompt: "") { new in
                        attempt { try VariableEditor.setLink(v, to: new) }
                    }
                    if let url = v.sourceURL {
                        Link(destination: url) { Image(systemName: "arrow.up.forward.square") }
                            .symbolMotion(.bounceUp)
                            .help("Open \(url.absoluteString)")
                            .clickableCursor()
                    }
                } }
            }
            .width(min: widths.link, ideal: widths.link)

            // Last: copies the whole line, KEY=value #Service/Provider/Account/Link.
            TableColumn("") { v in
                // The tick lives in the button's own state: a table cell
                // doesn't reliably redraw for a change in the table's state.
                CopyButton(id: v.id, feedback: copyFeedback,
                           help: "Copy as a .env line: KEY=value #Service/Provider/Account/Link (Touch ID). The clipboard clears after 60 seconds.",
                           accessibilityLabel: "Copy \(v.key) as a .env line") {
                    copyLine(v)
                }
            }
            .width(28)
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
                Button("Copy Line") { copyLine(v) }
                Button("Copy Value") { copy(v) }.disabled(!v.hasValue)
                if let url = v.sourceURL { Link("Open Link", destination: url) }
                if let extraMenu { extraMenu(v) }
                Divider()
            }
            if !picked.isEmpty && isEditable {
                Button(picked.count == 1 ? "Delete…" : "Delete \(picked.count) Items…", role: .destructive) {
                    pendingDeletion = picked
                }
            }
        } primaryAction: { ids in
            // Locked table: double-click a row to copy its .env line.
            guard !isEditable, ids.count == 1, let v = variables.first(where: { ids.contains($0.id) }) else { return }
            copyLine(v)
        }
        .onDeleteCommand {
            guard isEditable else { return }
            let picked = variables.filter { selection.contains($0.id) }
            if !picked.isEmpty { pendingDeletion = picked }
        }
        .overlay {
            if variables.isEmpty {
                Text(emptyText).foregroundStyle(.secondary)
            }
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked {
                revealed.removeAll()
                showsValues = false
            }
        }
        .onChange(of: showsValues) { _, show in
            if show { revealAll() } else { revealed.removeAll() }
        }
        .onAppear { if showsValues { revealAll() } }
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
            // Dots (or a revealed value) + the edit icon.
            value: min(320, max(150, revealedWidest + 28)),
            category: TextWidth.fit(vars.map(\.displayCategory) + ["Service"], extra: 38, min: 90, max: 160),
            service: TextWidth.fit(vars.map(\.displayService) + ["Provider"], extra: 38, min: 90, max: 200),
            account: TextWidth.fit(vars.map { $0.account?.login ?? "" } + ["Account"], extra: 38, min: 100, max: 300),
            link: TextWidth.fit(vars.map { $0.sourceURL?.absoluteString ?? "" } + ["Link"], extra: 40, min: 90, max: 380)
        )
    }


    @ViewBuilder
    private func valueCell(_ v: Variable) -> some View {
        HStack(spacing: DS.Space.s) {
            if !isEditable {
                Text(revealed[v.id] ?? (v.hasValue ? "••••••••" : ""))
                    .monospaced()
                    .foregroundStyle(revealed[v.id] == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Locked: hovering a shown value reveals all of it.
                    .help(revealed[v.id] ?? "")
            } else {
                // Click to edit in a multi-line editor that shows the whole value.
                Button { editingValueID = v.id } label: {
                    HStack(spacing: DS.Space.xs) {
                        Text(revealed[v.id] ?? (v.hasValue ? "••••••••" : ""))
                            .monospaced()
                            .foregroundStyle(revealed[v.id] == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(v.hasValue ? "Edit value" : "Add a value")
                .clickableCursor()
                .popover(isPresented: Binding(get: { editingValueID == v.id },
                                              set: { if !$0 && editingValueID == v.id { editingValueID = nil } }),
                         arrowEdge: .bottom) {
                    ValueEditor(
                        key: v.key,
                        hasValue: v.hasValue,
                        known: revealed[v.id],
                        load: { done in withValue(of: v, reason: "edit \(v.key)", done) },
                        save: { new in
                            let saved = attempt {
                                try VariableEditor.setValue(v, to: new, secrets: secrets)
                                if revealed[v.id] != nil || showsValues { revealed[v.id] = new.isEmpty ? nil : new }
                            }
                            navigation.show(saved
                                ? .success(new.isEmpty ? "Value cleared" : "Value saved",
                                           new.isEmpty ? "\(v.key) has no value now." : "The new value of \(v.key) is in your Keychain.")
                                : .failed("Couldn’t save the value", errorMessage ?? "Nothing was changed."))
                            return saved
                        },
                        close: { editingValueID = nil }
                    )
                }
            }

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
        var deleted: [String] = []
        for v in picked {
            let key = v.key
            if !attempt({ try VariableEditor.delete(v, context: context, secrets: secrets) }) { break }
            deleted.append(key)
            revealed[v.id] = nil
            selection.remove(v.id)
        }
        pendingDeletion = []
        if deleted.count == picked.count {
            navigation.show(.success(deleted.count == 1 ? "Variable deleted" : "\(deleted.count) variables deleted",
                                     "Their values were removed from your Keychain.",
                                     groups: [.init(title: "Deleted", names: deleted)]))
        } else {
            navigation.show(.failed("Couldn’t delete every variable",
                                    (errorMessage ?? "A value couldn’t be removed from the Keychain.")
                                    + (deleted.isEmpty ? "" : "\nDeleted: \(deleted.joined(separator: ", ")).")))
        }
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
            copyFeedback.flash(v.id)
        }
    }

    /// Copies `KEY=value #Service/Provider/Account/Link`, written exactly like
    /// the File view and Export. A name without a value needs no Touch ID.
    private func copyLine(_ v: Variable) {
        let finish: (String?) -> Void = { plain in
            let values = plain.map { [v.id: $0] } ?? [:]
            var line = EnvFileEdit.text(for: [v], values: values)
            while line.hasSuffix("\n") { line.removeLast() }
            SecureClipboard.copy(line)
            errorMessage = nil
            copyFeedback.flash(v.id)
        }
        if let plain = revealed[v.id] { finish(plain) }
        else if v.hasValue { withValue(of: v, reason: "copy \(v.key)") { finish($0) } }
        else { finish(nil) }
    }

    /// Reads every stored value with one Touch ID prompt. Cancelling turns
    /// Show Values back off.
    private func revealAll() {
        let withValues = variables.filter(\.hasValue)
        Task {
            do {
                var values: [Variable.ID: String] = [:]
                if !withValues.isEmpty {
                    let context = try await session.authenticatedContext(reason: "show values")
                    for v in withValues {
                        if let plain = try VariableEditor.value(of: v, secrets: secrets, context: context) { values[v.id] = plain }
                    }
                }
                guard showsValues else { return }
                revealed = values
                errorMessage = nil
            } catch {
                showsValues = false
                if let failure = error as? VariableEditor.Failure { errorMessage = failure.message }
                else if (error as? LAError).map({ [.userCancel, .appCancel, .systemCancel].contains($0.code) }) != true {
                    errorMessage = error.localizedDescription
                }
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

/// Which row just got copied. Observable, so each copy icon redraws on its
/// own: a Table cell doesn't reliably redraw for a change in the table's state.
@Observable
@MainActor
final class CopyFeedback {
    private(set) var flashingID: UUID?
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    /// Shows the tick on `id`'s copy icon for a moment.
    func flash(_ id: UUID) {
        withAnimation(.snappy) { flashingID = id }
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { flashingID = nil }
        }
    }
}

/// Copy icon that turns into a green tick after its row was copied — by this
/// button, a double-click on the row or the context menu.
struct CopyButton: View {
    let id: UUID
    let feedback: CopyFeedback
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        let didCopy = feedback.flashingID == id
        Button(action: action) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .foregroundStyle(didCopy ? AnyShapeStyle(DS.Status.success) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(didCopy ? "Copied" : help)
        .accessibilityLabel(didCopy ? "Copied" : accessibilityLabel)
        .clickableCursor()
    }
}

/// Multi-line value editor (a popover from the Value cell): wraps long values
/// so all of it is visible. The current value is read with Touch ID first;
/// if that is cancelled, typing still replaces it without showing it.
struct ValueEditor: View {
    let key: String
    let hasValue: Bool
    /// The value when it is already revealed in the table.
    let known: String?
    let load: (@escaping (String) -> Void) -> Void
    /// Saves; false keeps the editor open (the table shows the error).
    let save: (String) -> Bool
    let close: () -> Void

    @State private var text = ""
    @State private var original = ""
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(key).font(DS.Font.panelTitle).monospaced().lineLimit(1).truncationMode(.middle)

            EnvTextEditor(text: $text, wraps: true)
                .frame(width: 520, height: 200)
                .panel(radius: DS.Radius.small, bordered: true)
                .fieldHint(hint)

            HStack {
                Text("\(text.count) characters")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if save(text) { close() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text == original && isLoaded || (!isLoaded && text.isEmpty))
            }
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.l)
        .onAppear {
            if let known {
                text = known; original = known; isLoaded = true
            } else if hasValue {
                load { plain in
                    // Don't overwrite what the user started typing meanwhile.
                    if text.isEmpty { text = plain }
                    original = plain
                    isLoaded = true
                }
            } else {
                isLoaded = true
            }
        }
    }

    private var hint: String {
        if !isLoaded { return "The current value is hidden. What you type replaces it." }
        return "Saved to your Keychain. ⌘↩ saves, Esc cancels."
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

/// The Edit switch above a table: off keeps it locked (read-only).
///
/// Flipping it rebuilds every cell of the table (plain text ↔ fields and
/// menus), which is too much work for the frame the knob animates in. So the
/// knob has its own state and animates at once; the table follows after the
/// animation, without animating itself.
struct EditSwitch: View {
    @Binding var isOn: Bool
    @State private var knob = false

    /// About the length of the switch's own animation.
    private static let settle: Duration = .milliseconds(220)

    var body: some View {
        Toggle(isOn: $knob) {
            Label("Edit", systemImage: knob ? "lock.open" : "lock")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(knob ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help(knob ? "Lock the table again" : "Unlock to change names, values and sources")
        .clickableCursor()
        .onAppear { knob = isOn }
        // Locked from outside (another project, screen lock…): follow at once.
        .onChange(of: isOn) { _, new in if knob != new { knob = new } }
        .onChange(of: knob) { _, new in
            guard new != isOn else { return }
            Task { @MainActor in
                try? await Task.sleep(for: Self.settle)
                guard knob == new, isOn != new else { return } // flipped back meanwhile
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isOn = new }
            }
        }
    }
}

/// Toggle above a `VariableTable`: shows or hides every value at once.
struct ShowValuesButton: View {
    @Binding var isOn: Bool
    /// False when nothing in the table has a value.
    var isEnabled = true

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(isOn ? "Hide Values" : "Show Values", systemImage: isOn ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .symbolMotion(.bounce)
        .disabled(!isEnabled && !isOn)
        .help(isOn ? "Hide the values again" : "Show every value in this table (Touch ID)")
        .clickableCursor()
    }
}
