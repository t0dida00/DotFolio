import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import LocalAuthentication

/// Copies a key from anywhere (palette, menu bar): its value, or its whole
/// `.env` line (`KEY=value #Service/Provider/Account/Link`). Values are read
/// with the session's Touch ID and leave only through `SecureClipboard`.
@MainActor
enum KeyCopier {
    enum What { case value, line }

    enum Failure: LocalizedError {
        case noValue(String)
        var errorDescription: String? {
            switch self {
            case .noValue(let key): "\(key) has no value to copy."
            }
        }
    }

    /// Returns false when the Touch ID prompt was cancelled (nothing copied).
    @discardableResult
    static func copy(_ v: Variable, as what: What, session: SessionLock, secrets: any SecretStore) async throws -> Bool {
        var plain: String?
        if v.hasValue {
            do {
                let context = try await session.authenticatedContext(reason: "copy \(v.key)")
                plain = try VariableEditor.value(of: v, secrets: secrets, context: context)
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                return false
            }
        }
        switch what {
        case .value:
            guard let plain else { throw Failure.noValue(v.key) }
            SecureClipboard.copy(plain)
        case .line:
            var line = EnvFileEdit.text(for: [v], values: plain.map { [v.id: $0] } ?? [:])
            while line.hasSuffix("\n") { line.removeLast() }
            SecureClipboard.copy(line)
        }
        return true
    }
}
