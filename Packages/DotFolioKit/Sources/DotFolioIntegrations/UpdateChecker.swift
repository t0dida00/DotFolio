import Foundation

/// Checks the app's public GitHub repo for a newer release.
/// SECURITY: one unauthenticated GET to the public Releases API; no token,
/// nothing about the user is sent.
public struct UpdateChecker: Sendable {
    public struct Release: Decodable, Equatable, Sendable {
        public let tagName: String
        public let name: String?
        public let body: String?
        public let htmlUrl: URL
        public let publishedAt: Date?

        public var version: String { UpdateChecker.normalize(tagName) }
    }

    public enum Result: Equatable, Sendable {
        case upToDate(current: String)
        case available(Release)
        /// The repo has no published releases yet.
        case noReleases
    }

    public let repo: String
    private let session: URLSession

    public init(repo: String, session: URLSession = .shared) {
        self.repo = repo
        self.session = session
    }

    public func check(currentVersion: String) async throws -> Result {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return .noReleases }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let release = try GitHubClient.decoder.decode(Release.self, from: data)
        return Self.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate(current: currentVersion)
    }

    /// "v1.2.0" → "1.2.0"
    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Numeric, dot-separated comparison: 0.10.0 > 0.9.3, 1.0 == 1.0.0.
    /// Pre-release suffixes ("-beta") are ignored for ordering.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            normalize(s).split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
