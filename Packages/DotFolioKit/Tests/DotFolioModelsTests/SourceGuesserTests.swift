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
        Case(key: "NEXTAUTH_SECRET", service: "Auth", provider: nil),
        Case(key: "SMTP_HOST", service: "Email", provider: nil),
        Case(key: "DATA_STORE", service: nil, provider: nil),
        Case(key: "OWNER_EMAIL", service: nil, provider: nil),
        Case(key: "PUBLIC_URL", service: nil, provider: nil),
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
}
