import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels

@MainActor
struct RepoImporterTests {
    let context: ModelContext
    let repo = RepoImporter.RepoInfo(provider: .github, fullName: "acme/shop-web",
                                     url: URL(string: "https://github.com/acme/shop-web")!,
                                     defaultBranch: "main", description: "Storefront")

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    @Test func createsProjectWithKeysInEveryEnvironmentAndNoValues() throws {
        let example = """
        # Firebase web key
        FIREBASE_API_KEY=your-key-here
        DATABASE_URL=postgres://localhost/dev
        """
        let project = RepoImporter.importRepo(repo, envExample: example, envExampleSHA: "sha1", context: context)
        #expect(project.name == "shop-web")
        #expect(project.summary == "Storefront")
        #expect(project.provider == .github)
        #expect(project.repoFullName == "acme/shop-web")
        #expect(project.envExampleKeys == ["FIREBASE_API_KEY", "DATABASE_URL"])
        #expect(project.envExampleSHA == "sha1")
        for env in project.sortedEnvironments {
            #expect(env.sortedVariables.map(\.key) == ["DATABASE_URL", "FIREBASE_API_KEY"])
        }
        // Placeholder values from .env.example are never stored as secrets.
        #expect(project.allVariables.allSatisfy { !$0.hasValue })
        #expect(project.allVariables.first { $0.key == "FIREBASE_API_KEY" }?.notes == "Firebase web key")
    }

    @Test func reimportDoesNotDuplicateAndAddsNewKeys() throws {
        RepoImporter.importRepo(repo, envExample: "A=\n", envExampleSHA: "1", context: context)
        let again = RepoImporter.importRepo(repo, envExample: "A=\nB=\n", envExampleSHA: "2", context: context)
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 1)
        #expect(again.sortedEnvironments[0].sortedVariables.map(\.key) == ["A", "B"])
        #expect(again.envExampleSHA == "2")
    }

    @Test func repoWithoutEnvExampleStillImports() throws {
        let project = RepoImporter.importRepo(repo, envExample: nil, envExampleSHA: nil, context: context)
        #expect(project.allVariables.isEmpty)
        #expect(project.sortedEnvironments.count == 3)
        #expect(RepoImporter.existingProject(for: "ACME/shop-web", provider: .github, context: context) != nil)
    }
}
