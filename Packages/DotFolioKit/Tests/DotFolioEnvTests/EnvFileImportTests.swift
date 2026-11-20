import Foundation
import Testing
@testable import DotFolioEnv

struct EnvFileImportTests {
    @Test(arguments: [
        (".env", EnvFileKind.environment("development")),
        (".env.local", .environment("development")),
        (".env.development", .environment("development")),
        (".env.development.local", .environment("development")),
        (".env.dev", .environment("development")),
        (".env.staging", .environment("staging")),
        (".env.preview", .environment("staging")),
        (".env.production", .environment("production")),
        (".env.prod.local", .environment("production")),
        ("production.env", .environment("production")),
        (".ENV.PRODUCTION", .environment("production")),
        (".env.example", .template),
        (".env.production.example", .template),
        (".env.sample", .template),
        (".env.template", .template),
        (".env.test", .unknown),
        ("secrets.env", .unknown),
    ])
    func kindFromFileName(name: String, expected: EnvFileKind) {
        #expect(EnvFileImport.kind(forFileName: name) == expected)
    }

    @Test func parsesUTF8Data() throws {
        let entries = try EnvFileImport.entries(from: Data("A=1\nexport B=\"two\"\n".utf8))
        #expect(entries.map(\.key) == ["A", "B"])
        #expect(entries.map(\.value) == ["1", "two"])
    }

    @Test func refusesHugeOrBinaryFiles() {
        #expect(throws: EnvFileImport.Failure.tooLarge) {
            try EnvFileImport.entries(from: Data(count: EnvFileImport.maxBytes + 1))
        }
        #expect(throws: EnvFileImport.Failure.notText) {
            try EnvFileImport.entries(from: Data([0xFF, 0xFE, 0xFD]))
        }
    }
}
