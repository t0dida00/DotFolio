import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

struct ProjectListRow: View {
    let project: Project
    let match: ProjectSearch.Match

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ProjectTile(project: project, size: 34)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(project.name).lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.s)
            if let opened = project.lastOpenedAt {
                // Compact age (1m, 5h, 1d…), refreshed every 15 minutes.
                TimelineView(.periodic(from: .now, by: CompactAge.refreshInterval)) { context in
                    Text(CompactAge.string(since: opened, now: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .help("Last opened \(opened.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityLabel("Last opened \(opened.formatted(.relative(presentation: .named)))")
            }
        }
        .padding(.vertical, DS.Space.xs)
        .clickableCursor()
    }

    /// `~/Projects/app`. The sandbox's home is the app container, so the
    /// user's real home folder comes from the account record instead.
    private static func tildePath(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return path }
        let home = String(cString: dir)
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// While searching, say why a project matched; otherwise its repo.
    private var subtitle: String {
        switch match {
        case .variableKey(let key): "Matches \(key)"
        case .account(let login): "Uses \(login)"
        case .service(let name): "Uses \(name)"
        case .name, .repo:
            if project.origin == .local, let folder = ProjectFolder.resolve(project) {
                Self.tildePath(folder)
            } else {
                project.repoFullName.isEmpty ? "No repo" : project.repoFullName
            }
        }
    }
}
