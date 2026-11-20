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

    @Test func aNameInSeveralEnvironmentsCountsOnce() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let shop = Project.create(name: "Shop", in: context)
        let (dev, staging, prod) = (shop.sortedEnvironments[0], shop.sortedEnvironments[1], shop.sortedEnvironments[2])
        func add(_ key: String, to env: ProjectEnvironment, value: Bool, provider: String = "") {
            let v = Variable(key: key)
            context.insert(v)
            v.environment = env
            v.hasValue = value
            v.serviceLabel = provider
        }
        // DATABASE_URL everywhere, set only in development; source only on production's copy.
        add("DATABASE_URL", to: dev, value: true)
        add("DATABASE_URL", to: staging, value: false)
        add("DATABASE_URL", to: prod, value: false, provider: "Supabase")
        // STRIPE_KEY set in both environments it is in.
        add("STRIPE_KEY", to: dev, value: true, provider: "Stripe")
        add("STRIPE_KEY", to: prod, value: true, provider: "Stripe")

        let stats = OverviewStats(projects: [shop], accounts: [])
        #expect(stats.variableCount == 2)                 // names, not 5 copies
        #expect(stats.withValueCount == 1 && stats.missingCount == 1)
        #expect(stats.noSourceCount == 0)                 // one copy with a source is enough
        #expect(stats.services.map(\.variables) == [1, 1])
        #expect(stats.attention.first?.missing == 1 && stats.attention.first?.total == 2)
        #expect(Set(stats.recentlyUpdated.map(\.key)) == ["DATABASE_URL", "STRIPE_KEY"])
        #expect(stats.recentlyUpdated.count == 2)
        // Per-environment progress still counts each environment.
        #expect(stats.environments.map(\.total) == [2, 1, 2])
    }

    @Test func emptyIsSafe() {
        let stats = OverviewStats(projects: [], accounts: [])
        #expect(stats.valueCoverage == 1)
        #expect(stats.services.isEmpty)
        #expect(stats.attention.isEmpty)
    }
}
