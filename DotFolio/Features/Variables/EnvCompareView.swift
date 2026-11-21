import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

/// Compare: one row per name, one column per environment (Set / Empty /
/// Missing), and a Status. "Compare Values" (Touch ID) adds whether the values
/// are the same — only fingerprints are compared, values are never shown.
struct EnvCompareView: View {
    let project: Project
    /// Double-click a cell: show that name in that environment's table.
    let onOpen: (ProjectEnvironment) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionLock.self) private var session

    enum Filter: String, CaseIterable { case all = "All", missing = "Missing", differs = "Differs", same = "Same" }
    @State private var filter: Filter = .all
    /// Name → verdict, after Compare Values.
    @State private var verdicts: [String: EnvironmentComparison.Verdict] = [:]
    @State private var isComparing = false
    @State private var selection: Set<String> = []

    var body: some View {
        let environments = project.sortedEnvironments
        let rows = EnvironmentComparison.rows(for: project).map { row -> EnvironmentComparison.Row in
            var r = row
            r.verdict = verdicts[row.key]
            return r
        }
        let summary = EnvironmentComparison.summary(rows)
        let shown = rows.filter(matches)

        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.m) {
                EqualSegmentedPicker(options: Filter.allCases.map { ($0.rawValue, $0) }, selection: $filter, controlSize: .small)
                    .frame(width: 320)
                    .accessibilityLabel("Filter")
                Spacer()
                Button {
                    compareValues(rows, environments: environments)
                } label: {
                    Label(verdicts.isEmpty ? "Compare Values" : "Compare Again", systemImage: "equal.circle")
                }
                .buttonBorderShape(.capsule)
                .disabled(isComparing || rows.isEmpty)
                .help("Check with Touch ID whether each name has the same value everywhere. Values are never shown.")
                .clickableCursor()
            }

            Text(summaryText(summary))
                .font(.callout)
                .foregroundStyle(.secondary)

            Table(shown, selection: $selection) {
                TableColumn("Name") { row in
                    Text(row.key).monospaced().lineLimit(1)
                }
                .width(min: 120, ideal: TextWidth.fit(rows.map(\.key) + ["Name"], monospaced: true, extra: 20, min: 120, max: 280))
                TableColumnForEach(environments) { env in
                    TableColumn(env.name) { row in
                        CompareCell(state: row.cells[env.name] ?? .missing)
                    }
                    .width(min: 100, ideal: 120)
                }
                TableColumn("Status") { row in
                    StatusText(row: row)
                }
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .tableRowHover()
            .frame(height: DS.Table.height(rows: shown.count, minimumRows: 2))
            .contextMenu(forSelectionType: String.self) { keys in
                if keys.count == 1, let key = keys.first, let row = rows.first(where: { $0.key == key }) {
                    copyMenu(row, environments: environments)
                }
            } primaryAction: { keys in
                // Double-click: open the first environment that has the name.
                guard let key = keys.first, let row = rows.first(where: { $0.key == key }),
                      let env = environments.first(where: { row.variables[$0.name] != nil }) else { return }
                onOpen(env)
            }
            .overlay {
                if shown.isEmpty {
                    Text(rows.isEmpty ? "No variables yet." : "Nothing here for “\(filter.rawValue)”.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Double-click a name to open it · right-click to copy it to an environment that's missing it")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // Another project: start over.
        .onChange(of: project.id) { verdicts = [:]; selection = [] }
    }

    private func matches(_ row: EnvironmentComparison.Row) -> Bool {
        switch filter {
        case .all: true
        case .missing: row.isMissingSomewhere
        case .differs: if case .differs = row.verdict { true } else { false }
        case .same: row.verdict == .same
        }
    }

    private func summaryText(_ s: EnvironmentComparison.Summary) -> String {
        var parts = ["\(s.total) \(s.total == 1 ? "name" : "names")"]
        parts.append("\(s.missingSomewhere) missing somewhere")
        if s.onlyInOne > 0 { parts.append("\(s.onlyInOne) in one environment only") }
        if !verdicts.isEmpty {
            parts.append("\(s.same) same everywhere")
            parts.append("\(s.differs) different")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func compareValues(_ rows: [EnvironmentComparison.Row], environments: [ProjectEnvironment]) {
        isComparing = true
        Task {
            defer { isComparing = false }
            do {
                let auth = try await session.authenticatedContext(reason: "compare values in \(project.name)")
                let compared = try EnvironmentComparison.compareValues(rows, environmentOrder: environments.map(\.name),
                                                                       secrets: secrets, context: auth)
                verdicts = Dictionary(uniqueKeysWithValues: compared.compactMap { row in row.verdict.map { (row.key, $0) } })
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                // Prompt dismissed.
            } catch {
                navigation.show(.failed("Couldn’t compare values", ResultReport.describe(error)))
            }
        }
    }

    @ViewBuilder
    private func copyMenu(_ row: EnvironmentComparison.Row, environments: [ProjectEnvironment]) -> some View {
        let source = environments.compactMap { row.variables[$0.name] }.first
        let targets = environments.filter { row.cells[$0.name] == .missing }
        if let source, !targets.isEmpty {
            ForEach(targets) { target in
                Menu("Copy to \(target.name)") {
                    Button("Name Only") { copy(source, to: target, includeValue: false) }
                    Button("Name and Value (Touch ID)") { copy(source, to: target, includeValue: true) }
                        .disabled(!source.hasValue)
                }
            }
        } else {
            Text("In every environment")
        }
    }

    private func copy(_ variable: Variable, to target: ProjectEnvironment, includeValue: Bool) {
        Task {
            do {
                var auth: LAContext?
                if includeValue && variable.hasValue {
                    auth = try await session.authenticatedContext(reason: "copy \(variable.key) to \(target.name)")
                }
                let result = try VariableCopier.copy([variable], to: target, includeValues: includeValue,
                                                     context: context, secrets: secrets, authContext: auth)
                try? context.save()
                verdicts = [:] // values changed: compare again if needed
                navigation.show(result.copied == 1
                    ? .success("Copied to \(target.name)", "\(variable.key) was added to \(target.name)" + (includeValue ? " with its value." : ", name only."))
                    : .nothing("Already there", "\(variable.key) already exists in \(target.name)."))
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                // Prompt dismissed.
            } catch {
                navigation.show(.failed("Couldn’t copy \(variable.key)", ResultReport.describe(error)))
            }
        }
    }
}

/// Set / Empty / Missing, always with an icon (never color alone).
private struct CompareCell: View {
    let state: EnvironmentComparison.Cell

    var body: some View {
        switch state {
        case .hasValue:
            Label("Set", systemImage: "checkmark.circle.fill").foregroundStyle(DS.Status.success)
        case .noValue:
            Label("Empty", systemImage: "circle").foregroundStyle(.secondary)
        case .missing:
            Label("Missing", systemImage: "minus.circle").foregroundStyle(DS.Status.warning)
        }
    }
}

/// "Missing in staging", "Same in all", "Differs: production"…
private struct StatusText: View {
    let row: EnvironmentComparison.Row

    var body: some View {
        if row.isMissingSomewhere {
            Label("Missing in \(row.missingIn.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                .foregroundStyle(DS.Status.warning)
                .lineLimit(1)
        } else {
            switch row.verdict {
            case .same:
                Label("Same in all", systemImage: "equal.circle").foregroundStyle(DS.Status.success)
            case .differs(let groups):
                Label("Differs: " + groups.map { $0.joined(separator: " = ") }.joined(separator: " · "), systemImage: "notequal.circle")
                    .lineLimit(1)
            case .notComparable:
                Text("Fewer than two values").foregroundStyle(.secondary)
            case nil:
                Text("In every environment").foregroundStyle(.secondary)
            }
        }
    }
}
