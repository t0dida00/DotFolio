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
        Picker("Show", selection: $scope) {
            Text("All").tag("all")
            Text("Library").tag("library")
            Text("Dev").tag("development")
            Text("Staging").tag("staging")
            Text("Prod").tag("production")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
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
