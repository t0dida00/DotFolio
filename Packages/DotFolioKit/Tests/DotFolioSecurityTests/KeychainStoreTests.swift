import Foundation
import Testing
@testable import DotFolioSecurity

/// Runs against the real macOS Keychain. Plain `swift test` binaries are not
/// signed with keychain entitlements, so these tests use the legacy (file-based)
/// keychain without `.userPresence`. Each test gets its own random service name
/// and wipes it afterwards, so tests are isolated and leave nothing behind.
/// The `.userPresence` path is covered by app-hosted tests once signing is set up.
struct KeychainStoreTests {
    private func makeStore() -> KeychainStore {
        KeychainStore(configuration: .init(
            service: "app.dotfolio.tests.\(UUID().uuidString)",
            useDataProtectionKeychain: false,
            requireUserPresence: false
        ))
    }

    @Test func roundTripsAValue() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            try store.setString("AIzaSy-secret", for: "ref-1")
            #expect(try store.string(for: "ref-1") == "AIzaSy-secret")
        }
    }

    @Test func missingItemReturnsNil() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            #expect(try store.string(for: "does-not-exist") == nil)
            #expect(try store.contains("does-not-exist") == false)
        }
    }

    @Test func overwritesExistingValue() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            try store.setString("old", for: "ref")
            try store.setString("new", for: "ref")
            #expect(try store.string(for: "ref") == "new")
        }
    }

    @Test func deletesValue() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            try store.setString("value", for: "ref")
            try store.delete("ref")
            #expect(try store.string(for: "ref") == nil)
        }
    }

    @Test func deletingMissingItemIsNotAnError() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            try store.delete("never-existed")
        }
    }

    @Test func containsDoesNotNeedTheValue() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            try store.setString("value", for: "ref")
            #expect(try store.contains("ref"))
        }
    }

    @Test(arguments: [
        "",
        "multi\nline\nvalue",
        "-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n",
        "unicode ✓ tiếng Việt 🔐",
        "quotes \"double\" 'single' and = signs",
    ])
    func preservesValuesExactly(value: String) throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            try store.setString(value, for: "ref")
            #expect(try store.string(for: "ref") == value)
        }
    }

    @Test func storesBinaryData() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        do {
            let bytes = Data((0...255).map(UInt8.init))
            try store.setData(bytes, for: "bin", context: nil)
            #expect(try store.data(for: "bin", context: nil) == bytes)
        }
    }

    @Test func servicesAreIsolated() throws {
        let a = makeStore()
        let b = makeStore()
        defer { try? a.deleteAll(); try? b.deleteAll() }

        try a.setString("from-a", for: "same-ref")
        #expect(try b.string(for: "same-ref") == nil)

        try b.setString("from-b", for: "same-ref")
        #expect(try a.string(for: "same-ref") == "from-a")
        #expect(try b.string(for: "same-ref") == "from-b")
    }

    @Test func deleteAllRemovesOnlyItsOwnService() throws {
        let a = makeStore()
        let b = makeStore()
        defer { try? b.deleteAll() }

        for i in 0..<5 { try a.setString("v\(i)", for: "ref-\(i)") }
        try b.setString("keep", for: "ref-0")

        try a.deleteAll()

        for i in 0..<5 { #expect(try a.contains("ref-\(i)") == false) }
        #expect(try b.string(for: "ref-0") == "keep")
    }

    @Test func listsRefsWithoutReadingValues() throws {
        let store = makeStore()
        defer { try? store.deleteAll() }
        #expect(try store.allRefs().isEmpty)
        try store.setString("a", for: "ref-1")
        try store.setString("b", for: "ref-2")
        #expect(Set(try store.allRefs()) == ["ref-1", "ref-2"])
    }

    @Test func deleteAllOnEmptyServiceSucceeds() throws {
        try makeStore().deleteAll()
    }
}

struct InMemorySecretStoreTests {
    @Test func behavesLikeASecretStore() throws {
        let store = InMemorySecretStore()
        try store.setString("v", for: "r")
        #expect(try store.string(for: "r") == "v")
        #expect(try store.contains("r"))
        try store.delete("r")
        #expect(try store.string(for: "r") == nil)
    }
}
