import DotFolioModels
import DotFolioSecurity
import Foundation
import LocalAuthentication
import SwiftData

/// Add / rename / relink / set value / delete for one environment's variables.
/// Metadata goes to SwiftData; values only ever go to the secret store.
public enum VariableEditor {
    public enum Failure: Error, Equatable {
        case invalidKey
        case duplicateKey(String)
        case invalidLink
        case keychain(KeychainError)

        public var message: String {
            switch self {
            case .invalidKey: "Use letters, digits and _ (not starting with a digit)."
            case .duplicateKey(let key): "\(key) already exists in this environment."
            case .invalidLink: "Enter a web link, e.g. https://dashboard.example.com"
            case .keychain(let error): "Keychain error: \(error)"
            }
        }
    }

    // MARK: Add

    /// Creates a variable. The value (if any) is written to the secret store
    /// first; if that fails nothing is created.
    @MainActor
    @discardableResult
    public static func add(
        key rawKey: String, value: String = "", service: String = "", account: String = "", link: String = "",
        to environment: ProjectEnvironment, context: ModelContext, secrets: any SecretStore
    ) throws(Failure) -> Variable {
        let key = try validatedKey(rawKey, in: environment, excluding: nil)
        let url = try validatedLink(link)

        let variable = Variable(key: key, environment: nil)
        if !value.isEmpty {
            do { try secrets.setString(value, for: variable.secretRef.uuidString) }
            catch { throw .keychain(error as? KeychainError ?? .unexpectedStatus(-1)) }
            variable.hasValue = true
        }
        variable.sourceURL = url
        variable.serviceLabel = service.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(variable)
        variable.environment = environment
        variable.account = findOrCreateAccount(login: account, service: variable.serviceLabel, context: context)
        touch(environment)
        return variable
    }

    // MARK: Edit

    @MainActor
    public static func rename(_ variable: Variable, to rawKey: String) throws(Failure) {
        guard let environment = variable.environment else { return }
        let key = try validatedKey(rawKey, in: environment, excluding: variable)
        guard key != variable.key else { return }
        variable.key = key
        variable.updatedAt = .now
        touch(environment)
    }

    @MainActor
    public static func setLink(_ variable: Variable, to text: String) throws(Failure) {
        let url = try validatedLink(text)
        guard url != variable.sourceURL else { return }
        variable.sourceURL = url
        variable.updatedAt = .now
        if let environment = variable.environment { touch(environment) }
    }

    @MainActor
    public static func setService(_ variable: Variable, to text: String) {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label != variable.serviceLabel else { return }
        variable.serviceLabel = label
        variable.updatedAt = .now
        if let environment = variable.environment { touch(environment) }
    }

    /// Links the variable to the account with this login (case-insensitive),
    /// creating it if needed. Empty text unlinks. Changing the account drops a
    /// service-project link that belonged to the previous account.
    @MainActor
    public static func setAccount(_ variable: Variable, login: String, context: ModelContext) {
        let account = findOrCreateAccount(login: login, service: variable.displayService, context: context)
        guard account?.persistentModelID != variable.account?.persistentModelID else { return }
        variable.link(account: account, serviceProject: nil)
        if let environment = variable.environment { touch(environment) }
    }

    @MainActor
    static func findOrCreateAccount(login: String, service: String, context: ModelContext) -> Account? {
        let login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else { return nil }
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        if let match = existing.first(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame }) {
            return match
        }
        let type = ServiceType(matching: service) ?? .custom
        let account = Account(serviceType: type, login: login,
                              customServiceName: type == .custom && !service.isEmpty ? service : nil)
        context.insert(account)
        return account
    }

    /// Replaces the value. An empty string clears it (removes the Keychain item).
    /// Writing does not need authentication; only reading does.
    @MainActor
    public static func setValue(_ variable: Variable, to value: String, secrets: any SecretStore) throws(Failure) {
        do {
            if value.isEmpty {
                try secrets.delete(variable.secretRef.uuidString)
                variable.hasValue = false
            } else {
                try secrets.setString(value, for: variable.secretRef.uuidString)
                variable.hasValue = true
            }
        } catch {
            throw .keychain(error as? KeychainError ?? .unexpectedStatus(-1))
        }
        variable.updatedAt = .now
        if let environment = variable.environment { touch(environment) }
    }

    /// Reads the value with an already-authenticated context (see SessionLock).
    public static func value(of variable: Variable, secrets: any SecretStore, context: LAContext) throws(Failure) -> String? {
        guard variable.hasValue else { return nil }
        do { return try secrets.string(for: variable.secretRef.uuidString, context: context) }
        catch { throw .keychain(error as? KeychainError ?? .unexpectedStatus(-1)) }
    }

    // MARK: Delete

    /// SECURITY: removes the Keychain item first; if that fails the variable
    /// is kept so its secret is not orphaned.
    @MainActor
    public static func delete(_ variable: Variable, context: ModelContext, secrets: any SecretStore) throws(Failure) {
        if variable.hasValue {
            do { try secrets.delete(variable.secretRef.uuidString) }
            catch { throw .keychain(error as? KeychainError ?? .unexpectedStatus(-1)) }
        }
        if let environment = variable.environment { touch(environment) }
        context.delete(variable)
    }

    // MARK: Validation

    static func validatedKey(_ raw: String, in environment: ProjectEnvironment, excluding: Variable?) throws(Failure) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard InputValidation.isValidEnvKey(key) else { throw .invalidKey }
        let clash = (environment.variables ?? []).contains {
            $0.key == key && $0.persistentModelID != excluding?.persistentModelID
        }
        if clash { throw .duplicateKey(key) }
        return key
    }

    static func validatedLink(_ text: String) throws(Failure) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let url = InputValidation.webURL(trimmed) else { throw .invalidLink }
        return url
    }

    private static func touch(_ environment: ProjectEnvironment) {
        environment.project?.updatedAt = .now
    }
}
