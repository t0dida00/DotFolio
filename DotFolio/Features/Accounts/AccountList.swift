import AppKit
import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

extension Account {
    /// "1 project · 6 keys" — no provider names: one login serves many.
    /// Keys include Library keys, so they can outnumber the projects' ones.
    var usageSummary: String {
        let linked = allLinkedVariables
        let projects = Set(linked.compactMap { $0.project?.persistentModelID }).count
        return "\(projects) \(projects == 1 ? "project" : "projects") · \(linked.count) \(linked.count == 1 ? "key" : "keys")"
    }
}

/// Accounts filtered by the toolbar search (login, name, services, service projects).
struct AccountList: View {
    let accounts: [Account]
    let query: String
    @Binding var selection: PersistentIdentifier?
    let onDelete: (Account) -> Void
    @FocusState private var listFocused: Bool

    private var filtered: [Account] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = accounts.sorted { $0.login.localizedStandardCompare($1.login) == .orderedAscending }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { a in
            [a.login, a.displayName].contains { $0.localizedStandardContains(q) }
                || a.services.contains { $0.localizedStandardContains(q) }
                || (a.serviceProjects ?? []).contains { $0.name.localizedStandardContains(q) || $0.externalID.localizedStandardContains(q) }
        }
    }

    var body: some View {
        let rows = filtered
        if accounts.isEmpty {
            ContentUnavailableView("No accounts yet", systemImage: "person.crop.circle.badge.plus",
                                   description: Text("Add the logins your projects use — one login can cover Firebase, Google Cloud, Maps…"))
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(rows) { account in
                    HStack(spacing: DS.Space.s) {
                        AccountTile(services: account.services)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(account.login).lineLimit(1).truncationMode(.middle)
                            Text(subtitle(account)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                    .clickableCursor()
                    .sidebarRow(isSelected: selection == account.persistentModelID) {
                        selection = account.persistentModelID
                        listFocused = true
                    }
                    .contextMenu {
                        Button("Delete Account…", role: .destructive) { onDelete(account) }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .sidebarKeyboard(focused: $listFocused) { step in
                selection = SidebarSelection.neighbor(of: selection, in: rows.map(\.persistentModelID), step: step) ?? selection
            }
        }
    }

    private func subtitle(_ account: Account) -> String { account.usageSummary }
}
