import DotFolioModels
import SwiftData
import SwiftUI

/// Right column in Accounts mode: the new-account form, the selected
/// account, or a hint when nothing is selected.
struct AccountsDetailColumn: View {
    let accounts: [Account]
    @Binding var selection: PersistentIdentifier?
    @Binding var isCreating: Bool
    let onOpenProject: (Project) -> Void
    let onDelete: (Account) -> Void

    var body: some View {
        if isCreating {
            NewAccountForm(
                onCreated: { account in
                    isCreating = false
                    selection = account.persistentModelID
                },
                onCancel: { isCreating = false }
            )
        } else if let id = selection, let account = accounts.first(where: { $0.persistentModelID == id }) {
            AccountDetailView(
                account: account,
                onOpenProject: onOpenProject,
                onDelete: { onDelete(account) }
            )
            .id(account.persistentModelID)
        } else {
            ContentUnavailableView(
                accounts.isEmpty ? "No accounts yet" : "No account selected",
                systemImage: "person.crop.circle",
                description: Text("Accounts are the logins your variables come from — which Firebase, Stripe or AWS login a project uses.")
            )
        }
    }
}
