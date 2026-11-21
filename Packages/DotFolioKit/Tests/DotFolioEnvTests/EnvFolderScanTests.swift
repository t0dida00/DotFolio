import Foundation
import Testing
@testable import DotFolioEnv

struct EnvFolderScanTests {
    @Test func recognizesEnvFileNames() {
        for name in [".env", ".env.local", ".env.production", ".env.example", "production.env"] {
            #expect(EnvFolderScan.isEnvFileName(name), "\(name)")
        }
        for name in [".envrc", ".environment", "env", "README.md", ".env-cmdrc"] {
            #expect(!EnvFolderScan.isEnvFileName(name), "\(name)")
        }
    }

    @Test func scansThreeLevelsAndSkipsDependencies() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("A=1\n".utf8).write(to: url)
        }
        try write(".env")
        try write(".env.production")
        try write(".envrc")
        try write("apps/web/.env.local")
        try write("a/b/c/.env")        // depth 3: found
        try write("a/b/c/d/.env")      // depth 4: too deep
        try write("node_modules/pkg/.env")
        try write(".git/.env")
        try write("build/.env")

        let found = EnvFolderScan.scan(root).map(\.relativePath)
        #expect(found == [".env", ".env.production", "apps/web/.env.local", "a/b/c/.env"])
    }

    @Test func stopsAtMaxFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<5 { try Data().write(to: root.appending(path: ".env.f\(i)")) }
        #expect(EnvFolderScan.scan(root, maxFiles: 3).count == 3)
    }

    @Test func readsTheOriginRemote() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/other/fork.git
        [remote "origin"]
        \turl = git@github.com:octo/shop.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        """
        #expect(EnvFolderScan.repoWebURL(gitConfig: config) == URL(string: "https://github.com/octo/shop"))
        #expect(EnvFolderScan.webURL(fromRemote: "ssh://git@gitlab.com/group/sub/app.git") == URL(string: "https://gitlab.com/group/sub/app"))
        #expect(EnvFolderScan.webURL(fromRemote: "https://user@GitHub.com/octo/shop") == URL(string: "https://github.com/octo/shop"))
        #expect(EnvFolderScan.webURL(fromRemote: "/local/path/repo.git") == nil)
        #expect(EnvFolderScan.repoWebURL(gitConfig: "[core]\n\tbare = false\n") == nil)
    }
}
