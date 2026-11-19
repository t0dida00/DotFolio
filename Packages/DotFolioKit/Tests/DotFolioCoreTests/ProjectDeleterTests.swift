import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

private struct UndeletableStore: SecretStore {
    let inner = InMemorySecretStore()
    func setData(_ value: Data, for ref: String, context: LAContext?) throws { try inner.setData(value, for: ref, context: context) }
    func data(for ref: String, context: LAContext?) throws -> Data? { try inner.data(for: ref, context: context) }
    func delete(_ ref: String) throws { throw KeychainError.authenticationFailed }
    func contains(_ ref: String) throws -> Bool { try inner.contains(ref) }
    func deleteAll() throws {}
}

@MainActor
struct ProjectDeleterTests {
    private func make(in context: ModelContext, secrets: any SecretStore, name: String) throws -> Project {
        var draft = ProjectDraft()
        draft.name = name
        draft.rows = [EnvDraftRow(key: "A", value: "1"), EnvDraftRow(key: "B", value: "2"), EnvDraftRow(key: "C")]
        return try ProjectCreator.create(draft, includeValues: true, context: context, secrets: secrets)
    }

    @Test func removesKeychainItemsThenProject() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let secrets = InMemorySecretStore()
        let doomed = try make(in: context, secrets: secrets, name: "Doomed")
        _ = try make(in: context, secrets: secrets, name: "Kept")
        #expect(secrets.itemCount == 4)

        try ProjectDeleter.delete(doomed, context: context, secrets: secrets)

        #expect(secrets.itemCount == 2) // only "Kept" values remain
        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.name) == ["Kept"])
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 3)
    }

    @Test func keychainFailureKeepsProject() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let secrets = UndeletableStore()
        let project = try make(in: context, secrets: secrets, name: "Stuck")
        #expect(throws: ProjectDeleter.Failure.self) {
            try ProjectDeleter.delete(project, context: context, secrets: secrets)
        }
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 1)
        #expect(project.allVariables.filter(\.hasValue).count == 2)
    }
}
