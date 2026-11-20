import Foundation

/// Where a value comes from, written as an inline comment in a .env file:
///
///     OPENAI_API_KEY=sk-… #AI/OpenAI/me@example.com/https://platform.openai.com/api-keys
///
/// Fields in order: Service / Provider / Account / Link. Any can be left
/// empty (`#//me@example.com`) or left out at the end (`#AI/OpenAI`). The
/// link is everything after the third slash, so its own slashes are kept.
/// A comment without any "/" is an ordinary note, not source information.
public struct EnvSource: Equatable, Sendable {
    public var service = ""
    public var provider = ""
    public var account = ""
    public var link = ""

    public init(service: String = "", provider: String = "", account: String = "", link: String = "") {
        self.service = service
        self.provider = provider
        self.account = account
        self.link = link
    }

    public init(comment: String) {
        let text = comment.trimmingCharacters(in: .whitespaces)
        guard text.contains("/") else { return }
        let parts = text.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        service = parts.count > 0 ? parts[0] : ""
        provider = parts.count > 1 ? parts[1] : ""
        account = parts.count > 2 ? parts[2] : ""
        link = parts.count > 3 ? parts[3] : ""
    }

    public var isEmpty: Bool { [service, provider, account, link].allSatisfy(\.isEmpty) }

    /// The inline comment text (without "#") that `init(comment:)` reads
    /// back: `AI/OpenAI/me@example.com`. Trailing empty fields are dropped;
    /// empty when there is no source at all.
    public var comment: String {
        var fields = [service, provider, account, link]
        while fields.last?.isEmpty == true { fields.removeLast() }
        // A lone service needs a "/" to count as source information.
        if fields.count == 1 { fields.append("") }
        return fields.joined(separator: "/")
    }
}
