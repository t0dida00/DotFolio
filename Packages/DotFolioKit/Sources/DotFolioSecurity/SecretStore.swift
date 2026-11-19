import Foundation
import LocalAuthentication

/// Storage for secret values (variable values, OAuth tokens), addressed by an
/// opaque reference string. Implemented by `KeychainStore` in the app and by
/// `InMemorySecretStore` in tests and SwiftUI previews.
public protocol SecretStore {
    /// Creates or replaces the value for `ref`.
    func setData(_ value: Data, for ref: String, context: LAContext?) throws
    /// Returns the value, or `nil` when no item exists for `ref`.
    func data(for ref: String, context: LAContext?) throws -> Data?
    /// Removes the item. Deleting a missing item is not an error.
    func delete(_ ref: String) throws
    /// Whether an item exists, checked WITHOUT reading (or authenticating for) its value.
    func contains(_ ref: String) throws -> Bool
    /// Removes every item owned by this store (e.g. "erase all data").
    func deleteAll() throws
    /// References of every item this store owns. Reads attributes only —
    /// never values — so it needs no authentication.
    func allRefs() throws -> [String]
}

extension SecretStore {
    /// Stores that can't enumerate (test doubles) report nothing.
    public func allRefs() throws -> [String] { [] }
}

extension SecretStore {
    public func setString(_ value: String, for ref: String, context: LAContext? = nil) throws {
        try setData(Data(value.utf8), for: ref, context: context)
    }

    public func string(for ref: String, context: LAContext? = nil) throws -> String? {
        guard let data = try data(for: ref, context: context) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
        return string
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    /// The item is protected and no authenticated `LAContext` was supplied.
    case authenticationRequired
    case authenticationFailed
    case userCanceled
    /// The binary is not signed with the keychain entitlements (data protection keychain).
    case missingEntitlement
    case invalidData
    case accessControlCreationFailed
    case unexpectedStatus(OSStatus)
}

/// Thread-safe in-memory store for tests and previews. Never use in production:
/// values are kept unencrypted in process memory.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    /// Number of stored items (tests use it to prove nothing was left behind).
    public var itemCount: Int { lock.withLock { storage.count } }

    public func setData(_ value: Data, for ref: String, context: LAContext?) throws {
        lock.withLock { storage[ref] = value }
    }

    public func data(for ref: String, context: LAContext?) throws -> Data? {
        lock.withLock { storage[ref] }
    }

    public func delete(_ ref: String) throws {
        _ = lock.withLock { storage.removeValue(forKey: ref) }
    }

    public func contains(_ ref: String) throws -> Bool {
        lock.withLock { storage[ref] != nil }
    }

    public func deleteAll() throws {
        lock.withLock { storage.removeAll() }
    }

    public func allRefs() throws -> [String] {
        lock.withLock { Array(storage.keys) }
    }
}
