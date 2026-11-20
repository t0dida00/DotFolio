import Foundation

/// What a dotenv file is, judged by its name.
public enum EnvFileKind: Equatable, Sendable {
    /// Real values for one environment (`.env.production` → "production").
    case environment(String)
    /// `.env.example`, `.env.sample`, `.env.template`…: names only, the values
    /// are placeholders and must not be imported as secrets.
    case template
    /// A dotenv file whose name doesn't say which environment it is for.
    case unknown
}

/// Reading `.env*` files the user picked, for New Project and the Library.
public enum EnvFileImport {
    /// Larger files are not dotenv files; refuse instead of parsing megabytes.
    public static let maxBytes = 1_000_000

    public enum Failure: Error, Equatable {
        case tooLarge
        case notText
    }

    /// `.env`, `.env.local`, `.env.development.local` → development;
    /// `.env.staging` / `.env.preview` → staging; `.env.prod` → production;
    /// `.env.example` → template; `production.env` works too.
    public static func kind(forFileName name: String) -> EnvFileKind {
        let tokens = name.lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { $0 != "env" && $0 != "local" && !$0.isEmpty }

        if tokens.contains(where: { ["example", "sample", "template", "dist", "defaults", "tpl"].contains($0) }) {
            return .template
        }
        for token in tokens {
            switch token {
            case "development", "dev": return .environment("development")
            case "staging", "stage", "preview", "qa", "uat": return .environment("staging")
            case "production", "prod", "live": return .environment("production")
            default: continue
            }
        }
        // Plain `.env` / `.env.local` is what a developer runs locally.
        return tokens.isEmpty ? .environment("development") : .unknown
    }

    /// Parses `data` (the file's bytes) as UTF-8 dotenv text.
    public static func entries(from data: Data) throws(Failure) -> [EnvEntry] {
        guard data.count <= maxBytes else { throw .tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw .notText }
        return EnvParser.parse(text)
    }
}
