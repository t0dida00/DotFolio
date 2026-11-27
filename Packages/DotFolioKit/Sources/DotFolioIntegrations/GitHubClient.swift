import Foundation

// SECURITY: this client only ever sends GET requests to the GitHub API (plus
// the two OAuth device-flow POSTs to github.com/login). It has no code path
// that writes to a repository. Authorization is a GitHub App user token, and
// the App itself is configured with read-only permissions
// (Contents: read, Metadata: read), so GitHub enforces read-only too.

public struct GitHubDeviceCode: Decodable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: URL
    public let expiresIn: Int
    public let interval: Int
}

/// A signed-in account. `GitLabClient` returns the same shape.
public struct GitHubUser: Decodable, Equatable, Sendable {
    public let login: String
    public let name: String?
    public let email: String?
    public let avatarUrl: URL?

    public init(login: String, name: String?, email: String?, avatarUrl: URL?) {
        self.login = login
        self.name = name
        self.email = email
        self.avatarUrl = avatarUrl
    }
}

/// A repository the signed-in account can read. `GitLabClient` maps GitLab
/// projects to the same shape, so the picker and importer serve both hosts.
public struct GitHubRepo: Decodable, Identifiable, Hashable, Sendable {
    public struct Owner: Decodable, Hashable, Sendable {
        public let login: String
        public init(login: String) { self.login = login }
    }

    public let id: Int
    public let name: String
    public let fullName: String
    public let htmlUrl: URL
    public let `private`: Bool
    public let defaultBranch: String
    public let description: String?
    public let updatedAt: Date?
    public let owner: Owner

    public var isPrivate: Bool { `private` }

    public init(id: Int, name: String, fullName: String, htmlUrl: URL, isPrivate: Bool, defaultBranch: String,
                description: String?, updatedAt: Date?, owner: String) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.htmlUrl = htmlUrl
        self.private = isPrivate
        self.defaultBranch = defaultBranch
        self.description = description
        self.updatedAt = updatedAt
        self.owner = Owner(login: owner)
    }
}

public struct GitHubFile: Equatable, Sendable {
    public let text: String
    public let sha: String

    public init(text: String, sha: String) {
        self.text = text
        self.sha = sha
    }
}

/// Errors from either host's client (GitLab reuses them).
public enum GitHubError: Error, Equatable, Sendable {
    case notConfigured
    case expiredCode
    case accessDenied
    /// The token was revoked or expired; sign in again.
    case unauthorized
    case http(Int)
    case unexpected(String)
}

/// Minimal GitHub REST client: device-flow sign-in, current user, repos the
/// App can see, and reading a single file.
public struct GitHubClient: Sendable {
    public let clientID: String
    private let session: URLSession
    private let apiBase = URL(string: "https://api.github.com")!
    private let webBase = URL(string: "https://github.com")!

    public init(clientID: String, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    // MARK: Device flow

    public func requestDeviceCode() async throws -> GitHubDeviceCode {
        guard !clientID.isEmpty else { throw GitHubError.notConfigured }
        let data = try await postForm(webBase.appending(path: "login/device/code"), ["client_id": clientID])
        return try Self.decoder.decode(GitHubDeviceCode.self, from: data)
    }

    /// Polls until the user approves in the browser. Honors `slow_down`.
    public func pollForToken(
        _ code: GitHubDeviceCode,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> String {
        var interval = max(code.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await sleep(.seconds(interval))
            let data = try await postForm(webBase.appending(path: "login/oauth/access_token"), [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            let response = try Self.decoder.decode(TokenResponse.self, from: data)
            if let token = response.accessToken { return token }
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval = response.interval ?? interval + 5
            case "expired_token": throw GitHubError.expiredCode
            case "access_denied": throw GitHubError.accessDenied
            default: throw GitHubError.unexpected(response.errorDescription ?? response.error ?? "unknown")
            }
        }
        throw GitHubError.expiredCode
    }

    // MARK: Read-only API

    public func currentUser(token: String) async throws -> GitHubUser {
        try Self.decoder.decode(GitHubUser.self, from: try await get(apiBase.appending(path: "user"), token: token))
    }

    /// Repos the user can access through this App (where it is installed),
    /// most recently updated first. Follows pagination up to `maxPages`.
    public func repositories(token: String, maxPages: Int = 10) async throws -> [GitHubRepo] {
        var all: [GitHubRepo] = []
        for page in 1...maxPages {
            var url = apiBase.appending(path: "user/repos")
            url.append(queryItems: [
                .init(name: "per_page", value: "100"),
                .init(name: "page", value: String(page)),
                .init(name: "sort", value: "updated"),
            ])
            let batch = try Self.decoder.decode([GitHubRepo].self, from: try await get(url, token: token))
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    /// Reads a text file; nil when it doesn't exist.
    public func file(_ path: String, in fullName: String, ref: String, token: String) async throws -> GitHubFile? {
        var url = apiBase.appending(path: "repos/\(fullName)/contents/\(path)")
        url.append(queryItems: [.init(name: "ref", value: ref)])
        do {
            let data = try await get(url, token: token)
            let content = try Self.decoder.decode(ContentResponse.self, from: data)
            let base64 = content.content.replacingOccurrences(of: "\n", with: "")
            guard let decoded = Data(base64Encoded: base64), let text = String(data: decoded, encoding: .utf8) else {
                throw GitHubError.unexpected("\(path) is not UTF-8 text")
            }
            return GitHubFile(text: text, sha: content.sha)
        } catch GitHubError.http(404) {
            return nil
        }
    }

    // MARK: Plumbing

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?
        let interval: Int?
    }

    private struct ContentResponse: Decodable {
        let content: String
        let sha: String
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func postForm(_ url: URL, _ fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.unexpected("No HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw GitHubError.unauthorized
        default: throw GitHubError.http(http.statusCode)
        }
    }
}
