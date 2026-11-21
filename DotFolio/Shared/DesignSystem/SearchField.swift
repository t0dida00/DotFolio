import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search projects, keys, providers, accounts", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .clickableCursor()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}
