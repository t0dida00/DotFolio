import SwiftUI

/// Cancel + confirm pair used at the bottom of forms.
struct SheetButtons: View {
    let confirmTitle: String
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .clickableCursor()
            Button(confirmTitle, action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
                .clickableCursor()
        }
        .controlSize(.large)
    }
}
