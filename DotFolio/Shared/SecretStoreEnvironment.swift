import DotFolioSecurity
import LocalAuthentication
import SwiftUI

extension EnvironmentValues {
    /// Where variable values are stored. The app injects the Keychain store;
    /// the default refuses every write, so a view that forgot the injection
    /// (or a preview) can never silently "save" a secret somewhere else.
    @Entry var secretStore: any SecretStore = UnavailableSecretStore()
}

/// Fails closed: every operation throws.
struct UnavailableSecretStore: SecretStore {
    func setData(_ value: Data, for ref: String, context: LAContext?) throws { throw KeychainError.missingEntitlement }
    func data(for ref: String, context: LAContext?) throws -> Data? { throw KeychainError.missingEntitlement }
    func delete(_ ref: String) throws { throw KeychainError.missingEntitlement }
    func contains(_ ref: String) throws -> Bool { throw KeychainError.missingEntitlement }
    func deleteAll() throws { throw KeychainError.missingEntitlement }
    func allRefs() throws -> [String] { throw KeychainError.missingEntitlement }
}

extension KeychainError {
    /// Short, user-facing explanation.
    var userMessage: String {
        switch self {
        case .missingEntitlement:
            "Keychain isn’t available in this build. The app must be signed with your Apple Development team."
        case .authenticationRequired, .authenticationFailed:
            "Authentication is required to access the Keychain."
        case .userCanceled:
            "Authentication was canceled."
        case .invalidData, .accessControlCreationFailed, .unexpectedStatus:
            "The Keychain returned an unexpected error (\(self))."
        }
    }
}
