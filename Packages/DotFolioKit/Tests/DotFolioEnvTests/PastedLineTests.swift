import Testing
@testable import DotFolioEnv

/// A single line with a #Service/Provider/Account/Link comment.
struct PastedLineTests {
    @Test func oneLineFillsEveryPart() {
        let entries = EnvParser.parse(#"test2="this is another test" #AI/ClaudeCode/me@x.com"#)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.key == "test2")
        #expect(entry.value == "this is another test")
        #expect(entry.source == EnvSource(service: "AI", provider: "ClaudeCode", account: "me@x.com"))
    }

    @Test func exportPrefixAndLinkWork() {
        let entry = EnvParser.parse("export DB_URL=postgres://x #Database/Supabase/me@x.com/https://supabase.com/dashboard").first
        #expect(entry?.key == "DB_URL")
        #expect(entry?.source.link == "https://supabase.com/dashboard")
    }
}
