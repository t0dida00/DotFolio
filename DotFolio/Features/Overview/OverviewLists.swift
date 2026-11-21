import DotFolioModels
import SwiftData
import SwiftUI

struct AttentionList: View {
    let items: [OverviewStats.ProjectAttention]
    let onOpen: (Project) -> Void

    var body: some View {
        if items.isEmpty {
            Label("Every variable has a value.", systemImage: "checkmark.circle")
                .foregroundStyle(DS.Status.success)
        } else {
            VStack(spacing: DS.Space.xs) {
                ForEach(items) { item in
                    RowButton(action: { onOpen(item.project) }) {
                        ProjectTile(project: item.project, size: 24)
                        Text(item.project.name).lineLimit(1)
                        Spacer()
                        Label("\(item.missing) of \(item.total) missing", systemImage: "exclamationmark.circle")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(DS.Status.warning)
                    }
                }
            }
        }
    }
}

struct RecentList: View {
    let variables: [Variable]
    let onOpen: (Project) -> Void

    var body: some View {
        if variables.isEmpty {
            EmptyNote(text: "No variables yet.")
        } else {
            VStack(spacing: DS.Space.xs) {
                ForEach(variables) { v in
                    RowButton(action: { if let p = v.project { onOpen(p) } }) {
                        Image(systemName: v.hasValue ? "key.fill" : "key")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(v.key).font(.callout.monospaced()).lineLimit(1)
                            Text("\(v.project?.name ?? "?") · \(v.environment?.name ?? "?")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(v.updatedAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct RowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) { label }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.s)
                .background(.quaternary.opacity(hovering ? 0.6 : 0), in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickableCursor()
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
