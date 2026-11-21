import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity

@MainActor
struct FolderReloadTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let project: Project

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        project = Project.create(name: "Shop", in: context)
    }

    private func env(_ name: String) -> ProjectEnvironment { project.sortedEnvironments.first { $0.name == name }! }
    private func file(_ path: String, _ text: String) -> FolderReload.File { .init(path: path, entries: EnvParser.parse(text)) }
    private func values() throws -> [UUID: String] {
        var out: [UUID: String] = [:]
        for v in project.allVariables where v.hasValue {
            out[v.id] = try VariableEditor.value(of: v, secrets: secrets, context: LAContext())
        }
        return out
    }

    @Test func reportsAddedChangedAndRemovedPerEnvironment() throws {
        try VariableEditor.add(key: "SAME", value: "1", service: "Stripe", to: env("development"), context: context, secrets: secrets)
        try VariableEditor.add(key: "CHANGED", value: "old", to: env("development"), context: context, secrets: secrets)
        try VariableEditor.add(key: "GONE", value: "x", to: env("development"), context: context, secrets: secrets)
        try VariableEditor.add(key: "PROD_ONLY", value: "p", to: env("production"), context: context, secrets: secrets)
        try context.save()

        let result = FolderReload.compare(project, files: [
            file(".env", "SAME=1\nCHANGED=old\nNEW=n\n"),
            file(".env.local", "CHANGED=new\n"),            // later file wins
            file(".env.example", "SAME=\n"),
        ], currentValues: try values())

        #expect(result.checked == ["development"])          // production has no file: untouched
        #expect(result.ignored == [".env.example"])
        #expect(result.changes.count == 1)
        let plan = result.changes[0].plan
        #expect(plan.added.map(\.key) == ["NEW"])
        #expect(plan.values == ["CHANGED": "new"])           // SAME didn't change
        #expect(plan.sources.isEmpty)                         // no comment in the file: keep "Stripe"
        #expect(plan.removed == ["GONE"])
        #expect(result.changes[0].files == [".env", ".env.local"])
    }

    @Test func applyKeepsUntickedRemovals() throws {
        try VariableEditor.add(key: "KEEP", value: "k", to: env("development"), context: context, secrets: secrets)
        try VariableEditor.add(key: "DROP", value: "d", to: env("development"), context: context, secrets: secrets)
        try context.save()
        let result = FolderReload.compare(project, files: [file(".env", "NEW=n #Cache/Redis\n")], currentValues: try values())
        try FolderReload.apply(result.changes[0], removing: ["DROP"], context: context, secrets: secrets)
        try context.save()
        #expect(env("development").sortedVariables.map(\.key) == ["KEEP", "NEW"])
        #expect(env("development").sortedVariables.first { $0.key == "NEW" }?.serviceLabel == "Redis")
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func nothingToDoWhenTheFolderMatches() throws {
        try VariableEditor.add(key: "A", value: "1", to: env("development"), context: context, secrets: secrets)
        try context.save()
        let result = FolderReload.compare(project, files: [file(".env", "A=1\n")], currentValues: try values())
        #expect(result.isEmpty)
        #expect(result.checked == ["development"])
    }
}
