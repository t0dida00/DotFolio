import AppKit

/// Copies secrets so that clipboard managers skip them, and clears the
/// clipboard after a delay if it still holds what we put there.
@MainActor
enum SecureClipboard {
    /// nspasteboard.org convention honored by most clipboard managers.
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let clearAfter: Duration = .seconds(60)

    static func copy(_ secret: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(secret, forType: .string)
        pasteboard.setString("", forType: concealed)
        let stamp = pasteboard.changeCount

        Task {
            try? await Task.sleep(for: clearAfter)
            // Only clear if the user hasn't copied something else since.
            if NSPasteboard.general.changeCount == stamp {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
