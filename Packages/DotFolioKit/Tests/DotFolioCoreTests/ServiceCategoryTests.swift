import Foundation
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

@MainActor
struct ServiceCategoryTests {
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let env: ProjectEnvironment

    init() throws {
        context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        env = Project.create(name: "Shop", in: context).sortedEnvironments[0]
    }

    @Test func matchingAndSuggestions() {
        #expect(ServiceCategory(matching: "db") == .database)
        #expect(ServiceCategory(matching: "Cache") == .cache)
        #expect(ServiceCategory(matching: "Supabase") == nil)
        #expect(ServiceCategory.suggested(forProvider: "Redis") == .cache)
        #expect(ServiceCategory.suggested(forProvider: "Upstash Redis") == .cache)
        #expect(ServiceCategory.suggested(forProvider: "Stripe") == .payments)
        #expect(ServiceCategory.suggested(forProvider: "Firebase") == nil)
    }

    @Test func categoryAndProviderAreSeparate() throws {
        let v = try VariableEditor.add(key: "DATABASE_URL", category: "db", service: "Supabase", account: "me@gmail.com",
                                       to: env, context: context, secrets: secrets)
        #expect(v.serviceCategory == "Database")
        #expect(v.displayService == "Supabase")
        #expect(v.account?.services == ["Supabase"]) // only providers go on the account
        VariableEditor.setCategory(v, to: "storage")
        #expect(v.displayCategory == "Storage")
    }

    @Test func categoryIsGuessedFromProviderWhenEmpty() throws {
        let v = try VariableEditor.add(key: "REDIS_URL", service: "Redis", to: env, context: context, secrets: secrets)
        #expect(v.serviceCategory.isEmpty)
        #expect(v.displayCategory == "Cache")
    }

    @Test func migrationMovesCategoryWordsOutOfProvider() throws {
        let account = Account(login: "me@gmail.com", services: ["Supabase", "Database"])
        context.insert(account)
        let wrong = Variable(key: "DB_URL", environment: nil)
        context.insert(wrong)
        wrong.environment = env
        wrong.serviceLabel = "Database"
        wrong.account = account
        let right = Variable(key: "SUPA_KEY", environment: nil)
        context.insert(right)
        right.environment = env
        right.serviceLabel = "Supabase"

        #expect(ServiceCategoryMigration.run(context: context) == 1)
        #expect(wrong.serviceLabel.isEmpty)
        #expect(wrong.serviceCategory == "Database")
        #expect(right.serviceLabel == "Supabase")
        #expect(account.services == ["Supabase"])
        #expect(ServiceCategoryMigration.run(context: context) == 0) // idempotent
    }
}
