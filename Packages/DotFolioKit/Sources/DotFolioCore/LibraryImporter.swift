import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import SwiftData

/// Adds the keys of a `.env` file to the Library under one provider.
public enum LibraryImporter {
    public struct Result: Equatable, Sendable {
        public var added: Int
        /// Names already in the Library for this provider; never overwritten.
        public var skipped: [String]
    }

    /// All or nothing. Each value goes to the secret store before its key is
    /// inserted (like `VariableEditor.addToLibrary`); if any write fails, the
    /// keys added so far are removed again — Keychain items first.
    /// - Parameter includeValues: false for templates (`.env.example`).
    @MainActor
    @discardableResult
    public static func importKeys(
        _ entries: [EnvEntry], provider: String, category: String = "", account: String = "", includeValues: Bool = true,
        context: ModelContext, secrets: any SecretStore
    ) throws(VariableEditor.Failure) -> Result {
        var added: [Variable] = []
        var skipped: [String] = []
        for entry in entries {
            do {
                let key = try VariableEditor.addToLibrary(
                    key: entry.key, value: includeValues ? entry.value : "", category: category,
                    provider: provider, account: account, context: context, secrets: secrets
                )
                added.append(key)
            } catch .duplicateKey(let name) {
                skipped.append(name)
            } catch .invalidKey {
                skipped.append(entry.key)
            } catch {
                for key in added { try? VariableEditor.delete(key, context: context, secrets: secrets) }
                throw error
            }
        }
        return Result(added: added.count, skipped: skipped)
    }
}
