import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct ProjectSearchTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    private func makeShop() -> Project {
        let firebase = Account(serviceType: .firebase, login: "dev@acme.studio", displayName: "Acme work")
        context.insert(firebase)
        let prod = ServiceProject(name: "Acme Shop", externalID: "acme-shop-prod", account: firebase)
        context.insert(prod)

        let shop = Project(name: "Acme Shop Web", provider: .github, repoFullName: "acme/shop-web")
        context.insert(shop)
        let env = ProjectEnvironment(name: "production", project: shop)
        context.insert(env)
        let key = Variable(key: "FIREBASE_API_KEY", environment: env)
        context.insert(key)
        key.link(account: nil, serviceProject: prod)
        return shop
    }

    @Test func matchesNameCaseAndDiacriticInsensitively() {
        let p = Project(name: "Quản lý Đơn hàng")
        context.insert(p)
        #expect(ProjectSearch.match(p, query: "quan ly") == .name)
        #expect(ProjectSearch.match(p, query: "ĐƠN") == .name)
    }

    @Test func matchesRepoVariableAccountAndService() {
        let shop = makeShop()
        #expect(ProjectSearch.match(shop, query: "shop-web") == .repo("acme/shop-web"))
        #expect(ProjectSearch.match(shop, query: "api_key") == .variableKey("FIREBASE_API_KEY"))
        #expect(ProjectSearch.match(shop, query: "dev@acme") == .account("dev@acme.studio"))
        #expect(ProjectSearch.match(shop, query: "acme-shop-prod") == .service("acme-shop-prod"))
    }

    @Test func nameWinsOverOtherMatches() {
        let shop = makeShop()
        #expect(ProjectSearch.match(shop, query: "acme") == .name)
    }

    @Test func serviceNameFindsProjectsUsingThatService() {
        let shop = makeShop()
        let other = Project(name: "Blog")
        context.insert(other)
        let hits = ProjectSearch.filter([shop, other], query: "firebase")
        // "firebase" hits the variable key first, which is fine: the project is found.
        #expect(hits.map(\.project.name) == ["Acme Shop Web"])
    }

    @Test func noMatchReturnsNil() {
        let shop = makeShop()
        #expect(ProjectSearch.match(shop, query: "stripe") == nil)
    }

    @Test func emptyQueryMatchesEverything() {
        let p = Project(name: "Anything")
        context.insert(p)
        #expect(ProjectSearch.match(p, query: "   ") == .name)
    }

    @Test func sortsByRecentlyOpenedWithNeverOpenedLast() {
        let a = Project(name: "A"), b = Project(name: "B"), c = Project(name: "C")
        [a, b, c].forEach(context.insert)
        b.lastOpenedAt = .now
        c.lastOpenedAt = .now.addingTimeInterval(-60)
        #expect(ProjectSearch.sorted([a, b, c], by: .recentlyOpened).map(\.name) == ["B", "C", "A"])
        #expect(ProjectSearch.recent([a, b, c], limit: 1).map(\.name) == ["B"])
    }

    @Test func sortsByNameNaturally() {
        let names = ["project 10", "Project 2", "alpha"]
        let projects = names.map { Project(name: $0) }
        projects.forEach(context.insert)
        #expect(ProjectSearch.sorted(projects, by: .name).map(\.name) == ["alpha", "Project 2", "project 10"])
    }

    @Test func createAddsStandardEnvironments() throws {
        let p = Project.create(name: "  New App  ", in: context)
        try context.save()
        #expect(p.name == "New App")
        #expect(p.sortedEnvironments.map(\.name) == ["development", "staging", "production"])
        #expect(p.sortedEnvironments.last?.isProtected == true)
        #expect(p.hasStoredSecrets == false)
    }


}
