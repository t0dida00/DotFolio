import Foundation

// SECURITY: this client only ever sends GET requests to the GitLab REST API
// (v4). It has no code path that writes to a repository. It signs in with a
// personal access token the user creates with the read-only `read_api`
// scope, so GitLab enforces read-only too. Works for gitlab.com and
// self-hosted instances (https only).

/// Minimal GitLab REST client: current user, projects the user is a member
/// of, and reading a single file. Returns the same shapes as `GitHubClient`.
public struct GitLabClient: Sendable {
    public static let gitLabCom = URL(string: "https://gitlab.com")!

    /// The instance, e.g. https://gitlab.com or https://git.example.com/gitlab.
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = GitLabClient.gitLabCom, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Where the user creates a token, with name and scope filled in.
    public static func tokenPage(for baseURL: URL) -> URL {
        URL(string: root(baseURL) + "/-/user_settings/personal_access_tokens?name=Dotfolio&scopes=read_api")!
    }

    public func currentUser(token: String) async throws -> GitHubUser {
        let user = try Self.decoder.decode(User.self, from: try await get("user", token: token))
        return GitHubUser(login: user.username, name: user.name, email: user.publicEmail ?? user.email, avatarUrl: user.avatarUrl)
    }

    /// Projects the user is a member of (not archived), most recently active
    /// first, 100 per page.
    public func repositories(token: String, maxPages: Int = 10) async throws -> [GitHubRepo] {
        var all: [GitHubRepo] = []
        for page in 1...maxPages {
            let query = "projects?membership=true&archived=false&order_by=last_activity_at&per_page=100&page=\(page)"
            let batch = try Self.decoder.decode([Project].self, from: try await get(query, token: token))
            all += batch.map(\.repo)
            if batch.count < 100 { break }
        }
        return all
    }

    /// Reads a text file from a project ("group/sub/repo"); nil when missing.
    public func file(_ path: String, in fullName: String, ref: String, token: String) async throws -> GitHubFile? {
        let query = "projects/\(Self.encode(fullName))/repository/files/\(Self.encode(path))?ref=\(Self.encode(ref))"
        do {
            let file = try Self.decoder.decode(FileResponse.self, from: try await get(query, token: token))
            guard let data = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")),
                  let text = String(data: data, encoding: .utf8)
            else { throw GitHubError.unexpected("\(path) is not UTF-8 text") }
            return GitHubFile(text: text, sha: file.blobId)
        } catch GitHubError.http(404) {
            return nil
        }
    }

    // MARK: Responses

    private struct User: Decodable {
        let username: String
        let name: String?
        let email: String?
        let publicEmail: String?
        let avatarUrl: URL?
    }

    private struct Project: Decodable {
        struct Namespace: Decodable { let fullPath: String }
        let id: Int
        let name: String
        let pathWithNamespace: String
        let webUrl: URL
        let visibility: String?
        let defaultBranch: String?
        let description: String?
        let lastActivityAt: Date?
        let namespace: Namespace?

        var repo: GitHubRepo {
            GitHubRepo(id: id, name: name, fullName: pathWithNamespace, htmlUrl: webUrl,
                       isPrivate: visibility != "public", defaultBranch: defaultBranch ?? "main",
                       description: description, updatedAt: lastActivityAt,
                       owner: namespace?.fullPath ?? pathWithNamespace.components(separatedBy: "/").first ?? "")
        }
    }

    private struct FileResponse: Decodable {
        let content: String
        let blobId: String
    }

    // MARK: Plumbing

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // GitLab dates carry milliseconds ("2026-11-20T10:00:00.123Z").
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = precise.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return d
    }()

    /// Path segment encoding: "group/repo" → "group%2Frepo", as GitLab expects.
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? text
    }

    private static func root(_ url: URL) -> String {
        let text = url.absoluteString
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    private func get(_ pathAndQuery: String, token: String) async throws -> Data {
        guard let url = URL(string: Self.root(baseURL) + "/api/v4/" + pathAndQuery) else {
            throw GitHubError.unexpected("Bad GitLab address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.unexpected("No HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw GitHubError.unauthorized
        case 403: throw GitHubError.accessDenied
        default: throw GitHubError.http(http.statusCode)
        }
    }
}
