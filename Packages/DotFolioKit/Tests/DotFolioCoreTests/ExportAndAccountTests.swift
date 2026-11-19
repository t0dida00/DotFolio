import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity

@MainActor
struct EnvExportTests {
    @Test func buildsTextWithValuesAndReportsMissing() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let secrets = InMemorySecretStore()
        let project = Project.create(name: "Shop", in: context)
        let prod = project.sortedEnvironments.last!
        try VariableEditor.add(key: "API_KEY", value: "sk live", to: prod, context: context, secrets: secrets)
        try VariableEditor.add(key: "EMPTY", to: prod, context: context, secrets: secrets)

        let out = try EnvExport.build(prod, secrets: secrets, authContext: LAContext())
        #expect(out.missing == ["EMPTY"])
        #expect(out.text.contains("Never commit") || out.text.contains("never commit"))
        let parsed = EnvParser.parse(out.text)
        #expect(parsed.map(\.key) == ["API_KEY", "EMPTY"])
        #expect(parsed[0].value == "sk live")
        #expect(EnvExport.fileName(for: prod) == ".env.production")
        #expect(EnvExport.fileName(for: project.sortedEnvironments[0]) == ".env")
    }
}

@MainActor
struct AccountEditorTests {
    let context: ModelContext
    init() throws { context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true)) }

    @Test func createValidatesAndRejectsDuplicates() throws {
        let a = try AccountEditor.createAccount(services: ["firebase"], login: " dev@acme.studio ", context: context)
        #expect(a.login == "dev@acme.studio")
        #expect(a.services == ["Firebase"])
        #expect(throws: AccountEditor.Failure.duplicateLogin("DEV@acme.studio")) {
            try AccountEditor.createAccount(services: ["Stripe"], login: "DEV@acme.studio", context: context)
        }
        #expect(throws: AccountEditor.Failure.emptyLogin) {
            try AccountEditor.createAccount(services: [], login: "  ", context: context)
        }
    }

    @Test func oneLoginManyServices() throws {
        let a = try AccountEditor.createAccount(services: ["Firebase", "google cloud", "Resend", "FIREBASE"], login: "me@gmail.com", context: context)
        #expect(a.services == ["Firebase", "Google Cloud", "Resend"])
        #expect(a.serviceSummary == "Firebase, Google Cloud, Resend")
        try AccountEditor.update(a, services: ["Google Cloud", "Stripe"], login: "me@gmail.com", displayName: "Personal", notes: "", context: context)
        #expect(a.services == ["Google Cloud", "Stripe"])
        #expect(a.serviceType == .googleCloud)
    }

    @Test func serviceProjectsBelongToAServiceAndGetConsoleURL() throws {
        let a = try AccountEditor.createAccount(services: ["Google Cloud"], login: "me@gmail.com", context: context)
        let fb = try AccountEditor.addServiceProject(to: a, service: "firebase", name: "Shop prod", externalID: "shop-prod", context: context)
        let supa = try AccountEditor.addServiceProject(to: a, service: "Supabase", name: "Blog", externalID: "abcd", context: context)
        #expect(a.services == ["Google Cloud", "Firebase", "Supabase"]) // adding a project adds its service
        #expect(fb.serviceName == "Firebase")
        #expect(fb.resolvedConsoleURL?.absoluteString == "https://console.firebase.google.com/project/shop-prod/overview")
        #expect(supa.resolvedConsoleURL?.absoluteString == "https://supabase.com/dashboard/project/abcd")
        #expect(throws: AccountEditor.Failure.invalidURL) {
            try AccountEditor.update(fb, name: "Shop prod", externalID: "shop-prod", consoleURL: "nope nope")
        }
        #expect(throws: AccountEditor.Failure.emptyName) {
            try AccountEditor.addServiceProject(to: a, service: "Firebase", name: " ", context: context)
        }
        AccountEditor.delete(fb, context: context)
        try context.save()
        #expect(a.serviceProjects?.count == 1)
    }

    @Test func legacySingleServiceAccountsStillRead() {
        let legacy = Account(login: "old@acme.studio")
        legacy.serviceTypeRaw = ServiceType.stripe.rawValue
        #expect(legacy.services == ["Stripe"])
        legacy.removeService("Stripe")
        #expect(legacy.services.isEmpty)
    }

    @Test func deletingAccountKeepsVariablesUnlinked() throws {
        let secrets = InMemorySecretStore()
        let env = Project.create(name: "P", in: context).sortedEnvironments[0]
        let v = try VariableEditor.add(key: "A", account: "dev@acme.studio", to: env, context: context, secrets: secrets)
        let account = try #require(v.account)
        AccountEditor.delete(account, context: context)
        try context.save()
        #expect(v.account == nil)
        #expect(try context.fetchCount(FetchDescriptor<Variable>()) == 1)
    }
}
