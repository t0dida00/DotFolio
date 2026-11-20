import DotFolioCore
import DotFolioEnv
import DotFolioModels
import SwiftData
import SwiftUI

/// Files picked or dropped on the Library, waiting for a provider.
struct PendingLibraryImport: Identifiable {
    let id = UUID()
    let files: [EnvFilePicker.File]
}

/// "Import to Library": every key of the chosen `.env*` files goes under one
/// provider. Names already there are skipped, never overwritten. Values go
/// straight to the Keychain (all or nothing); templates bring names only.
struct LibraryImportSheet: View {
    let pending: PendingLibraryImport
    /// Called with a one-line summary after a successful import.
    let onImported: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.login) private var accounts: [Account]
    @Query(filter: #Predicate<Variable> { $0.inLibrary }) private var libraryKeys: [Variable]

    @State private var provider = ""
    @State private var category = ""
    @State private var account = ""
    @State private var error: String?
    @FocusState private var providerFocused: Bool

    var body: some View {
        let entries = Self.merged(pending.files)
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                TintedIcon(symbol: "square.and.arrow.down", tint: DS.Palette.violet, size: 36)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Import to Library").font(DS.Font.sheetTitle)
                    Text("\(entries.count) \(entries.count == 1 ? "key" : "keys") from \(pending.files.map(\.name).joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.s, verticalSpacing: DS.Space.s) {
                GridRow {
                    label("Provider")
                    field($provider, help: "Choose a provider", items: providerSuggestions)
                        .focused($providerFocused)
                        .fieldHint("Every imported key goes under this provider, e.g. Stripe.")
                }
                GridRow {
                    label("Service", optional: true)
                    field($category, help: "Choose what these keys are for", items: VariableTable.categorySuggestions)
                }
                GridRow {
                    label("Account", optional: true)
                    field($account, help: "Choose an account", items: accounts.map(\.login))
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(preview(entries))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(4)
                    .textSelection(.enabled)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Status.danger)
            }

            HStack {
                Spacer()
                SheetButtons(
                    confirmTitle: "Import \(entries.count) \(entries.count == 1 ? "Key" : "Keys")",
                    canConfirm: !entries.isEmpty,
                    onCancel: { dismiss() },
                    onConfirm: { importKeys(entries) }
                )
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 520)
        .onAppear { providerFocused = true }
    }

    // MARK: Pieces

    private func label(_ title: String, optional: Bool = false) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(title)
            if optional { Text("(optional)").foregroundStyle(.tertiary) }
        }
        .gridColumnAlignment(.trailing)
    }

    private func field(_ text: Binding<String>, help: String, items: [String]) -> some View {
        HStack(spacing: DS.Space.xs) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
            SuggestionMenu(help: help, items: items) { text.wrappedValue = $0 }
        }
    }

    /// Providers already in the Library first, then common ones.
    private var providerSuggestions: [String] {
        var seen = Set<String>()
        return (libraryKeys.map(\.serviceLabel) + VariableTable.serviceSuggestions)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func preview(_ entries: [EnvEntry]) -> String {
        let names = entries.map(\.key)
        let shown = names.prefix(12).joined(separator: "  ")
        return names.count > 12 ? "\(shown)  +\(names.count - 12) more" : shown
    }

    private var note: String {
        var text = "Values go to your Keychain. Names already under this provider are skipped, never overwritten."
        if pending.files.contains(where: { $0.kind == .template }) {
            text += " Values from example files aren’t imported — they’re placeholders."
        }
        return text
    }

    // MARK: Import

    /// One list from all files: a name appears once; real values win over
    /// template placeholders, and a later file wins over an earlier one.
    static func merged(_ files: [EnvFilePicker.File]) -> [EnvEntry] {
        var order: [String] = []
        var byKey: [String: EnvEntry] = [:]
        for file in files.sorted(by: { ($0.kind == .template ? 0 : 1) < ($1.kind == .template ? 0 : 1) }) {
            for entry in file.entries {
                if byKey[entry.key] == nil { order.append(entry.key) }
                byKey[entry.key] = EnvEntry(key: entry.key, value: file.kind == .template ? "" : entry.value)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    private func importKeys(_ entries: [EnvEntry]) {
        let providerName = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try LibraryImporter.importKeys(entries, provider: providerName, category: category, account: account,
                                                        context: context, secrets: secrets)
            var summary = "Imported \(result.added) \(result.added == 1 ? "key" : "keys") to \(providerName.isEmpty ? "No provider" : providerName)."
            if !result.skipped.isEmpty {
                summary += " Skipped \(result.skipped.count) already there: \(result.skipped.prefix(3).joined(separator: ", "))\(result.skipped.count > 3 ? "…" : "")."
            }
            onImported(summary)
            dismiss()
        } catch {
            self.error = "Nothing was imported. \(error.message)"
        }
    }
}
