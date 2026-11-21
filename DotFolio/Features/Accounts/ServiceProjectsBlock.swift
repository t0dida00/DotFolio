import AppKit
import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

struct ServiceProjectsBlock: View {
    let account: Account
    let service: String
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation

    @State private var newName = ""
    @State private var newID = ""
    @State private var newURL = ""
    @State private var error: String?

    /// Projects of this service. Projects created before services were
    /// tracked (no service set) are shown under the account's first service.
    private var items: [ServiceProject] {
        let isFirst = account.services.first == service
        return (account.serviceProjects ?? [])
            .filter { $0.serviceName.caseInsensitiveCompare(service) == .orderedSame || ($0.serviceName.isEmpty && isFirst) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label(service, systemImage: ServiceType.symbol(for: service))
                .font(DS.Font.panelTitle)

            ForEach(items) { sp in
                HStack(spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(sp.name).fontWeight(.medium)
                        if !sp.externalID.isEmpty {
                            Text(sp.externalID).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer()
                    if let console = sp.resolvedConsoleURL {
                        Link(destination: console) { Label("Open console", systemImage: "arrow.up.forward.square") }
                            .help(console.absoluteString)
                            .clickableCursor()
                    }
                    Button {
                        let name = sp.name
                        AccountEditor.delete(sp, context: context)
                        navigation.show(.success("Provider project removed", "\(name) was removed from this account."))
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove \(sp.name)")
                        .accessibilityLabel("Remove \(sp.name)")
                        .clickableCursor()
                }
                .padding(DS.Space.s)
                .panel(radius: DS.Radius.medium)
            }

            HStack(alignment: .bottom, spacing: DS.Space.s) {
                LabeledField("Project name", required: true) { TextField("", text: $newName) }
                LabeledField("Project ID") { TextField("", text: $newID).font(.body.monospaced()) }
                LabeledField("Console URL", optional: true) { TextField("", text: $newURL) }
                Button("Add", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .clickableCursor()
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)

            if let error { Text(error).font(.callout).foregroundStyle(DS.Status.danger) }
        }
        .padding(DS.Space.m)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous).strokeBorder(.separator))
    }

    private func add() {
        do {
            try AccountEditor.addServiceProject(to: account, service: service, name: newName, externalID: newID,
                                                consoleURL: newURL, context: context)
            navigation.show(.success("Provider project added", "\(newName.trimmingCharacters(in: .whitespaces)) was added to \(service)."))
            newName = ""; newID = ""; newURL = ""; error = nil
        } catch {
            self.error = error.message
            navigation.show(.failed("Couldn’t add the provider project", error.message))
        }
    }
}
