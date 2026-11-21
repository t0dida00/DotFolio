import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// Library keys and project keys grouped by provider ("" = no provider,
/// shown as "Other").
struct LibraryGroup: Identifiable {
    let provider: String
    let keys: [Variable]
    var id: String { provider.lowercased() }
    var title: String { provider.isEmpty ? "Other" : provider }

    static func make(from keys: [Variable]) -> [LibraryGroup] {
        let byProvider = Dictionary(grouping: keys) { $0.serviceLabel.lowercased() }
        return byProvider.values
            .map { keys in
                LibraryGroup(provider: keys.first(where: \.inLibrary)?.serviceLabel ?? keys[0].serviceLabel,
                             keys: keys.sorted(by: Library.displayOrder))
            }
            .sorted { a, b in
                // "Other" last, the rest alphabetically.
                if a.provider.isEmpty != b.provider.isEmpty { return !a.provider.isEmpty }
                return a.provider.localizedStandardCompare(b.provider) == .orderedAscending
            }
    }
}

/// "All keys" plus one row per provider; no projects here.
struct LibraryProviderList: View {
    let groups: [LibraryGroup]
    let total: Int
    /// nil = all providers.
    @Binding var selection: String?

    private static let allTag = "\u{0}all"
    @FocusState private var listFocused: Bool

    var body: some View {
        if total == 0 {
            ContentUnavailableView("No keys yet", systemImage: "books.vertical",
                                   description: Text("Keys you add here and the keys of every project show up here."))
        } else {
            let current = selection ?? Self.allTag
            List {
                row(title: "All keys", count: total, icon: TintedIcon(symbol: "books.vertical", tint: DS.Palette.violet, size: 28))
                    .sidebarRow(isSelected: current == Self.allTag) { select(Self.allTag) }
                Section("Providers") {
                    ForEach(groups) { group in
                        row(title: group.title, count: group.keys.count,
                            icon: TintedIcon(symbol: ServiceType.symbol(for: group.provider),
                                             tint: group.provider.isEmpty ? DS.Palette.neutral : ServiceType.tint(for: group.provider), size: 28))
                            .sidebarRow(isSelected: current == group.id) { select(group.id) }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .sidebarKeyboard(focused: $listFocused) { step in
                let order = [Self.allTag] + groups.map(\.id)
                if let next = SidebarSelection.neighbor(of: current, in: order, step: step) { select(next) }
            }
        }
    }

    private func select(_ id: String) {
        selection = id == Self.allTag ? nil : id
        listFocused = true
    }

    private func row(title: String, count: Int, icon: some View) -> some View {
        HStack(spacing: DS.Space.s) {
            icon
            Text(title).lineLimit(1)
            Spacer(minLength: DS.Space.s)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, DS.Space.xxs)
        .clickableCursor()
    }
}
