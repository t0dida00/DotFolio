import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

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
