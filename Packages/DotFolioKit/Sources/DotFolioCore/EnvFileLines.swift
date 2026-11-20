import DotFolioEnv
import DotFolioModels
import Foundation

/// One environment shown as the .env file a developer would write, one line
/// per variable: `KEY=value #Service/Provider/Account/Link`. Notes are left
/// out so the file stays short.
/// Values are hidden unless the caller passes them in `revealed` (plaintext
/// read from the Keychain after Touch ID, kept in memory only).
public enum EnvFileLines {
    public enum Value: Equatable, Sendable {
        /// No value stored yet: rendered as `KEY=`.
        case missing
        /// Stored in the Keychain but not revealed.
        case hidden
        /// Revealed, already quoted the way an export would write it.
        case plain(String)
    }

    public struct Line: Equatable, Sendable {
        public let key: String
        public let value: Value
        /// Inline comment text without "#"; empty when there is no source.
        public let source: String

        public init(key: String, value: Value, source: String) {
            self.key = key
            self.value = value
            self.source = source
        }
    }

    @MainActor
    public static func lines(for variables: [Variable], revealed: [UUID: String] = [:]) -> [Line] {
        variables.map { variable in
            let value: Value
            if let plain = revealed[variable.id] {
                value = .plain(EnvExporter.quote(plain))
            } else {
                value = variable.hasValue ? .hidden : .missing
            }
            return Line(key: variable.key, value: value, source: source(of: variable).comment)
        }
    }

    /// Service / Provider / Account / Link as written in an inline comment.
    @MainActor
    public static func source(of variable: Variable) -> EnvSource {
        EnvSource(service: variable.serviceCategory,
                  provider: variable.serviceLabel,
                  account: variable.account?.login ?? "",
                  link: variable.sourceURL?.absoluteString ?? "")
    }
}
