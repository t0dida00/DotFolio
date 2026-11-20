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

    @Test func importFillsColumnsFromSourceComments() {
        var draft = ProjectDraft()
        draft.rows = [EnvDraftRow(key: "B", value: "typed")]
        let entries = EnvParser.parse("""
        A='one' #AI/OpenAI/me@x.com/https://platform.openai.com/api-keys
        B=two #Database/Supabase
        C=3
        """)
        let result = draft.importEntries(entries, into: "development", includeValues: true)

        #expect(result == .init(added: 2, filled: 1, skipped: []))
        let a = draft.filledRows.first { $0.key == "A" }
        #expect(a?.category == "AI" && a?.service == "OpenAI" && a?.account == "me@x.com")
        #expect(a?.link == "https://platform.openai.com/api-keys")
        let b = draft.filledRows.first { $0.key == "B" }
        #expect(b?.value == "typed" && b?.category == "Database" && b?.service == "Supabase")
        let c = draft.filledRows.first { $0.key == "C" }
        #expect(c?.service == "" && c?.category == "")
    }

    // MARK: Library

    private let commented = EnvParser.parse("""
    test='this is a test' #AI/JEV/me@gmail.com
    test2='this is another test' #AI/ClaudeCode/me@gmail.com/https://console.anthropic.com
    PLAIN=value
    BAD_LINK=x #AI/JEV//not a link
    """)

    @Test func libraryImportUsesEachLinesProviderAndOther() throws {
        let secrets = InMemorySecretStore()
        let result = try LibraryImporter.importKeys(commented, context: context, secrets: secrets)

        #expect(result.added == 4)
        #expect(result.invalidLinks == ["BAD_LINK"])
        #expect(Library.keys(provider: "JEV", context: context).map(\.key).sorted() == ["BAD_LINK", "test"])
        let claude = try #require(Library.keys(provider: "ClaudeCode", context: context).first)
        #expect(claude.key == "test2" && claude.serviceCategory == "AI")
        #expect(claude.account?.login == "me@gmail.com")
        #expect(claude.sourceURL?.absoluteString == "https://console.anthropic.com")
        #expect(try secrets.string(for: claude.secretRef.uuidString) == "this is another test")
        // No provider → the "Other" group (empty provider).
        #expect(Library.keys(provider: "", context: context).map(\.key) == ["PLAIN"])
        // One login, both providers.
        #expect(Set(claude.account?.services ?? []) == ["JEV", "ClaudeCode"])
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func libraryImportSkipsExistingNamesPerProvider() throws {
        let secrets = InMemorySecretStore()
        let old = try VariableEditor.addToLibrary(key: "test", value: "old", provider: "jev", context: context, secrets: secrets)
        let result = try LibraryImporter.importKeys(commented, context: context, secrets: secrets)

        #expect(result.skipped == ["test"])
        #expect(try secrets.string(for: old.secretRef.uuidString) == "old") // never overwritten
    }

    @Test func libraryImportIsAllOrNothing() throws {
        let secrets = FailOnWriteStore(failOnWrite: 2)
        #expect(throws: VariableEditor.Failure.self) {
            try LibraryImporter.importKeys(file, context: context, secrets: secrets)
        }
        #expect(Library.keys(context: context).isEmpty)
        #expect(try secrets.allRefs().isEmpty)
    }

    @Test func libraryTemplateImportHasNoValues() throws {
        let secrets = InMemorySecretStore()
        try LibraryImporter.importKeys(file, includeValues: false, context: context, secrets: secrets)
        #expect(Library.keys(context: context).allSatisfy { !$0.hasValue })
        #expect(try secrets.allRefs().isEmpty)
    }
}
