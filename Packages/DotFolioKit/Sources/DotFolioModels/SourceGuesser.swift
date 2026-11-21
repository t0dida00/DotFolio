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

    /// Grouped by what each provider is usually for. Aliases come from the
    /// env var names in each provider's docs (e.g. `NEXT_PUBLIC_POSTHOG_KEY`,
    /// `CLERK_SECRET_KEY`). Short, ambiguous words are left out on purpose:
    /// `DO` (DO_NOT_TRACK), `HERE`, `JUNE` would match unrelated names.
    public static let entries: [Entry] = [
        // AI
        .init(name: "OpenAI", aliases: [["OPENAI"]], service: .ai),
        .init(name: "Azure OpenAI", aliases: [["AZURE", "OPENAI"], ["AOAI"]], service: .ai),
        .init(name: "Anthropic", aliases: [["ANTHROPIC"], ["CLAUDE"]], service: .ai),
        .init(name: "Hugging Face", aliases: [["HF"], ["HUGGINGFACE"], ["HUGGING", "FACE"]], service: .ai),
        .init(name: "Gemini", aliases: [["GEMINI"]], service: .ai),
        .init(name: "Groq", aliases: [["GROQ"]], service: .ai),
        .init(name: "Mistral", aliases: [["MISTRAL"]], service: .ai),
        .init(name: "Replicate", aliases: [["REPLICATE"]], service: .ai),
        .init(name: "Cohere", aliases: [["COHERE"], ["CO", "API"]], service: .ai),
        .init(name: "Perplexity", aliases: [["PERPLEXITY"], ["PPLX"]], service: .ai),
        .init(name: "Together AI", aliases: [["TOGETHER"], ["TOGETHERAI"]], service: .ai),
        .init(name: "Fireworks", aliases: [["FIREWORKS"]], service: .ai),
        .init(name: "DeepSeek", aliases: [["DEEPSEEK"]], service: .ai),
        .init(name: "xAI", aliases: [["XAI"], ["GROK"]], service: .ai),
        .init(name: "OpenRouter", aliases: [["OPENROUTER"]], service: .ai),
        .init(name: "ElevenLabs", aliases: [["ELEVENLABS"], ["ELEVEN", "LABS"], ["XI", "API"]], service: .ai),
        .init(name: "AssemblyAI", aliases: [["ASSEMBLYAI"], ["ASSEMBLY", "AI"]], service: .ai),
        .init(name: "Deepgram", aliases: [["DEEPGRAM"]], service: .ai),
        .init(name: "Ollama", aliases: [["OLLAMA"]], service: .ai),
        .init(name: "LangSmith", aliases: [["LANGSMITH"], ["LANGCHAIN"]], service: .ai),
        .init(name: "Voyage AI", aliases: [["VOYAGE"], ["VOYAGEAI"]], service: .ai),
        .init(name: "Jina AI", aliases: [["JINA"]], service: .ai),
        .init(name: "Stability AI", aliases: [["STABILITY"]], service: .ai),
        .init(name: "Runway", aliases: [["RUNWAYML"]], service: .ai),
        .init(name: "Vertex AI", aliases: [["VERTEX"], ["VERTEXAI"]], service: .ai),
        .init(name: "AWS Bedrock", aliases: [["BEDROCK"]], service: .ai),

        // Database (incl. vector databases)
        .init(name: "Supabase", aliases: [["SUPABASE"]], service: .database),
        .init(name: "Pinecone", aliases: [["PINECONE"]], service: .database),
        .init(name: "Weaviate", aliases: [["WEAVIATE"]], service: .database),
        .init(name: "Qdrant", aliases: [["QDRANT"]], service: .database),
        .init(name: "Chroma", aliases: [["CHROMA"], ["CHROMADB"]], service: .database),
        .init(name: "MongoDB", aliases: [["MONGODB"], ["MONGO"]], service: .database),
        .init(name: "Neon", aliases: [["NEON"]], service: .database),
        .init(name: "PlanetScale", aliases: [["PLANETSCALE"]], service: .database),
        .init(name: "Turso", aliases: [["TURSO"], ["LIBSQL"]], service: .database),
        .init(name: "Xata", aliases: [["XATA"]], service: .database),
        .init(name: "CockroachDB", aliases: [["COCKROACH"], ["COCKROACHDB"]], service: .database),
        .init(name: "Convex", aliases: [["CONVEX"]], service: .database),
        .init(name: "Appwrite", aliases: [["APPWRITE"]], service: .database),
        .init(name: "Fauna", aliases: [["FAUNA"], ["FAUNADB"]], service: .database),
        .init(name: "Prisma", aliases: [["PRISMA"]], service: .database),
        .init(name: "Firestore", aliases: [["FIRESTORE"]], service: .database),
        .init(name: "DynamoDB", aliases: [["DYNAMODB"], ["DYNAMO"]], service: .database),
        .init(name: "Vercel Postgres", aliases: [["VERCEL", "POSTGRES"]], service: .database),
        .init(name: "Aiven", aliases: [["AIVEN"]], service: .database),
        .init(name: "InstantDB", aliases: [["INSTANT", "APP"], ["INSTANTDB"]], service: .database),
        .init(name: "PocketBase", aliases: [["POCKETBASE"]], service: .database),

        // Cache
        .init(name: "Upstash", aliases: [["UPSTASH"]], service: .cache),
        .init(name: "Redis", aliases: [["REDIS"]], service: .cache),
        .init(name: "Vercel KV", aliases: [["VERCEL", "KV"]], service: .cache),
        .init(name: "Momento", aliases: [["MOMENTO"]], service: .cache),
        .init(name: "Valkey", aliases: [["VALKEY"]], service: .cache),

        // Storage & media
        .init(name: "Cloudinary", aliases: [["CLOUDINARY"]], service: .storage),
        .init(name: "UploadThing", aliases: [["UPLOADTHING"]], service: .storage),
        .init(name: "Backblaze", aliases: [["BACKBLAZE"], ["B2"]], service: .storage),
        .init(name: "DigitalOcean Spaces", aliases: [["DO", "SPACES"], ["SPACES"]], service: .storage),
        .init(name: "Wasabi", aliases: [["WASABI"]], service: .storage),
        .init(name: "ImageKit", aliases: [["IMAGEKIT"]], service: .storage),
        .init(name: "Mux", aliases: [["MUX"]], service: .storage),
        .init(name: "Vercel Blob", aliases: [["VERCEL", "BLOB"]], service: .storage),
        .init(name: "Bunny", aliases: [["BUNNY"], ["BUNNYCDN"]], service: .storage),
        .init(name: "Uploadcare", aliases: [["UPLOADCARE"]], service: .storage),

        // Auth
        .init(name: "Clerk", aliases: [["CLERK"]], service: .auth),
        .init(name: "Auth0", aliases: [["AUTH0"]], service: .auth),
        .init(name: "Kinde", aliases: [["KINDE"]], service: .auth),
        .init(name: "WorkOS", aliases: [["WORKOS"]], service: .auth),
        .init(name: "Okta", aliases: [["OKTA"]], service: .auth),
        .init(name: "Stytch", aliases: [["STYTCH"]], service: .auth),
        .init(name: "Auth.js", aliases: [["NEXTAUTH"], ["AUTHJS"]], service: .auth),
        .init(name: "Better Auth", aliases: [["BETTER", "AUTH"]], service: .auth),
        .init(name: "Descope", aliases: [["DESCOPE"]], service: .auth),
        .init(name: "Logto", aliases: [["LOGTO"]], service: .auth),
        .init(name: "Keycloak", aliases: [["KEYCLOAK"]], service: .auth),
        .init(name: "Cognito", aliases: [["COGNITO"]], service: .auth),

        // Payments
        .init(name: "Stripe", aliases: [["STRIPE"]], service: .payments),
        .init(name: "Paddle", aliases: [["PADDLE"]], service: .payments),
        .init(name: "PayPal", aliases: [["PAYPAL"]], service: .payments),
        .init(name: "Lemon Squeezy", aliases: [["LEMONSQUEEZY"], ["LEMON", "SQUEEZY"]], service: .payments),
        .init(name: "Square", aliases: [["SQUARE"]], service: .payments),
        .init(name: "Braintree", aliases: [["BRAINTREE"]], service: .payments),
        .init(name: "Adyen", aliases: [["ADYEN"]], service: .payments),
        .init(name: "Razorpay", aliases: [["RAZORPAY"]], service: .payments),
        .init(name: "Polar", aliases: [["POLAR"]], service: .payments),
        .init(name: "RevenueCat", aliases: [["REVENUECAT"]], service: .payments),
        .init(name: "Mollie", aliases: [["MOLLIE"]], service: .payments),
        .init(name: "Shopify", aliases: [["SHOPIFY"]], service: .payments),
        .init(name: "Coinbase Commerce", aliases: [["COINBASE"]], service: .payments),

        // Email
        .init(name: "Resend", aliases: [["RESEND"]], service: .email),
        .init(name: "SendGrid", aliases: [["SENDGRID"]], service: .email),
        .init(name: "Mailgun", aliases: [["MAILGUN"]], service: .email),
        .init(name: "Postmark", aliases: [["POSTMARK"]], service: .email),
        .init(name: "Amazon SES", aliases: [["SES"]], service: .email),
        .init(name: "Brevo", aliases: [["BREVO"], ["SENDINBLUE"]], service: .email),
        .init(name: "Mailchimp", aliases: [["MAILCHIMP"], ["MANDRILL"]], service: .email),
        .init(name: "Mailjet", aliases: [["MAILJET"], ["MJ", "APIKEY"]], service: .email),
        .init(name: "Loops", aliases: [["LOOPS"]], service: .email),
        .init(name: "MailerSend", aliases: [["MAILERSEND"]], service: .email),
        .init(name: "SparkPost", aliases: [["SPARKPOST"]], service: .email),
        .init(name: "Plunk", aliases: [["PLUNK"]], service: .email),

        // Messaging: SMS, push, chat
        .init(name: "Twilio", aliases: [["TWILIO"]], service: .messaging),
        .init(name: "Vonage", aliases: [["VONAGE"], ["NEXMO"]], service: .messaging),
        .init(name: "MessageBird", aliases: [["MESSAGEBIRD"]], service: .messaging),
        .init(name: "Plivo", aliases: [["PLIVO"]], service: .messaging),
        .init(name: "OneSignal", aliases: [["ONESIGNAL"]], service: .messaging),
        .init(name: "Pusher", aliases: [["PUSHER"]], service: .messaging),
        .init(name: "Ably", aliases: [["ABLY"]], service: .messaging),
        .init(name: "Slack", aliases: [["SLACK"]], service: .messaging),
        .init(name: "Discord", aliases: [["DISCORD"]], service: .messaging),
        .init(name: "Telegram", aliases: [["TELEGRAM"]], service: .messaging),
        .init(name: "Novu", aliases: [["NOVU"]], service: .messaging),
        .init(name: "Knock", aliases: [["KNOCK"]], service: .messaging),
        .init(name: "Stream", aliases: [["GETSTREAM"], ["STREAM", "API"]], service: .messaging),
        .init(name: "WhatsApp", aliases: [["WHATSAPP"]], service: .messaging),

        // Analytics
        .init(name: "PostHog", aliases: [["POSTHOG"]], service: .analytics),
        .init(name: "Mixpanel", aliases: [["MIXPANEL"]], service: .analytics),
        .init(name: "Segment", aliases: [["SEGMENT"]], service: .analytics),
        .init(name: "Amplitude", aliases: [["AMPLITUDE"]], service: .analytics),
        .init(name: "Google Analytics", aliases: [["GOOGLE", "ANALYTICS"], ["GA4"], ["GA", "MEASUREMENT"]], service: .analytics),
        .init(name: "Plausible", aliases: [["PLAUSIBLE"]], service: .analytics),
        .init(name: "Umami", aliases: [["UMAMI"]], service: .analytics),
        .init(name: "Fathom", aliases: [["FATHOM"]], service: .analytics),
        .init(name: "Heap", aliases: [["HEAP", "APP"], ["HEAPANALYTICS"]], service: .analytics),
        .init(name: "Hotjar", aliases: [["HOTJAR"]], service: .analytics),
        .init(name: "Microsoft Clarity", aliases: [["CLARITY"]], service: .analytics),

        // Monitoring & logs
        .init(name: "Sentry", aliases: [["SENTRY"]], service: .monitoring),
        .init(name: "Datadog", aliases: [["DATADOG"], ["DD"]], service: .monitoring),
        .init(name: "New Relic", aliases: [["NEW", "RELIC"], ["NEWRELIC"]], service: .monitoring),
        .init(name: "Honeycomb", aliases: [["HONEYCOMB"]], service: .monitoring),
        .init(name: "Grafana", aliases: [["GRAFANA"]], service: .monitoring),
        .init(name: "Better Stack", aliases: [["BETTERSTACK"], ["BETTER", "STACK"], ["LOGTAIL"]], service: .monitoring),
        .init(name: "Axiom", aliases: [["AXIOM"]], service: .monitoring),
        .init(name: "Bugsnag", aliases: [["BUGSNAG"]], service: .monitoring),
        .init(name: "Rollbar", aliases: [["ROLLBAR"]], service: .monitoring),
        .init(name: "Highlight", aliases: [["HIGHLIGHT"]], service: .monitoring),
        .init(name: "LogRocket", aliases: [["LOGROCKET"]], service: .monitoring),
        .init(name: "Checkly", aliases: [["CHECKLY"]], service: .monitoring),

        // Hosting & cloud
        .init(name: "Vercel", aliases: [["VERCEL"]], service: .hosting),
        .init(name: "Netlify", aliases: [["NETLIFY"]], service: .hosting),
        .init(name: "Cloudflare", aliases: [["CLOUDFLARE"], ["CF"], ["R2"]], service: .hosting),
        .init(name: "Railway", aliases: [["RAILWAY"]], service: .hosting),
        .init(name: "Render", aliases: [["RENDER"]], service: .hosting),
        .init(name: "Fly.io", aliases: [["FLY"], ["FLYIO"]], service: .hosting),
        .init(name: "Heroku", aliases: [["HEROKU"]], service: .hosting),
        .init(name: "DigitalOcean", aliases: [["DIGITALOCEAN"]], service: .hosting),
        .init(name: "Azure", aliases: [["AZURE"]], service: .hosting),
        .init(name: "Docker Hub", aliases: [["DOCKERHUB"], ["DOCKER", "HUB"]], service: .hosting),
        .init(name: "Expo", aliases: [["EXPO", "TOKEN"], ["EAS"]], service: .hosting),
        .init(name: "AWS", aliases: [["AWS"], ["S3"]], service: nil),
        .init(name: "Google Cloud", aliases: [["GOOGLE", "CLOUD"], ["GCP"], ["GCLOUD"], ["GOOGLE", "APPLICATION", "CREDENTIALS"]], service: nil),
        .init(name: "Firebase", aliases: [["FIREBASE"], ["FCM"]], service: nil),
        .init(name: "GitHub", aliases: [["GITHUB"], ["GH"]], service: nil),
        .init(name: "GitLab", aliases: [["GITLAB"]], service: nil),
        .init(name: "Linear", aliases: [["LINEAR"]], service: nil),

        // Search
        .init(name: "Algolia", aliases: [["ALGOLIA"]], service: .search),
        .init(name: "Meilisearch", aliases: [["MEILISEARCH"], ["MEILI"]], service: .search),
        .init(name: "Typesense", aliases: [["TYPESENSE"]], service: .search),
        .init(name: "Elasticsearch", aliases: [["ELASTIC"], ["ELASTICSEARCH"]], service: .search),
        .init(name: "OpenSearch", aliases: [["OPENSEARCH"]], service: .search),

        // Queues & background jobs
        .init(name: "QStash", aliases: [["QSTASH"]], service: .queue),
        .init(name: "Inngest", aliases: [["INNGEST"]], service: .queue),
        .init(name: "Trigger.dev", aliases: [["TRIGGER"], ["TRIGGERDEV"]], service: .queue),
        .init(name: "RabbitMQ", aliases: [["RABBITMQ"], ["RABBIT"], ["AMQP"]], service: .queue),
        .init(name: "Kafka", aliases: [["KAFKA"], ["CONFLUENT"]], service: .queue),
        .init(name: "Amazon SQS", aliases: [["SQS"]], service: .queue),

        // CMS
        .init(name: "Contentful", aliases: [["CONTENTFUL"]], service: .cms),
        .init(name: "Sanity", aliases: [["SANITY"]], service: .cms),
        .init(name: "Strapi", aliases: [["STRAPI"]], service: .cms),
        .init(name: "Storyblok", aliases: [["STORYBLOK"]], service: .cms),
        .init(name: "Prismic", aliases: [["PRISMIC"]], service: .cms),
        .init(name: "Hygraph", aliases: [["HYGRAPH"], ["GRAPHCMS"]], service: .cms),
        .init(name: "Payload", aliases: [["PAYLOAD"]], service: .cms),
        .init(name: "Directus", aliases: [["DIRECTUS"]], service: .cms),
        .init(name: "Ghost", aliases: [["GHOST"]], service: .cms),
        .init(name: "DatoCMS", aliases: [["DATOCMS"], ["DATO"]], service: .cms),

        // Feature flags
        .init(name: "LaunchDarkly", aliases: [["LAUNCHDARKLY"], ["LD", "SDK"]], service: .flags),
        .init(name: "Statsig", aliases: [["STATSIG"]], service: .flags),
        .init(name: "GrowthBook", aliases: [["GROWTHBOOK"]], service: .flags),
        .init(name: "Flagsmith", aliases: [["FLAGSMITH"]], service: .flags),
        .init(name: "Unleash", aliases: [["UNLEASH"]], service: .flags),
        .init(name: "ConfigCat", aliases: [["CONFIGCAT"]], service: .flags),
        .init(name: "Split", aliases: [["SPLITIO"], ["SPLIT", "SDK"]], service: .flags),

        // Data APIs: weather, geocoding, rates…
        .init(name: "Open-Meteo", aliases: [["OPEN", "METEO"], ["OPENMETEO"], ["METEO"]], service: .dataAPI),
        .init(name: "OpenWeather", aliases: [["OPENWEATHER"], ["OPENWEATHERMAP"], ["OWM"]], service: .dataAPI),
        .init(name: "WeatherAPI", aliases: [["WEATHERAPI"]], service: .dataAPI),
        .init(name: "Tomorrow.io", aliases: [["TOMORROW"], ["TOMORROWIO"]], service: .dataAPI),
        .init(name: "OpenCage", aliases: [["OPENCAGE"]], service: .dataAPI),
        .init(name: "ipinfo", aliases: [["IPINFO"]], service: .dataAPI),
        .init(name: "ipdata", aliases: [["IPDATA"]], service: .dataAPI),
        .init(name: "ExchangeRate-API", aliases: [["EXCHANGERATE"], ["EXCHANGE", "RATE"], ["EXCHANGE", "RATES"]], service: .dataAPI),
        .init(name: "NewsAPI", aliases: [["NEWSAPI"]], service: .dataAPI),
        .init(name: "Alpha Vantage", aliases: [["ALPHAVANTAGE"], ["ALPHA", "VANTAGE"]], service: .dataAPI),
        .init(name: "TMDB", aliases: [["TMDB"]], service: .dataAPI),

        // Maps
        .init(name: "Google Maps", aliases: [["GOOGLE", "MAPS"], ["GMAPS"]], service: .maps),
        .init(name: "Mapbox", aliases: [["MAPBOX"]], service: .maps),
        .init(name: "HERE", aliases: [["HERE", "API"], ["HERE", "MAPS"]], service: .maps),
        .init(name: "MapTiler", aliases: [["MAPTILER"]], service: .maps),
        .init(name: "Radar", aliases: [["RADAR"]], service: .maps),
    ]

    /// The catalog entry with this display name (case-insensitive).
    public static func entry(named name: String) -> Entry? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = entries.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { return exact }
        // Typed variants: "HuggingFace", "hugging-face", "METEO", "open_meteo".
        let squashed = squash(n)
        guard !squashed.isEmpty else { return nil }
        return entries.first { entry in
            squash(entry.name) == squashed || entry.aliases.contains { $0.joined() == squashed }
        }
    }

    /// Upper-cased letters and digits only: "Fly.io" → "FLYIO".
    static func squash(_ text: String) -> String {
        String(text.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
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
        "QUEUE": .queue, "QSTASH": .queue, "CRON": .queue, "JOB": .queue, "JOBS": .queue,
        "VECTOR": .database, "INFERENCE": .ai, "OPENAI": .ai,
        "CDN": .hosting,
        "TRACE": .monitoring, "TRACING": .monitoring, "OTEL": .monitoring, "OTLP": .monitoring,
        "SMS": .messaging, "PUSH": .messaging, "NOTIFICATION": .messaging, "NOTIFICATIONS": .messaging, "FCM": .messaging,
        "CMS": .cms,
        "FLAG": .flags, "FLAGS": .flags, "FEATURE": .flags, "FEATURES": .flags,
        "WEATHER": .dataAPI, "FORECAST": .dataAPI, "GEOCODING": .dataAPI, "GEOCODE": .dataAPI,
    ]

    /// After AUTH these words make it a credential (TWILIO_AUTH_TOKEN), not
    /// an auth service — with a known provider, its own service wins.
    static let credentialWords: Set<String> = ["TOKEN", "KEY", "SECRET"]

    /// Well-known whole names that carry no provider word (after prefixes are
    /// stripped), from the providers' docs and templates.
    static let exactNames: [String: (service: ServiceCategory, provider: String?)] = [
        "KV_REST_API_URL": (.cache, "Vercel KV"), "KV_REST_API_TOKEN": (.cache, "Vercel KV"),
        "KV_REST_API_READ_ONLY_TOKEN": (.cache, "Vercel KV"), "KV_URL": (.cache, "Vercel KV"),
        "BLOB_READ_WRITE_TOKEN": (.storage, "Vercel Blob"),
        "POSTGRES_PRISMA_URL": (.database, "Vercel Postgres"), "POSTGRES_URL_NON_POOLING": (.database, "Vercel Postgres"),
        "POSTGRES_URL_NO_SSL": (.database, "Vercel Postgres"),
        "AUTH_SECRET": (.auth, "Auth.js"), "AUTH_URL": (.auth, "Auth.js"), "AUTH_TRUST_HOST": (.auth, "Auth.js"),
        "DIRECT_URL": (.database, nil), "SHADOW_DATABASE_URL": (.database, nil),
        "GA_MEASUREMENT_ID": (.analytics, "Google Analytics"), "GA_TRACKING_ID": (.analytics, "Google Analytics"),
        "GOOGLE_APPLICATION_CREDENTIALS": (.auth, "Google Cloud"),
        "MONGODB_URI": (.database, "MongoDB"), "MONGO_URI": (.database, "MongoDB"),
    ]

    public static func guess(key: String, value: String? = nil) -> SourceGuess? {
        let tokens = tokens(of: key)
        var service: ServiceCategory?
        var provider: ProviderCatalog.Entry?
        var reasons: [String] = []

        // A documented name (KV_REST_API_URL) says it all.
        if let known = exactNames[tokens.joined(separator: "_")] {
            return SourceGuess(service: known.service.displayName, provider: known.provider,
                               reason: "Known name \(tokens.joined(separator: "_"))")
        }

        if let (entry, alias) = providerInName(tokens) {
            provider = entry
            reasons.append("Name has \(alias)")
        }
        if let index = serviceWordIndex(in: tokens, knownProvider: provider), let match = serviceWords[tokens[index]] {
            let word = tokens[index]
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

    /// The first word that says what the value is for. `AUTH` right before
    /// TOKEN/KEY/SECRET only names a credential when a provider is known
    /// (TWILIO_AUTH_TOKEN is Twilio's key, not an auth service).
    private static func serviceWordIndex(in tokens: [String], knownProvider: ProviderCatalog.Entry?) -> Int? {
        tokens.indices.first { i in
            guard serviceWords[tokens[i]] != nil else { return false }
            if tokens[i] == "AUTH", knownProvider?.service != nil, i + 1 < tokens.count,
               credentialWords.contains(tokens[i + 1]) {
                return false
            }
            return true
        }
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
        // Documented key formats. Longest prefix wins (sk-ant-, sk-or- before sk-).
        let prefixes: [(String, String)] = [
            ("sk-ant-", "Anthropic"), ("sk-or-", "OpenRouter"), ("sk-proj-", "OpenAI"), ("sk-", "OpenAI"),
            ("sk_live_", "Stripe"), ("sk_test_", "Stripe"), ("pk_live_", "Stripe"), ("pk_test_", "Stripe"),
            ("rk_live_", "Stripe"), ("rk_test_", "Stripe"), ("whsec_", "Stripe"),
            ("hf_", "Hugging Face"), ("gsk_", "Groq"), ("pplx-", "Perplexity"), ("r8_", "Replicate"),
            ("xai-", "xAI"), ("pcsk_", "Pinecone"),
            ("phc_", "PostHog"), ("phx_", "PostHog"), ("sntrys_", "Sentry"),
            ("xoxb-", "Slack"), ("xoxp-", "Slack"), ("xapp-", "Slack"),
            ("SG.", "SendGrid"), ("re_", "Resend"),
            ("AIza", "Google Cloud"), ("AKIA", "AWS"), ("ASIA", "AWS"),
            ("ghp_", "GitHub"), ("gho_", "GitHub"), ("ghu_", "GitHub"), ("ghs_", "GitHub"), ("github_pat_", "GitHub"),
            ("glpat-", "GitLab"), ("dop_v1_", "DigitalOcean"), ("shpat_", "Shopify"), ("shpss_", "Shopify"),
            ("lin_api_", "Linear"),
        ].sorted { $0.0.count > $1.0.count }
        if let match = prefixes.first(where: { value.hasPrefix($0.0) }) {
            return (match.1, nil, "Value looks like a \(match.1) key")
        }
        let hosts: [(String, String)] = [
            (".supabase.co", "Supabase"), (".supabase.com", "Supabase"), (".upstash.io", "Upstash"),
            (".neon.tech", "Neon"), (".mongodb.net", "MongoDB"), ("sentry.io", "Sentry"),
            (".psdb.cloud", "PlanetScale"), (".turso.io", "Turso"), (".firebaseapp.com", "Firebase"),
            (".rlwy.net", "Railway"), (".railway.app", "Railway"), (".render.com", "Render"),
            (".r2.cloudflarestorage.com", "Cloudflare"), (".amazonaws.com", "AWS"),
            (".redis.cloud", "Redis"), (".redislabs.com", "Redis"), (".cockroachlabs.cloud", "CockroachDB"),
            (".aivencloud.com", "Aiven"), (".algolia.net", "Algolia"), (".typesense.net", "Typesense"),
            ("open-meteo.com", "Open-Meteo"), ("openweathermap.org", "OpenWeather"),
            (".sanity.io", "Sanity"), ("contentful.com", "Contentful"), (".convex.cloud", "Convex"),
            (".pinecone.io", "Pinecone"), (".qdrant.io", "Qdrant"), (".weaviate.network", "Weaviate"),
            (".blob.vercel-storage.com", "Vercel Blob"), (".xata.sh", "Xata"),
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
