import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// "Reload from Folder": reads the local project's `.env*` files again and
/// lists what changed, per environment, for review. New names and changed
/// values or sources are ticked; names no longer in the file are not (delete
/// only what you tick). Values are compared after Touch ID and never shown.
struct FolderReloadSheet: View {
    let project: Project
    let folder: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionLock.self) private var session

    private enum Phase {
        case reading
        case ready(FolderReload.Result)
        case failed(String)
    }
    @State private var phase: Phase = .reading
    /// "env/key" of the removals the user ticked.
    @State private var removals: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                TintedIcon(symbol: "arrow.clockwise", tint: DS.Palette.violet, size: 40)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Reload from “\(folder.lastPathComponent)”").font(DS.Font.sheetTitle)
                    Text(folder.path(percentEncoded: false))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            switch phase {
            case .reading:
                HStack(spacing: DS.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Reading the folder and comparing…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Status.danger)
            case .ready(let result):
                if result.isEmpty {
                    Label(result.checked.isEmpty
                          ? "No .env file for development, staging or production was found in this folder."
                          : "Everything matches the folder (\(result.checked.joined(separator: ", "))).",
                          systemImage: result.checked.isEmpty ? "questionmark.folder" : "checkmark.circle.fill")
                        .foregroundStyle(result.checked.isEmpty ? AnyShapeStyle(DS.Status.warning) : AnyShapeStyle(DS.Status.success))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            ForEach(result.changes, id: \.environment.id) { change in
                                changeSection(change)
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                    .scrollBounceBehavior(.basedOnSize)
                }
                if !result.ignored.isEmpty {
                    Text("Not used: \(result.ignored.joined(separator: ", ")) (examples, or a name Dotfolio can't match to an environment).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                if case .ready(let result) = phase, !result.isEmpty {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Apply Changes") { apply(result) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.xxl)
        .frame(width: 620)
        .task { await load() }
    }

    // MARK: Pieces

    private func changeSection(_ change: FolderReload.Change) -> some View {
        let env = change.environment.name
        let plan = change.plan
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                EnvLabel(name: env).font(DS.Font.panelTitle)
                Text("from \(change.files.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.added, id: \.key) { entry in
                ChangeRow(key: entry.key, symbol: "plus.circle.fill", tint: DS.Status.success, detail: "New")
            }
            ForEach(plan.values.keys.sorted(), id: \.self) { key in
                ChangeRow(key: key, symbol: "pencil.circle.fill", tint: DS.Palette.blue,
                          detail: plan.values[key]?.isEmpty == true ? "Value cleared" : "Value changed")
            }
            ForEach(plan.sources.keys.sorted(), id: \.self) { key in
                let comment = plan.sources[key]?.comment ?? ""
                ChangeRow(key: key, symbol: "tag.circle.fill", tint: DS.Palette.violet,
                          detail: comment.isEmpty ? "Source cleared" : "Source: \(comment)")
            }
            ForEach(plan.removed, id: \.self) { key in
                let id = "\(env)/\(key)"
                Toggle(isOn: Binding(get: { removals.contains(id) },
                                     set: { on in if on { removals.insert(id) } else { removals.remove(id) } })) {
                    HStack(spacing: DS.Space.s) {
                        Text(key).monospaced()
                        Text("Not in the file — tick to delete it here too")
                            .font(.caption)
                            .foregroundStyle(DS.Status.danger)
                    }
                }
                .toggleStyle(.checkbox)
                .clickableCursor()
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: Reading and applying

    private func load() async {
        // Read the files while the sandbox grants access to the folder.
        let files: [FolderReload.File]
        do {
            files = try ProjectFolder.withAccess(to: folder) {
                EnvFolderScan.scan(folder).compactMap { found in
                    guard let data = try? Data(contentsOf: found.url),
                          let entries = try? EnvFileImport.entries(from: data) else { return nil }
                    return FolderReload.File(path: found.relativePath, entries: entries)
                }
            }
        } catch {
            phase = .failed(ResultReport.describe(error))
            return
        }
        // Current values, so an unchanged value isn't reported (one Touch ID).
        var current: [UUID: String] = [:]
        let withValues = project.allVariables.filter(\.hasValue)
        if !withValues.isEmpty {
            do {
                let auth = try await session.authenticatedContext(reason: "compare \(project.name) with its folder")
                for v in withValues {
                    if let plain = try VariableEditor.value(of: v, secrets: secrets, context: auth) { current[v.id] = plain }
                }
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                dismiss()
                return
            } catch {
                phase = .failed(ResultReport.describe(error))
                return
            }
        }
        phase = .ready(FolderReload.compare(project, files: files, currentValues: current))
    }

    private func apply(_ result: FolderReload.Result) {
        var added = 0, changed = 0, removed = 0
        do {
            for change in result.changes {
                let ticked = Set(change.plan.removed.filter { removals.contains("\(change.environment.name)/\($0)") })
                try FolderReload.apply(change, removing: ticked, context: context, secrets: secrets)
                added += change.plan.added.count
                changed += Set(change.plan.values.keys).union(change.plan.sources.keys).count
                removed += ticked.count
            }
            try? context.save()
            dismiss()
            var parts: [String] = []
            if added > 0 { parts.append("added \(added)") }
            if changed > 0 { parts.append("updated \(changed)") }
            if removed > 0 { parts.append("deleted \(removed)") }
            navigation.show(parts.isEmpty
                ? .nothing("Nothing applied", "No change was ticked.")
                : .success("Reloaded from folder", "“\(project.name)”: \(parts.joined(separator: ", ")). Values are in your Keychain."))
        } catch {
            try? context.save()
            phase = .failed((error as? EnvFileEdit.Failure)?.message ?? ResultReport.describe(error))
        }
    }
}

/// One change: the name, an icon with its own color, and what happened.
private struct ChangeRow: View {
    let key: String
    let symbol: String
    let tint: Color
    let detail: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(key).monospaced().lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
