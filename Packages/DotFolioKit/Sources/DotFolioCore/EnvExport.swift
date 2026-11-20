import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import LocalAuthentication

/// Builds the .env text for one environment, reading values from the
/// secret store with an authenticated context. The text is exactly what the
/// File view shows: one `KEY=value #Service/Provider/Account/Link` line per
/// variable, no header or notes (see `EnvFileEdit.text`).
public enum EnvExport {
    public struct Output: Sendable {
        public let text: String
        /// Variables written as `KEY=` because no value is stored yet.
        public let missing: [String]
    }

    /// Default file name: development → ".env", others → ".env.<name>".
    public static func fileName(for environment: ProjectEnvironment) -> String {
        environment.name == "development" ? ".env" : ".env.\(environment.name)"
    }

    @MainActor
    public static func build(_ environment: ProjectEnvironment, secrets: any SecretStore, authContext: LAContext?) throws -> Output {
        let variables = environment.sortedVariables
        var values: [UUID: String] = [:]
        var missing: [String] = []
        for variable in variables {
            if variable.hasValue {
                values[variable.id] = try secrets.string(for: variable.secretRef.uuidString, context: authContext) ?? ""
            } else {
                missing.append(variable.key)
            }
        }
        return Output(text: EnvFileEdit.text(for: variables, values: values), missing: missing)
    }
}
