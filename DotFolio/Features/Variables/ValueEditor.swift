import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

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
