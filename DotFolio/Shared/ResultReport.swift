import DotFolioCore
import DotFolioSecurity
import SwiftUI

/// The outcome of an action — add, edit, delete, import, sign-in — shown in a
/// small dialog whatever happened: success (green), nothing changed (amber) or
/// failure (red). State is always carried by an icon and a title, not color
/// alone. Show one with `AppNavigation.show(_:)`.
struct ResultReport: Identifiable {
    enum Outcome {
        case success, nothingNew, failure

        var color: Color {
            switch self {
            case .success: DS.Status.success
            case .nothingNew: DS.Status.warning
            case .failure: DS.Status.danger
            }
        }

        var symbol: String {
            switch self {
            case .success: "checkmark.circle"
            case .nothingNew: "exclamationmark.circle"
            case .failure: "xmark.octagon"
            }
        }
    }

    /// A titled list of names ("Added", "Already there").
    struct Group: Identifiable {
        let id = UUID()
        let title: String
        let names: [String]
    }

    let id = UUID()
    let outcome: Outcome
    let title: String
    let message: String
    var groups: [Group] = []

    // MARK: Builders

    static func success(_ title: String, _ message: String, groups: [Group] = []) -> ResultReport {
        ResultReport(outcome: .success, title: title, message: message, groups: groups)
    }

    static func nothing(_ title: String, _ message: String, groups: [Group] = []) -> ResultReport {
        ResultReport(outcome: .nothingNew, title: title, message: message, groups: groups)
    }

    /// `title` names what failed ("Couldn’t delete the project").
    static func failed(_ title: String, _ message: String) -> ResultReport {
        ResultReport(outcome: .failure, title: title, message: message)
    }

    /// The user-facing text of an error from any layer.
    static func describe(_ error: Error) -> String {
        if let failure = error as? VariableEditor.Failure { return failure.message }
        if let keychain = error as? KeychainError { return keychain.userMessage }
        return error.localizedDescription
    }

    static func failure(_ message: String, files: [String] = []) -> ResultReport {
        ResultReport(outcome: .failure, title: "Couldn’t import .env",
                     message: files.isEmpty ? message : "\(message)\n\(files.joined(separator: ", "))")
    }

    /// Files dropped on one environment.
    static func environment(_ name: String, added: [String], filled: [String], unchanged: [String], files: [String]) -> ResultReport {
        let from = files.joined(separator: ", ")
        var groups: [Group] = []
        if !added.isEmpty { groups.append(Group(title: "Added", names: added)) }
        if !filled.isEmpty { groups.append(Group(title: "Filled in (were empty)", names: filled)) }
        if !unchanged.isEmpty { groups.append(Group(title: "Already there, kept as they were", names: unchanged)) }

        if added.isEmpty && filled.isEmpty {
            return ResultReport(outcome: .nothingNew, title: "Nothing new to import",
                                message: "Every name in \(from) is already in \(name). Values already there are never replaced.",
                                groups: groups)
        }
        var parts: [String] = []
        if !added.isEmpty { parts.append("added \(count(added.count, "variable"))") }
        if !filled.isEmpty { parts.append("filled \(count(filled.count, "empty one"))") }
        return ResultReport(outcome: .success, title: "Imported .env successfully",
                            message: "From \(from): \(parts.joined(separator: " and ")) in \(name).",
                            groups: groups)
    }

    /// Files dropped on the Library.
    static func library(added: Int, skipped: [String], invalidLinks: [String], files: [String]) -> ResultReport {
        let from = files.joined(separator: ", ")
        var groups: [Group] = []
        if !skipped.isEmpty { groups.append(Group(title: "Already in the Library, kept as they were", names: skipped)) }
        if !invalidLinks.isEmpty { groups.append(Group(title: "Link left empty (not a web address)", names: invalidLinks)) }
        if added == 0 {
            return ResultReport(outcome: .nothingNew, title: "Nothing new to import",
                                message: "Every key in \(from) is already in the Library.", groups: groups)
        }
        return ResultReport(outcome: .success, title: "Imported .env successfully",
                            message: "From \(from): added \(count(added, "key")) to the Library.", groups: groups)
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Small dialog for an `ResultReport`.
struct ResultReportSheet: View {
    let report: ResultReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                TintedIcon(symbol: report.outcome.symbol, tint: report.outcome.color, size: 40)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(report.title).font(DS.Font.sheetTitle)
                    Text(report.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !report.groups.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        ForEach(report.groups) { group in
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                Text("\(group.title) · \(group.names.count)")
                                    .font(DS.Font.label)
                                    .foregroundStyle(.secondary)
                                Text(group.names.joined(separator: "\n"))
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(DS.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
                .panel()
            }

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(report.outcome == .failure ? DS.Status.danger : Color.accentColor)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .clickableCursor()
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 440)
    }
}
