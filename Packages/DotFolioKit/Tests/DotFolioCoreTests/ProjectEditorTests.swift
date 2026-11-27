import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels

@MainActor
struct ProjectEditorTests {
    let context: ModelContext
    init() throws { context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true)) }

    @Test func updatesNameSummaryAndRepoFromLink() throws {
        let p = Project.create(name: "Old", in: context)
        try ProjectEditor.update(p, name: "  Shop  ", summary: " Storefront ", link: "github.com/acme/shop-web")
        #expect(p.name == "Shop")
        #expect(p.summary == "Storefront")
        #expect(p.provider == .github)
        #expect(p.repoFullName == "acme/shop-web")
    }

    @Test func nonRepoLinkOrNoLinkClearsProvider() throws {
        let p = Project.create(name: "Shop", link: URL(string: "https://gitlab.com/acme/shop"), in: context)
        #expect(p.provider == .gitlab)
        try ProjectEditor.update(p, name: "Shop", summary: "", link: "https://acme.studio")
        #expect(p.provider == RepoProvider.none)
        #expect(p.repoFullName.isEmpty)
        #expect(p.repoURL?.host() == "acme.studio")
        try ProjectEditor.update(p, name: "Shop", summary: "", link: "")
        #expect(p.repoURL == nil)
    }

    @Test func unchangedLinkKeepsImportedRepoInfo() throws {
        let p = Project.create(name: "Shop", link: URL(string: "https://github.com/acme/shop"), in: context)
        p.importedFrom = "github:acme"
        try ProjectEditor.update(p, name: "Shop renamed", summary: "", link: "https://github.com/acme/shop")
        #expect(p.repoFullName == "acme/shop")
        #expect(p.importedFrom == "github:acme")
    }

    @Test func validates() {
        let p = Project.create(name: "Shop", in: context)
        #expect(throws: ProjectEditor.Failure.emptyName) { try ProjectEditor.update(p, name: " ", summary: "", link: "") }
        #expect(throws: ProjectEditor.Failure.invalidLink) { try ProjectEditor.update(p, name: "Shop", summary: "", link: "not a link") }
        #expect(p.name == "Shop")
    }
}

@MainActor
struct ProjectEditorProductionTests {
    let context: ModelContext
    init() throws { context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true)) }

    @Test func setsChangesAndRemovesProductionURL() throws {
        let p = Project.create(name: "Shop", in: context)
        try ProjectEditor.update(p, name: "Shop", summary: "", link: "", production: " shop.example.com ")
        #expect(p.productionURL?.absoluteString == "https://shop.example.com")
        p.recordHealth(HealthResult(statusCode: 503, responseTime: 0.1, error: nil))
        try ProjectEditor.update(p, name: "Shop", summary: "", link: "", production: "https://shop.example.com")
        #expect(p.health == .down, "same address keeps the last check")
        try ProjectEditor.update(p, name: "Shop", summary: "", link: "", production: "https://shop.example.org")
        #expect(p.health == .unknown, "new address forgets it")
        try ProjectEditor.update(p, name: "Shop", summary: "", link: "", production: "")
        #expect(p.productionURL == nil)
    }

    @Test func nilLeavesProductionAlone() throws {
        let p = Project.create(name: "Shop", in: context)
        p.productionURL = URL(string: "https://shop.example.com")
        try ProjectEditor.update(p, name: "Shop 2", summary: "", link: "")
        #expect(p.productionURL != nil)
    }

    @Test func refusesPlainHttpAndJunk() {
        let p = Project.create(name: "Shop", in: context)
        #expect(throws: ProjectEditor.Failure.insecureProductionURL) {
            try ProjectEditor.update(p, name: "Shop", summary: "", link: "", production: "http://shop.example.com")
        }
        #expect(throws: ProjectEditor.Failure.invalidProductionURL) {
            try ProjectEditor.update(p, name: "Shop", summary: "", link: "", production: "not a site")
        }
        #expect(p.productionURL == nil)
    }
}
