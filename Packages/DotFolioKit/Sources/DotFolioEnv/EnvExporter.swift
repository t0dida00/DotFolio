import Foundation

/// Renders `KEY=value` lines that `EnvParser` (and common dotenv loaders)
/// read back to exactly the same values.
public enum EnvExporter {
    /// - Parameter header: optional comment lines written at the top.
    public static func render(_ entries: [EnvEntry], header: [String] = []) -> String {
        var lines = header.map { "# \($0)" }
        if !header.isEmpty { lines.append("") }
        for entry in entries {
            if !entry.comment.isEmpty {
                lines += entry.comment.components(separatedBy: "\n").map { "# \($0)" }
            }
            lines.append("\(entry.key)=\(quote(entry.value))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Leaves simple values bare; otherwise picks the quoting that survives
    /// a round trip:
    /// - single quotes when the value has `$` (so loaders don't expand it) and
    ///   no single quote or newline,
    /// - double quotes with \n \" \\ escapes for everything else.
    public static func quote(_ value: String) -> String {
        if value.isEmpty { return "" }
        let needsQuoting = value.contains { " #\"'\\\n\r\t$`=".contains($0) }
            || value.first == " " || value.last == " "
        guard needsQuoting else { return value }
        if value.contains("$"), !value.contains("'"), !value.contains("\n"), !value.contains("\r") {
            return "'\(value)'"
        }
        var escaped = ""
        for char in value {
            switch char {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(char)
            }
        }
        return "\"\(escaped)\""
    }
}

/// Answers "would git ignore this .env file?" from a .gitignore's text, so
/// we can warn before writing secrets into a repo folder.
public enum GitignoreCheck {
    /// Best-effort match of common patterns (`.env`, `.env*`, `*.env`, `.env.*`,
    /// `/.env`, `**/.env`). Negations (`!.env`) re-include the file.
    public static func ignores(_ fileName: String, gitignore: String) -> Bool {
        var ignored = false
        for raw in gitignore.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let negated = line.hasPrefix("!")
            if negated { line.removeFirst() }
            line = line.replacingOccurrences(of: "**/", with: "")
            if line.hasPrefix("/") { line.removeFirst() }
            if line.hasSuffix("/") { continue } // directories only
            if matches(fileName, pattern: line) { ignored = !negated }
        }
        return ignored
    }

    private static func matches(_ name: String, pattern: String) -> Bool {
        // Glob with * and ? only, anchored to the whole name.
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "\\?", with: "[^/]") + "$"
        return name.range(of: regex, options: .regularExpression) != nil
    }
}
