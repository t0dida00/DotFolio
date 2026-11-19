import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

struct ProjectInputTests {
    @Test(arguments: [
        ("https://github.com/acme/shop-web", RepoProvider.github, "acme/shop-web"),
        ("https://github.com/acme/shop-web.git", .github, "acme/shop-web"),
        ("https://github.com/acme/shop-web/tree/main/src", .github, "acme/shop-web"),
        ("https://gitlab.com/group/sub/repo", .gitlab, "group/sub/repo"),
        ("https://gitlab.com/group/repo/-/issues", .gitlab, "group/repo"),
    ])
    func recognizesRepoLinks(link: String, provider: RepoProvider, fullName: String) throws {
        let repo = try #require(RepoLink(url: URL(string: link)!))
        #expect(repo.provider == provider)
        #expect(repo.fullName == fullName)
    }

    @Test(arguments: ["https://github.com/acme", "https://example.com/acme/shop", "https://github.com"])
    func ignoresNonRepoLinks(link: String) {
        #expect(RepoLink(url: URL(string: link)!) == nil)
    }

    @Test func webURLAcceptsBareHostsAndRejectsJunk() {
        #expect(InputValidation.webURL("github.com/acme/shop")?.absoluteString == "https://github.com/acme/shop")
        #expect(InputValidation.webURL("  https://console.firebase.google.com  ") != nil)
        #expect(InputValidation.webURL("") == nil)
        #expect(InputValidation.webURL("not a url") == nil)
        #expect(InputValidation.webURL("javascript:alert(1)") == nil)
        #expect(InputValidation.webURL("ftp://files.example.com") == nil)
        #expect(InputValidation.webURL("localhost") == nil)
    }

    @Test(arguments: ["API_KEY", "_PRIVATE", "a1", "NEXT_PUBLIC_URL"])
    func acceptsValidEnvKeys(key: String) {
        #expect(InputValidation.isValidEnvKey(key))
    }

    @Test(arguments: ["", "1ABC", "API-KEY", "API KEY", "KHÓA", "A.B"])
    func rejectsInvalidEnvKeys(key: String) {
        #expect(!InputValidation.isValidEnvKey(key))
    }

    @Test func findsDuplicateKeys() {
        #expect(InputValidation.duplicateKeys(["A", "B", "A", "", ""]) == ["A"])
        #expect(InputValidation.duplicateKeys(["a", "A"]).isEmpty)
    }

    @MainActor
    @Test func createFillsRepoFromLink() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let p = Project.create(name: "Shop", summary: "  Storefront  ", link: URL(string: "https://github.com/acme/shop-web"), in: context)
        #expect(p.summary == "Storefront")
        #expect(p.provider == .github)
        #expect(p.repoFullName == "acme/shop-web")

        let site = Project.create(name: "Site", link: URL(string: "https://acme.studio"), in: context)
        #expect(site.provider == RepoProvider.none)
        #expect(site.repoURL?.host() == "acme.studio")
    }
}
