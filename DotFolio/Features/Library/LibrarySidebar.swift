import SwiftUI

/// Left column in Libraries mode: the All · Library · Dev · Staging · Prod
/// filter, the providers, and New Key.
struct LibrarySidebar: View {
    let groups: [LibraryGroup]
    @Binding var scope: String
    @Binding var provider: String?
    @Binding var focusRequest: Int

    var body: some View {
        // Same place as Projects' All · Git · Local.
        EqualSegmentedPicker(options: [("All", "all"), ("Library", "library"), ("Dev", "development"),
                                       ("Staging", "staging"), ("Prod", "production")],
                             selection: $scope, controlSize: .small)
            .accessibilityLabel("Show")
            .padding(.horizontal, DS.Space.m)
        .padding(.bottom, DS.Space.xs)
        .help("Every key, only the Library’s own keys, or the project keys of development, staging or production")
        .clickableCursor()
        LibraryProviderList(groups: groups, total: groups.reduce(0) { $0 + $1.keys.count },
                            selection: $provider)
            .frame(maxHeight: .infinity)
        SidebarFooterButton(title: "New Key") {
            provider = nil
            focusRequest += 1
        }
    }
}
