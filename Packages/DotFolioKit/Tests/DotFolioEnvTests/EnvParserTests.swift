import Testing
@testable import DotFolioEnv

struct EnvParserTests {
    @Test func parsesBasicLines() {
        let entries = EnvParser.parse("""
        API_KEY=abc
        export DB_URL = postgres://u:p@h:5432/db
        EMPTY=
        """)
        #expect(entries == [
            EnvEntry(key: "API_KEY", value: "abc"),
            EnvEntry(key: "DB_URL", value: "postgres://u:p@h:5432/db"),
            EnvEntry(key: "EMPTY", value: ""),
        ])
    }

    @Test func keepsCommentAboveAsNote() {
        let entries = EnvParser.parse("""
        # Firebase web API key
        # from the console
        FIREBASE_API_KEY=

        # orphan comment

        OTHER=1
        """)
        #expect(entries[0].comment == "Firebase web API key\nfrom the console")
        #expect(entries[1].comment == "")
    }

    @Test func handlesQuotesAndInlineComments() {
        let entries = EnvParser.parse(#"""
        A="hello # not a comment"
        B='single $LITERAL \n'
        C=plain value # trailing comment
        D="line1\nline2"
        E=url#fragment
        """#)
        #expect(entries.map(\.value) == ["hello # not a comment", #"single $LITERAL \n"#, "plain value", "line1\nline2", "url#fragment"])
    }

    @Test func multilineDoubleQuotedValue() {
        let entries = EnvParser.parse("""
        KEY="-----BEGIN KEY-----
        abc
        -----END KEY-----"
        NEXT=1
        """)
        #expect(entries[0].value == "-----BEGIN KEY-----\nabc\n-----END KEY-----")
        #expect(entries[1].key == "NEXT")
    }

    @Test func skipsInvalidKeysAndLastDuplicateWins() {
        let entries = EnvParser.parse("""
        1BAD=x
        GOOD-ISH=x
        no_equals_sign
        DUP=first
        DUP=second
        """)
        #expect(entries == [EnvEntry(key: "DUP", value: "second")])
    }

    @Test func handlesWindowsLineEndings() {
        #expect(EnvParser.parse("A=1\r\nB=2\r\n").map(\.key) == ["A", "B"])
    }
}
