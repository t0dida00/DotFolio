import DotFolioModels
import SwiftUI

/// Top bar of the project browser: sort menu on the left, search on the
/// right (⌘F focuses it).
struct BrowserToolbar: View {
    @Binding var sort: ProjectSort
    @Binding var query: String
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(ProjectSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 15))
                .frame(width: 52, height: 36)
                .contentShape(.capsule)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .glassEffect(.regular.interactive(), in: .capsule)
            .clickableCursor()
            .symbolMotion(.bounce)
            .help("Sort projects")

            Spacer(minLength: 16)

            SearchField(text: $query, isFocused: $searchFocused)
                .frame(maxWidth: 300)
        }
        .padding(.leading, HomeView.trafficLightInset)
        .padding(.trailing, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        .background {
            // ⌘F focuses search, like most Mac apps.
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }
}
