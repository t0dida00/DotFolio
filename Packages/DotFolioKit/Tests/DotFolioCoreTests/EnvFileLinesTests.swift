import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity

@MainActor
struct EnvFileLinesTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    init() throws { context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true)) }

    @Test func hidesValuesAndMarksMissingOnes() throws {
        let env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
        try VariableEditor.add(key: "API_KEY", value: "sk live", to: env, context: context, secrets: secrets)
        try VariableEditor.add(key: "EMPTY", to: env, context: context, secrets: secrets)

        let lines = EnvFileLines.lines(for: env.sortedVariables)
        #expect(lines == [
            EnvFileLines.Line(key: "API_KEY", value: .hidden, source: ""),
            EnvFileLines.Line(key: "EMPTY", value: .missing, source: ""),
        ])
    }

    @Test func revealedValuesAreQuotedLikeAnExport() throws {
        let env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
        try VariableEditor.add(key: "API_KEY", value: "sk live", to: env, context: context, secrets: secrets)
        let v = env.sortedVariables[0]

        let lines = EnvFileLines.lines(for: [v], revealed: [v.id: "sk live"])
        #expect(lines == [EnvFileLines.Line(key: "API_KEY", value: .plain("\"sk live\""), source: "")])
    }

    @Test func oneLinePerVariableWithSourceAndNoNotes() throws {
        let env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
        try VariableEditor.add(key: "OPENAI_API_KEY", to: env, context: context, secrets: secrets)
        let v = env.sortedVariables[0]
        v.notes = "Personal key\nRotate yearly"
        VariableEditor.setCategory(v, to: "AI")
        VariableEditor.setService(v, to: "OpenAI")
        VariableEditor.setAccount(v, login: "me@example.com", context: context)
        try VariableEditor.setLink(v, to: "https://platform.openai.com/api-keys")

        let lines = EnvFileLines.lines(for: [v])
        #expect(lines == [
            EnvFileLines.Line(key: "OPENAI_API_KEY", value: .missing,
                   source: "AI/OpenAI/me@example.com/https://platform.openai.com/api-keys"),
        ])
    }
}

struct EnvSourceCommentTests {
    @Test(arguments: [
        EnvSource(service: "AI", provider: "OpenAI", account: "me@x.com", link: "https://a.b/c/d"),
        EnvSource(service: "Database", provider: "Supabase"),
        EnvSource(service: "Cache"),
        EnvSource(provider: "Stripe"),
        EnvSource(account: "me@x.com"),
        EnvSource(link: "https://dash.example.com/keys"),
    ])
    func roundTripsThroughInitComment(source: EnvSource) {
        #expect(EnvSource(comment: source.comment) == source)
    }

    @Test func emptySourceHasNoComment() {
        #expect(EnvSource().comment == "")
    }

    @Test func trailingEmptyFieldsAreDropped() {
        #expect(EnvSource(service: "Database", provider: "Supabase").comment == "Database/Supabase")
        #expect(EnvSource(service: "Cache").comment == "Cache/")
    }
}
