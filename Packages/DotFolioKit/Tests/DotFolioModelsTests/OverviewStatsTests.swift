import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct OverviewStatsTests {
    @Test func computesTotalsCoverageRankingAndAttention() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let gmail = Account(login: "me@gmail.com", services: ["Firebase", "Google Maps", "Google Cloud"])
        let stripe = Account(login: "billing@acme.studio", services: ["Stripe"])
        [gmail, stripe].forEach(context.insert)

        let shop = Project.create(name: "Shop", link: URL(string: "https://github.com/acme/shop"), in: context)
        let blog = Project.create(name: "Blog", in: context)

        func add(_ key: String, to env: ProjectEnvironment, value: Bool, service: String = "", account: Account? = nil,
                 updated: Date = .now) {
            let v = Variable(key: key, environment: nil)
            context.insert(v)
            v.environment = env
            v.hasValue = value
            v.serviceLabel = service
            v.account = account
            v.updatedAt = updated
        }
        let old = Date.now.addingTimeInterval(-200 * 86_400)
        add("FIREBASE_KEY", to: shop.sortedEnvironments[0], value: true, service: "Firebase", account: gmail, updated: old)
        add("MAPS_KEY", to: shop.sortedEnvironments[2], value: false, service: "Google Maps", account: gmail)
        add("STRIPE_KEY", to: shop.sortedEnvironments[2], value: true, service: "Stripe", account: stripe)
        add("FIREBASE_KEY", to: blog.sortedEnvironments[0], value: false, service: "firebase")
        add("MYSTERY", to: blog.sortedEnvironments[0], value: false)

        let stats = OverviewStats(projects: [shop, blog], accounts: [gmail, stripe])
        #expect(stats.projectCount == 2)
        #expect(stats.repoProjectCount == 1)
        #expect(stats.variableCount == 5)
        #expect(stats.withValueCount == 2)
        #expect(stats.missingCount == 3)
        #expect(stats.noSourceCount == 1)            // MYSTERY
        #expect(stats.staleCount == 1)               // old FIREBASE_KEY with a value
        #expect(stats.serviceCount == 4)             // Firebase, Google Maps, Google Cloud, Stripe
        #expect(stats.services.first == .init(name: "Firebase", variables: 2, projects: 2))
        // Categories are guessed from providers when not set: Stripe → Payments, Google Maps → Maps.
        #expect(Set(stats.categories.map(\.name)) == ["Payments", "Maps"])
        #expect(stats.environments.map(\.name) == ["development", "production"])
        #expect(stats.environments[1].withValue == 1 && stats.environments[1].total == 2)
        #expect(stats.accountRanking.map(\.account.login) == ["me@gmail.com", "billing@acme.studio"])
        #expect(stats.accountRanking[0].services == 3)
        #expect(stats.attention.map(\.project.name) == ["Blog", "Shop"])
    }

    @Test func emptyIsSafe() {
        let stats = OverviewStats(projects: [], accounts: [])
        #expect(stats.valueCoverage == 1)
        #expect(stats.services.isEmpty)
        #expect(stats.attention.isEmpty)
    }
}
