import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import Foundation
import LocalAuthentication

/// Builds the .env text for one environment, reading values from the
/// secret store with an authenticated context.
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
        var entries: [EnvEntry] = []
        var missing: [String] = []
        for variable in environment.sortedVariables {
            var value = ""
            if variable.hasValue {
                value = try secrets.string(for: variable.secretRef.uuidString, context: authContext) ?? ""
            } else {
                missing.append(variable.key)
            }
            entries.append(EnvEntry(key: variable.key, value: value, comment: variable.notes))
        }
        let project = environment.project?.name ?? "project"
        let header = [
            "\(project) — \(environment.name)",
            "Exported by DotFolio. Contains secrets: never commit this file.",
        ]
        return Output(text: EnvExporter.render(entries, header: header), missing: missing)
    }
}
