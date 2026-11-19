import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

@MainActor
struct IntegrityCheckTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let env: ProjectEnvironment

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
    }

    @Test func cleanDataReportsNothing() throws {
        try VariableEditor.add(key: "A", value: "1", to: env, context: context, secrets: secrets)
        try context.save()
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func findsAndRepairsKeychainMismatches() throws {
        let gone = try VariableEditor.add(key: "GONE", value: "x", to: env, context: context, secrets: secrets)
        try secrets.delete(gone.secretRef.uuidString)          // item lost
        try secrets.setString("leftover", for: UUID().uuidString) // orphan item
        try context.save()

        let report = try IntegrityCheck.run(context: context, secrets: secrets)
        #expect(report.missingSecrets.map(\.key) == ["GONE"])
        #expect(report.orphanedSecretRefs.count == 1)

        #expect(try IntegrityCheck.repair(report, context: context, secrets: secrets) == 2)
        #expect(!gone.hasValue)
        #expect(secrets.itemCount == 0)
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func reportsDuplicatesWithoutTouchingThem() throws {
        try VariableEditor.add(key: "DUP", to: env, context: context, secrets: secrets)
        let twin = Variable(key: "DUP", environment: nil)
        context.insert(twin)
        twin.environment = env // bypasses the editor's validation, like old data might
        try context.save()

        let report = try IntegrityCheck.run(context: context, secrets: secrets)
        #expect(report.duplicateKeys == [.init(project: "Shop", environment: "development", key: "DUP")])
        #expect(report.fixableCount == 0)
    }

    @Test func removesOrphanMetadataKeychainFirst() throws {
        let orphan = Variable(key: "LOST", environment: nil)
        context.insert(orphan)
        try secrets.setString("v", for: orphan.secretRef.uuidString)
        orphan.hasValue = true
        let account = Account(login: "me@gmail.com", services: ["Supabase", "Database"])
        context.insert(account)
        try context.save()

        let report = try IntegrityCheck.run(context: context, secrets: secrets)
        #expect(report.orphanVariables.count == 1)
        #expect(report.accountsWithCategoryWords.count == 1)
        try IntegrityCheck.repair(report, context: context, secrets: secrets)
        #expect(secrets.itemCount == 0)
        #expect(account.services == ["Supabase"])
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 0)
    }
}

/// The database file must never contain a secret value — only the Keychain does.
@MainActor
struct SecretsNeverInDatabaseTests {
    @Test func storeFileDoesNotContainValues() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dotfolio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "test.store")
        let container = try ModelContainer(for: Schema(DotFolioSchema.models), configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let secrets = InMemorySecretStore()
        let secret = "sk_live_SUPER_SECRET_\(UUID().uuidString)"

        var draft = ProjectDraft()
        draft.name = "Shop"
        draft.rows = [EnvDraftRow(key: "STRIPE_KEY", value: secret)]
        let project = try ProjectCreator.create(draft, includeValues: true, context: context, secrets: secrets)
        let v = try #require(project.allVariables.first)
        try VariableEditor.setValue(v, to: secret + "_rotated", secrets: secrets)
        try context.save()

        // Every file SwiftData wrote (store, -wal, -shm).
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
        for file in files {
            let bytes = try Data(contentsOf: file)
            #expect(bytes.range(of: Data("SUPER_SECRET".utf8)) == nil, "secret found in \(file.lastPathComponent)")
        }
        #expect(try secrets.string(for: v.secretRef.uuidString) == secret + "_rotated")
    }
}
