import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

/// Behaves like the real Keychain for `.userPresence` items: adding and
/// deleting work without authentication, overwriting an existing item doesn't.
final class NoOverwriteStore: SecretStore, @unchecked Sendable {
    let inner = InMemorySecretStore()
    func setData(_ value: Data, for ref: String, context: LAContext?) throws {
        if try inner.contains(ref) { throw KeychainError.authenticationRequired }
        try inner.setData(value, for: ref, context: context)
    }
    func data(for ref: String, context: LAContext?) throws -> Data? { try inner.data(for: ref, context: context) }
    func delete(_ ref: String) throws { try inner.delete(ref) }
    func contains(_ ref: String) throws -> Bool { try inner.contains(ref) }
    func deleteAll() throws { try inner.deleteAll() }
}

@MainActor
struct VariableEditorTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let env: ProjectEnvironment

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
    }

    @Test func addStoresValueInSecretStoreOnly() throws {
        let v = try VariableEditor.add(key: " API_KEY ", value: "s3cret", link: "dashboard.stripe.com", to: env, context: context, secrets: secrets)
        #expect(v.key == "API_KEY")
        #expect(v.hasValue)
        #expect(v.sourceURL?.absoluteString == "https://dashboard.stripe.com")
        #expect(try secrets.string(for: v.secretRef.uuidString) == "s3cret")
        #expect(env.variables?.count == 1)
    }

    @Test func addRejectsInvalidAndDuplicateKeys() throws {
        try VariableEditor.add(key: "A", to: env, context: context, secrets: secrets)
        #expect(throws: VariableEditor.Failure.invalidKey) {
            try VariableEditor.add(key: "1A", to: env, context: context, secrets: secrets)
        }
        #expect(throws: VariableEditor.Failure.duplicateKey("A")) {
            try VariableEditor.add(key: "A", to: env, context: context, secrets: secrets)
        }
        #expect(throws: VariableEditor.Failure.invalidLink) {
            try VariableEditor.add(key: "B", link: "not a link", to: env, context: context, secrets: secrets)
        }
        #expect(env.variables?.count == 1)
        #expect(secrets.itemCount == 0)
    }

    @Test func renameValidatesAgainstSiblings() throws {
        let a = try VariableEditor.add(key: "A", to: env, context: context, secrets: secrets)
        try VariableEditor.add(key: "B", to: env, context: context, secrets: secrets)
        #expect(throws: VariableEditor.Failure.duplicateKey("B")) { try VariableEditor.rename(a, to: "B") }
        try VariableEditor.rename(a, to: "A") // renaming to itself is fine
        try VariableEditor.rename(a, to: "C")
        #expect(a.key == "C")
    }

    @Test func setValueWritesAndClears() throws {
        let v = try VariableEditor.add(key: "A", to: env, context: context, secrets: secrets)
        #expect(!v.hasValue)
        try VariableEditor.setValue(v, to: "one", secrets: secrets)
        try VariableEditor.setValue(v, to: "two", secrets: secrets)
        #expect(try secrets.string(for: v.secretRef.uuidString) == "two")
        #expect(secrets.itemCount == 1)

        try VariableEditor.setValue(v, to: "", secrets: secrets)
        #expect(!v.hasValue)
        #expect(secrets.itemCount == 0)
    }

    @Test func replacingAValueNeverOverwritesTheProtectedItem() throws {
        let store = NoOverwriteStore()
        let v = try VariableEditor.add(key: "A", value: "one", to: env, context: context, secrets: store)
        let firstRef = v.secretRef
        try VariableEditor.setValue(v, to: "two", secrets: store) // would throw if it updated in place
        #expect(v.secretRef != firstRef)
        #expect(try store.string(for: v.secretRef.uuidString) == "two")
        #expect(store.inner.itemCount == 1) // old item removed
        try VariableEditor.setValue(v, to: "", secrets: store)
        #expect(!v.hasValue)
        #expect(store.inner.itemCount == 0)
    }

    @Test func setLinkValidatesAndClears() throws {
        let v = try VariableEditor.add(key: "A", to: env, context: context, secrets: secrets)
        try VariableEditor.setLink(v, to: "https://console.firebase.google.com")
        #expect(v.sourceURL?.host() == "console.firebase.google.com")
        #expect(throws: VariableEditor.Failure.invalidLink) { try VariableEditor.setLink(v, to: "nope nope") }
        try VariableEditor.setLink(v, to: "  ")
        #expect(v.sourceURL == nil)
    }

    @Test func deleteRemovesSecretThenVariable() throws {
        let v = try VariableEditor.add(key: "A", value: "x", to: env, context: context, secrets: secrets)
        try context.save()
        try VariableEditor.delete(v, context: context, secrets: secrets)
        try context.save()
        #expect(secrets.itemCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 0)
    }

    @Test func readValueUsesSecretStore() throws {
        let v = try VariableEditor.add(key: "A", value: "x", to: env, context: context, secrets: secrets)
        #expect(try VariableEditor.value(of: v, secrets: secrets, context: LAContext()) == "x")
    }
}

@MainActor
struct VariableServiceAccountTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let env: ProjectEnvironment

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
    }

    @Test func addLinksServiceAndAccount() throws {
        let v = try VariableEditor.add(key: "FIREBASE_KEY", service: "Firebase", account: "dev@acme.studio", to: env, context: context, secrets: secrets)
        #expect(v.serviceLabel == "Firebase")
        #expect(v.account?.login == "dev@acme.studio")
        #expect(v.account?.serviceType == .firebase)
    }

    @Test func accountsAreReusedCaseInsensitively() throws {
        let a = try VariableEditor.add(key: "A", account: "dev@acme.studio", to: env, context: context, secrets: secrets)
        let b = try VariableEditor.add(key: "B", account: "DEV@acme.studio", to: env, context: context, secrets: secrets)
        #expect(a.account?.persistentModelID == b.account?.persistentModelID)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        // The reverse lookup works: this account is used by the Shop project.
        #expect(a.account?.linkedProjects.map(\.name) == ["Shop"])
    }

    @Test func customServiceCreatesCustomAccount() throws {
        let v = try VariableEditor.add(key: "DB_URL", service: "DB", account: "admin", to: env, context: context, secrets: secrets)
        #expect(v.account?.serviceType == .custom)
        #expect(v.account?.serviceName == "DB")
        #expect(v.displayService == "DB")
    }

    @Test func setAccountAndServiceEditAndUnlink() throws {
        let v = try VariableEditor.add(key: "A", to: env, context: context, secrets: secrets)
        VariableEditor.setService(v, to: " Stripe ")
        #expect(v.serviceLabel == "Stripe")
        VariableEditor.setAccount(v, login: "billing@acme.studio", context: context)
        #expect(v.account?.serviceType == .stripe)
        VariableEditor.setAccount(v, login: "", context: context)
        #expect(v.account == nil)
    }

    @Test func sameLoginCollectsServicesAcrossVariables() throws {
        let a = try VariableEditor.add(key: "FIREBASE_KEY", service: "Firebase", account: "me@gmail.com", to: env, context: context, secrets: secrets)
        let b = try VariableEditor.add(key: "MAPS_KEY", service: "Google Maps", account: "me@gmail.com", to: env, context: context, secrets: secrets)
        #expect(a.account?.persistentModelID == b.account?.persistentModelID)
        #expect(a.account?.services == ["Firebase", "Google Maps"])
        VariableEditor.setService(b, to: "Google Cloud")
        #expect(a.account?.services == ["Firebase", "Google Maps", "Google Cloud"])
        // Each variable shows its own service, not the account's first one.
        #expect(b.displayService == "Google Cloud")
    }

    @Test func searchFindsServiceLabel() throws {
        let project = env.project!
        try VariableEditor.add(key: "DATABASE_URL", service: "Postgres", to: env, context: context, secrets: secrets)
        #expect(ProjectSearch.match(project, query: "postgres") == .service("Postgres"))
    }
}
