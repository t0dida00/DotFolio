import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while hovering a clickable element.
    /// Falls back to the default arrow when disabled, so the cursor never
    /// promises an action that won't happen.
    func clickableCursor() -> some View {
        modifier(ClickableCursor())
    }
}

private struct ClickableCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : nil)
    }
}
