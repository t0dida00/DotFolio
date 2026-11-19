import Foundation

/// Known service kinds. Stored as a raw string in SwiftData so new cases can be
/// added later without a schema migration; unknown raw values decode as `.custom`.
public enum ServiceType: String, CaseIterable, Codable, Sendable, Identifiable {
    case firebase
    case supabase
    case stripe
    case aws
    case googleCloud
    case googleMaps
    case vercel
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .firebase: "Firebase"
        case .supabase: "Supabase"
        case .stripe: "Stripe"
        case .aws: "AWS"
        case .googleCloud: "Google Cloud"
        case .googleMaps: "Google Maps"
        case .vercel: "Vercel"
        case .custom: "Custom"
        }
    }

    /// Matches typed text ("firebase", "Google Maps") to a known service.
    public init?(matching text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = ServiceType.allCases.first(where: {
            $0 != .custom && ($0.displayName.caseInsensitiveCompare(t) == .orderedSame || $0.rawValue.caseInsensitiveCompare(t) == .orderedSame)
        }) else { return nil }
        self = match
    }

    /// Builds a console URL for a service project when the service has a
    /// predictable URL pattern. Users can always override it manually.
    public func defaultConsoleURL(externalID: String) -> URL? {
        let id = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        switch self {
        case .firebase: return URL(string: "https://console.firebase.google.com/project/\(encoded)/overview")
        case .supabase: return URL(string: "https://supabase.com/dashboard/project/\(encoded)")
        case .googleCloud, .googleMaps: return URL(string: "https://console.cloud.google.com/home/dashboard?project=\(encoded)")
        case .stripe, .aws, .vercel, .custom: return nil
        }
    }
}

/// Where a `Project`'s repository is hosted.
public enum RepoProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case github
    case gitlab
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .none: "No repo"
        }
    }
}
