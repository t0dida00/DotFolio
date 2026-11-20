import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Adds the keys of a `.env` file to the Library. Each line says where it
/// belongs with a `#Service/Provider/Account/Link` comment; keys without a
/// provider go to the "Other" group (empty provider).
public enum LibraryImporter {
    public struct Result: Equatable, Sendable {
        public var added: Int
        /// Names already in the Library under the same provider; never overwritten.
        public var skipped: [String]
        /// Keys whose link wasn't a web address; imported without it.
        public var invalidLinks: [String] = []
    }

    /// All or nothing. Each value goes to the secret store before its key is
    /// inserted (like `VariableEditor.addToLibrary`); if any write fails, the
    /// keys added so far are removed again — Keychain items first.
    /// - Parameter includeValues: false for templates (`.env.example`).
    @MainActor
    @discardableResult
    public static func importKeys(
        _ entries: [EnvEntry], includeValues: Bool = true, context: ModelContext, secrets: any SecretStore
    ) throws(VariableEditor.Failure) -> Result {
        var added: [Variable] = []
        var result = Result(added: 0, skipped: [])
        for entry in entries {
            let source = entry.source
            var link = source.link
            if !link.isEmpty && InputValidation.webURL(link) == nil {
                result.invalidLinks.append(entry.key)
                link = ""
            }
            do {
                let key = try VariableEditor.addToLibrary(
                    key: entry.key, value: includeValues ? entry.value : "", category: source.service,
                    provider: source.provider, account: source.account, link: link, context: context, secrets: secrets
                )
                added.append(key)
            } catch .duplicateKey(let name) {
                result.skipped.append(name)
            } catch .invalidKey {
                result.skipped.append(entry.key)
            } catch {
                for key in added { try? VariableEditor.delete(key, context: context, secrets: secrets) }
                throw error
            }
        }
        result.added = added.count
        return result
    }
}
