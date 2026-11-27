import DotFolioModels
import SwiftData
import SwiftUI

/// Toolbar bell, top right: what happened while you weren't looking (a
/// production site went down or came back). The badge counts unread ones.
struct NotificationBell: View {
    @Query(sort: \AppNotification.createdAt, order: .reverse) private var notifications: [AppNotification]
    @State private var isOpen = false

    private var unread: Int { notifications.count { !$0.isRead } }

    var body: some View {
        Button { isOpen.toggle() } label: {
            // Plain gray bell like the other toolbar icons; unread adds a
            // small red dot, not a red bell.
            Label("Notifications", systemImage: "bell")
                .foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Circle()
                            .fill(DS.Status.danger)
                            .frame(width: 7, height: 7)
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .help(unread > 0 ? "\(unread) unread notification\(unread == 1 ? "" : "s")" : "Notifications")
        .accessibilityValue(NotificationFeed.badge(unread).map { "\($0) unread" } ?? "")
        .clickableCursor()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            NotificationList(notifications: notifications, close: { isOpen = false })
        }
    }
}

/// The bell's popover: newest first, unread ones marked with a dot.
private struct NotificationList: View {
    let notifications: [AppNotification]
    let close: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Query private var projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications").font(DS.Font.sectionTitle)
                Spacer(minLength: DS.Space.m)
                if notifications.contains(where: { !$0.isRead }) {
                    Button("Mark All as Read") { NotificationFeed.markAllRead(context: context) }
                        .buttonStyle(.link)
                        .clickableCursor()
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
            Divider()
            if notifications.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let existing = Set(projects.map(\.id))
                        ForEach(notifications) { note in
                            NotificationRow(note: note, projectDeleted: note.projectID.map { !existing.contains($0) } ?? false) { open(note) }
                            if note.id != notifications.last?.id { Divider().padding(.leading, 52) }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 380)
    }

    private var empty: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: "bell.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No notifications").font(DS.Font.panelTitle)
            Text("You’ll see here when a project’s production site goes down or comes back up.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity)
    }

    /// Marks it read; opens its project unless that project was deleted.
    private func open(_ note: AppNotification) {
        note.isRead = true
        guard let id = note.projectID, projects.contains(where: { $0.id == id }) else { return }
        close()
        navigation.projectToOpen = id
    }
}

private struct NotificationRow: View {
    let note: AppNotification
    /// Its project is gone: dimmed, says so, and clicking only marks it read.
    let projectDeleted: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                TintedIcon(symbol: symbol, tint: tint, size: 28)
                    .opacity(projectDeleted ? 0.55 : 1)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(note.title)
                        .fontWeight(note.isRead ? .regular : .semibold)
                        .lineLimit(1)
                    if !note.body.isEmpty {
                        Text(note.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text(note.createdAt.formatted(.relative(presentation: .named))
                             + (projectDeleted ? " · Project deleted" : ""))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(projectDeleted ? 0.55 : 1)
                Spacer(minLength: DS.Space.s)
                if !note.isRead {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        .padding(.top, DS.Space.xs + 2)
                        .accessibilityLabel("Unread")
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
            .contentShape(Rectangle())
            .background(hovering ? AnyShapeStyle(.quaternary.opacity(DS.Fill.subtle)) : AnyShapeStyle(.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickableCursor()
        .help(projectDeleted ? "This project was deleted" : "Open the project")
    }

    private var symbol: String {
        note.kind == .siteDown ? "xmark.octagon" : "checkmark.circle"
    }

    private var tint: Color {
        note.kind == .siteDown ? DS.Palette.red : DS.Palette.green
    }
}
