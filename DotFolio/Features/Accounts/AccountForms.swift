import AppKit
import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Editable copy of an account's fields.
struct AccountDraft: Equatable {
    var services: [String] = []
    var login = ""
    var displayName = ""
    var notes = ""

    init() {}

    init(_ account: Account) {
        services = account.services
        login = account.login
        displayName = account.displayName
        notes = account.notes
    }
}

/// Login · Display name · Providers (chips) · Notes.
struct AccountFields: View {
    @Binding var draft: AccountDraft

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.s) {
            GridRow {
                label("Login", required: true)
                TextField("", text: $draft.login)
                    .fieldHint("The email or username you sign in with.")
            }
            GridRow {
                label("Display name", optional: true)
                TextField("", text: $draft.displayName)
                    .fieldHint("Tells logins apart, e.g. Work, Personal, Client X.")
            }
            GridRow {
                label("Providers")
                ServiceChips(services: $draft.services)
            }
            GridRow {
                label("Notes", optional: true)
                TextField("", text: $draft.notes, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func label(_ text: String, required: Bool = false, optional: Bool = false) -> some View {
        Text.fieldTitle(text, required: required, optional: optional)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

/// Removable service chips plus an "Add Service" menu (known services or a custom name).
struct ServiceChips: View {
    @Binding var services: [String]
    @State private var customName = ""
    @State private var addingCustom = false

    private var available: [ServiceType] {
        ServiceType.allCases.filter { type in
            type != .custom && !services.contains { $0.caseInsensitiveCompare(type.displayName) == .orderedSame }
        }
    }

    var body: some View {
        FlowLayout(spacing: DS.Space.s) {
            ForEach(services, id: \.self) { service in
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: ServiceType.symbol(for: service))
                    Text(service)
                    Button {
                        services.removeAll { $0 == service }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove \(service)")
                    .accessibilityLabel("Remove \(service)")
                    .clickableCursor()
                }
                .chip()
            }

            if addingCustom {
                TextField("", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .accessibilityLabel("Provider name")
                    .fieldHint("Provider name · Return to add")
                    .onSubmit(addCustom)
                    .onExitCommand { addingCustom = false; customName = "" }
            } else {
                Menu {
                    ForEach(available) { type in
                        Button(type.displayName, systemImage: type.symbol) { add(type.displayName) }
                    }
                    if !available.isEmpty { Divider() }
                    Button("Other…") { addingCustom = true }
                } label: {
                    // Same shape as the service chips, so the row reads as one set.
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "plus")
                        Text("Add Provider")
                    }
                    .chip(dashed: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a provider this login is used for")
                .clickableCursor()
            }
        }
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !services.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        services.append(ServiceType(matching: trimmed)?.displayName ?? trimmed)
    }

    private func addCustom() {
        add(customName)
        customName = ""
        addingCustom = false
    }
}

struct NewAccountForm: View {
    let onCreated: (Account) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @State private var draft = AccountDraft()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                AccountTile(services: draft.services, size: 52)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("New Account").font(DS.Font.pageTitle)
                    Text("A login you use with one or more providers — e.g. your Gmail for Firebase, Google Cloud and Maps.")
                        .foregroundStyle(.secondary)
                }
            }
            AccountFields(draft: $draft)
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(DS.Status.danger) }
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
        .padding(DS.Space.xl)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func create() {
        do {
            let account = try AccountEditor.createAccount(services: draft.services, login: draft.login,
                                                          displayName: draft.displayName, notes: draft.notes, context: context)
            onCreated(account)
            navigation.show(.success("Account created", "\(account.login) was added."))
        } catch {
            self.error = error.message
            navigation.show(.failed("Couldn’t create the account", error.message))
        }
    }
}
