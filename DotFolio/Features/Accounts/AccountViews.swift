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
}

/// Square tile: the service's icon for single-service accounts, a person for
/// accounts used on several services.
struct AccountTile: View {
    let services: [String]
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: services.count == 1 ? ServiceType.symbol(for: services[0]) : "person.crop.circle")
            .font(.system(size: size * 0.42))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - List (left column)

/// Accounts filtered by the toolbar search (login, name, services, service projects).
struct AccountList: View {
    let accounts: [Account]
    let query: String
    @Binding var selection: PersistentIdentifier?
    let onDelete: (Account) -> Void

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
            List(selection: $selection) {
                ForEach(rows) { account in
                    HStack(spacing: 10) {
                        AccountTile(services: account.services)
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
        return "\(account.serviceSummary) · \(projects) \(projects == 1 ? "project" : "projects")"
    }
}

// MARK: - Detail (right column)

/// One account: login details, its services (each with its projects and
/// Open console), and the projects / variables that use it.
struct AccountDetailView: View {
    let account: Account
    let onOpenProject: (Project) -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var draft: AccountDraft
    @State private var error: String?
    /// Projects whose "Used by" section is open. Collapsed by default, unless
    /// the account is used by a single project.
    @State private var expandedProjects: Set<PersistentIdentifier> = []

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
                ServicesSection(account: account)
                Divider()
                usedBy
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Services can also change from elsewhere (e.g. adding a project here
        // or typing a service in a variable); keep the draft's list in sync.
        .onChange(of: account.services) { _, services in draft.services = services }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AccountTile(services: account.services, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.login).font(.title2.weight(.semibold)).textSelection(.enabled).lineLimit(2)
                Text(account.displayName.isEmpty ? account.serviceSummary : "\(account.displayName) · \(account.serviceSummary)")
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

    /// One collapsible section per project that uses this account. Each
    /// section lists #, Service, Provider, Link — one row per distinct
    /// (service, provider, console link) among that project's variables.
    private var usedBy: some View {
        VStack(alignment: .leading, spacing: 10) {
            let groups = usedByGroups
            HStack(alignment: .firstTextBaseline) {
                Text("Used by").font(.headline)
                if groups.count > 1 {
                    Text("\(groups.count) projects").foregroundStyle(.secondary)
                    Spacer()
                    let allOpen = groups.allSatisfy { expandedProjects.contains($0.id) }
                    Button(allOpen ? "Collapse All" : "Expand All") {
                        withAnimation(.smooth(duration: 0.2)) {
                            expandedProjects = allOpen ? [] : Set(groups.map(\.id))
                        }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .clickableCursor()
                }
            }
            if groups.isEmpty {
                Text("No variables use this account yet. Set it in a variable’s Account column.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        UsedBySection(
                            group: group,
                            isExpanded: Binding(
                                get: { expandedProjects.contains(group.id) },
                                set: { open in
                                    withAnimation(.smooth(duration: 0.2)) {
                                        if open { expandedProjects.insert(group.id) } else { expandedProjects.remove(group.id) }
                                    }
                                }
                            ),
                            onOpenProject: onOpenProject
                        )
                    }
                }
                Text("Click a project to show its services. Double-click a row to open the project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let groups = usedByGroups
            if groups.count == 1 { expandedProjects = [groups[0].id] }
        }
    }

    fileprivate struct UsedByRow: Identifiable {
        let index: Int
        let service: String
        let provider: String
        let link: URL?
        let keys: [String]
        var id: String { "\(service)|\(provider)|\(link?.absoluteString ?? "")" }
    }

    fileprivate struct UsedByGroup: Identifiable {
        let project: Project
        let rows: [UsedByRow]
        var id: PersistentIdentifier { project.persistentModelID }
    }

    /// Projects in name order; rows in the order their variables were found.
    private var usedByGroups: [UsedByGroup] {
        let variables = account.allLinkedVariables.sorted {
            ($0.project?.name ?? "").localizedStandardCompare($1.project?.name ?? "") == .orderedAscending
        }
        var projectOrder: [PersistentIdentifier] = []
        var projects: [PersistentIdentifier: Project] = [:]
        var rowOrder: [PersistentIdentifier: [String]] = [:]
        var rows: [PersistentIdentifier: [String: (service: String, provider: String, link: URL?, keys: [String])]] = [:]
        for v in variables {
            guard let project = v.project else { continue }
            let pid = project.persistentModelID
            if projects[pid] == nil {
                projects[pid] = project
                projectOrder.append(pid)
            }
            let link = v.sourceURL ?? v.serviceProject?.resolvedConsoleURL
            let key = "\(v.displayCategory.lowercased())|\(v.displayService.lowercased())|\(link?.absoluteString ?? "")"
            if rows[pid, default: [:]][key] == nil {
                rows[pid, default: [:]][key] = (v.displayCategory, v.displayService, link, [])
                rowOrder[pid, default: []].append(key)
            }
            rows[pid]![key]!.keys.append("\(v.key) (\(v.environment?.name ?? "?"))")
        }
        return projectOrder.map { pid in
            let groupRows = (rowOrder[pid] ?? []).enumerated().map { index, key in
                let r = rows[pid]![key]!
                return UsedByRow(index: index + 1, service: r.service, provider: r.provider, link: r.link, keys: r.keys)
            }
            return UsedByGroup(project: projects[pid]!, rows: groupRows)
        }
    }

    private func save() {
        do {
            try AccountEditor.update(account, services: draft.services, login: draft.login,
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
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                label("Login")
                TextField("", text: $draft.login, prompt: Text("email or username"))
            }
            GridRow {
                label("Display name")
                TextField("", text: $draft.displayName, prompt: Text("e.g. Work, Personal, Client X (optional)"))
            }
            GridRow {
                label("Providers")
                ServiceChips(services: $draft.services)
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
        FlowLayout(spacing: 6) {
            ForEach(services, id: \.self) { service in
                HStack(spacing: 5) {
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
                TextField("", text: $customName, prompt: Text("Provider name"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
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
                    HStack(spacing: 5) {
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Projects by provider").font(.headline)
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
        VStack(alignment: .leading, spacing: 8) {
            Label(service, systemImage: ServiceType.symbol(for: service))
                .font(.callout.weight(.semibold))

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
                .panel(radius: DS.Radius.medium)
            }

            HStack(spacing: 8) {
                TextField("", text: $newName, prompt: Text("Project name"))
                TextField("", text: $newID, prompt: Text("Project ID"))
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
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous).strokeBorder(.separator))
    }

    private func add() {
        do {
            try AccountEditor.addServiceProject(to: account, service: service, name: newName, externalID: newID,
                                                consoleURL: newURL, context: context)
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
                AccountTile(services: draft.services, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("New Account").font(.title2.weight(.semibold))
                    Text("A login you use with one or more providers — e.g. your Gmail for Firebase, Google Cloud and Maps.")
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
            let account = try AccountEditor.createAccount(services: draft.services, login: draft.login,
                                                          displayName: draft.displayName, notes: draft.notes, context: context)
            onCreated(account)
        } catch {
            self.error = error.message
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

/// Accordion for one project in an account's "Used by": a header row
/// (chevron, project, count) that toggles a table of services.
private struct UsedBySection: View {
    let group: AccountDetailView.UsedByGroup
    @Binding var isExpanded: Bool
    let onOpenProject: (Project) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider()
                table
                    .padding(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 14)
            ProjectTile(provider: group.project.provider, size: 26)
            Text(group.project.name)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(group.rows.count == 1 ? "1 service" : "\(group.rows.count) services")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Open Project") { onOpenProject(group.project) }
                .buttonStyle(.link)
                .font(.callout)
                .opacity(isHovering || isExpanded ? 1 : 0)
                .clickableCursor()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        // An explicit Rectangle: a bare ShapeStyle background takes on the
        // card's rounded corners on macOS 26 and leaves the bottom corners bare.
        .background {
            Rectangle().fill(isHovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.clear))
        }
        .onTapGesture { isExpanded.toggle() }
        .onHover { isHovering = $0 }
        .clickableCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAction { isExpanded.toggle() }
    }

    private var table: some View {
        let rows = group.rows
        return Table(rows) {
            TableColumn("#") { row in
                Text("\(row.index)").monospacedDigit().foregroundStyle(.secondary)
                    .help(row.keys.joined(separator: ", "))
            }
            .width(24)

            TableColumn("Service") { row in
                Text(row.service.isEmpty ? "—" : row.service)
                    .foregroundStyle(row.service.isEmpty ? .tertiary : .primary)
                    .help(row.keys.joined(separator: ", "))
            }
            .width(min: TextWidth.fit(rows.map(\.service) + ["Service"], extra: 20, min: 80, max: 160))

            TableColumn("Provider") { row in
                Text(row.provider.isEmpty ? "—" : row.provider)
                    .foregroundStyle(row.provider.isEmpty ? .tertiary : .primary)
            }
            .width(min: TextWidth.fit(rows.map(\.provider) + ["Provider"], extra: 20, min: 80, max: 180))

            TableColumn("Link") { row in
                if let url = row.link {
                    LinkText(url: url)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: TextWidth.fit(rows.map { $0.link?.absoluteString ?? "" } + ["Link"], extra: 20, min: 90, max: 420))
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        // Tall enough for every row; the column scrolls, not the table.
        .frame(height: DS.Table.height(rows: rows.count))
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .contextMenu(forSelectionType: AccountDetailView.UsedByRow.ID.self) { ids in
            Button("Open \(group.project.name)") { onOpenProject(group.project) }
            if let row = rows.first(where: { ids.contains($0.id) }), let url = row.link {
                Link("Open Console", destination: url)
            }
        } primaryAction: { _ in
            onOpenProject(group.project)
        }
    }
}
