import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct ProjectHealthTests {
    let context: ModelContext
    init() throws { context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true)) }

    private func project(url: String? = "https://shop.example.com") -> Project {
        let p = Project.create(name: "Shop", in: context)
        p.productionURL = url.flatMap(URL.init(string:))
        return p
    }

    private let up = HealthResult(statusCode: 200, responseTime: 0.2, error: nil)
    private let down = HealthResult(statusCode: 503, responseTime: 0.1, error: "HTTP 503")
    private let noAnswer = HealthResult(statusCode: nil, responseTime: nil, error: "Timed out")

    @Test func unknownUntilChecked() {
        let p = project()
        #expect(p.health == .unknown)
        #expect(project(url: nil).health == .unknown)
    }

    @Test func firstUpSaysNothingFirstDownAnnounces() {
        let p = project()
        #expect(p.recordHealth(up) == nil)
        #expect(p.health == .up)
        let q = project()
        #expect(q.recordHealth(noAnswer) == .wentDown(reason: "Timed out"))
        #expect(q.health == .down)
        #expect(q.healthError == "Timed out")
    }

    @Test func onlyChangesAreEvents() {
        let p = project()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        p.recordHealth(up, at: t0)
        #expect(p.recordHealth(down, at: t0 + 600) == .wentDown(reason: "HTTP 503"))
        #expect(p.recordHealth(down, at: t0 + 1200) == nil)
        #expect(p.healthDownSince == t0 + 600)
        #expect(p.recordHealth(up, at: t0 + 2400) == .recovered(downtime: 1800))
        #expect(p.healthDownSince == nil)
        #expect(p.healthError == nil)
        #expect(p.recordHealth(up, at: t0 + 3000) == nil)
    }

    @Test func tracksHowLongTheCurrentStateLasts() {
        let p = project()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        p.recordHealth(up, at: t0)
        p.recordHealth(up, at: t0 + 600)
        #expect(p.healthUpSince == t0, "repeated ups keep the start")
        #expect(p.healthDuration(now: t0 + 3600) == 3600)
        p.recordHealth(down, at: t0 + 4000)
        #expect(p.healthUpSince == nil)
        #expect(p.healthDuration(now: t0 + 4600) == 600)
        p.recordHealth(up, at: t0 + 5000)
        #expect(p.healthUpSince == t0 + 5000, "recovery restarts the clock")
        #expect(project().healthDuration() == nil)
    }

    @Test func summaryCountsAndOrders() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = project(); a.name = "Alpha"; a.recordHealth(up, at: t0)
        let b = project(); b.name = "Beta"; b.recordHealth(down, at: t0 + 100)
        let c = project(); c.name = "Gamma"; c.recordHealth(down, at: t0)
        let d = project(); d.name = "Delta"
        let e = project(); e.name = "Epsilon"; e.recordHealth(HealthResult(statusCode: 200, responseTime: 4.2, error: nil), at: t0)
        let none = project(url: nil); none.name = "No site"
        let s = UptimeSummary(projects: [a, b, c, d, e, none])
        #expect((s.up, s.slow, s.down, s.unchecked, s.total) == (1, 1, 2, 1, 5))
        #expect(s.projects.map(\.name) == ["Gamma", "Beta", "Epsilon", "Delta", "Alpha"])
        #expect(s.projects(.down).map(\.name) == ["Gamma", "Beta"])
        #expect(s.projects(.slow).map(\.name) == ["Epsilon"])
        #expect(s.projects(.unchecked).map(\.name) == ["Delta"])
        #expect(s.projects(.all).count == 5)
        #expect(s.availableFilters == [.all, .down, .slow, .up, .unchecked])
        #expect(UptimeSummary(projects: [a]).availableFilters == [.all, .up])
    }

    @Test func slowIsUpButOverTheThreshold() {
        let p = project()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(p.recordHealth(HealthResult(statusCode: 200, responseTime: 3.5, error: nil), at: t0) == nil)
        #expect(p.health == .slow)
        #expect(p.healthDuration(now: t0 + 60) == 60, "slow keeps the up clock")
        #expect(p.recordHealth(HealthResult(statusCode: 200, responseTime: 0.3, error: nil), at: t0 + 600) == nil)
        #expect(p.health == .up)
        #expect(p.healthUpSince == t0)
        p.recordHealth(HealthResult(statusCode: 200, responseTime: HealthStatus.slowThreshold, error: nil))
        #expect(p.health == .up, "exactly the threshold isn't slow")
    }

    @Test func statusCodesDecideUp() {
        #expect(HealthResult(statusCode: 301, responseTime: 0, error: nil).isUp)
        #expect(!HealthResult(statusCode: 404, responseTime: 0, error: nil).isUp)
        for code in [401, 403, 429] { #expect(HealthResult(statusCode: code, responseTime: 0, error: nil).isUp) }
        #expect(!HealthResult(statusCode: 502, responseTime: 0, error: nil).isUp)
        #expect(!HealthResult(statusCode: nil, responseTime: nil, error: nil).isUp)
        let p = project()
        p.recordHealth(HealthResult(statusCode: 500, responseTime: 0.1, error: nil))
        #expect(p.healthError == "HTTP 500")
    }

    @Test func clearForgetsTheLastCheck() {
        let p = project()
        p.recordHealth(down)
        p.clearHealth()
        #expect(p.health == .unknown)
        #expect(p.healthDownSince == nil && p.healthStatusCode == nil)
    }

    @Test(arguments: [
        ("https://www.liabeauty.com/", "liabeauty.com"),
        ("https://liabeauty.com", "liabeauty.com"),
        ("https://shop.example.com/eu/", "shop.example.com/eu"),
    ])
    func displayName(url: String, name: String) {
        #expect(project(url: url).productionDisplayName == name)
    }

    @Test func downtimeText() {
        let cases: [(Double, String)] = [(30, "1 min"), (1380, "23 min"), (3600, "1 h"), (7500, "2 h 5 min"), (273_600, "3 d 4 h")]
        for (seconds, text) in cases { #expect(DowntimeText.string(seconds) == text) }
    }
}
