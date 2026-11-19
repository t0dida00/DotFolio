import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

/// Fails on the Nth write, to exercise the rollback path.
private final class FailingSecretStore: SecretStore, @unchecked Sendable {
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
}

@MainActor
struct ProjectCreatorTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    private func draft() -> ProjectDraft {
        var d = ProjectDraft()
        d.name = "Shop"
        d.link = "github.com/acme/shop-web"
        d.environmentName = "production"
        d.rows = [
            EnvDraftRow(key: "API_KEY", value: "sk_live_123", service: "Stripe", account: "billing@acme.studio", link: "https://dashboard.stripe.com/apikeys"),
            EnvDraftRow(key: "EMPTY_ONE"),
            EnvDraftRow(key: "DB_URL", value: "postgres://u:p@h/db"),
            EnvDraftRow(), // trailing blank row is ignored
        ]
        return d
    }

    @Test func storesValuesInSecretStoreAndOnlyMetadataInDatabase() throws {
        let secrets = InMemorySecretStore()
        let project = try ProjectCreator.create(draft(), includeValues: true, context: context, secrets: secrets)

        #expect(project.provider == .github)
        #expect(project.repoFullName == "acme/shop-web")
        let prod = try #require(project.sortedEnvironments.first { $0.name == "production" })
        let vars = prod.sortedVariables
        #expect(vars.map(\.key) == ["API_KEY", "DB_URL", "EMPTY_ONE"])

        let api = try #require(vars.first { $0.key == "API_KEY" })
        #expect(api.hasValue)
        #expect(try secrets.string(for: api.secretRef.uuidString) == "sk_live_123")
        #expect(api.sourceURL?.host() == "dashboard.stripe.com")
        #expect(api.serviceLabel == "Stripe")
        #expect(api.account?.login == "billing@acme.studio")
        #expect(api.account?.serviceType == .stripe)

        let empty = try #require(vars.first { $0.key == "EMPTY_ONE" })
        #expect(!empty.hasValue)
        #expect(try secrets.contains(empty.secretRef.uuidString) == false)
    }

    @Test func keychainFailureRollsBackAndCreatesNothing() throws {
        let secrets = FailingSecretStore(failOnWrite: 2)
        #expect(throws: ProjectCreator.Failure.self) {
            try ProjectCreator.create(draft(), includeValues: true, context: context, secrets: secrets)
        }
        // First value was written, then removed by the rollback.
        #expect(secrets.writes == 2)
        #expect(secrets.inner.itemCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 0)
    }

    @Test func createWithoutValuesWritesNoSecrets() throws {
        let secrets = FailingSecretStore(failOnWrite: 1)
        let project = try ProjectCreator.create(draft(), includeValues: false, context: context, secrets: secrets)
        #expect(secrets.writes == 0)
        #expect(project.allVariables.allSatisfy { !$0.hasValue })
        #expect(project.allVariables.count == 3)
    }

    @Test func validationFlagsBadRows() {
        var d = ProjectDraft()
        d.name = "X"
        d.rows = [EnvDraftRow(key: "1BAD"), EnvDraftRow(key: "OK", link: "not a link"), EnvDraftRow(key: "OK")]
        #expect(d.keyIssue(for: d.rows[0]) != nil)
        #expect(d.linkIssue(for: d.rows[1]) != nil)
        #expect(d.keyIssue(for: d.rows[2]) == "Duplicate name")
        #expect(!d.canCreate)

        d.rows = [EnvDraftRow(key: "GOOD", value: "v")]
        #expect(d.canCreate)
        d.name = "  "
        #expect(!d.canCreate)
    }
}
