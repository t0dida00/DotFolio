import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication
import SwiftData
import SwiftUI

// MARK: - Right column

/// Library keys in collapsible provider sections, with the Add key card
/// pinned at the bottom.
struct LibraryView: View {
    let groups: [LibraryGroup]
    let total: Int
    /// Bumped by the left column's "New Key" button to focus the add card.
    let focusRequest: Int
    /// The left column's filter: "all", "library" or an environment name.
    let scope: String

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.secretStore) private var secrets

    @State private var expanded: Set<String> = []
    /// A lone provider starts open; this remembers that it was closed.
    @State private var collapsedSingles: Set<String> = []
    @FocusState private var addNameFocused: Bool
    @State private var dropTargeted = false

    /// "12 keys across 4 providers · 9 from projects" (of the groups shown).
    private var librarySummary: String {
        let shown = groups.flatMap(\.keys)
        let fromProjects = shown.filter { !$0.inLibrary }.count
        var text = "\(total) \(total == 1 ? "key" : "keys") across \(groups.count) \(groups.count == 1 ? "provider" : "providers")"
        if fromProjects > 0 { text += " · \(fromProjects) from projects" }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Library").font(DS.Font.pageTitle)
                            Text(total == 0
                                 ? "Keys you reuse across projects — a personal OpenAI key, a Stripe test key. Not tied to any project."
                                 : librarySummary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            open(EnvFilePicker.choose(message: "Choose .env files. A comment like #Service/Provider/Account/Link after a value says where the key belongs; keys without a provider go to Other."))
                        } label: {
                            Label("Import .env…", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .symbolMotion(.bounceDown)
                        .clickableCursor()
                        .help("Add the keys of .env files to the Library — or drop the files here")
                    }

                    if groups.isEmpty {
                        if scope != "all" {
                            ContentUnavailableView("No keys here", systemImage: "line.3.horizontal.decrease.circle",
                                                   description: Text(scope == "library"
                                                                     ? "The Library has no keys of its own yet."
                                                                     : "No project has variables in \(scope)."))
                        } else if total > 0 {
                            ContentUnavailableView.search
                        }
                    }

                    VStack(spacing: DS.Space.s) {
                        ForEach(groups) { group in
                            LibrarySection(
                                group: group,
                                isExpanded: Binding(
                                    get: { groups.count == 1 ? !collapsedSingles.contains(group.id) : expanded.contains(group.id) },
                                    set: { open in
                                        withAnimation(.smooth(duration: 0.2)) {
                                            if groups.count == 1 {
                                                if open { collapsedSingles.remove(group.id) } else { collapsedSingles.insert(group.id) }
                                            } else {
                                                if open { expanded.insert(group.id) } else { expanded.remove(group.id) }
                                            }
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)

            AddVariableCard(target: .library, nameFocused: $addNameFocused, onDropFiles: { open($0) })
                .padding(.horizontal, DS.Space.xl)
                .padding(.vertical, DS.Space.m)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
        }
        .onChange(of: focusRequest) { _, _ in addNameFocused = true }

        .dropDestination(for: URL.self) { urls, _ in
            open(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
                    .overlay { Label("Drop .env files to add them to the Library", systemImage: "square.and.arrow.down").font(DS.Font.sectionTitle) }
                    .padding(DS.Space.s)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Reads the files and adds every key straight away: each line's
    /// `#Service/Provider/Account/Link` comment says where it goes.
    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let names = urls.map(\.lastPathComponent)
        do {
            let files = try EnvFilePicker.read(urls)
            let entries = Self.merged(files)
            guard !entries.isEmpty else {
                navigation.show(.nothing("No variables found", "\(names.joined(separator: ", ")) has no KEY=value lines."))
                return
            }
            let result = try LibraryImporter.importKeys(entries, context: context, secrets: secrets)
            navigation.show(.library(added: result.added, skipped: result.skipped, invalidLinks: result.invalidLinks, files: names))
        } catch let failure as VariableEditor.Failure {
            navigation.show(.failure("Nothing was imported. \(failure.message)"))
        } catch {
            navigation.show(.failure(error.localizedDescription))
        }
    }

    /// One list from all files: a name appears once; real values win over
    /// template placeholders (`.env.example` brings names and comments only),
    /// and a later file wins over an earlier one.
    static func merged(_ files: [EnvFilePicker.File]) -> [EnvEntry] {
        var order: [String] = []
        var byKey: [String: EnvEntry] = [:]
        for file in files.sorted(by: { ($0.kind == .template ? 0 : 1) < ($1.kind == .template ? 0 : 1) }) {
            for var entry in file.entries {
                if file.kind == .template { entry.value = "" }
                if byKey[entry.key] == nil { order.append(entry.key) }
                byKey[entry.key] = entry
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
