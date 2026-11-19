import Foundation
import Testing
@testable import DotFolioIntegrations

/// Its own stub so it can't race GitHubClientTests' shared handler.
final class UpdateStub: URLProtocol, @unchecked Sendable {
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
struct UpdateCheckerTests {
    let checker: UpdateChecker

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateStub.self]
        checker = UpdateChecker(repo: "acme/app", session: URLSession(configuration: config))
        UpdateStub.requests = []
    }

    @Test(arguments: [
        ("0.2.0", "0.1.0", true), ("0.10.0", "0.9.3", true), ("1.0", "1.0.0", false),
        ("v1.2.0", "1.2.0", false), ("1.2.0", "1.10.0", false), ("2.0.0-beta", "1.9.9", true),
    ])
    func comparesVersions(candidate: String, current: String, newer: Bool) {
        #expect(UpdateChecker.isNewer(candidate, than: current) == newer)
    }

    @Test func reportsAvailableRelease() async throws {
        UpdateStub.handler = { _ in (200, #"{"tag_name":"v0.2.0","name":"DotFolio 0.2.0","body":"- Faster","html_url":"https://github.com/acme/app/releases/tag/v0.2.0","published_at":"2026-12-01T10:00:00Z"}"#) }
        let result = try await checker.check(currentVersion: "0.1.0")
        guard case .available(let release) = result else { Issue.record("expected update"); return }
        #expect(release.version == "0.2.0")
        #expect(UpdateStub.requests.first?.httpMethod == "GET")
        #expect(UpdateStub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func upToDateAndNoReleases() async throws {
        UpdateStub.handler = { _ in (200, #"{"tag_name":"0.1.0","name":null,"body":null,"html_url":"https://github.com/acme/app/releases/tag/0.1.0","published_at":null}"#) }
        #expect(try await checker.check(currentVersion: "0.1.0") == .upToDate(current: "0.1.0"))
        UpdateStub.handler = { _ in (404, "{}") }
        #expect(try await checker.check(currentVersion: "0.1.0") == .noReleases)
    }
}
