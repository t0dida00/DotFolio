import Foundation

/// Asks a production URL whether it's up.
/// SECURITY: read-only — HEAD (GET when the server refuses HEAD), ephemeral
/// session: no cookies, no cache, no credentials, nothing about the user.
public struct HealthChecker: Sendable {
    /// What one attempt saw. Mirrors `HealthResult` (DotFolioModels) without
    /// depending on it.
    public struct Answer: Equatable, Sendable {
        public var statusCode: Int?
        public var responseTime: Double?
        public var error: String?
        /// This Mac had no network, so the answer says nothing about the
        /// site. Never record it as down.
        public var isOffline = false

        /// Same rule as `HealthStatus.isAnswering` (DotFolioModels): 2xx/3xx,
        /// or 401/403/429 from a server that's up but protected.
        public var isUp: Bool { statusCode.map { (200..<400).contains($0) || [401, 403, 429].contains($0) } ?? false }
    }

    private let session: URLSession
    private let timeout: TimeInterval
    /// Wait before the second attempt. One failure alone never counts as down.
    private let retryDelay: Duration

    public init(session: URLSession? = nil, timeout: TimeInterval = 15, retryDelay: Duration = .seconds(30)) {
        self.session = session ?? Self.makeSession()
        self.timeout = timeout
        self.retryDelay = retryDelay
    }

    /// Up on the first try, or the second try's answer.
    public func check(_ url: URL) async -> Answer {
        let first = await attempt(url)
        if first.isUp || first.isOffline { return first }
        try? await Task.sleep(for: retryDelay)
        if Task.isCancelled { return first }
        return await attempt(url)
    }

    /// One request: HEAD, then GET if HEAD isn't allowed (405/501).
    func attempt(_ url: URL) async -> Answer {
        let head = await request(url, method: "HEAD")
        if let status = head.statusCode, status == 405 || status == 501 {
            return await request(url, method: "GET")
        }
        return head
    }

    private func request(_ url: URL, method: String) async -> Answer {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        // Browser-like, so bot filters don't block the check; still says who it is.
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")
        let start = ContinuousClock.now
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let status = (response as? HTTPURLResponse)?.statusCode
            let answer = Answer(statusCode: status, responseTime: seconds, error: nil)
            return answer.isUp ? answer : Answer(statusCode: status, responseTime: seconds, error: status.map { "HTTP \($0)" } ?? "No response")
        } catch {
            return Answer(statusCode: nil, responseTime: nil, error: Self.describe(error), isOffline: Self.isOffline(error))
        }
    }

    /// Errors that come from this Mac's connection, not from the site.
    static func isOffline(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff].contains(code)
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15 DOTFOLIO-uptime"

    static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "No response" }
        switch urlError.code {
        case .timedOut: return "Timed out"
        case .cannotFindHost, .dnsLookupFailed: return "Host not found"
        case .cannotConnectToHost: return "Connection refused"
        case .notConnectedToInternet, .networkConnectionLost: return "No internet connection"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return "Certificate problem"
        case .appTransportSecurityRequiresSecureConnection: return "Not HTTPS"
        case .httpTooManyRedirects, .redirectToNonExistentLocation: return "Redirect loop"
        default: return "No response"
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }
}
