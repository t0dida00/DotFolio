import DotFolioCore
import DotFolioModels
import SwiftUI

/// Inline editor for a project's name, description, link and local folder.
struct ProjectInfoEditor: View {
    let project: Project
    let onDone: () -> Void
    @Environment(AppNavigation.self) private var navigation
    @Environment(HealthMonitor.self) private var monitor

    @State private var name: String
    @State private var summary: String
    @State private var link: String
    @State private var production: String
    @State private var error: String?
    @State private var folderPath: String?
    @FocusState private var nameFocused: Bool

    init(project: Project, onDone: @escaping () -> Void) {
        self.project = project
        self.onDone = onDone
        _name = State(initialValue: project.name)
        _summary = State(initialValue: project.summary)
        _link = State(initialValue: project.repoURL?.absoluteString ?? "")
        _production = State(initialValue: project.productionURL?.absoluteString ?? "")
    }

    /// The production field's problem, if any.
    private var productionFailure: ProjectEditor.Failure? {
        do { _ = try ProjectEditor.productionURL(production); return nil } catch { return error }
    }

    private var productionHint: String {
        if let productionFailure { return productionFailure.message }
        return "The live site. Dotfolio checks it every 10 minutes and notifies you when it goes down."
    }

    private var linkIsInvalid: Bool {
        let text = link.trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && InputValidation.webURL(text) == nil
    }

    private var linkHint: String {
        let text = link.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return "A GitHub or GitLab link is recognized as the project’s repo." }
        guard let url = InputValidation.webURL(text) else { return "Enter a web link, e.g. https://github.com/owner/repo" }
        if let repo = RepoLink(url: url) { return "Recognized \(repo.provider.displayName) repo \(repo.fullName)" }
        return "Saved as a plain link (not a repo)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.m) {
                ProjectTile(project: project, size: 52)
                Text("Edit Project").font(DS.Font.pageTitle)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.s, verticalSpacing: DS.Space.s) {
                GridRow {
                    label("Project name", required: true)
                    TextField("", text: $name)
                        .focused($nameFocused)
                        .fieldHint("Shown in the project list and tabs, e.g. My App.")
                }
                GridRow {
                    label("Description", optional: true)
                    TextField("", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                        .fieldHint("A short note about what this project is.")
                }
                GridRow {
                    label("Project link", optional: true)
                    TextField("", text: $link)
                        .fieldHint(linkHint, isError: linkIsInvalid)
                }
                GridRow {
                    label("Production URL", optional: true)
                    TextField("", text: $production)
                        .fieldHint(productionHint, isError: productionFailure != nil)
                }
                GridRow {
                    label("Local folder")
                    HStack(spacing: DS.Space.s) {
                        Text(folderPath ?? "Not set")
                            .foregroundStyle(folderPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folderPath ?? "Where Export saves .env files")
                        Spacer(minLength: 8)
                        Button(folderPath == nil ? "Choose…" : "Change…") {
                            if ProjectFolder.choose(for: project) != nil { refreshFolder() }
                        }
                        if folderPath != nil {
                            Button("Remove") {
                                project.localFolderBookmark = nil
                                refreshFolder()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(DS.Status.danger) }
                Spacer()
                Button("Cancel", action: onDone)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || productionFailure != nil)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.m)
        .panel(radius: DS.Radius.medium, bordered: true)
        .onAppear {
            nameFocused = true
            refreshFolder()
        }
    }

    private func label(_ text: String, required: Bool = false, optional: Bool = false) -> some View {
        Text.fieldTitle(text, required: required, optional: optional)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func refreshFolder() {
        folderPath = ProjectFolder.resolve(project)?.path(percentEncoded: false)
    }

    private func save() {
        do {
            let previousProduction = project.productionURL
            try ProjectEditor.update(project, name: name, summary: summary, link: link, production: production)
            if project.productionURL != previousProduction, project.productionURL != nil {
                monitor.requestNotificationPermission()
                Task { await monitor.check(project) }
            }
            onDone()
            navigation.show(.success("Project saved", "“\(project.name)” was updated."))
        } catch {
            self.error = error.message
            navigation.show(.failed("Couldn’t save the project", error.message))
        }
    }
}
