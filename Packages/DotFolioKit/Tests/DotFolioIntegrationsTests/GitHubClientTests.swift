import Foundation
import Testing
@testable import DotFolioIntegrations

/// Serves canned responses so no request ever reaches GitHub.
final class StubProtocol: URLProtocol, @unchecked Sendable {
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
struct GitHubClientTests {
    let client: GitHubClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = GitHubClient(clientID: "Iv1.test", session: URLSession(configuration: config))
        StubProtocol.requests = []
    }

    @Test func missingClientIDIsReported() async {
        await #expect(throws: GitHubError.notConfigured) {
            _ = try await GitHubClient(clientID: "").requestDeviceCode()
        }
    }

    @Test func requestsDeviceCode() async throws {
        StubProtocol.handler = { _ in (200, #"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#) }
        let code = try await client.requestDeviceCode()
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.interval == 5)
        let request = try #require(StubProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
    }

    @Test func pollsThroughPendingAndSlowDown() async throws {
        var calls = 0
        StubProtocol.handler = { _ in
            calls += 1
            switch calls {
            case 1: return (200, #"{"error":"authorization_pending"}"#)
            case 2: return (200, #"{"error":"slow_down","interval":10}"#)
            default: return (200, #"{"access_token":"ghu_token","token_type":"bearer"}"#)
            }
        }
        let code = GitHubDeviceCode(deviceCode: "dc", userCode: "X", verificationUri: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5)
        nonisolated(unsafe) var waits: [Duration] = []
        let token = try await client.pollForToken(code) { waits.append($0) }
        #expect(token == "ghu_token")
        #expect(waits == [.seconds(5), .seconds(5), .seconds(10)])
    }

    @Test func deniedAndExpiredAreDistinct() async throws {
        let code = GitHubDeviceCode(deviceCode: "dc", userCode: "X", verificationUri: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 1)
        StubProtocol.handler = { _ in (200, #"{"error":"access_denied"}"#) }
        await #expect(throws: GitHubError.accessDenied) { _ = try await client.pollForToken(code) { _ in } }
        StubProtocol.handler = { _ in (200, #"{"error":"expired_token"}"#) }
        await #expect(throws: GitHubError.expiredCode) { _ = try await client.pollForToken(code) { _ in } }
    }

    @Test func apiCallsAreReadOnlyGETsWithBearerToken() async throws {
        StubProtocol.handler = { request in
            if request.url?.path == "/user" { return (200, #"{"login":"acme-dev","name":"Acme","email":null,"avatar_url":null}"#) }
            return (200, "[]")
        }
        let user = try await client.currentUser(token: "t")
        _ = try await client.repositories(token: "t")
        #expect(user.login == "acme-dev")
        #expect(StubProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(StubProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer t" })
    }

    @Test func paginatesRepositories() async throws {
        func repo(_ id: Int) -> String {
            #"{"id":\#(id),"name":"r\#(id)","full_name":"acme/r\#(id)","html_url":"https://github.com/acme/r\#(id)","private":true,"default_branch":"main","description":null,"updated_at":"2026-11-19T10:00:00Z","owner":{"login":"acme"}}"#
        }
        StubProtocol.handler = { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            let ids = page == "1" ? Array(1...100) : [101, 102]
            return (200, "[" + ids.map(repo).joined(separator: ",") + "]")
        }
        let repos = try await client.repositories(token: "t")
        #expect(repos.count == 102)
        #expect(repos.first?.fullName == "acme/r1")
        #expect(repos.first?.isPrivate == true)
        #expect(StubProtocol.requests.count == 2)
    }

    @Test func readsFileAndTreats404AsMissing() async throws {
        let body = Data("API_KEY=\nDB_URL=\n".utf8).base64EncodedString()
        StubProtocol.handler = { request in
            request.url!.path.hasSuffix(".env.example") ? (200, #"{"content":"\#(body)","sha":"abc123"}"#) : (404, "{}")
        }
        let file = try await client.file(".env.example", in: "acme/shop", ref: "main", token: "t")
        #expect(file == GitHubFile(text: "API_KEY=\nDB_URL=\n", sha: "abc123"))
        #expect(try await client.file("missing", in: "acme/shop", ref: "main", token: "t") == nil)
    }

    @Test func unauthorizedIsSurfaced() async {
        StubProtocol.handler = { _ in (401, "{}") }
        await #expect(throws: GitHubError.unauthorized) { _ = try await client.currentUser(token: "revoked") }
    }
}
