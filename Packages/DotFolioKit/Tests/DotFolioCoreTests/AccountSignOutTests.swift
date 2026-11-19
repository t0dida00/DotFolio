import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

@MainActor
struct AccountSignOutTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    private func repo(_ name: String) -> RepoImporter.RepoInfo {
        .init(provider: .github, fullName: name, url: URL(string: "https://github.com/\(name)")!, defaultBranch: "main", description: nil)
    }

    @Test func findsTaggedAndLegacyImportsButNotHandMadeProjects() throws {
        let tag = AccountSignOut.source(provider: .github, login: "Octo")
        RepoImporter.importRepo(repo("octo/tagged"), envExample: nil, envExampleSHA: nil, source: tag, context: context)
        RepoImporter.importRepo(repo("octo/legacy"), envExample: nil, envExampleSHA: nil, context: context)       // no tag
        RepoImporter.importRepo(repo("other/theirs"), envExample: nil, envExampleSHA: nil, source: "github:other", context: context)
        Project.create(name: "Manual", link: URL(string: "https://github.com/octo/not-listed"), in: context) // hand-made
        Project.create(name: "Plain", in: context)

        let found = AccountSignOut.projects(provider: .github, login: "octo",
                                            repoFullNames: ["octo/tagged", "octo/legacy"], context: context)
        #expect(Set(found.map(\.repoFullName)) == ["octo/tagged", "octo/legacy"])
    }

    @Test func deletingRemovesValuesAndProjects() throws {
        let tag = AccountSignOut.source(provider: .github, login: "octo")
        let project = RepoImporter.importRepo(repo("octo/app"), envExample: "API_KEY=\n", envExampleSHA: "1", source: tag, context: context)
        let variable = try #require(project.allVariables.first)
        try VariableEditor.setValue(variable, to: "secret", secrets: secrets)
        Project.create(name: "Keep me", in: context)
        try context.save()

        let doomed = AccountSignOut.projects(provider: .github, login: "octo", repoFullNames: [], context: context)
        try AccountSignOut.deleteProjects(doomed, context: context, secrets: secrets)

        #expect(secrets.itemCount == 0)
        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.name) == ["Keep me"])
    }
}
