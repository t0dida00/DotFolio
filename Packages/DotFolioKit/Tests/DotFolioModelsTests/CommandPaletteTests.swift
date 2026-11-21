import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct CommandPaletteTests {
    @Test func ranksExactThenPrefixThenWordThenContains() {
        #expect(CommandPalette.rank("Stripe", "stripe") == 0)
        #expect(CommandPalette.rank("STRIPE_SECRET_KEY", "stripe") == 1)
        #expect(CommandPalette.rank("NEXT_PUBLIC_STRIPE_KEY", "stripe") == 2)
        #expect(CommandPalette.rank("mystripekey", "stripe") == 3)
        #expect(CommandPalette.rank("OpenAI", "stripe") == nil)
    }

    @Test func projectsBeforeKeysBeforeActionsAndMetadataOnly() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let shop = Project.create(name: "Shop", in: context)
        let env = shop.sortedEnvironments[0]
        let key = Variable(key: "SHOP_URL", environment: nil)
        context.insert(key)
        key.environment = env
        let stripe = Variable(key: "API_KEY", environment: nil)
        context.insert(stripe)
        stripe.environment = env
        stripe.serviceLabel = "Stripe"

        let shopResults = CommandPalette.results(query: "shop", projects: [shop], variables: [key, stripe])
        #expect(shopResults.map(\.title).prefix(2) == ["Shop", "SHOP_URL"])
        // Provider matches, but as a weaker hit than a name.
        #expect(CommandPalette.results(query: "stripe", projects: [shop], variables: [key, stripe]).map(\.title) == ["API_KEY"])
        #expect(CommandPalette.results(query: "verify", projects: [], variables: []).map(\.title) == ["Verify Data…"])
        #expect(CommandPalette.results(query: "  ", projects: [shop], variables: [key]).isEmpty)
        #expect(stripe.hasValue == false) // values are never looked at
    }

    @Test func sameNameFollowsEnvironmentOrder() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let shop = Project.create(name: "Shop", in: context)
        var vars: [Variable] = []
        for env in shop.sortedEnvironments.reversed() {   // inserted production first
            let v = Variable(key: "DATABASE_URL", environment: nil)
            context.insert(v)
            v.environment = env
            vars.append(v)
        }
        let order = CommandPalette.results(query: "database", projects: [], variables: vars).compactMap { item -> String? in
            if case .variable(let v) = item { return v.environment?.name }
            return nil
        }
        #expect(order == ["development", "staging", "production"])
    }
}
