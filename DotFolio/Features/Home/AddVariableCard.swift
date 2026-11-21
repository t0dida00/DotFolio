import DotFolioCore
import DotFolioEnv
import DotFolioModels
import SwiftData
import SwiftUI

/// "Add variable", pinned to the bottom of the detail column.
/// Layout: the form 60% (Name 30% · Value 70%, then Service · Provider ·
/// Account · Link) and a drop zone for .env files 40%.
struct AddVariableCard: View {
    /// Where new variables go.
    enum Target {
        case environment(ProjectEnvironment)
        case library
    }

    let target: Target
    var nameFocused: FocusState<Bool>.Binding
    /// Handles .env files dropped (or chosen) in the drop zone. Nil = add them
    /// to the target environment. The Library passes its own import.
    var onDropFiles: (([URL]) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets
    @Environment(AppNavigation.self) private var navigation

    @State private var newKey = ""
    @State private var newValue = ""
    @State private var newCategory = ""
    @State private var newService = ""
    @State private var newAccount = ""
    @State private var newLink = ""
    @State private var errorMessage: String?
    @State private var dropTargeted = false
    /// Show the value being typed (it's the user's own input, not a stored secret).
    @State private var showsNewValue = false
    @FocusState private var valueFocused: Bool

    private var isLibrary: Bool {
        if case .library = target { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Label(isLibrary ? "Add key" : "Add variable", systemImage: "plus.circle")
                    .font(DS.Font.panelTitle)
                    .symbolMotion(.bounce)
                Spacer()
                HStack(spacing: DS.Space.xs) {
                    Text("to")
                    switch target {
                    case .environment(let environment): EnvLabel(name: environment.name)
                    case .library: Label("Library", systemImage: "books.vertical")
                    }
                }
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ProportionalRow(fractions: [0.6, 0.4], spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ProportionalRow(fractions: [0.3, 0.7]) {
                        LabeledField("Name", required: true) {
                            TextField("", text: $newKey)
                                .font(.system(.body, design: .monospaced))
                                .focused(nameFocused)
                        }
                        LabeledField("Value") {
                            // The eye sits inside the field. Native rounded fields
                            // can't hold a button, so this one draws its own box;
                            // it stretches to the Name field's height.
                            HStack(spacing: DS.Space.xs) {
                                Group {
                                    if showsNewValue {
                                        TextField("", text: $newValue)
                                    } else {
                                        SecureField("", text: $newValue)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .focused($valueFocused)
                                // Typed here, not read from the Keychain: no Touch ID.
                                Button { showsNewValue.toggle() } label: {
                                    Image(systemName: showsNewValue ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .buttonStyle(.borderless)
                                .help(showsNewValue ? "Hide what you typed" : "Show what you typed")
                                .accessibilityLabel(showsNewValue ? "Hide value" : "Show value")
                                .clickableCursor()
                            }
                            .padding(.horizontal, DS.Space.s)
                            .frame(maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                                    .strokeBorder(.separator)
                            )
                            .overlay(
                                // Focus ring like the other fields.
                                RoundedRectangle(cornerRadius: DS.Radius.small + 2, style: .continuous)
                                    .stroke(Color.accentColor.opacity(valueFocused ? 0.5 : 0), lineWidth: 3)
                                    .padding(-2)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { valueFocused = true }
                        }
                    }

                    ProportionalRow(fractions: [0.2, 0.2, 0.25, 0.35]) {
                        LabeledField("Service") {
                            TextField("", text: $newCategory)
                        }
                        LabeledField("Provider") {
                            TextField("", text: $newService)
                        }
                        LabeledField("Account") {
                            TextField("", text: $newAccount)
                        }
                        LabeledField("Link") {
                            TextField("", text: $newLink)
                        }
                    }

                    HStack {
                        // Only errors here: the Keychain hint lives once, under the table.
                        Text(errorMessage ?? " ")
                            .font(.caption)
                            .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
                            .lineLimit(2)
                        Spacer()
                        Button(action: add) {
                            Label("Add Variable", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .symbolMotion(.bounce)
                        .buttonBorderShape(.capsule)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        .clickableCursor()
                    }
                }
                dropZone
            }
        }
        .textFieldStyle(.roundedBorder)
        .onSubmit(add)
        .padding(DS.Space.m)
        .panel(radius: DS.Radius.medium, bordered: true)

    }

    // MARK: Drop zone

    private var dropZone: some View {
        // Centered in the space next to the form: icon, title, one short line,
        // then the button. The long explanation is in the tooltip.
        VStack(spacing: DS.Space.s) {
            TintedIcon(symbol: dropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc",
                       tint: DS.Palette.violet, size: 34)
            VStack(spacing: DS.Space.xxs) {
                Text(dropTargeted ? "Release to add" : "Drop .env files")
                    .font(DS.Font.panelTitle)
                Text(dropSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Button("Choose Files…") {
                handleDrop(EnvFilePicker.choose(message: "Choose .env files. \(dropHint)"))
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(dropHint)
        // Light brand violet, a little stronger while files hover over it.
        .background(DS.Palette.violet.opacity(dropTargeted ? 0.14 : 0.06),
                    in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                .strokeBorder(dropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(DS.Palette.violet.opacity(0.3)),
                              style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .animation(.snappy, value: dropTargeted)
    }

    /// One line under the title.
    private var dropSubtitle: String {
        switch target {
        case .environment(let environment): "Added to \(environment.name) · values already there are kept"
        case .library: "Each key goes under the provider in its comment"
        }
    }

    private var dropHint: String {
        switch target {
        case .environment(let environment):
            "Every name is added to \(environment.name), with its value and #Service/Provider/Account/Link comment. Values already there are kept."
        case .library:
            "Each key goes under the provider in its #Service/Provider comment, the rest under Other."
        }
    }

    /// A folder opens the project-folder import; files are read and added.
    private func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let folder = urls.first(where: \.hasDirectoryPath) {
            navigation.folderToImport = PendingFolder(url: folder)
            return
        }
        if let onDropFiles { onDropFiles(urls); return }
        guard case .environment(let environment) = target else { return }
        let names = urls.map(\.lastPathComponent)
        do {
            let files = try EnvFilePicker.read(urls)
            let dropped = files.map { FolderImport.DroppedFile(name: $0.name, entries: $0.entries, isTemplate: $0.kind == .template) }
            guard dropped.contains(where: { !$0.entries.isEmpty }) else {
                navigation.show(.nothing("No variables found", "\(names.joined(separator: ", ")) has no KEY=value lines."))
                return
            }
            let result = try FolderImport.add(dropped, to: environment, context: context, secrets: secrets)
            try? context.save()
            errorMessage = nil
            navigation.show(.environment(environment.name, added: result.addedKeys, filled: result.filledKeys,
                                         unchanged: result.unchangedKeys, files: names))
        } catch let failure as VariableEditor.Failure {
            navigation.show(.failure("Nothing was imported. \(failure.message)"))
        } catch {
            navigation.show(.failure(error.localizedDescription))
        }
    }

    private func add() {
        do {
            switch target {
            case .environment(let environment):
                try VariableEditor.add(key: newKey, value: newValue, category: newCategory, service: newService, account: newAccount,
                                       link: newLink, to: environment, context: context, secrets: secrets)
            case .library:
                try VariableEditor.addToLibrary(key: newKey, value: newValue, category: newCategory, provider: newService,
                                                account: newAccount, link: newLink, context: context, secrets: secrets)
            }
            errorMessage = nil
            let key = newKey.trimmingCharacters(in: .whitespaces)
            switch target {
            case .environment(let environment):
                navigation.show(.success("Variable added", "\(key) was added to \(environment.name)" + (newValue.isEmpty ? ", without a value." : "; its value is in your Keychain.")))
            case .library:
                navigation.show(.success("Key added", "\(key) was added to the Library" + (newValue.isEmpty ? ", without a value." : "; its value is in your Keychain.")))
            }
            newKey = ""; newValue = ""; newCategory = ""; newService = ""; newAccount = ""; newLink = ""
            showsNewValue = false
            nameFocused.wrappedValue = true
        } catch let failure as VariableEditor.Failure {
            errorMessage = failure.message
            navigation.show(.failed(isLibrary ? "Couldn’t add the key" : "Couldn’t add the variable", failure.message))
        } catch {
            errorMessage = error.localizedDescription
            navigation.show(.failed(isLibrary ? "Couldn’t add the key" : "Couldn’t add the variable", error.localizedDescription))
        }
    }
}

/// Small caption above a field.
struct LabeledField<Field: View>: View {
    let title: String
    var required = false
    var optional = false
    @ViewBuilder let field: Field

    init(_ title: String, required: Bool = false, optional: Bool = false, @ViewBuilder field: () -> Field) {
        self.title = title
        self.required = required
        self.optional = optional
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text.fieldTitle(title, required: required, optional: optional)
                .font(DS.Font.label)
                .foregroundStyle(.secondary)
            field
        }
    }
}

/// Lays children out side by side, each taking a fraction of the width.
private struct ProportionalRow: Layout {
    let fractions: [CGFloat]
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let height = zip(subviews, widths(for: width)).map { $0.sizeThatFits(.init(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(for: bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: .init(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func widths(for total: CGFloat) -> [CGFloat] {
        let available = max(0, total - spacing * CGFloat(max(0, fractions.count - 1)))
        return fractions.map { available * $0 }
    }
}

