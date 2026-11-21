import Testing
@testable import DotFolioModels

struct SourceGuesserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let key: String
        let service: String?
        let provider: String?
        var testDescription: String { key }
    }

    @Test(arguments: [
        Case(key: "DATABASE_URL", service: "Database", provider: nil),
        Case(key: "FIREBASE_API_KEY", service: nil, provider: "Firebase"),
        Case(key: "FIREBASE_AUTH_DOMAIN", service: "Auth", provider: "Firebase"),
        Case(key: "FIREBASE_STORAGE_BUCKET", service: "Storage", provider: "Firebase"),
        Case(key: "NUXT_HF_MODEL", service: "AI", provider: "Hugging Face"),
        Case(key: "NUXT_HF_VISION_MODEL", service: "AI", provider: "Hugging Face"),
        Case(key: "NUXT_HF_TOKEN", service: "AI", provider: "Hugging Face"),
        Case(key: "OPENAI_MODEL", service: "AI", provider: "OpenAI"),
        Case(key: "STRIPE_SECRET_KEY", service: "Payments", provider: "Stripe"),
        Case(key: "STRIPE_WEBHOOK_SECRET", service: "Payments", provider: "Stripe"),
        Case(key: "STRIPE_CHECKOUT_SESSION", service: "Payments", provider: "Stripe"),
        Case(key: "NEXT_PUBLIC_SUPABASE_ANON_KEY", service: "Database", provider: "Supabase"),
        Case(key: "VITE_GOOGLE_MAPS_API_KEY", service: "Maps", provider: "Google Maps"),
        Case(key: "REDIS_URL", service: "Cache", provider: "Redis"),
        Case(key: "SENTRY_DSN", service: "Monitoring", provider: "Sentry"),
        Case(key: "NEXTAUTH_SECRET", service: "Auth", provider: "Auth.js"),
        Case(key: "SMTP_HOST", service: "Email", provider: nil),
        Case(key: "DATA_STORE", service: nil, provider: nil),
        Case(key: "OWNER_EMAIL", service: nil, provider: nil),
        Case(key: "PUBLIC_URL", service: nil, provider: nil),
        // Enriched catalog (v2)
        Case(key: "VITE_OPEN_METEO_FORECAST_URL", service: "Data API", provider: "Open-Meteo"),
        Case(key: "VITE_OPEN_METEO_GEOCODING_URL", service: "Data API", provider: "Open-Meteo"),
        Case(key: "OPENWEATHER_API_KEY", service: "Data API", provider: "OpenWeather"),
        Case(key: "TWILIO_AUTH_TOKEN", service: "Messaging", provider: "Twilio"),
        Case(key: "TWILIO_ACCOUNT_SID", service: "Messaging", provider: "Twilio"),
        Case(key: "SLACK_BOT_TOKEN", service: "Messaging", provider: "Slack"),
        Case(key: "ONESIGNAL_APP_ID", service: "Messaging", provider: "OneSignal"),
        Case(key: "FCM_SERVER_KEY", service: "Messaging", provider: "Firebase"),
        Case(key: "KV_REST_API_URL", service: "Cache", provider: "Vercel KV"),
        Case(key: "BLOB_READ_WRITE_TOKEN", service: "Storage", provider: "Vercel Blob"),
        Case(key: "POSTGRES_PRISMA_URL", service: "Database", provider: "Vercel Postgres"),
        Case(key: "AUTH_SECRET", service: "Auth", provider: "Auth.js"),
        Case(key: "DIRECT_URL", service: "Database", provider: nil),
        Case(key: "NEXT_PUBLIC_GA_MEASUREMENT_ID", service: "Analytics", provider: "Google Analytics"),
        Case(key: "NEXT_PUBLIC_POSTHOG_KEY", service: "Analytics", provider: "PostHog"),
        Case(key: "NEXT_PUBLIC_PLAUSIBLE_DOMAIN", service: "Analytics", provider: "Plausible"),
        Case(key: "CLERK_SECRET_KEY", service: "Auth", provider: "Clerk"),
        Case(key: "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY", service: "Auth", provider: "Clerk"),
        Case(key: "KINDE_CLIENT_SECRET", service: "Auth", provider: "Kinde"),
        Case(key: "CONTENTFUL_SPACE_ID", service: "CMS", provider: "Contentful"),
        Case(key: "SANITY_API_TOKEN", service: "CMS", provider: "Sanity"),
        Case(key: "LAUNCHDARKLY_SDK_KEY", service: "Feature flags", provider: "LaunchDarkly"),
        Case(key: "STATSIG_SERVER_SECRET", service: "Feature flags", provider: "Statsig"),
        Case(key: "FEATURE_NEW_CHECKOUT", service: "Feature flags", provider: nil),
        Case(key: "GROQ_API_KEY", service: "AI", provider: "Groq"),
        Case(key: "XAI_API_KEY", service: "AI", provider: "xAI"),
        Case(key: "AZURE_OPENAI_ENDPOINT", service: "AI", provider: "Azure OpenAI"),
        Case(key: "DEEPSEEK_API_KEY", service: "AI", provider: "DeepSeek"),
        Case(key: "PINECONE_API_KEY", service: "Database", provider: "Pinecone"),
        Case(key: "QDRANT_URL", service: "Database", provider: "Qdrant"),
        Case(key: "CONVEX_DEPLOYMENT", service: "Database", provider: "Convex"),
        Case(key: "MONGODB_URI", service: "Database", provider: "MongoDB"),
        Case(key: "RESEND_API_KEY", service: "Email", provider: "Resend"),
        Case(key: "BREVO_API_KEY", service: "Email", provider: "Brevo"),
        Case(key: "INNGEST_EVENT_KEY", service: "Queue", provider: "Inngest"),
        Case(key: "TRIGGER_SECRET_KEY", service: "Queue", provider: "Trigger.dev"),
        Case(key: "TYPESENSE_API_KEY", service: "Search", provider: "Typesense"),
        Case(key: "RAILWAY_TOKEN", service: "Hosting", provider: "Railway"),
        Case(key: "NEW_RELIC_LICENSE_KEY", service: "Monitoring", provider: "New Relic"),
        Case(key: "OTEL_EXPORTER_OTLP_ENDPOINT", service: "Monitoring", provider: nil),
        Case(key: "AZURE_STORAGE_ACCOUNT", service: "Storage", provider: "Azure"),
        Case(key: "MAPBOX_TOKEN", service: "Maps", provider: "Mapbox"),
        Case(key: "LOG_LEVEL", service: nil, provider: nil),
        Case(key: "DO_NOT_TRACK", service: nil, provider: nil),
        Case(key: "NODE_HEAP_SIZE", service: nil, provider: nil),
        Case(key: "CONTENT_SECURITY_POLICY", service: nil, provider: nil),
    ])
    func guessesFromName(_ c: Case) {
        let guess = SourceGuesser.guess(key: c.key)
        #expect(guess?.service == c.service)
        #expect(guess?.provider == c.provider)
        if c.service == nil && c.provider == nil { #expect(guess == nil) }
    }

    @Test func valuesFillWhatTheNameDoesNotSay() {
        #expect(SourceGuesser.guess(key: "SECRET", value: "sk_live_abc")?.provider == "Stripe")
        #expect(SourceGuesser.guess(key: "SECRET", value: "sk_live_abc")?.service == "Payments")
        #expect(SourceGuesser.guess(key: "TOKEN", value: "sk-ant-api03-x")?.provider == "Anthropic")
        #expect(SourceGuesser.guess(key: "TOKEN", value: "sk-proj-x")?.provider == "OpenAI")
        let db = SourceGuesser.guess(key: "DATABASE_URL", value: "postgres://u:p@db.abc.supabase.co:5432/postgres")
        #expect(db?.service == "Database")
        #expect(db?.provider == "Supabase")
        #expect(SourceGuesser.guess(key: "CONN", value: "rediss://default:x@eu1.upstash.io:6379")?.provider == "Upstash")
        #expect(SourceGuesser.guess(key: "CONN", value: "redis://localhost:6379")?.service == "Cache")
    }

    @Test func nameBeatsValue() {
        // The name says Firebase; a value that looks like OpenAI doesn't change that.
        #expect(SourceGuesser.guess(key: "FIREBASE_API_KEY", value: "sk-x")?.provider == "Firebase")
    }

    @Test func explainsTheGuess() {
        #expect(SourceGuesser.guess(key: "FIREBASE_AUTH_DOMAIN")?.reason == "Name has FIREBASE · Name has AUTH")
        #expect(SourceGuesser.guess(key: "SECRET", value: "whsec_1")?.reason == "Value looks like a Stripe key")
    }

    @Test func catalogDrivesProviderCategory() {
        #expect(ServiceCategory.suggested(forProvider: "Hugging Face") == .ai)
        #expect(ServiceCategory.suggested(forProvider: "Supabase") == .database)
        #expect(ServiceCategory.suggested(forProvider: "Firebase") == nil)
        #expect(ServiceCategory.suggested(forProvider: "Postgres") == .database)
    }

    @Test func moreKeyFormatsAndHosts() {
        #expect(SourceGuesser.guess(key: "TOKEN", value: "sk-or-v1-abc")?.provider == "OpenRouter")
        #expect(SourceGuesser.guess(key: "TOKEN", value: "sk-ant-api03-x")?.provider == "Anthropic")
        #expect(SourceGuesser.guess(key: "TOKEN", value: "gsk_abc")?.provider == "Groq")
        #expect(SourceGuesser.guess(key: "TOKEN", value: "xoxb-1-2")?.service == "Messaging")
        #expect(SourceGuesser.guess(key: "KEY", value: "SG.abc.def")?.provider == "SendGrid")
        #expect(SourceGuesser.guess(key: "KEY", value: "AKIAIOSFODNN7EXAMPLE")?.provider == "AWS")
        #expect(SourceGuesser.guess(key: "KEY", value: "glpat-xyz")?.provider == "GitLab")
        #expect(SourceGuesser.guess(key: "CONN", value: "postgresql://u:p@x.rlwy.net:5432/railway")?.provider == "Railway")
        let weather = SourceGuesser.guess(key: "BASE", value: "https://api.open-meteo.com/v1/forecast")
        #expect(weather?.provider == "Open-Meteo")
        #expect(weather?.service == "Data API")
    }

    @Test func typedProviderNamesFindTheirEntry() {
        #expect(ProviderCatalog.entry(named: "HuggingFace")?.name == "Hugging Face")
        #expect(ProviderCatalog.entry(named: "METEO")?.name == "Open-Meteo")
        #expect(ProviderCatalog.entry(named: "fly.io")?.name == "Fly.io")
        #expect(ServiceCategory.suggested(forProvider: "HuggingFace") == .ai)
        #expect(ServiceCategory.suggested(forProvider: "JEV") == nil)
    }

    @Test func catalogIsConsistent() {
        let names = ProviderCatalog.entries.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count, "duplicate provider names")
        var owner: [String: String] = [:]
        for entry in ProviderCatalog.entries {
            for alias in entry.aliases {
                #expect(!alias.isEmpty && alias.allSatisfy { $0 == $0.uppercased() && !$0.contains("_") }, "\(entry.name): \(alias)")
                let key = alias.joined(separator: "_")
                if let other = owner[key] { Issue.record("\(key) belongs to \(other) and \(entry.name)") }
                owner[key] = entry.name
            }
        }
        #expect(ProviderCatalog.entries.count >= 150)
    }

    @Test func newServicesRoundTrip() {
        for category in [ServiceCategory.messaging, .cms, .flags, .dataAPI] {
            #expect(ServiceCategory(matching: category.displayName) == category)
        }
        #expect(ServiceCategory(matching: "sms") == .messaging)
        #expect(ServiceCategory(matching: "weather") == .dataAPI)
        #expect(ServiceCategory(matching: "feature flags") == .flags)
    }
}
