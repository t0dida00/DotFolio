import Foundation
import Testing
@testable import DotFolioIntegrations

/// Its own stub so it can't race the other suites' handlers.
final class HealthStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<Int, URLError>)?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        switch Self.handler?(request) ?? .success(500) {
        case .success(let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct HealthCheckerTests {
    let checker: HealthChecker
    let url = URL(string: "https://shop.example.com")!

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HealthStub.self]
        checker = HealthChecker(session: URLSession(configuration: config), retryDelay: .zero)
        HealthStub.requests = []
    }

    @Test func upOnFirstTryWithHeadOnly() async {
        HealthStub.handler = { _ in .success(200) }
        let answer = await checker.check(url)
        #expect(answer.isUp)
        #expect(answer.responseTime != nil)
        #expect(HealthStub.requests.map(\.httpMethod) == ["HEAD"])
        #expect(HealthStub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(HealthStub.requests.first?.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func protectedSitesCountAsUp() async {
        for code in [401, 403, 429] {
            HealthStub.requests = []
            HealthStub.handler = { _ in .success(code) }
            #expect(await checker.check(url).isUp, "HTTP \(code)")
            #expect(HealthStub.requests.count == 1, "no retry")
        }
        #expect(HealthStub.requests.first?.value(forHTTPHeaderField: "User-Agent")?.contains("Safari") == true)
        HealthStub.handler = { _ in .success(404) }
        #expect(!(await checker.check(url).isUp))
    }

    @Test func fallsBackToGetWhenHeadIsRefused() async {
        HealthStub.handler = { $0.httpMethod == "HEAD" ? .success(405) : .success(200) }
        #expect(await checker.check(url).isUp)
        #expect(HealthStub.requests.map(\.httpMethod) == ["HEAD", "GET"])
    }

    @Test func oneFailureIsRetriedBeforeDown() async {
        var calls = 0
        HealthStub.handler = { _ in calls += 1; return calls == 1 ? .success(502) : .success(200) }
        #expect(await checker.check(url).isUp)
        #expect(HealthStub.requests.count == 2)
    }

    @Test func downAfterTwoFailures() async {
        HealthStub.handler = { _ in .success(503) }
        let answer = await checker.check(url)
        #expect(!answer.isUp)
        #expect(answer.statusCode == 503)
        #expect(answer.error == "HTTP 503")
        #expect(HealthStub.requests.count == 2)
    }

    @Test func offlineIsNotDownAndNotRetried() async {
        HealthStub.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        let answer = await checker.check(url)
        #expect(answer.isOffline)
        #expect(!answer.isUp)
        #expect(HealthStub.requests.count == 1)
        #expect(HealthChecker.isOffline(URLError(.networkConnectionLost)))
        #expect(!HealthChecker.isOffline(URLError(.timedOut)))
    }

    @Test func namesNetworkErrors() async {
        HealthStub.handler = { _ in .failure(URLError(.timedOut)) }
        let answer = await checker.check(url)
        #expect(answer.statusCode == nil)
        #expect(answer.error == "Timed out")
        #expect(!answer.isOffline, "a site that times out is down, not offline")
        #expect(HealthChecker.describe(URLError(.cannotFindHost)) == "Host not found")
        #expect(HealthChecker.describe(URLError(.serverCertificateHasBadDate)) == "Certificate problem")
    }
}
