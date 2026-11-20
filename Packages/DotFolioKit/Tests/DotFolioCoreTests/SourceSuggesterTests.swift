import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity

@MainActor
struct SourceSuggesterTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let project: Project

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        project = Project.create(name: "Shop", in: context)
    }

    private var dev: ProjectEnvironment { project.sortedEnvironments.first { $0.name == "development" }! }
    private var prod: ProjectEnvironment { project.sortedEnvironments.first { $0.name == "production" }! }

    @Test func newVariablesGetEmptyFieldsFilled() throws {
        let auth = try VariableEditor.add(key: "FIREBASE_AUTH_DOMAIN", to: dev, context: context, secrets: secrets)
        #expect(auth.serviceCategory == "Auth")
        #expect(auth.serviceLabel == "Firebase")
        let model = try VariableEditor.add(key: "NUXT_HF_MODEL", to: dev, context: context, secrets: secrets)
        #expect(model.serviceCategory == "")       // AI is already implied by Hugging Face
        #expect(model.displayCategory == "AI")
        #expect(model.serviceLabel == "Hugging Face")
        let plain = try VariableEditor.add(key: "OWNER_EMAIL", to: dev, context: context, secrets: secrets)
        #expect(plain.serviceCategory == "" && plain.serviceLabel == "")
    }

    @Test func whatTheUserTypedIsNeverReplaced() throws {
        let v = try VariableEditor.add(key: "STRIPE_SECRET_KEY", category: "Billing", service: "Paddle",
                                       to: dev, context: context, secrets: secrets)
        #expect(v.serviceCategory == "Payments")   // "Billing" normalized, not replaced
        #expect(v.serviceLabel == "Paddle")
    }

    @Test func valueHintsAreUsedOnlyWhileAdding() throws {
        let v = try VariableEditor.add(key: "SECRET", value: "sk_test_123", to: dev, context: context, secrets: secrets)
        #expect(v.serviceLabel == "Stripe")
        #expect(v.displayCategory == "Payments")
    }

    @Test func earlierChoiceForTheSameNameWins() throws {
        let first = try VariableEditor.add(key: "DATA_STORE", to: dev, context: context, secrets: secrets)
        VariableEditor.setService(first, to: "Supabase")
        VariableEditor.setCategory(first, to: "Database")
        let second = try VariableEditor.add(key: "DATA_STORE", to: prod, context: context, secrets: secrets)
        #expect(second.serviceLabel == "Supabase")
        #expect(second.serviceCategory == "")      // Database is implied by Supabase
        #expect(second.displayCategory == "Database")
        #expect(SourceSuggester.suggest(key: "DATA_STORE", history: SourceHistory(context: context))?.reason
                == "Same name used elsewhere")
    }

    @Test func envCommentBeatsTheGuess() throws {
        let plan = EnvFileEdit.plan("REDIS_URL=x #Queue/Upstash\n", for: dev, currentValues: [:])
        try EnvFileEdit.apply(plan, to: dev, context: context, secrets: secrets)
        let v = try #require(dev.sortedVariables.first)
        #expect(v.serviceCategory == "Queue")
        #expect(v.serviceLabel == "Upstash")
    }

    @Test func libraryKeysMoveOnlyWhenTheNameStaysUnique() throws {
        try VariableEditor.addToLibrary(key: "STRIPE_SECRET_KEY", provider: "Stripe", context: context, secrets: secrets)
        // Same name, no provider given: guessing Stripe would clash, so it stays put.
        let other = try VariableEditor.addToLibrary(key: "STRIPE_SECRET_KEY", context: context, secrets: secrets)
        #expect(other.serviceLabel == "")
        let fresh = try VariableEditor.addToLibrary(key: "OPENAI_API_KEY", context: context, secrets: secrets)
        #expect(fresh.serviceLabel == "OpenAI")
    }

    @Test func reviewListsOnlyWhatWouldChangeAndApplies() throws {
        // Created as from a repo import: no guessing at creation time.
        for key in ["DATABASE_URL", "FIREBASE_API_KEY", "PUBLIC_URL"] {
            let v = Variable(key: key, environment: nil)
            context.insert(v)
            v.environment = dev
        }
        let items = SourceSuggester.reviewAll(context: context)
        #expect(items.map(\.key) == ["DATABASE_URL", "FIREBASE_API_KEY"])
        #expect(items.first?.place == "Shop · development")
        #expect(items.first?.service == "Database")
        #expect(items.first?.provider == nil)
        #expect(items.last?.provider == "Firebase")

        #expect(SourceSuggester.apply(items, context: context) == 2)
        #expect(SourceSuggester.reviewAll(context: context).isEmpty)
        #expect(try IntegrityCheck.run(context: context, secrets: secrets).isClean)
    }

    @Test func repoImportFillsSources() throws {
        let repo = RepoImporter.RepoInfo(provider: .github, fullName: "me/app", url: URL(string: "https://github.com/me/app")!,
                                         defaultBranch: "main", description: nil)
        let p = RepoImporter.importRepo(repo, envExample: "STRIPE_SECRET_KEY=sk_test_xxx\nOWNER_EMAIL=\n",
                                        envExampleSHA: nil, context: context)
        let keys = p.sortedEnvironments[0].sortedVariables
        #expect(keys.first { $0.key == "STRIPE_SECRET_KEY" }?.serviceLabel == "Stripe")
        #expect(keys.first { $0.key == "OWNER_EMAIL" }?.serviceLabel == "")
    }
}
