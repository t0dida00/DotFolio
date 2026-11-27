import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct NotificationFeedTests {
    let context: ModelContext
    init() throws { context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true)) }

    @Test func newestFirstAndUnreadCount() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        NotificationFeed.post(.siteDown, title: "Shop is down", body: "HTTP 503", projectID: nil, at: t0, context: context)
        NotificationFeed.post(.siteRecovered, title: "Shop is back up", body: "23 min", projectID: nil, at: t0 + 60, context: context)
        let all = NotificationFeed.all(context: context)
        #expect(all.map(\.title) == ["Shop is back up", "Shop is down"])
        #expect(all.first?.kind == .siteRecovered)
        #expect(NotificationFeed.unreadCount(context: context) == 2)
        NotificationFeed.markAllRead(context: context)
        #expect(NotificationFeed.unreadCount(context: context) == 0)
    }

    @Test func keepsOnlyTheNewest() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<(NotificationFeed.limit + 5) {
            NotificationFeed.post(.siteDown, title: "#\(i)", body: "", projectID: nil, at: t0 + Double(i), context: context)
        }
        let all = NotificationFeed.all(context: context)
        #expect(all.count == NotificationFeed.limit)
        #expect(all.first?.title == "#\(NotificationFeed.limit + 4)")
        #expect(all.last?.title == "#5")
    }

    @Test func badgeText() {
        #expect(NotificationFeed.badge(0) == nil)
        #expect(NotificationFeed.badge(3) == "3")
        #expect(NotificationFeed.badge(12) == "9+")
    }
}
