import Foundation
import Testing
@testable import DotFolioIntegrations

/// Its own stub so it can't race the other suites' handlers.
final class GitLabStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct GitLabClientTests {
    let client: GitLabClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitLabStub.self]
        client = GitLabClient(baseURL: URL(string: "https://git.example.com/gitlab/")!, session: URLSession(configuration: config))
        GitLabStub.requests = []
    }

    @Test func readsTheUserWithAToken() async throws {
        GitLabStub.handler = { _ in (200, #"{"username":"khoa","name":"Khoa","email":null,"public_email":"k@example.com","avatar_url":"https://git.example.com/a.png"}"#) }
        let user = try await client.currentUser(token: "glpat-x")
        #expect(user.login == "khoa")
        #expect(user.email == "k@example.com")
        let request = try #require(GitLabStub.requests.first)
        #expect(request.url?.absoluteString == "https://git.example.com/gitlab/api/v4/user")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer glpat-x")
    }

    @Test func mapsProjectsAndPages() async throws {
        func project(_ id: Int, visibility: String = "private") -> String {
            #"{"id":\#(id),"name":"r\#(id)","path_with_namespace":"acme/web/r\#(id)","web_url":"https://git.example.com/acme/web/r\#(id)","visibility":"\#(visibility)","default_branch":null,"description":"Shop","last_activity_at":"2026-11-20T10:00:00.123Z","namespace":{"full_path":"acme/web"}}"#
        }
        GitLabStub.handler = { request in
            let page = request.url?.query?.contains("page=2") == true
            let ids = page ? [100] : Array(0..<100)
            return (200, "[" + ids.map { project($0, visibility: $0 == 1 ? "public" : "private") }.joined(separator: ",") + "]")
        }
        let repos = try await client.repositories(token: "t")
        #expect(repos.count == 101)
        #expect(GitLabStub.requests.count == 2)
        let first = repos[0]
        #expect(first.fullName == "acme/web/r0")
        #expect(first.isPrivate)
        #expect(!repos[1].isPrivate)
        #expect(first.defaultBranch == "main", "empty projects have no default branch")
        #expect(first.owner.login == "acme/web")
        #expect(first.updatedAt != nil, "dates with milliseconds decode")
        #expect(GitLabStub.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func readsAFileByProjectPath() async throws {
        let text = "API_KEY=\nDB_URL=\n"
        GitLabStub.handler = { _ in (200, #"{"content":"\#(Data(text.utf8).base64EncodedString())","blob_id":"abc123"}"#) }
        let file = try await client.file(".env.example", in: "acme/web/shop", ref: "main", token: "t")
        #expect(file == GitHubFile(text: text, sha: "abc123"))
        #expect(GitLabStub.requests.first?.url?.absoluteString
                == "https://git.example.com/gitlab/api/v4/projects/acme%2Fweb%2Fshop/repository/files/.env.example?ref=main")
    }

    @Test func missingFileIsNilAndBadTokenIsUnauthorized() async throws {
        GitLabStub.handler = { _ in (404, "{}") }
        #expect(try await client.file(".env.example", in: "a/b", ref: "main", token: "t") == nil)
        GitLabStub.handler = { _ in (401, "{}") }
        await #expect(throws: GitHubError.unauthorized) { try await client.currentUser(token: "bad") }
    }

    @Test func tokenPageHasNameAndScope() {
        #expect(GitLabClient.tokenPage(for: GitLabClient.gitLabCom).absoluteString
                == "https://gitlab.com/-/user_settings/personal_access_tokens?name=DOTFOLIO&scopes=read_api")
    }
}
