import Foundation

/// A guess of where a variable comes from: what it's for (Service) and who
/// provides it (Provider), from its name and — while it is in memory during
/// a create or import — its value. Values are only looked at, never kept.
public struct SourceGuess: Equatable, Sendable {
    public var service: String?
    public var provider: String?
    /// Short English explanation shown in Suggest Sources ("Name has STRIPE").
    public var reason: String

    public init(service: String? = nil, provider: String? = nil, reason: String) {
        self.service = service
        self.provider = provider
        self.reason = reason
    }
}

/// Known providers: display name (as used in the Provider column), the name
/// tokens that identify them, and what they are usually for.
public enum ProviderCatalog {
    public struct Entry: Sendable {
        public let name: String
        /// Each alias is a run of name tokens, e.g. ["GOOGLE", "MAPS"].
        public let aliases: [[String]]
        public let service: ServiceCategory?
    }

    public static let entries: [Entry] = [
        .init(name: "Firebase", aliases: [["FIREBASE"]], service: nil),
        .init(name: "Supabase", aliases: [["SUPABASE"]], service: .database),
        .init(name: "Stripe", aliases: [["STRIPE"]], service: .payments),
        .init(name: "OpenAI", aliases: [["OPENAI"]], service: .ai),
        .init(name: "Anthropic", aliases: [["ANTHROPIC"], ["CLAUDE"]], service: .ai),
        .init(name: "Hugging Face", aliases: [["HF"], ["HUGGINGFACE"], ["HUGGING", "FACE"]], service: .ai),
        .init(name: "Gemini", aliases: [["GEMINI"]], service: .ai),
        .init(name: "Groq", aliases: [["GROQ"]], service: .ai),
        .init(name: "Mistral", aliases: [["MISTRAL"]], service: .ai),
        .init(name: "Replicate", aliases: [["REPLICATE"]], service: .ai),
        .init(name: "Pinecone", aliases: [["PINECONE"]], service: .database),
        .init(name: "Google Maps", aliases: [["GOOGLE", "MAPS"], ["GMAPS"]], service: .maps),
        .init(name: "Google Cloud", aliases: [["GOOGLE", "CLOUD"], ["GCP"], ["GCLOUD"]], service: nil),
        .init(name: "AWS", aliases: [["AWS"], ["S3"]], service: nil),
        .init(name: "Vercel", aliases: [["VERCEL"]], service: .hosting),
        .init(name: "Netlify", aliases: [["NETLIFY"]], service: .hosting),
        .init(name: "Cloudflare", aliases: [["CLOUDFLARE"], ["CF"], ["R2"]], service: .hosting),
        .init(name: "Upstash", aliases: [["UPSTASH"], ["QSTASH"]], service: .cache),
        .init(name: "Redis", aliases: [["REDIS"]], service: .cache),
        .init(name: "MongoDB", aliases: [["MONGODB"], ["MONGO"]], service: .database),
        .init(name: "Neon", aliases: [["NEON"]], service: .database),
        .init(name: "PlanetScale", aliases: [["PLANETSCALE"]], service: .database),
        .init(name: "Turso", aliases: [["TURSO"]], service: .database),
        .init(name: "PostHog", aliases: [["POSTHOG"]], service: .analytics),
        .init(name: "Mixpanel", aliases: [["MIXPANEL"]], service: .analytics),
        .init(name: "Segment", aliases: [["SEGMENT"]], service: .analytics),
        .init(name: "Amplitude", aliases: [["AMPLITUDE"]], service: .analytics),
        .init(name: "Sentry", aliases: [["SENTRY"]], service: .monitoring),
        .init(name: "Datadog", aliases: [["DATADOG"], ["DD"]], service: .monitoring),
        .init(name: "Resend", aliases: [["RESEND"]], service: .email),
        .init(name: "SendGrid", aliases: [["SENDGRID"]], service: .email),
        .init(name: "Mailgun", aliases: [["MAILGUN"]], service: .email),
        .init(name: "Postmark", aliases: [["POSTMARK"]], service: .email),
        .init(name: "Clerk", aliases: [["CLERK"]], service: .auth),
        .init(name: "Auth0", aliases: [["AUTH0"]], service: .auth),
        .init(name: "Cloudinary", aliases: [["CLOUDINARY"]], service: .storage),
        .init(name: "UploadThing", aliases: [["UPLOADTHING"]], service: .storage),
        .init(name: "Algolia", aliases: [["ALGOLIA"]], service: .search),
        .init(name: "Meilisearch", aliases: [["MEILISEARCH"], ["MEILI"]], service: .search),
        .init(name: "Mapbox", aliases: [["MAPBOX"]], service: .maps),
        .init(name: "Twilio", aliases: [["TWILIO"]], service: nil),
        .init(name: "GitHub", aliases: [["GITHUB"], ["GH"]], service: nil),
        .init(name: "Paddle", aliases: [["PADDLE"]], service: .payments),
        .init(name: "PayPal", aliases: [["PAYPAL"]], service: .payments),
        .init(name: "Lemon Squeezy", aliases: [["LEMONSQUEEZY"], ["LEMON", "SQUEEZY"]], service: .payments),
    ]

    /// The catalog entry with this display name (case-insensitive).
    public static func entry(named name: String) -> Entry? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
}

public enum SourceGuesser {
    /// Framework prefixes that say nothing about the source.
    static let prefixes = ["NEXT_PUBLIC_", "NUXT_PUBLIC_", "EXPO_PUBLIC_", "REACT_APP_", "VITE_", "NUXT_", "PUBLIC_"]

    /// Name words that say what a value is for. The first one in the name wins
    /// (STRIPE_CHECKOUT_SESSION → Payments, not Auth). `EMAIL` alone is left
    /// out on purpose: OWNER_EMAIL is configuration, not an email service.
    static let serviceWords: [String: ServiceCategory] = [
        "DATABASE": .database, "DB": .database, "POSTGRES": .database, "POSTGRESQL": .database, "PG": .database,
        "MYSQL": .database, "MONGO": .database, "MONGODB": .database, "PRISMA": .database, "SQL": .database,
        "REDIS": .cache, "CACHE": .cache, "KV": .cache, "MEMCACHED": .cache,
        "AUTH": .auth, "JWT": .auth, "SESSION": .auth, "OAUTH": .auth, "NEXTAUTH": .auth,
        "MODEL": .ai, "LLM": .ai, "EMBEDDING": .ai, "EMBEDDINGS": .ai,
        "BUCKET": .storage, "STORAGE": .storage, "UPLOAD": .storage, "UPLOADS": .storage, "S3": .storage,
        "PAYMENT": .payments, "PAYMENTS": .payments, "BILLING": .payments, "CHECKOUT": .payments,
        "SMTP": .email, "MAIL": .email, "MAILER": .email,
        "DSN": .monitoring,
        "ANALYTICS": .analytics, "GA": .analytics, "GTAG": .analytics,
        "MAPS": .maps,
        "SEARCH": .search,
        "QUEUE": .queue, "QSTASH": .queue,
    ]

    public static func guess(key: String, value: String? = nil) -> SourceGuess? {
        let tokens = tokens(of: key)
        var service: ServiceCategory?
        var provider: ProviderCatalog.Entry?
        var reasons: [String] = []

        if let (entry, alias) = providerInName(tokens) {
            provider = entry
            reasons.append("Name has \(alias)")
        }
        if let word = tokens.first(where: { serviceWords[$0] != nil }), let match = serviceWords[word] {
            service = match
            if !reasons.contains(where: { $0.hasSuffix(word) }) { reasons.append("Name has \(word)") }
        }

        if let value, !value.isEmpty {
            let fromValue = Self.fromValue(value)
            if provider == nil, let name = fromValue.provider, let entry = ProviderCatalog.entry(named: name) {
                provider = entry
                reasons.append(fromValue.reason)
            }
            if service == nil, let match = fromValue.service {
                service = match
                if !reasons.contains(fromValue.reason) { reasons.append(fromValue.reason) }
            }
        }

        if service == nil, let fallback = provider?.service {
            service = fallback
        }
        guard service != nil || provider != nil else { return nil }
        return SourceGuess(service: service?.displayName, provider: provider?.name,
                           reason: reasons.joined(separator: " · "))
    }

    /// Upper-cased name words without framework prefixes: NUXT_HF_MODEL → [HF, MODEL].
    static func tokens(of key: String) -> [String] {
        var name = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for prefix in prefixes where name.hasPrefix(prefix) && name.count > prefix.count {
            name.removeFirst(prefix.count)
            break
        }
        return name.split(separator: "_").map(String.init).filter { !$0.isEmpty }
    }

    /// Longest alias first, so GOOGLE_MAPS beats a shorter match.
    private static func providerInName(_ tokens: [String]) -> (ProviderCatalog.Entry, String)? {
        var best: (entry: ProviderCatalog.Entry, alias: [String], index: Int)?
        for entry in ProviderCatalog.entries {
            for alias in entry.aliases where alias.count <= tokens.count {
                for start in 0...(tokens.count - alias.count) where Array(tokens[start..<start + alias.count]) == alias {
                    let better = best.map { alias.count > $0.alias.count || (alias.count == $0.alias.count && start < $0.index) } ?? true
                    if better { best = (entry, alias, start) }
                }
            }
        }
        return best.map { ($0.entry, $0.alias.joined(separator: "_")) }
    }

    /// Well-known key formats and connection strings.
    private static func fromValue(_ raw: String) -> (provider: String?, service: ServiceCategory?, reason: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        let prefixes: [(String, String)] = [
            ("sk-ant-", "Anthropic"),
            ("sk_live_", "Stripe"), ("sk_test_", "Stripe"), ("pk_live_", "Stripe"), ("pk_test_", "Stripe"),
            ("rk_live_", "Stripe"), ("rk_test_", "Stripe"), ("whsec_", "Stripe"),
            ("sk-", "OpenAI"),
            ("hf_", "Hugging Face"),
            ("ghp_", "GitHub"), ("github_pat_", "GitHub"),
            ("re_", "Resend"),
        ]
        if let match = prefixes.first(where: { value.hasPrefix($0.0) }) {
            return (match.1, nil, "Value looks like a \(match.1) key")
        }
        let hosts: [(String, String)] = [
            (".supabase.co", "Supabase"), (".supabase.com", "Supabase"), (".upstash.io", "Upstash"),
            (".neon.tech", "Neon"), (".mongodb.net", "MongoDB"), ("sentry.io", "Sentry"),
            (".psdb.cloud", "PlanetScale"), (".turso.io", "Turso"), (".firebaseapp.com", "Firebase"),
        ]
        let host = hosts.first { lower.contains($0.0) }?.1
        let scheme: ServiceCategory? = switch true {
        case lower.hasPrefix("postgres://"), lower.hasPrefix("postgresql://"), lower.hasPrefix("mysql://"),
             lower.hasPrefix("mongodb://"), lower.hasPrefix("mongodb+srv://"), lower.hasPrefix("libsql://"): .database
        case lower.hasPrefix("redis://"), lower.hasPrefix("rediss://"): .cache
        default: nil
        }
        var provider = host
        if provider == nil, lower.hasPrefix("mongodb") { provider = "MongoDB" }
        let reason = provider.map { "Value points to \($0)" } ?? (scheme.map { "Value is a \($0.displayName.lowercased()) URL" } ?? "")
        return (provider, scheme, reason)
    }
}
