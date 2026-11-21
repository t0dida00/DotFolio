import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct LibraryEverythingTests {
    @Test func showsLibraryAndProjectKeysAndForgetsDeletedProjects() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let mine = Variable(key: "OPENAI_API_KEY", environment: nil)
        mine.inLibrary = true
        mine.serviceLabel = "OpenAI"
        context.insert(mine)

        let shop = Project.create(name: "Shop", in: context)
        for env in shop.sortedEnvironments {
            let v = Variable(key: "OPENAI_API_KEY", environment: nil)
            context.insert(v)
            v.environment = env
            v.serviceLabel = "OpenAI"
        }
        try context.save()

        func everything() throws -> [Variable] {
            let library = try context.fetch(FetchDescriptor<Variable>(predicate: #Predicate { $0.inLibrary }))
            let projects = try context.fetch(FetchDescriptor<Variable>(predicate: #Predicate { !$0.inLibrary }))
            return Library.everything(libraryKeys: library, projectVariables: projects)
        }

        let rows = try everything()
        #expect(rows.map(Library.origin(of:)) == ["Library", "Shop · development", "Shop · staging", "Shop · production"])
        #expect(Library.filter(rows, query: "shop").count == 3)
        #expect(rows.filter(Library.Scope.library.matches).map(Library.origin(of:)) == ["Library"])
        #expect(rows.filter(Library.Scope(rawValue: "production").matches).map(Library.origin(of:)) == ["Shop · production"])
        #expect(rows.filter(Library.Scope(rawValue: "all").matches).count == 4)
        #expect(Library.Scope(rawValue: "staging").rawValue == "staging")

        context.delete(shop)
        try context.save()
        let after = try everything()
        #expect(after.map(Library.origin(of:)) == ["Library"])   // the Library's own key stays
    }

    @Test func groupsByProviderWithOtherLast() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        func key(_ name: String, _ provider: String) -> Variable {
            let v = Variable(key: name, environment: nil)
            v.inLibrary = true
            v.serviceLabel = provider
            context.insert(v)
            return v
        }
        let groups = Library.groups([key("B", "stripe"), key("A", "Stripe"), key("X", ""), key("K", "OpenAI")])
        #expect(groups.map(\.provider) == ["OpenAI", "stripe", ""])
        #expect(groups[1].keys.map(\.key) == ["A", "B"])
    }
}
