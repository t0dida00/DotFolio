import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

@MainActor
struct LibraryTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
    }

    @Test func addsKeysWithValuesInTheSecretStoreOnly() throws {
        let k = try VariableEditor.addToLibrary(key: "OPENAI_API_KEY", value: "sk-123", category: "ai", provider: "OpenAI",
                                                account: "me@gmail.com", context: context, secrets: secrets)
        #expect(k.inLibrary)
        #expect(k.environment == nil && k.project == nil)
        #expect(k.serviceCategory == "AI")
        #expect(k.account?.services == ["OpenAI"])
        #expect(try secrets.string(for: k.secretRef.uuidString) == "sk-123")
        #expect(Library.keys(context: context).map(\.key) == ["OPENAI_API_KEY"])
    }

    @Test func namesAreUniquePerProvider() throws {
        try VariableEditor.addToLibrary(key: "API_KEY", provider: "OpenAI", context: context, secrets: secrets)
        try VariableEditor.addToLibrary(key: "API_KEY", provider: "Anthropic", context: context, secrets: secrets) // allowed
        #expect(throws: VariableEditor.Failure.duplicateKey("API_KEY")) {
            try VariableEditor.addToLibrary(key: "API_KEY", provider: "openai", context: context, secrets: secrets)
        }
        #expect(throws: VariableEditor.Failure.invalidKey) {
            try VariableEditor.addToLibrary(key: "1BAD", provider: "OpenAI", context: context, secrets: secrets)
        }
    }

    @Test func renameAndMoveRespectProviderScope() throws {
        let a = try VariableEditor.addToLibrary(key: "A", provider: "OpenAI", context: context, secrets: secrets)
        try VariableEditor.addToLibrary(key: "B", provider: "OpenAI", context: context, secrets: secrets)
        try VariableEditor.addToLibrary(key: "A", provider: "Stripe", context: context, secrets: secrets)
        #expect(throws: VariableEditor.Failure.duplicateKey("B")) { try VariableEditor.rename(a, to: "B") }
        try VariableEditor.rename(a, to: "C")
        #expect(a.key == "C")
        try VariableEditor.setLibraryProvider(a, to: "Anthropic", context: context)
        #expect(a.serviceLabel == "Anthropic")
        try VariableEditor.rename(a, to: "A") // free under Anthropic
        #expect(throws: VariableEditor.Failure.duplicateKey("A")) {
            try VariableEditor.setLibraryProvider(a, to: "Stripe", context: context)
        }
    }

    @Test func replacingAndDeletingValues() throws {
        let k = try VariableEditor.addToLibrary(key: "K", value: "one", provider: "Stripe", context: context, secrets: secrets)
        let first = k.secretRef
        try VariableEditor.setValue(k, to: "two", secrets: secrets)
        #expect(k.secretRef != first)
        #expect(secrets.itemCount == 1)
        try VariableEditor.delete(k, context: context, secrets: secrets)
        #expect(secrets.itemCount == 0)
    }

    @Test func copiesIntoAProjectAsIndependentValues() throws {
        let k = try VariableEditor.addToLibrary(key: "STRIPE_KEY", value: "sk_test", category: "payments", provider: "Stripe",
                                                link: "https://dashboard.stripe.com", context: context, secrets: secrets)
        let env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
        let result = try VariableCopier.copy([k], to: env, includeValues: true, context: context, secrets: secrets, authContext: LAContext())
        #expect(result.copied == 1)
        let copy = try #require(env.variables?.first)
        #expect(!copy.inLibrary)
        #expect(copy.serviceLabel == "Stripe" && copy.serviceCategory == "Payments")
        #expect(copy.secretRef != k.secretRef)
        #expect(try secrets.string(for: copy.secretRef.uuidString) == "sk_test")
        // The library key is untouched and still in the library.
        #expect(Library.keys(context: context).count == 1)
        // Copying again skips the existing name.
        #expect(try VariableCopier.copy([k], to: env, includeValues: false, context: context, secrets: secrets).skipped == ["STRIPE_KEY"])
    }

    @Test func integrityCheckKeepsLibraryKeys() throws {
        try VariableEditor.addToLibrary(key: "K", value: "v", provider: "OpenAI", context: context, secrets: secrets)
        try context.save()
        let report = try IntegrityCheck.run(context: context, secrets: secrets)
        #expect(report.isClean)
        try IntegrityCheck.repair(report, context: context, secrets: secrets)
        #expect(Library.keys(context: context).count == 1)
        #expect(secrets.itemCount == 1)
    }

    @Test func integrityReportsLibraryDuplicates() throws {
        try VariableEditor.addToLibrary(key: "K", provider: "OpenAI", context: context, secrets: secrets)
        let twin = Variable(key: "K", environment: nil)
        twin.inLibrary = true
        twin.serviceLabel = "OpenAI"
        context.insert(twin)
        try context.save()
        let report = try IntegrityCheck.run(context: context, secrets: secrets)
        #expect(report.duplicateKeys == [.init(project: "Library", environment: "OpenAI", key: "K")])
        #expect(report.fixableCount == 0)
    }

    @Test func eraseAllRemovesLibrary() throws {
        try VariableEditor.addToLibrary(key: "K", value: "v", provider: "OpenAI", context: context, secrets: secrets)
        try context.save()
        try DataEraser.eraseAll(context: context, secretStores: [secrets])
        #expect(Library.keys(context: context).isEmpty)
        #expect(secrets.itemCount == 0)
    }

    @Test func searchCoversMetadataOnly() throws {
        try VariableEditor.addToLibrary(key: "OPENAI_API_KEY", value: "sk-secret", provider: "OpenAI", context: context, secrets: secrets)
        try VariableEditor.addToLibrary(key: "STRIPE_KEY", provider: "Stripe", context: context, secrets: secrets)
        let all = Library.keys(context: context)
        #expect(Library.filter(all, query: "stripe").map(\.key) == ["STRIPE_KEY"])
        #expect(Library.filter(all, query: "sk-secret").isEmpty) // values are never searched
    }
}
