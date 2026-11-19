import Foundation
import LocalAuthentication
import Security

/// Generic-password Keychain wrapper. One instance = one `kSecAttrService`
/// namespace (e.g. "<bundleID>.secret" for variable values, "<bundleID>.oauth"
/// for tokens).
public struct KeychainStore: SecretStore, Sendable {
    public struct Configuration: Sendable {
        public var service: String
        /// Shared access group so the future CLI can read the same items.
        /// Requires the `keychain-access-groups` entitlement (needs a Team ID).
        public var accessGroup: String?
        /// SECURITY: the data protection keychain is the modern, iOS-style
        /// keychain with per-item access control. It requires a signed binary
        /// with entitlements, so plain `swift test` runs turn it off.
        public var useDataProtectionKeychain: Bool
        /// SECURITY: when true, every item is created with `.userPresence`, so
        /// the Keychain itself (not just our UI) refuses to return the value
        /// without Touch ID / password. Only effective with the data protection keychain.
        public var requireUserPresence: Bool

        public init(service: String, accessGroup: String? = nil, useDataProtectionKeychain: Bool = true, requireUserPresence: Bool = true) {
            self.service = service
            self.accessGroup = accessGroup
            self.useDataProtectionKeychain = useDataProtectionKeychain
            self.requireUserPresence = requireUserPresence
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: SecretStore

    public func setData(_ value: Data, for ref: String, context: LAContext?) throws {
        var addQuery = baseQuery(ref: ref)
        addQuery[kSecValueData as String] = value
        try applyProtection(to: &addQuery)

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Updating a protected item needs authentication, like reading it.
            var query = baseQuery(ref: ref)
            applyAuthentication(context, to: &query)
            let attributes: [String: Any] = [kSecValueData as String: value]
            try check(SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
        default:
            try check(addStatus)
        }
    }

    public func data(for ref: String, context: LAContext?) throws -> Data? {
        var query = baseQuery(ref: ref)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        applyAuthentication(context, to: &query)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw KeychainError.invalidData }
        return data
    }

    public func delete(_ ref: String) throws {
        let status = SecItemDelete(baseQuery(ref: ref) as CFDictionary)
        if status == errSecItemNotFound { return }
        try check(status)
    }

    public func contains(_ ref: String) throws -> Bool {
        // Ask for attributes only: no secret is decrypted, so no authentication
        // is needed even for `.userPresence` items.
        var query = baseQuery(ref: ref)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    public func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
        ]
        applyKeychainSelection(to: &query)
        // The legacy keychain deletes only one item per call; loop until empty.
        while true {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecItemNotFound { return }
            try check(status)
            if configuration.useDataProtectionKeychain { return }
        }
    }

    // MARK: Query building

    private func baseQuery(ref: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: ref,
        ]
        applyKeychainSelection(to: &query)
        return query
    }

    private func applyKeychainSelection(to query: inout [String: Any]) {
        if configuration.useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
            if let group = configuration.accessGroup {
                query[kSecAttrAccessGroup as String] = group
            }
        }
    }

    private func applyProtection(to query: inout [String: Any]) throws {
        // SECURITY: "WhenUnlockedThisDeviceOnly" = readable only while the Mac is
        // unlocked, never synced to iCloud Keychain and never restored onto another
        // device from a backup. Future multi-Mac sync will use our own E2E layer.
        let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if configuration.useDataProtectionKeychain && configuration.requireUserPresence {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(nil, accessibility, .userPresence, &error) else {
                throw KeychainError.accessControlCreationFailed
            }
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = accessibility
        }
    }

    private func applyAuthentication(_ context: LAContext?, to query: inout [String: Any]) {
        guard configuration.useDataProtectionKeychain, configuration.requireUserPresence else { return }
        if let context {
            // Reuse the session's already-authenticated context: one Touch ID
            // unlocks the session instead of one prompt per secret.
            query[kSecUseAuthenticationContext as String] = context
        } else {
            // SECURITY: never let a random code path trigger a system prompt.
            // Without a session context the read fails; the caller must unlock first.
            let silent = LAContext()
            silent.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = silent
        }
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed: throw KeychainError.authenticationRequired
        case errSecAuthFailed: throw KeychainError.authenticationFailed
        case errSecUserCanceled: throw KeychainError.userCanceled
        case errSecMissingEntitlement: throw KeychainError.missingEntitlement
        default: throw KeychainError.unexpectedStatus(status)
        }
    }
}

extension KeychainStore {
    /// Store for variable values.
    public static func secrets(bundleID: String, accessGroup: String? = nil) -> KeychainStore {
        KeychainStore(configuration: .init(service: "\(bundleID).secret", accessGroup: accessGroup))
    }

    /// Store for GitHub/GitLab OAuth tokens. Tokens are read by background
    /// sync without user interaction, so they skip `.userPresence` but keep
    /// the this-device-only, when-unlocked protection.
    public static func oauthTokens(bundleID: String, accessGroup: String? = nil) -> KeychainStore {
        KeychainStore(configuration: .init(service: "\(bundleID).oauth", accessGroup: accessGroup, requireUserPresence: false))
    }
}
