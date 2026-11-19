import DotFolioModels
import SwiftUI

/// The selected variable: masked value, where it comes from, notes, dates.
/// SECURITY: the value is never read here. Reveal/Copy will authenticate
/// with Touch ID through the Keychain once signing is set up.
struct VariableDetailView: View {
    let variable: Variable
    let environment: ProjectEnvironment

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(variable.key)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Chip(text: environment.name, systemImage: environment.isProtected ? "lock" : "square.stack.3d.up")
                    Chip(text: variable.hasValue ? "Value set" : "Not set",
                         systemImage: variable.hasValue ? "checkmark.circle" : "exclamationmark.circle",
                         tint: variable.hasValue ? .green : .orange)
                }
            }

            Section("Value") {
                LabeledContent("Value") {
                    HStack(spacing: 8) {
                        Text(variable.hasValue ? "••••••••••••" : "—")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(variable.hasValue ? "Value hidden" : "No value")
                        Button("Reveal", systemImage: "eye") {}
                            .disabled(true)
                        Button("Copy", systemImage: "doc.on.doc") {}
                            .disabled(true)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                .help("Reveal and Copy ask for Touch ID — available once Keychain access is set up.")
            }

            Section("Source") {
                if let url = variable.sourceURL {
                    LabeledContent("Link") {
                        Link(destination: url) {
                            Label(url.host() ?? url.absoluteString, systemImage: "arrow.up.forward.square")
                        }
                        .clickableCursor()
                        .help(url.absoluteString)
                    }
                }
                if let account = variable.account {
                    LabeledContent("Account", value: "\(account.serviceName) · \(account.login)")
                }
                if let serviceProject = variable.serviceProject {
                    LabeledContent("Service project") {
                        HStack(spacing: 8) {
                            Text(serviceProject.externalID.isEmpty ? serviceProject.name : serviceProject.externalID)
                            if let console = serviceProject.resolvedConsoleURL {
                                Link("Open console", destination: console)
                                    .clickableCursor()
                            }
                        }
                    }
                }
                if variable.sourceURL == nil && variable.account == nil {
                    Text("No source linked yet.").foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                Text(variable.notes.isEmpty ? "No notes" : variable.notes)
                    .foregroundStyle(variable.notes.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Section("Details") {
                LabeledContent("Created", value: variable.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Updated", value: variable.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct Chip: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
