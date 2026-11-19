import Testing
@testable import DotFolioEnv

struct EnvExporterTests {
    @Test(arguments: [
        "plain", "", "with space", "has#hash", "quote\"inside", "it's", "price $5 and ${HOME}",
        "back\\slash", "multi\nline\nvalue", "tab\there", " leading", "trailing ", "a=b", "`tick`",
        "-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----", "unicode ✓ tiếng Việt",
        "both $ and ' quote",
    ])
    func roundTripsThroughParser(value: String) {
        let text = EnvExporter.render([EnvEntry(key: "KEY", value: value)])
        #expect(EnvParser.parse(text) == [EnvEntry(key: "KEY", value: value)])
    }

    @Test func simpleValuesStayBare() {
        #expect(EnvExporter.render([EnvEntry(key: "A", value: "abc123"), EnvEntry(key: "B", value: "")]) == "A=abc123\nB=\n")
    }

    @Test func dollarValuesUseSingleQuotes() {
        #expect(EnvExporter.quote("pa$$word") == "'pa$$word'")
    }

    @Test func writesHeaderAndComments() {
        let text = EnvExporter.render([EnvEntry(key: "A", value: "1", comment: "first\nsecond")], header: ["Exported by DotFolio"])
        #expect(text == "# Exported by DotFolio\n\n# first\n# second\nA=1\n")
    }
}

struct GitignoreCheckTests {
    @Test(arguments: [".env", ".env*", "/.env", "**/.env", "*.env", ".env.*\n.env"])
    func recognizesCommonPatterns(pattern: String) {
        #expect(GitignoreCheck.ignores(".env", gitignore: pattern))
    }

    @Test func productionFile() {
        #expect(GitignoreCheck.ignores(".env.production", gitignore: ".env*"))
        #expect(GitignoreCheck.ignores(".env.production", gitignore: ".env.*"))
        #expect(!GitignoreCheck.ignores(".env.production", gitignore: ".env"))
    }

    @Test func negationAndUnrelatedLines() {
        #expect(!GitignoreCheck.ignores(".env", gitignore: ".env*\n!.env"))
        #expect(!GitignoreCheck.ignores(".env", gitignore: "node_modules/\n# .env\ndist"))
        #expect(!GitignoreCheck.ignores(".env", gitignore: ""))
    }
}
