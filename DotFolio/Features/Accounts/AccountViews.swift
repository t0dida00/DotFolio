import AppKit
import DotFolioCore
import DotFolioModels
import SwiftData
import SwiftUI

// MARK: - Service icons

extension ServiceType {
    /// SF Symbol for this service.
    var symbol: String {
        switch self {
        case .firebase: "flame"
        case .supabase: "bolt"
        case .stripe: "creditcard"
        case .aws: "cloud"
        case .googleCloud: "cloud.sun"
        case .googleMaps: "map"
        case .vercel: "triangle"
        case .custom: "square.stack.3d.up"
        }
    }

    /// Symbol for any service name, custom ones included.
    static func symbol(for name: String) -> String {
        ServiceType(matching: name)?.symbol ?? ServiceType.custom.symbol
    }

    /// Hue for a provider's icon tile.
    var tint: Color {
        switch self {
        case .firebase: DS.Palette.orange
        case .supabase: DS.Palette.aqua
        case .stripe: DS.Palette.violet
        case .aws: DS.Palette.yellow
        case .googleCloud: DS.Palette.blue
        case .googleMaps: DS.Palette.green
        case .vercel: DS.Palette.neutral
        case .custom: DS.Palette.magenta
        }
    }

    static func tint(for name: String) -> Color {
        (ServiceType(matching: name) ?? .custom).tint
    }
}

extension ServiceCategory {
    var symbol: String {
        switch self {
        case .database: "cylinder.split.1x2"
        case .cache: "bolt.horizontal"
        case .storage: "externaldrive"
        case .auth: "person.badge.key"
        case .payments: "creditcard"
        case .email: "envelope"
        case .analytics: "chart.bar"
        case .monitoring: "waveform.path.ecg"
        case .hosting: "server.rack"
        case .maps: "map"
        case .search: "magnifyingglass"
        case .queue: "tray.2"
        case .ai: "sparkles"
        case .other: "square.dashed"
        }
    }

    static func symbol(for name: String) -> String {
        (ServiceCategory(matching: name) ?? .other).symbol
    }

    /// Grouped hues: data → blue, money → green, identity & AI → violet,
    /// comms → magenta, observability → orange, infrastructure → aqua.
    var tint: Color {
        switch self {
        case .database, .cache, .storage, .search, .queue: DS.Palette.blue
        case .payments: DS.Palette.green
        case .auth, .ai: DS.Palette.violet
        case .email: DS.Palette.magenta
        case .analytics, .monitoring: DS.Palette.orange
        case .hosting, .maps: DS.Palette.aqua
        case .other: DS.Palette.neutral
        }
    }

    static func tint(for name: String) -> Color {
        (ServiceCategory(matching: name) ?? .other).tint
    }
}

/// Square tile: the service's icon for single-service accounts, a person for
/// accounts used on several services.
/// An account is a login, not a provider (one login serves many), so its
/// tile is always the person symbol.
struct AccountTile: View {
    let services: [String]
    var size: CGFloat = 28

    var body: some View {
        TintedIcon(symbol: "person.crop.circle", tint: DS.Palette.violet, size: size)
    }
}

extension Account {
    /// "1 project · 6 keys" — no provider names: one login serves many.
    /// Keys include Library keys, so they can outnumber the projects' ones.
    var usageSummary: String {
        let linked = allLinkedVariables
        let projects = Set(linked.compactMap { $0.project?.persistentModelID }).count
        return "\(projects) \(projects == 1 ? "project" : "projects") · \(linked.count) \(linked.count == 1 ? "key" : "keys")"
    }
}

// MARK: - List (left column)

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

// MARK: - Detail (right column)

/// One account: login details, its services (each with its projects and
/// Open console), and the projects / variables that use it.
struct AccountDetailView: View {
    let account: Account
    let onOpenProject: (Project) -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @State private var draft: AccountDraft
    @State private var error: String?
    /// "Used by" sections that are open (project IDs, or `libraryID`).
    /// Collapsed by default, unless there is a single section.
    @State private var expanded: Set<String> = []
    private static let libraryID = "library"

    init(account: Account, onOpenProject: @escaping (Project) -> Void, onDelete: @escaping () -> Void) {
        self.account = account
        self.onOpenProject = onOpenProject
        self.onDelete = onDelete
        _draft = State(initialValue: AccountDraft(account))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                AccountFields(draft: $draft)
                if draft != AccountDraft(account) || error != nil {
                    HStack {
                        if let error { Text(error).font(.callout).foregroundStyle(DS.Status.danger) }
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
                ServicesSection(account: account)
                Divider()
                usedBy
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Services can also change from elsewhere (e.g. adding a project here
        // or typing a service in a variable); keep the draft's list in sync.
        .onChange(of: account.services) { _, services in draft.services = services }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            AccountTile(services: account.services, size: 52)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(account.login).font(DS.Font.pageTitle).textSelection(.enabled).lineLimit(2)
                Text(account.displayName.isEmpty ? account.usageSummary : "\(account.displayName) · \(account.usageSummary)")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(DS.Status.danger)
            }
            .buttonStyle(.bordered)
            .tint(DS.Status.danger)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .help("Delete account…")
            .accessibilityLabel("Delete account")
            .clickableCursor()
        }
    }

    /// Every key that uses this login, as the same editable table as a
    /// project's: one collapsible section per project (a table per
    /// environment), then the Library keys.
    private var usedBy: some View {
        let keys = AccountKeys(account: account)
        let sectionIDs = keys.projects.map { Self.sectionID($0.project) } + (keys.library.isEmpty ? [] : [Self.libraryID])
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Used by").font(DS.Font.sectionTitle)
                if !keys.isEmpty {
                    Text("\(keys.count) \(keys.count == 1 ? "key" : "keys")").foregroundStyle(.secondary)
                }
                Spacer()
                if sectionIDs.count > 1 {
                    let allOpen = sectionIDs.allSatisfy(expanded.contains)
                    Button(allOpen ? "Collapse All" : "Expand All") {
                        withAnimation(.smooth(duration: 0.2)) { expanded = allOpen ? [] : Set(sectionIDs) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .clickableCursor()
                }
            }
            if keys.isEmpty {
                Text("No keys use this account yet. Set it in a key’s Account column.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: DS.Space.s) {
                    ForEach(keys.projects) { group in
                        AccountKeysSection(
                            title: group.project.name,
                            count: group.count,
                            icon: AnyView(ProjectTile(project: group.project, size: 28)),
                            isExpanded: binding(for: Self.sectionID(group.project), single: sectionIDs.count == 1),
                            onOpen: { onOpenProject(group.project) }
                        ) {
                            ForEach(group.environments) { env in
                                VStack(alignment: .leading, spacing: DS.Space.xs) {
                                    EnvLabel(name: env.environment.name).font(DS.Font.panelTitle)
                                    AccountKeysTable(keys: env.keys)
                                }
                            }
                        }
                    }
                    if !keys.library.isEmpty {
                        AccountKeysSection(
                            title: "Library",
                            count: keys.library.count,
                            icon: AnyView(TintedIcon(symbol: "books.vertical", tint: DS.Palette.violet, size: 28)),
                            isExpanded: binding(for: Self.libraryID, single: sectionIDs.count == 1),
                            onOpen: nil
                        ) {
                            AccountKeysTable(keys: keys.library)
                        }
                    }
                }
            }
        }
    }

    private static func sectionID(_ project: Project) -> String { "\(project.persistentModelID.hashValue)" }

    private func binding(for id: String, single: Bool) -> Binding<Bool> {
        Binding(
            get: { single || expanded.contains(id) },
            set: { open in
                withAnimation(.smooth(duration: 0.2)) {
                    if open { expanded.insert(id) } else { expanded.remove(id) }
                }
            }
        )
    }

    private func save() {
        do {
            try AccountEditor.update(account, services: draft.services, login: draft.login,
                                     displayName: draft.displayName, notes: draft.notes, context: context)
            draft = AccountDraft(account)
            error = nil
            navigation.show(.success("Account saved", "\(account.login) was updated."))
        } catch {
            self.error = error.message
            navigation.show(.failed("Couldn’t save the account", error.message))
        }
    }
}

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

// MARK: - Services and their projects

/// One block per service of the account, each listing its projects
/// (e.g. Firebase project IDs) with Open console.
private struct ServicesSection: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Projects by provider").font(DS.Font.sectionTitle)
            Text("The projects inside each provider — e.g. a Firebase project ID. Open the console straight from here.")
                .font(.callout).foregroundStyle(.secondary)

            if account.services.isEmpty {
                Text("Add a provider above to list its projects.")
                    .foregroundStyle(.secondary)
            }
            ForEach(account.services, id: \.self) { service in
                ServiceProjectsBlock(account: account, service: service)
            }
        }
    }
}

private struct ServiceProjectsBlock: View {
    let account: Account
    let service: String
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation

    @State private var newName = ""
    @State private var newID = ""
    @State private var newURL = ""
    @State private var error: String?

    /// Projects of this service. Projects created before services were
    /// tracked (no service set) are shown under the account's first service.
    private var items: [ServiceProject] {
        let isFirst = account.services.first == service
        return (account.serviceProjects ?? [])
            .filter { $0.serviceName.caseInsensitiveCompare(service) == .orderedSame || ($0.serviceName.isEmpty && isFirst) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label(service, systemImage: ServiceType.symbol(for: service))
                .font(DS.Font.panelTitle)

            ForEach(items) { sp in
                HStack(spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
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
                    Button {
                        let name = sp.name
                        AccountEditor.delete(sp, context: context)
                        navigation.show(.success("Provider project removed", "\(name) was removed from this account."))
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove \(sp.name)")
                        .accessibilityLabel("Remove \(sp.name)")
                        .clickableCursor()
                }
                .padding(DS.Space.s)
                .panel(radius: DS.Radius.medium)
            }

            HStack(alignment: .bottom, spacing: DS.Space.s) {
                LabeledField("Project name", required: true) { TextField("", text: $newName) }
                LabeledField("Project ID") { TextField("", text: $newID).font(.body.monospaced()) }
                LabeledField("Console URL", optional: true) { TextField("", text: $newURL) }
                Button("Add", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .clickableCursor()
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)

            if let error { Text(error).font(.callout).foregroundStyle(DS.Status.danger) }
        }
        .padding(DS.Space.m)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous).strokeBorder(.separator))
    }

    private func add() {
        do {
            try AccountEditor.addServiceProject(to: account, service: service, name: newName, externalID: newID,
                                                consoleURL: newURL, context: context)
            navigation.show(.success("Provider project added", "\(newName.trimmingCharacters(in: .whitespaces)) was added to \(service)."))
            newName = ""; newID = ""; newURL = ""; error = nil
        } catch {
            self.error = error.message
            navigation.show(.failed("Couldn’t add the provider project", error.message))
        }
    }
}

// MARK: - New account (right column)

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

// MARK: - Flow layout

/// Wraps children onto new lines when they don't fit (for chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Used by section

/// Accordion for one project (or the Library) in an account's "Used by":
/// a header row (chevron, tile, name, key count, Open Project) that toggles
/// the editable key tables.
private struct AccountKeysSection<Content: View>: View {
    let title: String
    let count: Int
    let icon: AnyView
    @Binding var isExpanded: Bool
    let onOpen: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.m) { content }
                    .padding(DS.Space.m)
                    .transition(.opacity)
            }
        }
        .panel(radius: DS.Radius.medium, bordered: true)
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 16)
            icon
            Text(title).font(DS.Font.sectionTitle).lineLimit(1)
            Text("\(count) \(count == 1 ? "key" : "keys")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Space.s)
            if let onOpen {
                Button("Open Project", action: onOpen)
                    .buttonStyle(.link)
                    .font(.callout)
                    .opacity(isHovering || isExpanded ? 1 : 0)
                    .clickableCursor()
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .contentShape(Rectangle())
        .background {
            Rectangle().fill(isHovering ? AnyShapeStyle(.quaternary.opacity(DS.Fill.control)) : AnyShapeStyle(Color.clear))
        }
        .onTapGesture { isExpanded.toggle() }
        .onHover { isHovering = $0 }
        .clickableCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAction { isExpanded.toggle() }
    }
}

/// The shared editable `VariableTable` for a set of keys, with a footer for
/// deleting the selection and showing errors.
private struct AccountKeysTable: View {
    let keys: [Variable]

    @State private var selection: Set<Variable.ID> = []
    @State private var pendingDeletion: [Variable] = []
    @State private var errorMessage: String?
    @State private var showsValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Spacer()
                ShowValuesButton(isOn: $showsValues, isEnabled: keys.contains(where: \.hasValue))
            }
            VariableTable(
                variables: keys,
                selection: $selection,
                pendingDeletion: $pendingDeletion,
                errorMessage: $errorMessage,
                showsValues: $showsValues,
                emptyText: "No keys"
            )
            HStack(spacing: DS.Space.s) {
                Button {
                    pendingDeletion = keys.filter { selection.contains($0.id) }
                } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty)
                    .help("Delete selected")
                    .accessibilityLabel("Delete selected keys")
                    .clickableCursor()
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(DS.Status.danger)
                        .lineLimit(2)
                }
            }
        }
    }
}
