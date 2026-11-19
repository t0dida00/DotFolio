import Foundation
import SwiftData

// Schema rules (kept so future multi-Mac sync stays possible, e.g. CloudKit):
// - every stored property has a default value,
// - every relationship is optional,
// - no `@Attribute(.unique)`; uniqueness (e.g. variable key per environment)
//   is enforced in the service layer instead.
//
// SECURITY: no model in this file ever stores a secret value. `Variable` only
// keeps `secretRef`, the identifier of the Keychain item holding the value.

// MARK: - Account

/// A login on an external service (e.g. the Firebase account `me@work.com`).
@Model
public final class Account {
    public var id: UUID = UUID()
    public var serviceTypeRaw: String = ServiceType.custom.rawValue
    /// Only meaningful when `serviceType == .custom`.
    public var customServiceName: String?
    /// Login email or username.
    public var login: String = ""
    public var displayName: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ServiceProject.account)
    public var serviceProjects: [ServiceProject]? = []

    /// Variables linked directly to this account (with or without a service project).
    @Relationship(deleteRule: .nullify, inverse: \Variable.account)
    public var variables: [Variable]? = []

    public init(
        serviceType: ServiceType,
        login: String,
        displayName: String = "",
        customServiceName: String? = nil,
        notes: String = ""
    ) {
        self.serviceTypeRaw = serviceType.rawValue
        self.login = login
        self.displayName = displayName
        self.customServiceName = customServiceName
        self.notes = notes
    }

    public var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRaw) ?? .custom }
        set { serviceTypeRaw = newValue.rawValue }
    }

    /// "Firebase", or the custom name for `.custom` accounts.
    public var serviceName: String {
        if serviceType == .custom, let name = customServiceName, !name.isEmpty { return name }
        return serviceType.displayName
    }
}

// MARK: - ServiceProject

/// A project inside an `Account` (e.g. Firebase project `projecta-prod`).
@Model
public final class ServiceProject {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Provider-side identifier, e.g. the Firebase project ID.
    public var externalID: String = ""
    public var consoleURL: URL?
    public var notes: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public var account: Account?

    @Relationship(deleteRule: .nullify, inverse: \Variable.serviceProject)
    public var variables: [Variable]? = []

    public init(name: String, externalID: String = "", consoleURL: URL? = nil, notes: String = "", account: Account? = nil) {
        self.name = name
        self.externalID = externalID
        self.consoleURL = consoleURL
        self.notes = notes
        self.account = account
    }

    /// Explicit console URL, falling back to the service's known URL pattern.
    public var resolvedConsoleURL: URL? {
        consoleURL ?? account?.serviceType.defaultConsoleURL(externalID: externalID)
    }
}

// MARK: - Project

/// One of the user's own projects, usually backed by a GitHub/GitLab repo.
@Model
public final class Project {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Optional free-text description. Not named `description` to avoid
    /// clashing with `CustomStringConvertible`.
    public var summary: String = ""
    public var providerRaw: String = RepoProvider.none.rawValue
    public var repoURL: URL?
    /// "owner/repo" (GitHub) or "group/subgroup/repo" (GitLab), used for API calls.
    public var repoFullName: String = ""
    public var defaultBranch: String = "main"
    /// Security-scoped bookmark to the local checkout. Needed because the app is
    /// sandboxed; a bookmark is not a secret, so it may live in the database.
    public var localFolderBookmark: Data?
    public var envExamplePath: String = ".env.example"
    /// Keys found in the last fetched `.env.example` (used by the sync feature).
    public var envExampleKeys: [String] = []
    /// Git blob SHA of the last fetched `.env.example`, to detect changes cheaply.
    public var envExampleSHA: String?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    /// Drives the "Recent" section on the home screen.
    public var lastOpenedAt: Date?
    /// Account this project was imported from, e.g. "github:octocat".
    /// Nil for projects created by hand. Signing out removes these projects.
    public var importedFrom: String?

    @Relationship(deleteRule: .cascade, inverse: \ProjectEnvironment.project)
    public var environments: [ProjectEnvironment]? = []

    public init(name: String, provider: RepoProvider = .none, repoURL: URL? = nil, repoFullName: String = "", defaultBranch: String = "main") {
        self.name = name
        self.providerRaw = provider.rawValue
        self.repoURL = repoURL
        self.repoFullName = repoFullName
        self.defaultBranch = defaultBranch
    }

    public var provider: RepoProvider {
        get { RepoProvider(rawValue: providerRaw) ?? .none }
        set { providerRaw = newValue.rawValue }
    }

    public var sortedEnvironments: [ProjectEnvironment] {
        (environments ?? []).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

// MARK: - ProjectEnvironment

/// development / staging / production / custom. Not named `Environment` to avoid
/// clashing with SwiftUI's `@Environment`.
@Model
public final class ProjectEnvironment {
    public var id: UUID = UUID()
    public var name: String = "development"
    public var sortOrder: Int = 0
    /// Protected environments (e.g. production) ask for extra confirmation on export.
    public var isProtected: Bool = false
    public var createdAt: Date = Date.now

    public var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \Variable.environment)
    public var variables: [Variable]? = []

    public init(name: String, sortOrder: Int = 0, isProtected: Bool = false, project: Project? = nil) {
        self.name = name
        self.sortOrder = sortOrder
        self.isProtected = isProtected
        self.project = project
    }

    public static let defaultNames = ["development", "staging", "production"]

    public var sortedVariables: [Variable] {
        (variables ?? []).sorted { $0.key < $1.key }
    }
}

// MARK: - Variable

/// Metadata for one environment variable. The value lives only in the Keychain.
@Model
public final class Variable {
    public var id: UUID = UUID()
    public var key: String = ""
    public var notes: String = ""
    /// Keychain item identifier (`kSecAttrAccount`). Decoupled from `id` so key
    /// rotation / history can later point a variable at a new item.
    public var secretRef: UUID = UUID()
    /// Whether a value exists in the Keychain. Lets the UI show "missing value"
    /// without unlocking the Keychain; reveals existence only, never content.
    public var hasValue: Bool = false
    /// Where to get or manage this value (e.g. the provider's API keys page).
    public var sourceURL: URL?
    /// Free-text description of the service ("DB", "Firebase", "Stripe"…).
    /// Falls back to the linked account's service in the UI when empty.
    public var serviceLabel: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public var environment: ProjectEnvironment?
    /// Invariant (enforced by the service layer): when `serviceProject` is set,
    /// `account == serviceProject.account`.
    public var account: Account?
    public var serviceProject: ServiceProject?

    public init(key: String, notes: String = "", environment: ProjectEnvironment? = nil) {
        self.key = key
        self.notes = notes
        self.environment = environment
    }
}
