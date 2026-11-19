import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// "New Project", shown inline in the right panel: name, optional description
/// and link, and a .env table (#, Name, Value, Service, Provider, Account, Link).
struct NewProjectForm: View {
    @Environment(\.modelContext) private var context
    /// Back to the project list (after Create or Cancel).
    let onClose: () -> Void
    @Environment(\.secretStore) private var secrets

    @State private var draft = ProjectDraft()
    @State private var selection: Set<EnvDraftRow.ID> = []
    @State private var keychainError: KeychainError?
    @State private var confirmDiscard = false
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
                fieldLabel("Project name")
                TextField("", text: $draft.name, prompt: Text("My App"))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }
            GridRow {
                fieldLabel("Description", optional: true)
                TextField("", text: $draft.summary, prompt: Text("What this project is"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }
            GridRow {
                fieldLabel("Project link", optional: true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    // verbatim: a plain Text would render the URL as a blue link.
                    TextField("", text: $draft.link, prompt: Text(verbatim: "https://github.com/owner/repo"))
                        .textFieldStyle(.roundedBorder)
                    Text(linkHint)
                        .font(.caption)
                        .foregroundStyle(draft.linkIsInvalid ? AnyShapeStyle(DS.Status.danger) : AnyShapeStyle(.secondary))
                }
            }
        }
    }

    private func fieldLabel(_ title: String, optional: Bool = false) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(title)
            if optional { Text("(optional)").foregroundStyle(.tertiary) }
        }
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
                EnvironmentPicker(names: ProjectEnvironment.defaultNames, selection: $draft.environmentName)
            }

            Table(draft.rows, selection: $selection) {
                TableColumn("#") { row in
                    Text("\(index(of: row) + 1)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(20)

                TableColumn("Name") { row in
                    TextField("", text: binding(row.id, \.key), prompt: Text("API_KEY"))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(draft.keyIssue(for: row) == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.Status.danger))
                        .help(draft.keyIssue(for: row) ?? "")
                }
                .width(TextWidth.fit(draft.rows.map(\.key) + ["API_KEY"], monospaced: true, extra: 20, min: 80, max: 260))

                TableColumn("Value") { row in
                    HStack(spacing: DS.Space.s) {
                        // SECURITY: masked by default; the eye only reveals what
                        // the user just typed (nothing is read from the Keychain).
                        Group {
                            if row.isRevealed {
                                TextField("", text: binding(row.id, \.value), prompt: Text("value"))
                            } else {
                                SecureField("", text: binding(row.id, \.value), prompt: Text("value"))
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
                    TextField("", text: binding(row.id, \.category), prompt: Text("e.g. Database"))
                        .textFieldStyle(.plain)
                }
                .width(TextWidth.fit(draft.rows.map(\.category) + ["e.g. Database"], extra: 20, min: 100, max: 160))

                TableColumn("Provider") { row in
                    TextField("", text: binding(row.id, \.service), prompt: Text("e.g. Supabase"))
                        .textFieldStyle(.plain)
                }
                .width(TextWidth.fit(draft.rows.map(\.service) + ["e.g. Supabase"], extra: 20, min: 100, max: 200))

                TableColumn("Account") { row in
                    TextField("", text: binding(row.id, \.account), prompt: Text("email or username"))
                        .textFieldStyle(.plain)
                }
                .width(TextWidth.fit(draft.rows.map(\.account) + ["email or username"], extra: 20, min: 130, max: 300))

                TableColumn("Link") { row in
                    TextField("", text: binding(row.id, \.link), prompt: Text(verbatim: "https://…"))
                        .textFieldStyle(.plain)
                        .foregroundStyle(draft.linkIssue(for: row) == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.Status.danger))
                        .help(draft.linkIssue(for: row) ?? "Where to get or manage this value")
                }
                .width(TextWidth.fit(draft.rows.map(\.link) + ["https://…"], extra: 20, min: 100, max: 360))
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 140, maxHeight: .infinity)
            .onDeleteCommand(perform: deleteSelected)

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
                Text(issueSummary ?? "Values are stored in your Mac’s Keychain, never in the database.")
                    .font(.caption)
                    .foregroundStyle(issueSummary == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
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
        guard let first = issues.first else { return nil }
        return issues.count == 1 ? first : "\(first) (+\(issues.count - 1) more)"
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Also creates staging and production.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            SheetButtons(confirmTitle: "Create Project", canConfirm: draft.canCreate, onCancel: cancel, onConfirm: { save(includeValues: true) })
        }
    }

    // MARK: Actions

    private func save(includeValues: Bool) {
        guard draft.canCreate else { return }
        do {
            try ProjectCreator.create(draft, includeValues: includeValues, context: context, secrets: secrets)
            onClose()
        } catch ProjectCreator.Failure.keychain(let error) {
            keychainError = error
        } catch {
            keychainError = .unexpectedStatus(-1)
        }
    }

    /// Asks before throwing away typed input; closes right away otherwise.
    private func cancel() {
        let hasInput = !draft.trimmedName.isEmpty || !draft.summary.isEmpty || !draft.link.isEmpty || !draft.filledRows.isEmpty
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
