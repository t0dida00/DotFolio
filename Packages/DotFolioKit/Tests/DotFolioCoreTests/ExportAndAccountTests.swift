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
        let a = try AccountEditor.createAccount(service: .firebase, login: " dev@acme.studio ", context: context)
        #expect(a.login == "dev@acme.studio")
        #expect(throws: AccountEditor.Failure.duplicateLogin("DEV@acme.studio")) {
            try AccountEditor.createAccount(service: .stripe, login: "DEV@acme.studio", context: context)
        }
        #expect(throws: AccountEditor.Failure.emptyLogin) {
            try AccountEditor.createAccount(service: .stripe, login: "  ", context: context)
        }
    }

    @Test func customServiceNameOnlyForCustom() throws {
        let a = try AccountEditor.createAccount(service: .custom, customName: "Resend", login: "x", context: context)
        #expect(a.serviceName == "Resend")
        try AccountEditor.update(a, service: .stripe, customName: "ignored", login: "x", displayName: "", notes: "", context: context)
        #expect(a.customServiceName == nil)
        #expect(a.serviceName == "Stripe")
    }

    @Test func serviceProjectsCRUDAndConsoleFallback() throws {
        let a = try AccountEditor.createAccount(service: .firebase, login: "dev@acme.studio", context: context)
        let sp = try AccountEditor.addServiceProject(to: a, name: "Shop prod", externalID: "shop-prod", context: context)
        #expect(sp.resolvedConsoleURL?.absoluteString == "https://console.firebase.google.com/project/shop-prod/overview")
        #expect(throws: AccountEditor.Failure.invalidURL) {
            try AccountEditor.update(sp, name: "Shop prod", externalID: "shop-prod", consoleURL: "nope nope")
        }
        #expect(throws: AccountEditor.Failure.emptyName) {
            try AccountEditor.addServiceProject(to: a, name: " ", context: context)
        }
        AccountEditor.delete(sp, context: context)
        try context.save()
        #expect(a.serviceProjects?.isEmpty == true)
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
