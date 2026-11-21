import DotFolioCore
import DotFolioModels
import SwiftData
import SwiftUI

/// "Suggest Sources…": Service / Provider guesses for variables that have
/// empty ones, to tick and apply. Uses names and earlier choices only, never
/// values, so no Touch ID. Only empty fields are filled.
struct SuggestSourcesSheet: View {
    /// Variables to look at; nil = every project and the Library.
    var variables: [Variable]? = nil

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var items: [SourceSuggester.Item] = []
    @State private var picked: Set<SourceSuggester.Item.ID> = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                TintedIcon(symbol: "wand.and.stars", tint: DS.Palette.violet, size: 40)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Suggest Sources").font(DS.Font.sheetTitle)
                    Text(summary).foregroundStyle(.secondary)
                }
            }

            if !items.isEmpty {
                ScrollView {
                    table
                }
                .frame(maxHeight: 460)
                .scrollBounceBehavior(.basedOnSize)
            }

            HStack {
                if !items.isEmpty {
                    Button(picked.count == items.count ? "Select None" : "Select All") {
                        picked = picked.count == items.count ? [] : Set(items.map(\.id))
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button(items.isEmpty ? "Done" : "Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                if !items.isEmpty {
                    Button("Apply \(picked.count)", action: apply)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(picked.isEmpty)
                }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.xxl)
        .frame(width: 900)
        .onAppear(perform: load)
    }

    private var summary: String {
        guard loaded else { return "Looking at your variables…" }
        if items.isEmpty { return "Nothing to suggest: every name we recognize already has a Service and Provider." }
        return "\(items.count) \(items.count == 1 ? "variable" : "variables") with an empty Service or Provider. Only empty fields are filled."
    }

    private var table: some View {
        Table(items) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(
                    get: { picked.contains(item.id) },
                    set: { on in if on { picked.insert(item.id) } else { picked.remove(item.id) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .clickableCursor()
            }
            .width(20)
            TableColumn("Where") { item in
                Text(item.place).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 120, ideal: TextWidth.fit(items.map(\.place) + ["Where"], extra: 16, min: 120, max: 220))
            TableColumn("Name") { item in
                Text(item.key).monospaced().lineLimit(1)
            }
            .width(min: 140, ideal: TextWidth.fit(items.map(\.key) + ["Name"], monospaced: true, extra: 16, min: 140, max: 260))
            TableColumn("Service") { item in
                Text(item.service ?? "—").foregroundStyle(item.service == nil ? .tertiary : .primary)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Provider") { item in
                Text(item.provider ?? "—").foregroundStyle(item.provider == nil ? .tertiary : .primary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Why") { item in
                Text(item.reason).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .help(item.reason)
            }
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: DS.Table.height(rows: items.count))
    }

    private func load() {
        items = variables.map { SourceSuggester.review($0, context: context) } ?? SourceSuggester.reviewAll(context: context)
        picked = Set(items.map(\.id))
        loaded = true
    }

    private func apply() {
        let chosen = items.filter { picked.contains($0.id) }
        SourceSuggester.apply(chosen, context: context)
        try? context.save()
        dismiss()
        navigation.show(.success("Sources filled",
                                 "Service and Provider were filled for \(chosen.count) \(chosen.count == 1 ? "variable" : "variables").",
                                 groups: [.init(title: "Filled", names: chosen.map(\.key))]))
    }
}
