import Foundation

/// What a variable is for (Database, Cache, Storage…), as opposed to who
/// provides it (Supabase, Redis, AWS…).
public enum ServiceCategory: String, CaseIterable, Identifiable, Sendable {
    case database, cache, storage, auth, payments, email, analytics, monitoring, hosting, maps, search, queue, ai, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .database: "Database"
        case .cache: "Cache"
        case .storage: "Storage"
        case .auth: "Auth"
        case .payments: "Payments"
        case .email: "Email"
        case .analytics: "Analytics"
        case .monitoring: "Monitoring"
        case .hosting: "Hosting"
        case .maps: "Maps"
        case .search: "Search"
        case .queue: "Queue"
        case .ai: "AI"
        case .other: "Other"
        }
    }

    /// Matches typed text, including common synonyms ("DB" → Database).
    public init?(matching text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let synonyms: [String: ServiceCategory] = [
            "db": .database, "sql": .database, "storage": .storage, "files": .storage, "blob": .storage,
            "authentication": .auth, "login": .auth, "billing": .payments, "payment": .payments,
            "mail": .email, "smtp": .email, "logging": .monitoring, "logs": .monitoring, "errors": .monitoring,
            "llm": .ai, "cdn": .hosting, "deploy": .hosting, "queues": .queue, "jobs": .queue,
        ]
        if let match = ServiceCategory.allCases.first(where: { $0.displayName.lowercased() == t || $0.rawValue == t }) {
            self = match
        } else if let match = synonyms[t] {
            self = match
        } else {
            return nil
        }
    }

    /// Best guess from the provider name, used when no category was chosen.
    public static func suggested(forProvider provider: String) -> ServiceCategory? {
        // A known provider (see ProviderCatalog) first, then name fragments.
        if let entry = ProviderCatalog.entry(named: provider) { return entry.service }
        let p = provider.lowercased()
        let table: [(String, ServiceCategory)] = [
            ("redis", .cache), ("upstash", .cache), ("memcache", .cache),
            ("supabase", .database), ("postgres", .database), ("mysql", .database), ("mongo", .database),
            ("planetscale", .database), ("neon", .database), ("prisma", .database), ("turso", .database),
            ("s3", .storage), ("r2", .storage), ("cloudinary", .storage), ("uploadthing", .storage),
            ("stripe", .payments), ("paddle", .payments), ("lemon", .payments), ("paypal", .payments),
            ("resend", .email), ("sendgrid", .email), ("mailgun", .email), ("postmark", .email), ("ses", .email),
            ("posthog", .analytics), ("mixpanel", .analytics), ("segment", .analytics), ("amplitude", .analytics),
            ("sentry", .monitoring), ("datadog", .monitoring), ("logtail", .monitoring),
            ("vercel", .hosting), ("netlify", .hosting), ("cloudflare", .hosting), ("fly", .hosting),
            ("google maps", .maps), ("mapbox", .maps),
            ("algolia", .search), ("meilisearch", .search), ("elastic", .search),
            ("openai", .ai), ("anthropic", .ai), ("gemini", .ai),
            ("auth0", .auth), ("clerk", .auth),
        ]
        return table.first { p.contains($0.0) }?.1
    }
}
