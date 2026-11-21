import SwiftUI

/// The big "New …" button pinned at the bottom of a list column.
struct SidebarFooterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .clickableCursor()
        .padding(DS.Space.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
