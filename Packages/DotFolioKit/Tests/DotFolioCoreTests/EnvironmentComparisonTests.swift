import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioModels
import DotFolioSecurity

@MainActor
struct EnvironmentComparisonTests {
    @Test func rowsCellsVerdictsAndSummary() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let secrets = InMemorySecretStore()
        let project = Project.create(name: "Shop", in: context)
        let envs = project.sortedEnvironments // development, staging, production
        func add(_ key: String, _ value: String, _ env: ProjectEnvironment) throws {
            try VariableEditor.add(key: key, value: value, to: env, context: context, secrets: secrets)
        }
        try add("SAME", "x", envs[0]); try add("SAME", "x", envs[1]); try add("SAME", "x", envs[2])
        try add("DIFF", "a", envs[0]); try add("DIFF", "a", envs[1]); try add("DIFF", "b", envs[2])
        try add("ONLY_DEV", "1", envs[0])
        try add("EMPTY", "", envs[0]); try add("EMPTY", "v", envs[2])
        try context.save()

        let rows = EnvironmentComparison.rows(for: project)
        #expect(rows.map(\.key) == ["DIFF", "EMPTY", "ONLY_DEV", "SAME"])
        let onlyDev = rows.first { $0.key == "ONLY_DEV" }!
        #expect(onlyDev.cells == ["development": .hasValue, "staging": .missing, "production": .missing])
        #expect(onlyDev.missingIn == ["production", "staging"])

        let order = envs.map(\.name)
        let compared = try EnvironmentComparison.compareValues(rows, environmentOrder: order, secrets: secrets, context: LAContext())
        func verdict(_ key: String) -> EnvironmentComparison.Verdict? { compared.first { $0.key == key }?.verdict }
        #expect(verdict("SAME") == .same)
        #expect(verdict("DIFF") == .differs(groups: [["development", "staging"], ["production"]]))
        #expect(verdict("ONLY_DEV") == .notComparable)
        #expect(verdict("EMPTY") == .notComparable)   // only one environment has a value

        let summary = EnvironmentComparison.summary(compared)
        #expect(summary == .init(total: 4, missingSomewhere: 2, onlyInOne: 1, same: 1, differs: 1))
        // No plain value appears in the output.
        #expect(!String(describing: compared.map(\.verdict)).contains("\"a\""))
    }
}
