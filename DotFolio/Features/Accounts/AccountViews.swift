import DotFolioCore
import DotFolioModels
import SwiftData
import SwiftUI

// MARK: - Service icon

extension ServiceType {
    /// SF Symbol shown for accounts of this service.
    var symbol: String {
        switch self {
        case .firebase: "flame"
        case .supabase: "bolt"
        case .stripe: "creditcard"
        case .aws: "cloud"
        case .googleCloud: "cloud.sun"
        case .googleMaps: "map"
        case .vercel: "triangle"
        case .custom: "person.crop.circle"
        }
    }
}

struct AccountTile: View {
    let service: ServiceType
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: service.symbol)
            .font(.system(size: size * 0.42))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - List (left column)

/// Accounts filtered by the toolbar search (login, name, service, service projects).
struct AccountList: View {
    let accounts: [Account]
    let query: String
    @Binding var selection: PersistentIdentifier?
    let onDelete: (Account) -> Void

    private var filtered: [Account] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = accounts.sorted {
            $0.serviceName == $1.serviceName
                ? $0.login.localizedStandardCompare($1.login) == .orderedAscending
                : $0.serviceName.localizedStandardCompare($1.serviceName) == .orderedAscending
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { a in
            [a.login, a.displayName, a.serviceName].contains { $0.localizedStandardContains(q) }
                || (a.serviceProjects ?? []).contains { $0.name.localizedStandardContains(q) || $0.externalID.localizedStandardContains(q) }
        }
    }

    var body: some View {
        let rows = filtered
        if accounts.isEmpty {
            ContentUnavailableView("No accounts yet", systemImage: "person.crop.circle.badge.plus",
                                   description: Text("Add the service logins your projects use — Firebase, Stripe, AWS…"))
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(selection: $selection) {
                ForEach(rows) { account in
                    HStack(spacing: 10) {
                        AccountTile(service: account.serviceType)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.login).lineLimit(1).truncationMode(.middle)
                            Text(subtitle(account)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .clickableCursor()
                    .tag(account.persistentModelID)
                    .contextMenu {
                        Button("Delete Account…", role: .destructive) { onDelete(account) }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func subtitle(_ account: Account) -> String {
        let projects = account.linkedProjects.count
        return "\(account.serviceName) · \(projects) \(projects == 1 ? "project" : "projects")"
    }
}

// MARK: - Detail (right column)

/// One account: editable details, its service projects (with Open console),
/// and the projects / variables that use it.
struct AccountDetailView: View {
    let account: Account
    let onOpenProject: (Project) -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var draft: AccountDraft
    @State private var error: String?

    init(account: Account, onOpenProject: @escaping (Project) -> Void, onDelete: @escaping () -> Void) {
        self.account = account
        self.onOpenProject = onOpenProject
        self.onDelete = onDelete
        _draft = State(initialValue: AccountDraft(account))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                AccountFields(draft: $draft)
                if draft != AccountDraft(account) || error != nil {
                    HStack {
                        if let error { Text(error).font(.callout).foregroundStyle(.red) }
                        Spacer()
                        Button("Revert") { draft = AccountDraft(account); error = nil }
                            .buttonStyle(.bordered)
                        Button("Save Changes", action: save)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
                }
                Divider()
                ServiceProjectsSection(account: account)
                Divider()
                usedBy
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AccountTile(service: account.serviceType, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.login).font(.title2.weight(.semibold)).textSelection(.enabled).lineLimit(2)
                Text(account.displayName.isEmpty ? account.serviceName : "\(account.displayName) · \(account.serviceName)")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .help("Delete account…")
            .accessibilityLabel("Delete account")
            .clickableCursor()
        }
    }

    private var usedBy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Used by").font(.headline)
            let variables = account.allLinkedVariables
            let projects = account.linkedProjects
            if projects.isEmpty {
                Text("No variables use this account yet. Set it in a variable’s Account column.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    let keys = variables.filter { $0.project?.persistentModelID == project.persistentModelID }
                    Button { onOpenProject(project) } label: {
                        HStack(spacing: 10) {
                            ProjectTile(provider: project.provider, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.name).foregroundStyle(.primary)
                                Text(keys.map { "\($0.key) (\($0.environment?.name ?? "?"))" }.joined(separator: ", "))
                                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(project.name)")
                    .clickableCursor()
                }
            }
        }
    }

    private func save() {
        do {
            try AccountEditor.update(account, service: draft.service, customName: draft.customName, login: draft.login,
                                     displayName: draft.displayName, notes: draft.notes, context: context)
            draft = AccountDraft(account)
            error = nil
        } catch {
            self.error = error.message
        }
    }
}

/// Editable copy of an account's fields.
struct AccountDraft: Equatable {
    var service: ServiceType = .firebase
    var customName = ""
    var login = ""
    var displayName = ""
    var notes = ""

    init() {}

    init(_ account: Account) {
        service = account.serviceType
        customName = account.customServiceName ?? ""
        login = account.login
        displayName = account.displayName
        notes = account.notes
    }
}

/// Service · Login · Display name · Notes.
struct AccountFields: View {
    @Binding var draft: AccountDraft

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                label("Service")
                HStack(spacing: 8) {
                    Picker("", selection: $draft.service) {
                        ForEach(ServiceType.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .clickableCursor()
                    if draft.service == .custom {
                        TextField("", text: $draft.customName, prompt: Text("Service name, e.g. Resend"))
                    }
                }
            }
            GridRow {
                label("Login")
                TextField("", text: $draft.login, prompt: Text("email or username"))
            }
            GridRow {
                label("Display name")
                TextField("", text: $draft.displayName, prompt: Text("e.g. Work, Personal, Client X (optional)"))
            }
            GridRow {
                label("Notes")
                TextField("", text: $draft.notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...4)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
}

// MARK: - Service projects

/// Projects inside the account (e.g. Firebase projects), each with Open console.
private struct ServiceProjectsSection: View {
    let account: Account
    @Environment(\.modelContext) private var context

    @State private var newName = ""
    @State private var newID = ""
    @State private var newURL = ""
    @State private var error: String?

    private var items: [ServiceProject] {
        (account.serviceProjects ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(account.serviceName) projects").font(.headline)
            Text("The projects inside this account, e.g. a Firebase project ID. Open the console straight from here.")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(items) { sp in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sp.name).fontWeight(.medium)
                        if !sp.externalID.isEmpty {
                            Text(sp.externalID).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer()
                    if let console = sp.resolvedConsoleURL {
                        Link(destination: console) { Label("Open console", systemImage: "arrow.up.forward.square") }
                            .help(console.absoluteString)
                            .clickableCursor()
                    }
                    Button { AccountEditor.delete(sp, context: context) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove \(sp.name)")
                        .accessibilityLabel("Remove \(sp.name)")
                        .clickableCursor()
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                TextField("", text: $newName, prompt: Text("Name, e.g. Shop prod"))
                TextField("", text: $newID, prompt: Text("Project ID, e.g. shop-prod"))
                    .font(.body.monospaced())
                TextField("", text: $newURL, prompt: Text(verbatim: "Console URL (optional)"))
                Button("Add", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .clickableCursor()
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)

            if let error { Text(error).font(.callout).foregroundStyle(.red) }
        }
    }

    private func add() {
        do {
            try AccountEditor.addServiceProject(to: account, name: newName, externalID: newID, consoleURL: newURL, context: context)
            newName = ""; newID = ""; newURL = ""; error = nil
        } catch {
            self.error = error.message
        }
    }
}

// MARK: - New account (right column)

struct NewAccountForm: View {
    let onCreated: (Account) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @State private var draft = AccountDraft()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AccountTile(service: draft.service, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("New Account").font(.title2.weight(.semibold))
                    Text("A login you use on a service, like your work Firebase account.")
                        .foregroundStyle(.secondary)
                }
            }
            AccountFields(draft: $draft)
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Create Account", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.login.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func create() {
        do {
            let account = try AccountEditor.createAccount(service: draft.service, customName: draft.customName, login: draft.login,
                                                          displayName: draft.displayName, notes: draft.notes, context: context)
            onCreated(account)
        } catch {
            self.error = error.message
        }
    }
}
