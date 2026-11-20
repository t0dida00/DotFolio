import Foundation

/// One `KEY=value` line from a .env / .env.example file.
public struct EnvEntry: Equatable, Sendable {
    public var key: String
    public var value: String
    /// Comment lines directly above the entry (without "#"), joined by newlines.
    public var comment: String
    /// Comment at the end of the entry's line (without "#"), e.g.
    /// `KEY=value #AI/OpenAI/me@x.com` → "AI/OpenAI/me@x.com".
    public var inlineComment: String

    public init(key: String, value: String = "", comment: String = "", inlineComment: String = "") {
        self.key = key
        self.value = value
        self.comment = comment
        self.inlineComment = inlineComment
    }

    /// Service / provider / account / link written in the inline comment.
    public var source: EnvSource { EnvSource(comment: inlineComment) }
}

/// Parses dotenv files the way most loaders (dotenv, docker compose, Vite) do:
/// - `KEY=value`, optional `export ` prefix, spaces around `=`
/// - `#` comments on their own line; ` #` starts an inline comment in unquoted values
/// - single quotes are literal; double quotes support \n \t \" \\ escapes and span lines
/// - invalid keys are skipped; for duplicate keys the last one wins (like dotenv)
public enum EnvParser {
    public static func parse(_ text: String) -> [EnvEntry] {
        var entries: [EnvEntry] = []
        var indexByKey: [String: Int] = [:]
        var pendingComment: [String] = []

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { pendingComment = []; continue }
            if trimmed.hasPrefix("#") {
                pendingComment.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            var rest = Substring(trimmed)
            if rest.hasPrefix("export ") { rest = rest.dropFirst("export ".count).drop(while: { $0 == " " }) }
            guard let eq = rest.firstIndex(of: "=") else { pendingComment = []; continue }
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { pendingComment = []; continue }
            var raw = String(rest[rest.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            let value: String
            var inline = ""
            if raw.hasPrefix("\"") {
                // Double-quoted values may continue on following lines.
                while !hasClosingQuote(raw, quote: "\""), i < lines.count {
                    raw += "\n" + lines[i]
                    i += 1
                }
                value = unescape(quotedBody(raw, quote: "\""))
                inline = trailingComment(raw, quote: "\"")
            } else if raw.hasPrefix("'") {
                value = quotedBody(raw, quote: "'")
                inline = trailingComment(raw, quote: "'")
            } else {
                if let hash = raw.range(of: " #") {
                    inline = String(raw[hash.upperBound...]).trimmingCharacters(in: .whitespaces)
                    raw = String(raw[..<hash.lowerBound])
                } else if raw.hasPrefix("#") {
                    // `KEY= #comment` / `KEY=#comment`: empty value.
                    inline = String(raw.dropFirst()).trimmingCharacters(in: .whitespaces)
                    raw = ""
                }
                value = raw.trimmingCharacters(in: .whitespaces)
            }

            let entry = EnvEntry(key: key, value: value, comment: pendingComment.joined(separator: "\n"), inlineComment: inline)
            pendingComment = []
            if let existing = indexByKey[key] {
                entries[existing] = entry
            } else {
                indexByKey[key] = entries.count
                entries.append(entry)
            }
        }
        return entries
    }

    public static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, key.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        let head = CharacterSet.letters.union(["_"])
        let body = head.union(.decimalDigits)
        return head.contains(first) && key.unicodeScalars.allSatisfy(body.contains)
    }

    private static func hasClosingQuote(_ raw: String, quote: Character) -> Bool {
        var escaped = false
        for (offset, char) in raw.enumerated() where offset > 0 {
            if escaped { escaped = false; continue }
            if char == "\\" && quote == "\"" { escaped = true; continue }
            if char == quote { return true }
        }
        return false
    }

    /// Text of a `#` comment after the closing quote, if any.
    private static func trailingComment(_ raw: String, quote: Character) -> String {
        var escaped = false
        var closing: String.Index?
        var index = raw.index(after: raw.startIndex)
        while index < raw.endIndex {
            let char = raw[index]
            if escaped { escaped = false } else if char == "\\" && quote == "\"" { escaped = true } else if char == quote { closing = index; break }
            index = raw.index(after: index)
        }
        guard let closing else { return "" }
        let rest = raw[raw.index(after: closing)...].trimmingCharacters(in: .whitespaces)
        return rest.hasPrefix("#") ? String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) : ""
    }

    private static func quotedBody(_ raw: String, quote: Character) -> String {
        var body = ""
        var escaped = false
        for char in raw.dropFirst() {
            if escaped { body.append("\\"); body.append(char); escaped = false; continue }
            if char == "\\" && quote == "\"" { escaped = true; continue }
            if char == quote { break }
            body.append(char)
        }
        return body
    }

    private static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for char in s {
            if escaped {
                switch char {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append(char)
                }
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                out.append(char)
            }
        }
        return out
    }
}
