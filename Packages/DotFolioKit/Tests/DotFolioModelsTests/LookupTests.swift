import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct LookupTests {
    /// Builds the example from the spec: Project A uses Firebase account
    /// khoa.work@gmail.com / projecta-prod in production, plus a Stripe key.
    private struct Fixture {
        let context: ModelContext
        let firebaseWork: Account
        let firebasePersonal: Account
        let stripe: Account
        let projectaProd: ServiceProject
        let projectA: Project
        let projectB: Project
        let prod: ProjectEnvironment
    }

    private func makeFixture() throws -> Fixture {
        let container = try DotFolioSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let firebaseWork = Account(serviceType: .firebase, login: "khoa.work@gmail.com")
        let firebasePersonal = Account(serviceType: .firebase, login: "me@personal.dev")
        let stripe = Account(serviceType: .stripe, login: "billing@client.com")
        [firebaseWork, firebasePersonal, stripe].forEach(context.insert)

        let projectaProd = ServiceProject(name: "Project A prod", externalID: "projecta-prod", account: firebaseWork)
        context.insert(projectaProd)

        let projectA = Project(name: "Project A", provider: .github, repoFullName: "khoa/project-a")
        let projectB = Project(name: "Project B")
        [projectA, projectB].forEach(context.insert)

        let dev = ProjectEnvironment(name: "development", sortOrder: 0, project: projectA)
        let prod = ProjectEnvironment(name: "production", sortOrder: 2, isProtected: true, project: projectA)
        let bDev = ProjectEnvironment(name: "development", project: projectB)
        [dev, prod, bDev].forEach(context.insert)

        func variable(_ key: String, in env: ProjectEnvironment) -> Variable {
            let v = Variable(key: key, environment: env)
            context.insert(v)
            return v
        }

        variable("FIREBASE_API_KEY", in: prod).link(account: nil, serviceProject: projectaProd)
        variable("FIREBASE_PROJECT_ID", in: prod).link(account: nil, serviceProject: projectaProd)
        variable("FIREBASE_API_KEY", in: dev).link(account: firebasePersonal, serviceProject: nil)
        variable("STRIPE_SECRET_KEY", in: prod).link(account: stripe, serviceProject: nil)
        _ = variable("UNLINKED", in: dev)
        variable("STRIPE_SECRET_KEY", in: bDev).link(account: stripe, serviceProject: nil)

        try context.save()
        return Fixture(context: context, firebaseWork: firebaseWork, firebasePersonal: firebasePersonal,
                       stripe: stripe, projectaProd: projectaProd, projectA: projectA, projectB: projectB, prod: prod)
    }

    @Test func linkingAServiceProjectImpliesItsAccount() throws {
        let f = try makeFixture()
        let v = try #require(f.prod.variables?.first { $0.key == "FIREBASE_API_KEY" })
        #expect(v.account?.login == "khoa.work@gmail.com")
        #expect(v.serviceProject?.externalID == "projecta-prod")
    }

    @Test func linkingAServiceProjectOverridesAMismatchedAccount() throws {
        let f = try makeFixture()
        let v = Variable(key: "X", environment: f.prod)
        f.context.insert(v)
        v.link(account: f.firebasePersonal, serviceProject: f.projectaProd)
        #expect(v.account?.id == f.firebaseWork.id)
    }

    @Test func projectSourceUsagesGroupByAccountAndServiceProject() throws {
        let f = try makeFixture()
        let usages = f.projectA.sourceUsages
        #expect(usages.count == 3)

        let prodFirebase = try #require(usages.first { $0.serviceProject?.externalID == "projecta-prod" })
        #expect(prodFirebase.account.login == "khoa.work@gmail.com")
        #expect(Set(prodFirebase.variables.map(\.key)) == ["FIREBASE_API_KEY", "FIREBASE_PROJECT_ID"])

        #expect(Set(f.projectA.linkedAccounts.map(\.login)) ==
                ["khoa.work@gmail.com", "me@personal.dev", "billing@client.com"])
    }

    @Test func accountListsProjectsThatUseIt() throws {
        let f = try makeFixture()
        #expect(f.firebaseWork.linkedProjects.map(\.name) == ["Project A"])
        #expect(Set(f.stripe.linkedProjects.map(\.name)) == ["Project A", "Project B"])
        #expect(f.projectaProd.linkedProjects.map(\.name) == ["Project A"])
    }

    @Test func accountKeysGroupByProjectEnvironmentAndLibrary() throws {
        let f = try makeFixture()
        let libraryKey = Variable(key: "STRIPE_TEST_KEY", environment: nil)
        libraryKey.inLibrary = true
        f.context.insert(libraryKey)
        libraryKey.link(account: f.stripe, serviceProject: nil)

        let keys = AccountKeys(account: f.stripe)
        #expect(keys.projects.map(\.project.name) == ["Project A", "Project B"])
        #expect(keys.projects[0].environments.map(\.environment.name) == ["production"])
        #expect(keys.projects[0].environments[0].keys.map(\.key) == ["STRIPE_SECRET_KEY"])
        #expect(keys.library.map(\.key) == ["STRIPE_TEST_KEY"])
        #expect(keys.count == 3)

        // Through a provider project: both production keys of Project A.
        let work = AccountKeys(account: f.firebaseWork)
        #expect(work.projects.map(\.count) == [2])
        #expect(work.library.isEmpty)
        #expect(AccountKeys(account: Account(serviceType: .firebase, login: "nobody")).isEmpty)
    }

    @Test func accountVariablesAreNotDuplicated() throws {
        let f = try makeFixture()
        // Linked via service project AND directly (same variables) -> counted once.
        #expect(f.firebaseWork.allLinkedVariables.count == 2)
    }

    @Test func deletingAnAccountKeepsVariablesButUnlinksThem() throws {
        let f = try makeFixture()
        f.context.delete(f.firebaseWork)
        try f.context.save()

        let keys = f.prod.sortedVariables.map(\.key)
        #expect(keys.contains("FIREBASE_API_KEY"))
        let v = try #require(f.prod.variables?.first { $0.key == "FIREBASE_API_KEY" })
        #expect(v.account == nil)
        #expect(v.serviceProject == nil) // service project cascaded with its account
    }

    @Test func deletingAProjectCascadesToEnvironmentsAndVariables() throws {
        let f = try makeFixture()
        f.context.delete(f.projectA)
        try f.context.save()

        #expect(try f.context.fetchCount(FetchDescriptor<ProjectEnvironment>()) == 1)
        #expect(try f.context.fetchCount(FetchDescriptor<Variable>()) == 1)
        #expect(try f.context.fetchCount(FetchDescriptor<Account>()) == 3)
    }

    @Test func environmentsAreSortedByOrder() throws {
        let f = try makeFixture()
        #expect(f.projectA.sortedEnvironments.map(\.name) == ["development", "production"])
    }

    @Test func consoleURLFallsBackToServicePattern() throws {
        let f = try makeFixture()
        #expect(f.projectaProd.resolvedConsoleURL?.absoluteString ==
                "https://console.firebase.google.com/project/projecta-prod/overview")
        f.projectaProd.consoleURL = URL(string: "https://example.com/custom")
        #expect(f.projectaProd.resolvedConsoleURL?.absoluteString == "https://example.com/custom")
    }

    @Test func unknownServiceRawValueFallsBackToCustom() {
        let account = Account(serviceType: .custom, login: "x", customServiceName: "Resend")
        #expect(account.serviceName == "Resend")
        account.serviceTypeRaw = "something-from-the-future"
        #expect(account.serviceType == .custom)
    }
}
