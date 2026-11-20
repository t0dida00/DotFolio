import DotFolioEnv
import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

/// Fails on the Nth write, to exercise the rollback path.
private final class FailOnWriteStore: SecretStore, @unchecked Sendable {
    let inner = InMemorySecretStore()
    let failOnWrite: Int
    private(set) var writes = 0
    init(failOnWrite: Int) { self.failOnWrite = failOnWrite }

    func setData(_ value: Data, for ref: String, context: LAContext?) throws {
        writes += 1
        if writes == failOnWrite { throw KeychainError.missingEntitlement }
        try inner.setData(value, for: ref, context: context)
    }
    func data(for ref: String, context: LAContext?) throws -> Data? { try inner.data(for: ref, context: context) }
    func delete(_ ref: String) throws { try inner.delete(ref) }
    func contains(_ ref: String) throws -> Bool { try inner.contains(ref) }
    func deleteAll() throws { try inner.deleteAll() }
    func allRefs() throws -> [String] { try inner.allRefs() }
}

@MainActor
struct EnvImportTests {
    let context: ModelContext

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    private let file = [
        EnvEntry(key: "API_KEY", value: "sk_1"),
        EnvEntry(key: "DB_URL", value: "postgres://x"),
        EnvEntry(key: "EMPTY", value: ""),
    ]

    // MARK: New Project draft

    @Test func importAddsRowsAndKeepsWhatWasTyped() {
        var draft = ProjectDraft()
        draft.rows = [EnvDraftRow(key: "API_KEY", value: "typed"), EnvDraftRow(key: "DB_URL"), EnvDraftRow()]
        let result = draft.importEntries(file, into: "development", includeValues: true)

        #expect(result == .init(added: 1, filled: 1, skipped: ["API_KEY"]))
        #expect(draft.filledRows.map(\.key) == ["API_KEY", "DB_URL", "EMPTY"])
        #expect(draft.filledRows.map(\.value) == ["typed", "postgres://x", ""])
        #expect(draft.rows.last?.isBlank == true) // fresh row to keep typing
    }

    @Test func templatesImportNamesOnly() {
        var draft = ProjectDraft()
        draft.importEntries(file, into: "development", includeValues: false)
        #expect(draft.filledRows.allSatisfy { $0.value.isEmpty })
    }

    @Test func eachEnvironmentKeepsItsOwnRows() {
        var draft = ProjectDraft()
        draft.importEntries([EnvEntry(key: "A", value: "dev")], into: "development", includeValues: true)
        draft.importEntries([EnvEntry(key: "A", value: "prod")], into: "production", includeValues: true)

        #expect(draft.environmentsWithRows == ["development", "production"])
        draft.environmentName = "production"
        #expect(draft.filledRows.map(\.value) == ["prod"])
        draft.environmentName = "staging"
        #expect(draft.rows.count == 1 && draft.rows[0].isBlank)
    }

    @Test func createBlockedByIssueInAnotherEnvironment() {
        var draft = ProjectDraft()
        draft.name = "Shop"
        draft.rowsByEnvironment["production"] = [EnvDraftRow(key: "1BAD")]
        #expect(!draft.canCreate)
        #expect(draft.otherEnvironmentsWithIssues == ["production"])
        draft.rowsByEnvironment["production"] = [EnvDraftRow(key: "GOOD")]
        #expect(draft.canCreate)
    }

    @Test func createWritesEveryEnvironment() throws {
        let secrets = InMemorySecretStore()
        var draft = ProjectDraft()
        draft.name = "Shop"
        draft.importEntries([EnvEntry(key: "A", value: "dev")], into: "development", includeValues: true)
        draft.importEntries([EnvEntry(key: "A", value: "prod"), EnvEntry(key: "B", value: "")], into: "production", includeValues: true)

        let project = try ProjectCreator.create(draft, includeValues: true, context: context, secrets: secrets)
        let envs = Dictionary(uniqueKeysWithValues: project.sortedEnvironments.map { ($0.name, $0) })
        #expect(envs["development"]?.sortedVariables.map(\.key) == ["A"])
        #expect(envs["production"]?.sortedVariables.map(\.key) == ["A", "B"])
        #expect(envs["staging"]?.sortedVariables.isEmpty == true)

        let prodA = try #require(envs["production"]?.sortedVariables.first)
        #expect(try secrets.string(for: prodA.secretRef.uuidString) == "prod")
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    // MARK: Library

    @Test func libraryImportAddsUnderProviderAndSkipsExisting() throws {
        let secrets = InMemorySecretStore()
        try VariableEditor.addToLibrary(key: "API_KEY", value: "old", provider: "Stripe", context: context, secrets: secrets)

        let result = try LibraryImporter.importKeys(file, provider: "stripe", category: "Payments",
                                                    context: context, secrets: secrets)
        #expect(result == .init(added: 2, skipped: ["API_KEY"]))
        let keys = Library.keys(provider: "Stripe", context: context)
        #expect(Set(keys.map(\.key)) == ["API_KEY", "DB_URL", "EMPTY"])
        let old = try #require(keys.first { $0.key == "API_KEY" })
        #expect(try secrets.string(for: old.secretRef.uuidString) == "old") // never overwritten
        let db = try #require(keys.first { $0.key == "DB_URL" })
        #expect(try secrets.string(for: db.secretRef.uuidString) == "postgres://x")
        #expect(keys.first { $0.key == "EMPTY" }?.hasValue == false)
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func libraryImportIsAllOrNothing() throws {
        let secrets = FailOnWriteStore(failOnWrite: 2)
        #expect(throws: VariableEditor.Failure.self) {
            try LibraryImporter.importKeys(file, provider: "Stripe", context: context, secrets: secrets)
        }
        #expect(Library.keys(context: context).isEmpty)
        #expect(try secrets.allRefs().isEmpty)
    }

    @Test func libraryTemplateImportHasNoValues() throws {
        let secrets = InMemorySecretStore()
        try LibraryImporter.importKeys(file, provider: "Stripe", includeValues: false, context: context, secrets: secrets)
        #expect(Library.keys(context: context).allSatisfy { !$0.hasValue })
        #expect(try secrets.allRefs().isEmpty)
    }
}
