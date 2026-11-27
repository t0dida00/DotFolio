import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

// Size note: One form (fields, per-environment draft table, import) whose parts share the draft state, so it stays in one file.

/// "New Project", shown inline in the right panel: name, optional description
/// and link, and a .env table (#, Name, Value, Service, Provider, Account, Link).
struct NewProjectForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    /// Back to the project list (after Create or Cancel).
    let onClose: () -> Void
    @Environment(\.secretStore) private var secrets
    @Environment(HealthMonitor.self) private var health

    @State private var draft = ProjectDraft()
    @State private var selection: Set<EnvDraftRow.ID> = []
    @State private var keychainError: KeychainError?
    @State private var confirmDiscard = false
    /// Result of the last .env import, shown under the table.
    @State private var importNotice: String?
    @State private var importError: String?
    @State private var dropTargeted = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            header
            fields
            envTable
            footer
        }
        .padding(.horizontal, DS.Space.xxl)
        .padding(.top, DS.Space.s)
        .padding(.bottom, DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { nameFocused = true }
        .confirmationDialog("Discard this new project?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive, action: onClose)
        } message: {
            Text("What you entered here will be lost.")
        }
        .alert(
            "Values couldn’t be saved",
            isPresented: Binding(get: { keychainError != nil }, set: { if !$0 { keychainError = nil } }),
            presenting: keychainError
        ) { _ in
            Button("Create Without Values") { save(includeValues: false) }
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text("\(error.userMessage)\n\nYou can still create the project with variable names and links, and add the values later. Nothing was written to the database.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Button(action: cancel) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .symbolMotion(.wiggleBackward)
            .glassEffect(.regular.interactive(), in: .circle)
            .clickableCursor()
            .help("Back to projects")
            .accessibilityLabel("Back to projects")

            Text("New Project").font(DS.Font.pageTitle)
        }
        // The header sits in the title bar row; keep clear of the traffic lights.
        .padding(.leading, HomeView.trafficLightInset - 24)
    }

    // MARK: Fields

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.s, verticalSpacing: DS.Space.s) {
            GridRow {
                fieldLabel("Project name", required: true)
                TextField("", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .fieldHint("Shown in the project list and tabs, e.g. My App.")
            }
            GridRow {
                fieldLabel("Description", optional: true)
                TextField("", text: $draft.summary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .fieldHint("A short note about what this project is.")
            }
            GridRow {
                fieldLabel("Project link", optional: true)
                TextField("", text: $draft.link)
                    .textFieldStyle(.roundedBorder)
                    .fieldHint(linkHint, isError: draft.linkIsInvalid)
            }
            GridRow {
                fieldLabel("Production URL", optional: true)
                TextField("", text: $draft.production)
                    .textFieldStyle(.roundedBorder)
                    .fieldHint(draft.productionIssue?.message
                               ?? "The live site. Dotfolio checks it every 10 minutes and notifies you when it goes down.",
                               isError: draft.productionIssue != nil)
            }
        }
    }

    private func fieldLabel(_ title: String, required: Bool = false, optional: Bool = false) -> some View {
        Text.fieldTitle(title, required: required, optional: optional)
            .gridColumnAlignment(.trailing)
    }

    private var linkHint: String {
        if draft.linkIsInvalid { return "Enter a web link, e.g. https://github.com/owner/repo" }
        if let url = InputValidation.webURL(draft.link), let repo = RepoLink(url: url) {
            return "Recognized \(repo.provider.displayName) repo \(repo.fullName)"
        }
        return "A GitHub or GitLab link is recognized as the project’s repo."
    }

    // MARK: .env table

    private var envTable: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Environment variables").font(DS.Font.panelTitle)
                Spacer()
                Button {
                    importFiles(EnvFilePicker.choose(message: "Choose .env files. .env.production goes to production, .env.staging to staging, .env and .env.local to development. A comment like #Service/Provider/Account/Link after a value fills those columns."))
                } label: {
                    Label("Import .env…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .symbolMotion(.bounceDown)
                .clickableCursor()
                .help("Fill the table from .env files — or drop them on the table")
                EnvironmentPicker(names: ProjectEnvironment.defaultNames, selection: $draft.environmentName)
            }

            Table(draft.rows, selection: $selection) {
                TableColumn("#") { row in
                    Text("\(index(of: row) + 1)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(20)

                TableColumn("Name *") { row in
                    TextField("", text: binding(row.id, \.key))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(draft.keyIssue(for: row) == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.Status.danger))
                        .help(draft.keyIssue(for: row) ?? "")
                }
                .width(min: TextWidth.fit(draft.rows.map(\.key) + ["Name"], monospaced: true, extra: 20, min: 80, max: 260), ideal: TextWidth.fit(draft.rows.map(\.key) + ["Name"], monospaced: true, extra: 20, min: 80, max: 260))

                TableColumn("Value") { row in
                    HStack(spacing: DS.Space.s) {
                        // SECURITY: masked by default; the eye only reveals what
                        // the user just typed (nothing is read from the Keychain).
                        Group {
                            if row.isRevealed {
                                TextField("", text: binding(row.id, \.value))
                            } else {
                                SecureField("", text: binding(row.id, \.value))
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))

                        Button {
                            toggleReveal(row.id)
                        } label: {
                            Image(systemName: row.isRevealed ? "eye.slash" : "eye")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .symbolMotion(.bounce)
                        .foregroundStyle(.secondary)
                        .clickableCursor()
                        .help(row.isRevealed ? "Hide value" : "Show value")
                        .accessibilityLabel(row.isRevealed ? "Hide value" : "Show value")
                        .opacity(row.value.isEmpty ? 0 : 1)
                    }
                }
                .width(min(320, max(140, (draft.rows.filter(\.isRevealed).map { TextWidth.of($0.value, monospaced: true, cached: false) }.max() ?? 0) + 50)))

                TableColumn("Service") { row in
                    TextField("", text: binding(row.id, \.category))
                        .textFieldStyle(.plain)
                }
                .width(min: TextWidth.fit(draft.rows.map(\.category) + ["Service"], extra: 20, min: 100, max: 160), ideal: TextWidth.fit(draft.rows.map(\.category) + ["Service"], extra: 20, min: 100, max: 160))

                TableColumn("Provider") { row in
                    TextField("", text: binding(row.id, \.service))
                        .textFieldStyle(.plain)
                }
                .width(min: TextWidth.fit(draft.rows.map(\.service) + ["Provider"], extra: 20, min: 100, max: 200), ideal: TextWidth.fit(draft.rows.map(\.service) + ["Provider"], extra: 20, min: 100, max: 200))

                TableColumn("Account") { row in
                    TextField("", text: binding(row.id, \.account))
                        .textFieldStyle(.plain)
                }
                .width(min: TextWidth.fit(draft.rows.map(\.account) + ["Account"], extra: 20, min: 130, max: 300), ideal: TextWidth.fit(draft.rows.map(\.account) + ["Account"], extra: 20, min: 130, max: 300))

                TableColumn("Link") { row in
                    TextField("", text: binding(row.id, \.link))
                        .textFieldStyle(.plain)
                        .foregroundStyle(draft.linkIssue(for: row) == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.Status.danger))
                        .help(draft.linkIssue(for: row) ?? "Where to get or manage this value")
                }
                .width(min: TextWidth.fit(draft.rows.map(\.link) + ["Link"], extra: 20, min: 100, max: 360), ideal: TextWidth.fit(draft.rows.map(\.link) + ["Link"], extra: 20, min: 100, max: 360))
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 140, maxHeight: .infinity)
            .onDeleteCommand(perform: deleteSelected)
            .dropDestination(for: URL.self) { urls, _ in
                importFiles(urls)
                return !urls.isEmpty
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                        .overlay { Label("Drop .env files to import", systemImage: "square.and.arrow.down").font(DS.Font.panelTitle) }
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 0) {
                Button(action: addRow) { Image(systemName: "plus").frame(width: 24, height: 20) }
                    .symbolMotion(.bounce)
                    .help("Add variable")
                    .accessibilityLabel("Add variable")
                Button(action: deleteSelected) { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .symbolMotion(.bounce)
                    .disabled(selection.isEmpty)
                    .help("Remove selected")
                    .accessibilityLabel("Remove selected")
                Spacer()
                let problem = issueSummary ?? importError
                Text(problem ?? importNotice ?? "Values are stored in your Mac’s Keychain, never in the database.")
                    .font(.caption)
                    .foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
                    .lineLimit(2)
            }
            .buttonStyle(.borderless)
            .clickableCursor()
        }
    }

    private var issueSummary: String? {
        let issues = draft.filledRows.compactMap { row -> String? in
            if let k = draft.keyIssue(for: row) { return "Row \(index(of: row) + 1): \(k)" }
            if let l = draft.linkIssue(for: row) { return "Row \(index(of: row) + 1): \(l)" }
            return nil
        }
        guard let first = issues.first else {
            let others = draft.otherEnvironmentsWithIssues
            return others.isEmpty ? nil : "Fix the names in \(others.joined(separator: ", ")) before creating."
        }
        return issues.count == 1 ? first : "\(first) (+\(issues.count - 1) more)"
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(environmentSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            SheetButtons(confirmTitle: "Create Project", canConfirm: draft.canCreate, onCancel: cancel, onConfirm: { save(includeValues: true) })
        }
    }

    /// Which environments get variables; all three are always created.
    private var environmentSummary: String {
        let filled = draft.environmentsWithRows.map { "\($0) \(draft.filledRows(in: $0).count)" }
        guard !filled.isEmpty else { return "Also creates staging and production." }
        return "Variables: \(filled.joined(separator: " · ")). All three environments are created."
    }

    // MARK: Actions

    /// Reads the files and fills each environment's table: the file name
    /// picks the environment (.env.production → production); templates and
    /// unrecognized names go to the environment shown, templates without values.
    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let files: [EnvFilePicker.File]
        do { files = try EnvFilePicker.read(urls) } catch {
            importError = error.localizedDescription
            importNotice = nil
            return
        }
        var counts: [String: Int] = [:]
        var kept: [String] = []
        var firstTarget: String?
        for file in files {
            let target: String
            let includeValues: Bool
            switch file.kind {
            case .environment(let name): target = name; includeValues = true
            case .template: target = draft.environmentName; includeValues = false
            case .unknown: target = draft.environmentName; includeValues = true
            }
            let result = draft.importEntries(file.entries, into: target, includeValues: includeValues)
            counts[target, default: 0] += result.added + result.filled
            kept += result.skipped
            if firstTarget == nil { firstTarget = target }
        }
        // Show what was just imported.
        if let firstTarget, counts[draft.environmentName, default: 0] == 0 { draft.environmentName = firstTarget }
        selection.removeAll()
        importError = nil

        let order = ProjectEnvironment.defaultNames
        let parts = counts.sorted { (order.firstIndex(of: $0.key) ?? 9, $0.key) < (order.firstIndex(of: $1.key) ?? 9, $1.key) }
            .map { "\($0.value) to \($0.key)" }
        var notice = parts.isEmpty || counts.values.allSatisfy({ $0 == 0 }) ? "Nothing new to import." : "Imported \(parts.joined(separator: ", "))."
        if !kept.isEmpty {
            notice += " Kept \(kept.count) you already had: \(kept.prefix(3).joined(separator: ", "))\(kept.count > 3 ? "…" : "")."
        }
        importNotice = notice
        let added = counts.values.reduce(0, +)
        navigation.show(added == 0
            ? .nothing("Nothing new to import", notice)
            : .success("Imported .env successfully", notice, groups: kept.isEmpty ? [] : [.init(title: "Already in the table, kept as typed", names: kept)]))
    }

    private func save(includeValues: Bool) {
        guard draft.canCreate else { return }
        do {
            let project = try ProjectCreator.create(draft, includeValues: includeValues, context: context, secrets: secrets)
            let count = Set(project.allVariables.map(\.key)).count
            if project.productionURL != nil {
                health.requestNotificationPermission()
                Task { await health.check(project) }
            }
            onClose()
            navigation.projectToOpen = project.id
            navigation.show(.success("Project created",
                                     "“\(project.name)” was created with \(count) \(count == 1 ? "variable" : "variables")"
                                     + (includeValues ? "; values are in your Keychain." : ", names only.")))
        } catch ProjectCreator.Failure.keychain(let error) {
            keychainError = error
            navigation.show(.failed("Couldn’t create the project", "Values couldn’t be saved to your Keychain, so nothing was created. \(error.userMessage)"))
        } catch {
            keychainError = .unexpectedStatus(-1)
            navigation.show(.failed("Couldn’t create the project", ResultReport.describe(error)))
        }
    }

    /// Asks before throwing away typed input; closes right away otherwise.
    private func cancel() {
        let hasInput = !draft.trimmedName.isEmpty || !draft.summary.isEmpty || !draft.link.isEmpty || !draft.production.isEmpty
            || !draft.environmentsWithRows.isEmpty
        if hasInput { confirmDiscard = true } else { onClose() }
    }

    private func index(of row: EnvDraftRow) -> Int {
        draft.rows.firstIndex { $0.id == row.id } ?? 0
    }

    private func binding(_ id: EnvDraftRow.ID, _ keyPath: WritableKeyPath<EnvDraftRow, String>) -> Binding<String> {
        Binding(
            get: { draft.rows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let i = draft.rows.firstIndex(where: { $0.id == id }) else { return }
                draft.rows[i][keyPath: keyPath] = newValue
                // Spreadsheet feel: typing in the last row adds a fresh empty one.
                if i == draft.rows.count - 1, !draft.rows[i].isBlank { draft.rows.append(EnvDraftRow()) }
            }
        )
    }

    private func toggleReveal(_ id: EnvDraftRow.ID) {
        guard let i = draft.rows.firstIndex(where: { $0.id == id }) else { return }
        draft.rows[i].isRevealed.toggle()
    }

    private func addRow() {
        draft.rows.append(EnvDraftRow())
    }

    private func deleteSelected() {
        draft.rows.removeAll { selection.contains($0.id) }
        selection.removeAll()
        if draft.rows.isEmpty { draft.rows = [EnvDraftRow()] }
    }
}

#Preview {
    NewProjectForm(onClose: {})
        .modelContainer(try! DotFolioSchema.makeContainer(inMemory: true))
}
