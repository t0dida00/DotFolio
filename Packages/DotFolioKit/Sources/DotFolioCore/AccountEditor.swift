import DotFolioModels
import Foundation
import SwiftData

/// CRUD for accounts (one login, several services) and the projects inside
/// each service (e.g. Firebase projects). Metadata only; no secrets here.
public enum AccountEditor {
    public enum Failure: Error, Equatable {
        case emptyLogin
        case duplicateLogin(String)
        case emptyName
        case invalidURL

        public var message: String {
            switch self {
            case .emptyLogin: "Enter the email or username of the account."
            case .duplicateLogin(let login): "\(login) already exists."
            case .emptyName: "Enter a name."
            case .invalidURL: "Enter a web link, e.g. https://console.firebase.google.com/…"
            }
        }
    }

    // MARK: Accounts

    @MainActor
    @discardableResult
    public static func createAccount(services: [String], login: String, displayName: String = "",
                                     notes: String = "", context: ModelContext) throws(Failure) -> Account {
        let login = try validatedLogin(login, excluding: nil, context: context)
        let account = Account(login: login, displayName: displayName.trimmingCharacters(in: .whitespaces),
                              services: services, notes: notes)
        context.insert(account)
        return account
    }

    @MainActor
    public static func update(_ account: Account, services: [String], login: String,
                              displayName: String, notes: String, context: ModelContext) throws(Failure) {
        account.login = try validatedLogin(login, excluding: account, context: context)
        for old in account.services where !services.contains(where: { $0.caseInsensitiveCompare(old) == .orderedSame }) {
            account.removeService(old)
        }
        for service in services { account.addService(service) }
        account.displayName = displayName.trimmingCharacters(in: .whitespaces)
        account.notes = notes
        account.updatedAt = .now
    }

    /// Variables keep existing (unlinked); its service projects go with it.
    @MainActor
    public static func delete(_ account: Account, context: ModelContext) {
        context.delete(account)
    }

    // MARK: Service projects

    @MainActor
    @discardableResult
    public static func addServiceProject(to account: Account, service: String, name: String, externalID: String = "",
                                         consoleURL: String = "", context: ModelContext) throws(Failure) -> ServiceProject {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw .emptyName }
        let url = try validatedURL(consoleURL)
        account.addService(service)
        let canonical = ServiceType(matching: service)?.displayName ?? service.trimmingCharacters(in: .whitespaces)
        let sp = ServiceProject(name: name, externalID: externalID.trimmingCharacters(in: .whitespaces), consoleURL: url,
                                serviceName: canonical)
        context.insert(sp)
        sp.account = account
        account.updatedAt = .now
        return sp
    }

    @MainActor
    public static func update(_ sp: ServiceProject, name: String, externalID: String, consoleURL: String) throws(Failure) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw .emptyName }
        sp.consoleURL = try validatedURL(consoleURL)
        sp.name = name
        sp.externalID = externalID.trimmingCharacters(in: .whitespaces)
        sp.updatedAt = .now
    }

    /// Variables linked to it keep their account link.
    @MainActor
    public static func delete(_ sp: ServiceProject, context: ModelContext) {
        context.delete(sp)
    }

    // MARK: Validation

    @MainActor
    static func validatedLogin(_ raw: String, excluding: Account?, context: ModelContext) throws(Failure) -> String {
        let login = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else { throw .emptyLogin }
        let all = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        if all.contains(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame && $0.persistentModelID != excluding?.persistentModelID }) {
            throw .duplicateLogin(login)
        }
        return login
    }

    static func validatedURL(_ text: String) throws(Failure) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let url = InputValidation.webURL(trimmed) else { throw .invalidURL }
        return url
    }
}
