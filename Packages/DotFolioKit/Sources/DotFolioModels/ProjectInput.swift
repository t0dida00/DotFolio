import Foundation

/// Recognizes GitHub / GitLab repository links so a pasted project link fills
/// in the provider and "owner/repo" automatically.
public struct RepoLink: Equatable, Sendable {
    public let provider: RepoProvider
    public let fullName: String

    public init?(url: URL) {
        guard let host = url.host()?.lowercased() else { return nil }
        var parts = url.path().split(separator: "/").map(String.init)
        if let last = parts.last, last.hasSuffix(".git") { parts[parts.count - 1] = String(last.dropLast(4)) }

        switch host {
        case "github.com", "www.github.com":
            guard parts.count >= 2 else { return nil }
            provider = .github
            fullName = "\(parts[0])/\(parts[1])"
        case "gitlab.com", "www.gitlab.com":
            // GitLab allows nested groups; "/-/" starts a sub-page (issues, tree…).
            let repoParts = Array(parts.prefix { $0 != "-" })
            guard repoParts.count >= 2 else { return nil }
            provider = .gitlab
            fullName = repoParts.joined(separator: "/")
        default:
            return nil
        }
    }
}

/// Validation helpers for user-entered links and environment variable names.
public enum InputValidation {
    /// http(s) URL with a host, or nil. Whitespace is trimmed; a bare
    /// "github.com/owner/repo" gets "https://" prepended.
    public static func webURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }

    /// POSIX-style env var name: letter or underscore, then letters, digits, underscores.
    public static func isValidEnvKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }
        let head = CharacterSet.letters.union(["_"])
        let body = head.union(.decimalDigits)
        return key.unicodeScalars.allSatisfy(\.isASCII)
            && head.contains(first)
            && key.unicodeScalars.allSatisfy(body.contains)
    }

    /// Keys that appear more than once (exact match, like a shell would treat them).
    public static func duplicateKeys(_ keys: [String]) -> Set<String> {
        var seen = Set<String>(), dupes = Set<String>()
        for key in keys where !key.isEmpty {
            if !seen.insert(key).inserted { dupes.insert(key) }
        }
        return dupes
    }
}
