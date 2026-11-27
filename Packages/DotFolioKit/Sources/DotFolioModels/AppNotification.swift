import Foundation
import SwiftData

/// An in-app notification, listed under the toolbar bell. Holds only what's
/// shown (no secret values): "liabeauty is down", "liabeauty.com · HTTP 503".
@Model
public final class AppNotification {
    public enum Kind: String, Sendable {
        case siteDown, siteRecovered
    }

    public var id: UUID = UUID()
    public var kindRaw: String = Kind.siteDown.rawValue
    public var title: String = ""
    public var body: String = ""
    /// The project it's about; clicking the notification opens it. Not a
    /// relationship, so deleting the project leaves the notification readable.
    public var projectID: UUID?
    public var createdAt: Date = Date.now
    public var isRead: Bool = false

    public init(kind: Kind, title: String, body: String, projectID: UUID?, createdAt: Date = .now) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.projectID = projectID
        self.createdAt = createdAt
    }

    public var kind: Kind { Kind(rawValue: kindRaw) ?? .siteDown }
}

/// The bell's list: newest first, capped so it never grows without end.
public enum NotificationFeed {
    public static let limit = 50

    @MainActor
    public static func all(context: ModelContext) -> [AppNotification] {
        let sort = [SortDescriptor(\AppNotification.createdAt, order: .reverse)]
        return (try? context.fetch(FetchDescriptor<AppNotification>(sortBy: sort))) ?? []
    }

    /// Adds one and drops the oldest beyond `limit`.
    @MainActor
    @discardableResult
    public static func post(_ kind: AppNotification.Kind, title: String, body: String, projectID: UUID?,
                            at date: Date = .now, context: ModelContext) -> AppNotification {
        let note = AppNotification(kind: kind, title: title, body: body, projectID: projectID, createdAt: date)
        context.insert(note)
        for old in all(context: context).dropFirst(limit) { context.delete(old) }
        return note
    }

    @MainActor
    public static func unreadCount(context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<AppNotification>(predicate: #Predicate { !$0.isRead }))) ?? 0
    }

    @MainActor
    public static func markAllRead(context: ModelContext) {
        for note in all(context: context) where !note.isRead { note.isRead = true }
    }

    /// "9+" past nine, nil at zero: the bell's badge.
    public static func badge(_ count: Int) -> String? {
        count <= 0 ? nil : count > 9 ? "9+" : "\(count)"
    }
}
