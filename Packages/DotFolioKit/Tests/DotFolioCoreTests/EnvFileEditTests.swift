import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity

@MainActor
struct EnvFileEditTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let env: ProjectEnvironment

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
    }

    private func values() throws -> [UUID: String] {
        var out: [UUID: String] = [:]
        for v in env.sortedVariables where v.hasValue {
            out[v.id] = try VariableEditor.value(of: v, secrets: secrets, context: LAContext())
        }
        return out
    }

    private func variable(_ key: String) -> Variable? { env.sortedVariables.first { $0.key == key } }

    @Test func unchangedTextChangesNothing() throws {
        try VariableEditor.add(key: "API_KEY", value: "sk live", category: "AI", service: "OpenAI",
                               account: "me@x.com", link: "https://platform.openai.com/api-keys",
                               to: env, context: context, secrets: secrets)
        try VariableEditor.add(key: "EMPTY", to: env, context: context, secrets: secrets)
        let current = try values()
        let text = EnvFileEdit.text(for: env.sortedVariables, values: current)
        #expect(text == "API_KEY=\"sk live\" #AI/OpenAI/me@x.com/https://platform.openai.com/api-keys\nEMPTY=\n")
        #expect(EnvFileEdit.plan(text, for: env, currentValues: current).isEmpty)
    }

    @Test func addsChangesAndRemoves() throws {
        try VariableEditor.add(key: "KEEP", value: "old", to: env, context: context, secrets: secrets)
        try VariableEditor.add(key: "GONE", value: "bye", to: env, context: context, secrets: secrets)
        try VariableEditor.add(key: "CLEAR", value: "x", to: env, context: context, secrets: secrets)
        let current = try values()

        let text = """
        CLEAR=
        KEEP=new #Database/Supabase/me@x.com
        NEW_ONE=abc #Cache/Redis
        """
        let plan = EnvFileEdit.plan(text, for: env, currentValues: current)
        #expect(plan.added.map(\.key) == ["NEW_ONE"])
        #expect(plan.values == ["CLEAR": "", "KEEP": "new"])
        #expect(plan.sources == ["KEEP": EnvSource(service: "Database", provider: "Supabase", account: "me@x.com")])
        #expect(plan.removed == ["GONE"])

        try EnvFileEdit.apply(plan, to: env, context: context, secrets: secrets)
        try context.save()
        #expect(env.sortedVariables.map(\.key) == ["CLEAR", "KEEP", "NEW_ONE"])
        #expect(variable("CLEAR")?.hasValue == false)
        #expect(variable("KEEP")?.serviceLabel == "Supabase")
        #expect(variable("KEEP")?.account?.login == "me@x.com")
        #expect(variable("NEW_ONE")?.serviceCategory == "Cache")
        let after = try values()
        #expect(after[variable("KEEP")!.id] == "new")
        #expect(after[variable("NEW_ONE")!.id] == "abc")
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func unreadValueIsNeverCleared() throws {
        try VariableEditor.add(key: "SECRET", value: "s3cret", to: env, context: context, secrets: secrets)
        // Value not read (empty currentValues): an empty value in the text keeps it.
        #expect(EnvFileEdit.plan("SECRET=\n", for: env, currentValues: [:]).isEmpty)
        #expect(EnvFileEdit.plan("SECRET=other\n", for: env, currentValues: [:]).values == ["SECRET": "other"])
    }

    @Test func badLinkChangesNothing() throws {
        try VariableEditor.add(key: "A", value: "1", to: env, context: context, secrets: secrets)
        let plan = EnvFileEdit.plan("A=2\nB=3 #AI/OpenAI/me@x.com/not a link\n", for: env, currentValues: try values())
        #expect(throws: EnvFileEdit.Failure.invalidLink(key: "B")) {
            try EnvFileEdit.apply(plan, to: env, context: context, secrets: secrets)
        }
        #expect(env.sortedVariables.map(\.key) == ["A"])
        #expect(try values()[variable("A")!.id] == "1")
    }

    @Test func roundTripsTrickyValues() throws {
        for (i, value) in ["has #hash", "price $5", "multi\nline", "it's \"quoted\""].enumerated() {
            try VariableEditor.add(key: "K\(i)", value: value, to: env, context: context, secrets: secrets)
        }
        let current = try values()
        let text = EnvFileEdit.text(for: env.sortedVariables, values: current)
        #expect(EnvFileEdit.plan(text, for: env, currentValues: current).isEmpty)
    }
}
