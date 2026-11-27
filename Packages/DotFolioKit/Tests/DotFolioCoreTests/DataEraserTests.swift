import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

private struct BrokenStore: SecretStore {
    func setData(_ value: Data, for ref: String, context: LAContext?) throws {}
    func data(for ref: String, context: LAContext?) throws -> Data? { nil }
    func delete(_ ref: String) throws {}
    func contains(_ ref: String) throws -> Bool { false }
    func deleteAll() throws { throw KeychainError.authenticationFailed }
}

@MainActor
struct DataEraserTests {
    private func seeded() throws -> (ModelContext, InMemorySecretStore) {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let secrets = InMemorySecretStore()
        var draft = ProjectDraft()
        draft.name = "Shop"
        draft.rows = [EnvDraftRow(key: "API_KEY", value: "secret")]
        try ProjectCreator.create(draft, includeValues: true, context: context, secrets: secrets)
        context.insert(Account(serviceType: .stripe, login: "a@b.c"))
        try context.save()
        return (context, secrets)
    }

    @Test func erasesSecretsAndAllMetadata() throws {
        let (context, secrets) = try seeded()
        #expect(secrets.itemCount == 1)
        NotificationFeed.post(.siteDown, title: "Shop is down", body: "", projectID: nil, context: context)

        try DataEraser.eraseAll(context: context, secretStores: [secrets])

        #expect(secrets.itemCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ProjectEnvironment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AppNotification>()) == 0)
    }

    @Test func keychainFailureKeepsDatabase() throws {
        let (context, _) = try seeded()
        #expect(throws: DataEraser.Failure.self) {
            try DataEraser.eraseAll(context: context, secretStores: [BrokenStore()])
        }
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 1)
    }
}
