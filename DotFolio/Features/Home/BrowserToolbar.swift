import DotFolioModels
import SwiftUI

/// Sort menu for the window toolbar. Sort and search are native toolbar
/// items: macOS places them after the traffic lights and, in full screen,
/// slides them in with the menu bar when you point at the top.
struct BrowserSortMenu: View {
    @Binding var sort: ProjectSort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(ProjectSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "line.3.horizontal.decrease")
        }
        .help("Sort projects")
        .clickableCursor()
    }
}

/// Search field for the window toolbar; ⌘F focuses it.
struct BrowserSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        SearchField(text: $query, isFocused: $focused)
            .frame(width: 300)
            .background {
                // ⌘F focuses search, like most Mac apps.
                Button("") { focused = true }
                    .keyboardShortcut("f")
                    .hidden()
            }
    }
}
