import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// "Verify Data…": checks the database against the Keychain and the app's
/// rules, explains each problem, and repairs what can be repaired safely.
/// Reads Keychain item names only, never values — no Touch ID needed.
struct VerifyDataSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(\.dismiss) private var dismiss

    @State private var report: IntegrityCheck.Report?
    @State private var error: String?
    @State private var repairedCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Verify Data").font(DS.Font.sheetTitle)
                    Text(summary).foregroundStyle(.secondary)
                }
            }

            if let report, !report.isClean {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    issue(report.missingSecrets.count, "Values missing from the Keychain",
                          "Marked as set, but the Keychain item is gone. Repair marks them Not set so you can re-enter them.")
                    issue(report.orphanedSecretRefs.count, "Leftover Keychain items",
                          "Stored values no variable points at. Repair deletes them from the Keychain.")
                    issue(report.orphanVariables.count + report.orphanEnvironments.count, "Detached variables or environments",
                          "Not attached to any project. Repair removes them (Keychain values first).")
                    issue(report.orphanServiceProjects.count, "Provider projects without an account",
                          "Repair removes them.")
                    issue(report.accountsWithCategoryWords.count, "Service names listed as providers",
                          "e.g. “Database” on an account. Repair moves them to the Service column.")
                    issue(report.duplicateKeys.count, "Duplicate variable names",
                          report.duplicateKeys.prefix(3).map { "\($0.key) in \($0.project) · \($0.environment)" }.joined(separator: ", ")
                            + " — rename or delete one yourself; DOTFOLIO won’t guess which is right.",
                          fixable: false)
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(DS.Status.danger)
            }

            HStack {
                Button("Check Again", action: check)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                if let report, report.fixableCount > 0 {
                    Button("Repair \(report.fixableCount) \(report.fixableCount == 1 ? "Issue" : "Issues")", action: repair)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.xxl)
        .frame(width: 520)
        .onAppear(perform: check)
    }

    private var icon: String {
        guard let report else { return "magnifyingglass" }
        return report.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var tint: Color {
        guard let report else { return .secondary }
        return report.isClean ? DS.Status.success : DS.Status.warning
    }

    private var summary: String {
        if let repairedCount, report?.isClean == true { return "Repaired \(repairedCount). Everything is consistent now." }
        guard let report else { return "Checking…" }
        if report.isClean { return "Everything is consistent: every stored value has a variable and every variable’s value is in the Keychain." }
        return "Found \(report.issueCount) \(report.issueCount == 1 ? "issue" : "issues")."
    }

    @ViewBuilder
    private func issue(_ count: Int, _ title: String, _ detail: String, fixable: Bool = true) -> some View {
        if count > 0 {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DS.Status.warning)
                    .frame(minWidth: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !fixable {
                    Text("Manual").font(DS.Font.label).foregroundStyle(.secondary)
                }
            }
            .padding(DS.Space.s)
            .panel(radius: DS.Radius.medium)
        }
    }

    private func check() {
        do {
            report = try IntegrityCheck.run(context: context, secrets: secrets)
            error = nil
        } catch {
            self.error = (error as? KeychainError)?.userMessage ?? error.localizedDescription
        }
    }

    private func repair() {
        guard let report else { return }
        do {
            repairedCount = try IntegrityCheck.repair(report, context: context, secrets: secrets)
            check()
        } catch {
            self.error = (error as? KeychainError)?.userMessage ?? error.localizedDescription
        }
    }
}
