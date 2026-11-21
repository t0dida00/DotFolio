import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity

@MainActor
struct FolderImportTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    private func source(_ path: String, _ text: String, _ env: String?) -> FolderImport.Source {
        FolderImport.Source(relativePath: path, entries: EnvParser.parse(text), environment: env)
    }

    @Test func laterFileWinsAndTemplatesGiveNamesEverywhere() {
        let merged = FolderImport.merge([
            source(".env", "DB_URL=postgres://a\nPORT=3000\n", "development"),
            source(".env.local", "DB_URL=postgres://local #Database/Supabase\n", "development"),
            source(".env.production", "DB_URL=postgres://prod\n", "production"),
            source(".env.example", "DB_URL=changeme\nSENTRY_DSN=xxx\n", nil),
        ])
        let dev = merged.rowsByEnvironment["development"] ?? []
        #expect(dev.map(\.key) == ["DB_URL", "PORT", "SENTRY_DSN"])
        #expect(dev.first { $0.key == "DB_URL" }?.value == "postgres://local")
        #expect(dev.first { $0.key == "DB_URL" }?.service == "Supabase")
        #expect(dev.first { $0.key == "SENTRY_DSN" }?.value == "")
        #expect(merged.rowsByEnvironment["staging"]?.map(\.key) == ["DB_URL", "SENTRY_DSN"])
        #expect(merged.rowsByEnvironment["staging"]?.allSatisfy { $0.value.isEmpty } == true)
        #expect(merged.rowsByEnvironment["production"]?.first?.value == "postgres://prod")
        #expect(merged.conflicts == [FolderImport.Conflict(environment: "development", key: "DB_URL", keptFrom: ".env.local")])
        #expect(merged.nameCount == 3)
    }

    @Test func createsAProjectWithValuesInTheKeychain() throws {
        let merged = FolderImport.merge([
            source(".env", "API_KEY=sk-1\n", "development"),
            source(".env.production", "API_KEY=sk-2\n", "production"),
        ])
        #expect(FolderImport.problems(in: merged).isEmpty)
        let draft = FolderImport.draft(name: "shop", link: URL(string: "https://github.com/octo/shop"), merged: merged)
        let project = try ProjectCreator.create(draft, includeValues: true, context: context, secrets: secrets)
        try context.save()
        #expect(project.provider == .github)
        #expect(project.repoFullName == "octo/shop")
        let values = try project.allVariables.map { try VariableEditor.value(of: $0, secrets: secrets, context: LAContext()) }
        #expect(Set(values.compactMap { $0 }) == ["sk-1", "sk-2"])
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func dropsLinksThatArentWebAddresses() {
        let merged = FolderImport.merge([source(".env", "A=x #AI/OpenAI/me/not a link\n", "development")])
        #expect(merged.rowsByEnvironment["development"]?.first?.link == "")
        #expect(merged.rowsByEnvironment["development"]?.first?.service == "OpenAI")
        #expect(FolderImport.problems(in: merged).isEmpty)
    }

    @Test func addingToAProjectNeverOverwrites() throws {
        let project = Project.create(name: "Shop", in: context)
        let dev = project.sortedEnvironments[0]
        try VariableEditor.add(key: "KEEP", value: "mine", to: dev, context: context, secrets: secrets)
        try VariableEditor.add(key: "EMPTY", to: dev, context: context, secrets: secrets)

        let merged = FolderImport.merge([source(".env", "KEEP=theirs\nEMPTY=filled\nNEW=n #Cache/Redis\n", "development")])
        let result = try FolderImport.add(merged, to: project, context: context, secrets: secrets)
        try context.save()
        #expect(result == FolderImport.AddResult(addedKeys: ["NEW"], filledKeys: ["EMPTY"], unchangedKeys: ["KEEP"]))

        func value(_ key: String) throws -> String? {
            let v = dev.sortedVariables.first { $0.key == key }!
            return try VariableEditor.value(of: v, secrets: secrets, context: LAContext())
        }
        #expect(try value("KEEP") == "mine")
        #expect(try value("EMPTY") == "filled")
        #expect(try value("NEW") == "n")
        #expect(dev.sortedVariables.first { $0.key == "NEW" }?.serviceLabel == "Redis")
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func folderProjectsAreLocalAndSurviveSignOut() throws {
        let merged = FolderImport.merge([source(".env", "A=1\n", "development")])
        let project = try FolderImport.createProject(name: "iWeather", link: URL(string: "https://github.com/octo/iWeather"),
                                                     merged: merged, folderBookmark: Data([1, 2, 3]),
                                                     context: context, secrets: secrets)
        let fromGitHub = Project.create(name: "Shop", link: URL(string: "https://github.com/octo/shop"), in: context)
        try context.save()
        #expect(project.origin == .local)
        #expect(project.provider == .github)
        #expect(fromGitHub.origin == .github)
        #expect(Project.create(name: "Hand", in: context).origin == .manual)

        let removed = AccountSignOut.projects(provider: .github, login: "octo", repoFullNames: ["octo/iWeather", "octo/shop"], context: context)
        #expect(removed.map(\.name) == ["Shop"])
    }

    @Test func droppedFilesGoToTheEnvironmentTheyWereDroppedOn() throws {
        let project = Project.create(name: "Shop", in: context)
        let staging = project.sortedEnvironments.first { $0.name == "staging" }!
        let files = [
            FolderImport.DroppedFile(name: ".env.production", entries: EnvParser.parse("A=1\n"), isTemplate: false),
            FolderImport.DroppedFile(name: ".env.example", entries: EnvParser.parse("A=x\nB=y\n"), isTemplate: true),
        ]
        let result = try FolderImport.add(files, to: staging, context: context, secrets: secrets)
        try context.save()
        #expect(result.added == 2)
        #expect(staging.sortedVariables.map(\.key) == ["A", "B"])
        #expect(staging.sortedVariables.first { $0.key == "B" }?.hasValue == false)
        #expect(project.sortedEnvironments.filter { $0.name != "staging" }.allSatisfy { ($0.variables ?? []).isEmpty })
        let a = staging.sortedVariables.first { $0.key == "A" }!
        #expect(try VariableEditor.value(of: a, secrets: secrets, context: LAContext()) == "1")
    }
}
