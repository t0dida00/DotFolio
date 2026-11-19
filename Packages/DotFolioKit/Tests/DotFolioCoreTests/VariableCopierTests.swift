import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

@MainActor
struct VariableCopierTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let dev: ProjectEnvironment
    let staging: ProjectEnvironment

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let envs = Project.create(name: "Shop", in: context).sortedEnvironments
        dev = envs[0]; staging = envs[1]
        try VariableEditor.add(key: "API_KEY", value: "dev-key", service: "Stripe", account: "dev@acme.studio",
                               link: "https://dashboard.stripe.com", to: dev, context: context, secrets: secrets)
        try VariableEditor.add(key: "DB_URL", value: "postgres://dev", to: dev, context: context, secrets: secrets)
        try VariableEditor.add(key: "EMPTY", to: dev, context: context, secrets: secrets)
    }

    @Test func namesOnlyCopiesMetadataWithoutValues() throws {
        let result = try VariableCopier.copy(dev.sortedVariables, to: staging, includeValues: false, context: context, secrets: secrets)
        #expect(result == .init(copied: 3, skipped: []))
        let api = try #require(staging.variables?.first { $0.key == "API_KEY" })
        #expect(!api.hasValue)
        #expect(api.serviceLabel == "Stripe")
        #expect(api.account?.login == "dev@acme.studio")
        #expect(api.sourceURL?.host() == "dashboard.stripe.com")
        #expect(secrets.itemCount == 2) // only the originals
    }

    @Test func valuesAreCopiedIntoIndependentItems() throws {
        try VariableCopier.copy(dev.sortedVariables, to: staging, includeValues: true, context: context, secrets: secrets, authContext: LAContext())
        let original = try #require(dev.variables?.first { $0.key == "API_KEY" })
        let copy = try #require(staging.variables?.first { $0.key == "API_KEY" })
        #expect(copy.hasValue)
        #expect(copy.secretRef != original.secretRef)
        #expect(try secrets.string(for: copy.secretRef.uuidString) == "dev-key")

        // Editing the copy leaves the original alone.
        try VariableEditor.setValue(copy, to: "staging-key", secrets: secrets)
        #expect(try secrets.string(for: original.secretRef.uuidString) == "dev-key")
        #expect(secrets.itemCount == 4)
    }

    @Test func existingKeysAreSkippedNotOverwritten() throws {
        try VariableEditor.add(key: "DB_URL", value: "postgres://staging", to: staging, context: context, secrets: secrets)
        let result = try VariableCopier.copy(dev.sortedVariables, to: staging, includeValues: true, context: context, secrets: secrets, authContext: LAContext())
        #expect(result == .init(copied: 2, skipped: ["DB_URL"]))
        let db = try #require(staging.variables?.first { $0.key == "DB_URL" })
        #expect(try secrets.string(for: db.secretRef.uuidString) == "postgres://staging")
    }
}
