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
        key rawKey: String, value: String = "", category: String = "", service: String = "", account: String = "", link: String = "",
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
        variable.serviceCategory = normalizedCategory(category)
        context.insert(variable)
        variable.environment = environment
        variable.account = findOrCreateAccount(login: account, service: variable.serviceLabel, context: context)
        touch(environment)
        return variable
    }

    // MARK: Library

    /// Adds a key to the Library (no project). Names are unique per provider,
    /// so `API_KEY` can exist under both OpenAI and Anthropic. Same order as
    /// `add`: the value goes to the secret store first.
    @MainActor
    @discardableResult
    public static func addToLibrary(
        key rawKey: String, value: String = "", category: String = "", provider: String = "", account: String = "", link: String = "",
        context: ModelContext, secrets: any SecretStore
    ) throws(Failure) -> Variable {
        let providerName = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = try validatedKey(rawKey, siblings: Library.keys(provider: providerName, context: context), excluding: nil)
        let url = try validatedLink(link)

        let variable = Variable(key: key, environment: nil)
        variable.inLibrary = true
        if !value.isEmpty {
            do { try secrets.setString(value, for: variable.secretRef.uuidString) }
            catch { throw .keychain(error as? KeychainError ?? .unexpectedStatus(-1)) }
            variable.hasValue = true
        }
        variable.sourceURL = url
        variable.serviceLabel = providerName
        variable.serviceCategory = normalizedCategory(category)
        context.insert(variable)
        variable.account = findOrCreateAccount(login: account, service: providerName, context: context)
        return variable
    }

    /// Moves a library key to another provider, keeping names unique there.
    @MainActor
    public static func setLibraryProvider(_ variable: Variable, to text: String, context: ModelContext) throws(Failure) {
        let provider = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider != variable.serviceLabel else { return }
        _ = try validatedKey(variable.key, siblings: Library.keys(provider: provider, context: context), excluding: variable)
        setService(variable, to: provider)
    }

    // MARK: Edit

    /// Renames within the variable's scope: its environment, or for a library
    /// key the other library keys of the same provider.
    @MainActor
    public static func rename(_ variable: Variable, to rawKey: String) throws(Failure) {
        let key: String
        if let environment = variable.environment {
            key = try validatedKey(rawKey, in: environment, excluding: variable)
        } else if variable.inLibrary, let context = variable.modelContext {
            key = try validatedKey(rawKey, siblings: Library.keys(provider: variable.serviceLabel, context: context), excluding: variable)
        } else {
            return
        }
        guard key != variable.key else { return }
        variable.key = key
        variable.updatedAt = .now
        if let environment = variable.environment { touch(environment) }
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
        variable.account?.addService(label)
        variable.updatedAt = .now
        if let environment = variable.environment { touch(environment) }
    }

    /// Sets what the value is for ("Database", "Cache"…). Known names and
    /// synonyms are normalized ("db" → "Database"); anything else is kept as typed.
    @MainActor
    public static func setCategory(_ variable: Variable, to text: String) {
        let category = normalizedCategory(text)
        guard category != variable.serviceCategory else { return }
        variable.serviceCategory = category
        variable.updatedAt = .now
        if let environment = variable.environment { touch(environment) }
    }

    static func normalizedCategory(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServiceCategory(matching: trimmed)?.displayName ?? trimmed
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
        // One login can serve several services: reuse it and remember the service.
        if let match = existing.first(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame }) {
            match.addService(service)
            return match
        }
        let account = Account(login: login, services: [service])
        context.insert(account)
        return account
    }

    /// Replaces the value. An empty string clears it (removes the Keychain item).
    ///
    /// SECURITY / correctness: an existing item is never updated in place —
    /// updating a `.userPresence` item needs Touch ID, which writing must not.
    /// The new value goes into a NEW item; only once that succeeded does the
    /// variable point at it and the old item get deleted (deleting needs no
    /// authentication). If the write fails, the old value is untouched.
    @MainActor
    public static func setValue(_ variable: Variable, to value: String, secrets: any SecretStore) throws(Failure) {
        let oldRef = variable.secretRef
        let hadValue = variable.hasValue
        do {
            if value.isEmpty {
                if hadValue { try secrets.delete(oldRef.uuidString) }
                variable.hasValue = false
            } else {
                let newRef = UUID()
                try secrets.setString(value, for: newRef.uuidString)
                variable.secretRef = newRef
                variable.hasValue = true
                if hadValue { try? secrets.delete(oldRef.uuidString) }
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
        try validatedKey(raw, siblings: environment.variables ?? [], excluding: excluding)
    }

    /// Valid env name, not already used by one of `siblings` (other than `excluding`).
    static func validatedKey(_ raw: String, siblings: [Variable], excluding: Variable?) throws(Failure) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard InputValidation.isValidEnvKey(key) else { throw .invalidKey }
        let clash = siblings.contains {
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
