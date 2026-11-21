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

// MARK: - Left column

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

// MARK: - Right column

/// Library keys in collapsible provider sections, with the Add key card
/// pinned at the bottom.
struct LibraryView: View {
    let groups: [LibraryGroup]
    let total: Int
    /// Bumped by the left column's "New Key" button to focus the add card.
    let focusRequest: Int
    /// The left column's filter: "all", "library" or an environment name.
    let scope: String

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets

    @State private var expanded: Set<String> = []
    /// A lone provider starts open; this remembers that it was closed.
    @State private var collapsedSingles: Set<String> = []
    @FocusState private var addNameFocused: Bool
    @State private var dropTargeted = false

    /// "12 keys across 4 providers · 9 from projects" (of the groups shown).
    private var librarySummary: String {
        let shown = groups.flatMap(\.keys)
        let fromProjects = shown.filter { !$0.inLibrary }.count
        var text = "\(total) \(total == 1 ? "key" : "keys") across \(groups.count) \(groups.count == 1 ? "provider" : "providers")"
        if fromProjects > 0 { text += " · \(fromProjects) from projects" }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Library").font(DS.Font.pageTitle)
                            Text(total == 0
                                 ? "Keys you reuse across projects — a personal OpenAI key, a Stripe test key. Not tied to any project."
                                 : librarySummary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            open(EnvFilePicker.choose(message: "Choose .env files. A comment like #Service/Provider/Account/Link after a value says where the key belongs; keys without a provider go to Other."))
                        } label: {
                            Label("Import .env…", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .symbolMotion(.bounceDown)
                        .clickableCursor()
                        .help("Add the keys of .env files to the Library — or drop the files here")
                    }

                    if groups.isEmpty {
                        if scope != "all" {
                            ContentUnavailableView("No keys here", systemImage: "line.3.horizontal.decrease.circle",
                                                   description: Text(scope == "library"
                                                                     ? "The Library has no keys of its own yet."
                                                                     : "No project has variables in \(scope)."))
                        } else if total > 0 {
                            ContentUnavailableView.search
                        }
                    }

                    VStack(spacing: DS.Space.s) {
                        ForEach(groups) { group in
                            LibrarySection(
                                group: group,
                                isExpanded: Binding(
                                    get: { groups.count == 1 ? !collapsedSingles.contains(group.id) : expanded.contains(group.id) },
                                    set: { open in
                                        withAnimation(.smooth(duration: 0.2)) {
                                            if groups.count == 1 {
                                                if open { collapsedSingles.remove(group.id) } else { collapsedSingles.insert(group.id) }
                                            } else {
                                                if open { expanded.insert(group.id) } else { expanded.remove(group.id) }
                                            }
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)

            AddVariableCard(target: .library, nameFocused: $addNameFocused, onDropFiles: { open($0) })
                .padding(.horizontal, DS.Space.xl)
                .padding(.vertical, DS.Space.m)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
        }
        .onChange(of: focusRequest) { _, _ in addNameFocused = true }

        .dropDestination(for: URL.self) { urls, _ in
            open(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
                    .overlay { Label("Drop .env files to add them to the Library", systemImage: "square.and.arrow.down").font(DS.Font.sectionTitle) }
                    .padding(DS.Space.s)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Reads the files and adds every key straight away: each line's
    /// `#Service/Provider/Account/Link` comment says where it goes.
    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let names = urls.map(\.lastPathComponent)
        do {
            let files = try EnvFilePicker.read(urls)
            let entries = Self.merged(files)
            guard !entries.isEmpty else {
                navigation.show(.nothing("No variables found", "\(names.joined(separator: ", ")) has no KEY=value lines."))
                return
            }
            let result = try LibraryImporter.importKeys(entries, context: context, secrets: secrets)
            navigation.show(.library(added: result.added, skipped: result.skipped, invalidLinks: result.invalidLinks, files: names))
        } catch let failure as VariableEditor.Failure {
            navigation.show(.failure("Nothing was imported. \(failure.message)"))
        } catch {
            navigation.show(.failure(error.localizedDescription))
        }
    }

    /// One list from all files: a name appears once; real values win over
    /// template placeholders (`.env.example` brings names and comments only),
    /// and a later file wins over an earlier one.
    static func merged(_ files: [EnvFilePicker.File]) -> [EnvEntry] {
        var order: [String] = []
        var byKey: [String: EnvEntry] = [:]
        for file in files.sorted(by: { ($0.kind == .template ? 0 : 1) < ($1.kind == .template ? 0 : 1) }) {
            for var entry in file.entries {
                if file.kind == .template { entry.value = "" }
                if byKey[entry.key] == nil { order.append(entry.key) }
                byKey[entry.key] = entry
            }
        }
        return order.compactMap { byKey[$0] }
    }
}

/// One provider: header (chevron, provider tile, name, count) and its keys.
private struct LibrarySection: View {
    let group: LibraryGroup
    @Binding var isExpanded: Bool

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selection: Set<Variable.ID> = []
    @State private var pendingDeletion: [Variable] = []
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var hovering = false
    @State private var showsValues = false
    /// The Edit switch: off = read-only (double-click a row copies it).
    @State private var editUnlocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    VariableTable(
                        variables: group.keys,
                        selection: $selection,
                        pendingDeletion: $pendingDeletion,
                        errorMessage: $errorMessage,
                        showsValues: $showsValues,
                        isEditable: editUnlocked,
                        showsOrigin: true,
                        emptyText: "No keys",
                        extraMenu: { v in AnyView(addToProjectMenu(v)) }
                    )
                    footer
                }
                .padding(DS.Space.m)
                .transition(.opacity)
            }
        }
        .panel(radius: DS.Radius.medium, bordered: true)
        // Collapsing or the session locking puts the table back to read-only.
        .onChange(of: isExpanded) { _, open in if !open { editUnlocked = false } }
        .onChange(of: session.isUnlocked) { _, unlocked in if !unlocked { editUnlocked = false } }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 16)
            TintedIcon(symbol: ServiceType.symbol(for: group.provider),
                       tint: group.provider.isEmpty ? DS.Palette.neutral : ServiceType.tint(for: group.provider), size: 28)
            Text(group.title).font(DS.Font.sectionTitle)
            Text("\(group.keys.count) \(group.keys.count == 1 ? "key" : "keys")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if isExpanded {
                ShowValuesButton(isOn: $showsValues, isEnabled: group.keys.contains(where: \.hasValue))
                EditSwitch(isOn: $editUnlocked)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .contentShape(Rectangle())
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(DS.Fill.control)) : AnyShapeStyle(Color.clear))
        .onHover { hovering = $0 }
        .onTapGesture { isExpanded.toggle() }
        .clickableCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAction { isExpanded.toggle() }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                pendingDeletion = group.keys.filter { selection.contains($0.id) }
            } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty || !editUnlocked)
                .help(editUnlocked ? "Delete selected" : "Turn on Edit to delete keys")
                .accessibilityLabel("Delete selected keys")
                .clickableCursor()
            Spacer()
            Text(errorMessage ?? notice ?? (editUnlocked
                ? "Right-click a key to add it to a project"
                : "Double-click a key to copy it as a .env line · right-click to add it to a project · turn on Edit to change it"))
                .font(.caption)
                .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
                .lineLimit(2)
        }
    }

    /// Add to Project ▸ project ▸ environment ▸ name only / name and value.
    @ViewBuilder
    private func addToProjectMenu(_ key: Variable) -> some View {
        Menu("Add to Project") {
            if projects.isEmpty {
                Text("No projects yet")
            }
            ForEach(projects) { project in
                Menu(project.name) {
                    ForEach(project.sortedEnvironments) { env in
                        Menu(env.name) {
                            Button("Name Only") { add(key, to: env, includeValue: false) }
                            Button("Name and Value (Touch ID)") { add(key, to: env, includeValue: true) }
                                .disabled(!key.hasValue)
                        }
                    }
                }
            }
        }
    }

    private func add(_ key: Variable, to env: ProjectEnvironment, includeValue: Bool) {
        Task {
            do {
                var auth: LAContext?
                if includeValue && key.hasValue {
                    auth = try await session.authenticatedContext(reason: "add \(key.key) to \(env.project?.name ?? "the project")")
                }
                let result = try VariableCopier.copy([key], to: env, includeValues: includeValue,
                                                     context: context, secrets: secrets, authContext: auth)
                errorMessage = nil
                let place = "\(env.project?.name ?? "") · \(env.name)"
                notice = result.copied == 1 ? "Added \(key.key) to \(place)." : "\(key.key) already exists in \(place) — skipped."
                navigation.show(result.copied == 1
                    ? .success("Added to project", "\(key.key) was added to \(place)" + (includeValue ? " with its value." : ", name only."))
                    : .nothing("Already there", "\(key.key) already exists in \(place). It was left as it was."))
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                // Prompt dismissed.
            } catch {
                errorMessage = (error as? KeychainError)?.userMessage ?? error.localizedDescription
            }
        }
    }
}
