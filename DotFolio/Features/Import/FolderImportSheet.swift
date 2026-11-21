import AppKit
import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// A project folder the user dropped or chose, waiting for the import sheet.
struct PendingFolder: Identifiable {
    let id = UUID()
    let url: URL
}

/// "Import shop": the `.env*` files found in a dropped project folder, to tick
/// and send to an environment. Creates the project (or adds to the one already
/// linked to the folder) and remembers the folder as its Local folder.
/// SECURITY: values are read into memory only to be written to the Keychain.
struct FolderImportSheet: View {
    let folder: URL

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigation.self) private var navigation
    @Query private var projects: [Project]

    /// Where a file's lines go.
    enum Target: Hashable {
        case environment(String)
        /// Names only, in every environment (`.env.example`).
        case namesOnly
    }

    struct Row: Identifiable {
        let id = UUID()
        let path: String
        let kind: EnvFileKind
        let entries: [EnvEntry]
        /// Why the file can't be imported (too large, not text).
        let error: String?
        var isIncluded: Bool
        var target: Target
    }

    @State private var rows: [Row] = []
    @State private var name = ""
    @State private var repoURL: URL?
    @State private var existing: Project?
    /// Add to `existing` (true) or create a new project.
    @State private var addsToExisting = true
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            header

            if loaded {
                if let existing {
                    existingChoice(existing)
                }
                if existing == nil || !addsToExisting {
                    LabeledField("Project name", required: true) {
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }
                        .fieldHint(name.trimmingCharacters(in: .whitespaces).isEmpty
                                   ? "A name is required." : "The project’s name in DOTFOLIO.",
                                   isError: name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if rows.isEmpty {
                    Text("No .env files in this folder or the 3 folders below it.")
                        .foregroundStyle(.secondary)
                        .padding(DS.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                } else {
                    ScrollView { table }
                        .frame(maxHeight: 360)
                        .scrollBounceBehavior(.basedOnSize)
                    notes
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Status.danger)
            }

            footer
        }
        .padding(DS.Space.xxl)
        .frame(width: 820)
        .onAppear(perform: load)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: DS.Space.m) {
            TintedIcon(symbol: "folder", tint: DS.Palette.violet, size: 40)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Import “\(folder.lastPathComponent)”").font(DS.Font.sheetTitle)
                Text(folder.path(percentEncoded: false))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let repoURL {
                    LinkText(url: repoURL, title: RepoLink(url: repoURL)?.fullName)
                }
            }
        }
    }

    private func existingChoice(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("“\(project.name)” is already linked to this folder.", systemImage: "info.circle")
                .font(DS.Font.panelTitle)
            Picker("Import into", selection: $addsToExisting) {
                Text("Add to “\(project.name)”").tag(true)
                Text("New project").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .clickableCursor()
            Text(addsToExisting
                 ? "New names are added and empty values filled in. Nothing already there is changed."
                 : "A separate project is created from the files below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var table: some View {
        Table($rows) {
            TableColumn("") { $row in
                Toggle("", isOn: $row.isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(row.error != nil)
                    .clickableCursor()
            }
            .width(20)
            TableColumn("File") { $row in
                Text(row.path)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(row.isIncluded ? .primary : .secondary)
                    .help(row.path)
            }
            .width(min: 160, ideal: TextWidth.fit(rows.map(\.path) + ["File"], monospaced: true, extra: 16, min: 160, max: 320))
            TableColumn("Variables") { $row in
                if let error = row.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Status.warning)
                        .lineLimit(1)
                } else {
                    Text(countText(row))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Import into") { $row in
                Picker("Import into", selection: $row.target) {
                    ForEach(ProjectEnvironment.defaultNames, id: \.self) { env in
                        EnvLabel(name: env).tag(Target.environment(env))
                    }
                    Divider()
                    Text("Names only, every environment").tag(Target.namesOnly)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(row.error != nil || !row.isIncluded)
                .clickableCursor()
            }
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: DS.Table.height(rows: rows.count))
    }

    @ViewBuilder
    private var notes: some View {
        let merged = self.merged
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Values go to your Keychain. When two files set the same name for one environment, the lower one in the list wins, like .env.local over .env. Example files bring names only.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !merged.conflicts.isEmpty {
                let shown = merged.conflicts.prefix(3).map { "\($0.key) (\($0.environment)) from \($0.keptFrom)" }
                Label("Set twice, keeping: " + shown.joined(separator: ", ") + (merged.conflicts.count > 3 ? "…" : ""),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(DS.Status.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(primaryTitle, action: importNow)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .clickableCursor()
    }

    // MARK: State

    private var included: [Row] { rows.filter { $0.isIncluded && $0.error == nil } }

    private var merged: FolderImport.Merged {
        FolderImport.merge(included.map { row in
            switch row.target {
            case .environment(let env): FolderImport.Source(relativePath: row.path, entries: row.entries, environment: env)
            case .namesOnly: FolderImport.Source(relativePath: row.path, entries: row.entries, environment: nil)
            }
        })
    }

    private var isAdding: Bool { existing != nil && addsToExisting }

    private var primaryTitle: String {
        if isAdding, let existing { return "Add to “\(existing.name)”" }
        return "Create Project"
    }

    private var canImport: Bool {
        guard loaded else { return false }
        if isAdding { return !included.isEmpty }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func countText(_ row: Row) -> String {
        let n = row.entries.count
        if row.target == .namesOnly { return n == 1 ? "1 name" : "\(n) names" }
        return n == 1 ? "1 variable" : "\(n) variables"
    }

    // MARK: Loading

    private func load() {
        guard !loaded else { return }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }

        name = folder.lastPathComponent
        repoURL = EnvFolderScan.repoWebURL(in: folder)
        rows = EnvFolderScan.scan(folder).map(Self.row)
        // Example files only count when there is nothing better.
        let hasRealFiles = rows.contains { $0.kind != .template && $0.error == nil }
        for i in rows.indices where rows[i].kind == .template {
            rows[i].isIncluded = !hasRealFiles && rows[i].error == nil
        }
        existing = matchingProject()
        loaded = true
    }

    private static func row(_ found: EnvFolderScan.Found) -> Row {
        let kind = EnvFileImport.kind(forFileName: found.fileName)
        let target: Target = switch kind {
        case .environment(let env): .environment(env)
        case .template: .namesOnly
        case .unknown: .environment("development")
        }
        do {
            let data = try Data(contentsOf: found.url)
            let entries = try EnvFileImport.entries(from: data)
            // Unknown names (.env.test) are listed but left unticked.
            return Row(path: found.relativePath, kind: kind, entries: entries, error: nil,
                       isIncluded: kind != .unknown && !entries.isEmpty, target: target)
        } catch EnvFileImport.Failure.tooLarge {
            return Row(path: found.relativePath, kind: kind, entries: [], error: "Too large", isIncluded: false, target: target)
        } catch {
            return Row(path: found.relativePath, kind: kind, entries: [], error: "Not a text file", isIncluded: false, target: target)
        }
    }

    /// The project already linked to this folder, or imported from its repo.
    private func matchingProject() -> Project? {
        let path = folder.standardizedFileURL.path(percentEncoded: false)
        if let byFolder = projects.first(where: {
            ProjectFolder.resolve($0)?.standardizedFileURL.path(percentEncoded: false) == path
        }) {
            return byFolder
        }
        guard let repo = repoURL.flatMap(RepoLink.init(url:)) else { return nil }
        return projects.first {
            $0.provider == repo.provider && $0.repoFullName.lowercased() == repo.fullName.lowercased()
        }
    }

    // MARK: Import

    private func importNow() {
        errorMessage = nil
        let merged = self.merged
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        do {
            let project: Project
            var report: ResultReport
            if isAdding, let existing {
                let result = try FolderImport.add(merged, to: existing, context: context, secrets: secrets)
                project = existing
                report = result.changedNothing
                    ? .nothing("Nothing new to import", "Everything in these files is already in “\(existing.name)”.")
                    : .success("Imported into “\(existing.name)”",
                               "Added \(result.added), filled \(result.filled) empty ones. Nothing already there was changed.",
                               groups: [.init(title: "Added", names: result.addedKeys), .init(title: "Filled in", names: result.filledKeys)]
                                   .filter { !$0.names.isEmpty })
            } else {
                project = try FolderImport.createProject(name: name, link: repoURL, merged: merged, folderBookmark: bookmark,
                                                         context: context, secrets: secrets)
                report = .success("Project imported",
                                  "“\(project.name)” was created from \(included.count) \(included.count == 1 ? "file" : "files") with \(merged.nameCount) variables. Values are in your Keychain.",
                                  groups: [.init(title: "Files", names: included.map(\.path))])
            }
            if let bookmark { project.localFolderBookmark = bookmark }
            try context.save()
            navigation.projectToOpen = project.id
            dismiss()
            navigation.show(report)
        } catch ProjectCreator.Failure.keychain {
            errorMessage = "Values couldn’t be saved to your Keychain. Nothing was created."
        } catch let failure as VariableEditor.Failure {
            errorMessage = failure.message
        } catch {
            errorMessage = "The project couldn’t be saved."
        }
    }
}
