import AppKit
import SwiftUI

/// Left-column lists (Projects, Accounts, Libraries) draw their own selection:
/// the quiet gray highlight macOS uses for an unfocused list, in every state —
/// never the accent fill the system paints while the list has focus.
/// Rows select on click (⌘-click / ⇧-click for several where the list allows
/// it), and ↑/↓ move the selection once the list has been clicked.
extension View {
    func sidebarRow(isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .listRowBackground(SidebarHighlight(isSelected: isSelected))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Keyboard for a sidebar list: ↑/↓ call `onMove(-1 / +1)`.
    func sidebarKeyboard(focused: FocusState<Bool>.Binding, onMove: @escaping (Int) -> Void) -> some View {
        self
            .focusable()
            .focusEffectDisabled()
            .focused(focused)
            .onKeyPress(.upArrow) { onMove(-1); return .handled }
            .onKeyPress(.downArrow) { onMove(1); return .handled }
    }
}

private struct SidebarHighlight: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
            .padding(.horizontal, DS.Space.s)
    }
}

enum SidebarSelection {
    /// The row `step` rows away from `current` (clamped); the first row when
    /// nothing is selected.
    static func neighbor<ID: Equatable>(of current: ID?, in order: [ID], step: Int) -> ID? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else { return order.first }
        return order[min(max(index + step, 0), order.count - 1)]
    }

    /// Finder-style click: ⌘ toggles a row, ⇧ selects the range from the
    /// anchor, a plain click selects just that row.
    static func click<ID: Hashable>(_ id: ID, selection: Set<ID>, anchor: ID?, order: [ID]) -> Set<ID> {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            var picked = selection
            if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
            return picked
        }
        if flags.contains(.shift), let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
            return Set(order[min(a, b)...max(a, b)])
        }
        return [id]
    }
}
