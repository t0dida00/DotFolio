import AppKit
import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftUI

/// "Export .env" for one environment: copy to clipboard, save into the
/// project's folder, or save anywhere. Reading values needs Touch ID once
/// per session; protected environments, overwrites and files git would
/// commit are confirmed first.
struct ExportMenu: View {
    let project: Project
    let environment: ProjectEnvironment

    @Environment(\.secretStore) private var secrets
    @Environment(SessionLock.self) private var session

    private enum Target: Equatable {
        case clipboard
        case folder(URL)
        case file(URL)
    }

    private struct Pending: Identifiable {
        let id = UUID()
        let target: Target
        let warnings: [String]
    }

    @State private var pending: Pending?
    @State private var notice: (text: String, isError: Bool)?

    private var fileName: String { EnvExport.fileName(for: environment) }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Menu {
                Button("Copy to Clipboard", systemImage: "doc.on.clipboard") { request(.clipboard) }
                Divider()
                if let folder = ProjectFolder.resolve(project) {
                    Button("Save \(fileName) to “\(folder.lastPathComponent)”", systemImage: "folder") { request(.folder(folder)) }
                    Button("Change Project Folder…") { if let url = ProjectFolder.choose(for: project) { request(.folder(url)) } }
                } else {
                    Button("Save \(fileName) to Project Folder…", systemImage: "folder") {
                        if let url = ProjectFolder.choose(for: project) { request(.folder(url)) }
                    }
                }
                Button("Save As…", systemImage: "square.and.arrow.down") { saveAs() }
            } label: {
                Label("Export \(fileName)", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .symbolMotion(.bounceUp)
            .fixedSize()
            .disabled((environment.variables ?? []).isEmpty)
            .help("Export this environment as a .env file. Reading values asks for Touch ID.")
            .clickableCursor()

            if let notice {
                Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(notice.isError ? AnyShapeStyle(DS.Status.danger) : AnyShapeStyle(DS.Status.success))
                    .lineLimit(2)
                    .symbolMotion(notice.isError ? .wiggle : .bounce, onAppear: true)
                    // A new notice is a new view, so its icon plays again.
                    .id(notice.text)
                    .transition(.opacity)
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { item in
            Button(confirmButton(item.target), role: environment.isProtected ? .destructive : nil) { perform(item.target) }
        } message: { item in
            Text(item.warnings.joined(separator: "\n\n"))
        }
    }

    // MARK: Flow

    private var confirmTitle: String {
        environment.isProtected ? "Export \(environment.name) values?" : "Export \(fileName)?"
    }

    private func confirmButton(_ target: Target) -> String {
        switch target {
        case .clipboard: "Copy to Clipboard"
        case .folder, .file: "Save \(fileName)"
        }
    }

    private func request(_ target: Target) {
        var warnings: [String] = []
        if environment.isProtected {
            warnings.append("\(environment.name.capitalized) is a protected environment. The exported values are real production secrets.")
        }
        if case .folder(let folder) = target {
            warnings += ProjectFolder.warnings(writing: fileName, into: folder)
        }
        if warnings.isEmpty { perform(target) } else { pending = Pending(target: target, warnings: warnings) }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = true
        panel.message = "The file contains secrets. Don’t save it inside a folder that is committed to git."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        request(.file(url))
    }

    private func perform(_ target: Target) {
        pending = nil
        Task {
            do {
                var auth: LAContext?
                if (environment.variables ?? []).contains(where: \.hasValue) {
                    auth = try await session.authenticatedContext(reason: "export \(environment.name) values")
                }
                let output = try EnvExport.build(environment, secrets: secrets, authContext: auth)
                let message: String
                switch target {
                case .clipboard:
                    SecureClipboard.copy(output.text)
                    message = "Copied — the clipboard clears in 60 seconds."
                case .folder(let folder):
                    try ProjectFolder.withAccess(to: folder) {
                        try ProjectFolder.write(output.text, to: folder.appending(path: fileName))
                    }
                    message = "Saved \(fileName) to \(folder.lastPathComponent)."
                case .file(let url):
                    try ProjectFolder.write(output.text, to: url)
                    message = "Saved \(url.lastPathComponent)."
                }
                let missing = output.missing.isEmpty ? "" : " \(output.missing.count) \(output.missing.count == 1 ? "variable has" : "variables have") no value."
                show(message + missing, isError: false)
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                // Prompt dismissed.
            } catch let error as KeychainError {
                show(error.userMessage, isError: true)
            } catch {
                show(error.localizedDescription, isError: true)
            }
        }
    }

    private func show(_ text: String, isError: Bool) {
        withAnimation { notice = (text, isError) }
        Task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { notice = nil }
        }
    }
}
