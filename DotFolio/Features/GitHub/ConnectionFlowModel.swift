import AppKit
import DotFolioCore
import DotFolioIntegrations
import DotFolioModels
import DotFolioSecurity
import Foundation
import Observation
import SwiftData

// Size note: One state machine for sign-in and repo import (steps share the client, token and progress), so it stays in one file even though it is over ~350 lines.

/// "Connect your repo host" flow: GitHub device-flow sign-in or GitLab
/// (gitlab.com / self-hosted) personal access token, picking repos, and
/// importing them as projects. One host at a time: `host`.
@Observable
@MainActor
final class ConnectionFlowModel {
    enum Step: Equatable {
        case idle
        case gitLabHost
        case loading(String)
        case waitingForGitHub(DeviceCode)
        case connected(ConnectedAccount)
        case choosingRepos
        case importing(done: Int, total: Int)
        case importFinished(ImportSummary)
        case failed(Failure)
    }

    /// The repo host the flow is talking to.
    enum Host: Equatable {
        case github
        case gitlab(URL)

        var provider: RepoProvider { self == .github ? .github : .gitlab }
        var name: String {
            switch self {
            case .github: "GitHub"
            case .gitlab(let url): url.host() == GitLabClient.gitLabCom.host() ? "GitLab" : (url.host() ?? "GitLab")
            }
        }
        var brand: BrandMark { self == .github ? .github : .gitlab }
        var tokenRef: String { self == .github ? "github" : "gitlab" }
        var userKey: String { self == .github ? RepoConnections.gitHubUserKey : RepoConnections.gitLabUserKey }
    }

    /// One line of the import log.
    struct ImportLogEntry: Identifiable, Equatable {
        enum Outcome: Equatable { case keys(Int), noEnvExample, unreadable }
        let id = UUID()
        let repo: String
        let outcome: Outcome
    }

    struct ImportSummary: Equatable {
        var projects = 0
        var withEnvExample = 0
        var variables = 0
        var unreadable = 0
        var cancelled = false
    }

    /// GitHub device flow code shown to the user (not a secret: it is useless
    /// without the user approving it in their own logged-in browser session).
    struct DeviceCode: Equatable {
        var userCode: String
        var verificationURL: URL
        var expiresAt: Date
    }

    struct ConnectedAccount: Equatable {
        var provider: RepoProvider
        var username: String
        var email: String?
        var avatarURL: URL?
        var repoCount: Int
        var privateRepoCount: Int
    }

    enum Failure: Equatable {
        case notConfigured
        case codeExpired
        case accessDenied
        case signedOut
        case network
        case other(String)

        var title: String {
            switch self {
            case .notConfigured: "GitHub sign-in isn’t set up yet."
            case .codeExpired: "The code expired."
            case .accessDenied: "Access was denied."
            case .signedOut: "Your session ended."
            case .network: "Couldn’t reach the server."
            case .other: "Something went wrong."
            }
        }

        var message: String {
            switch self {
            case .notConfigured: "Add the GitHub App’s Client ID to GitHubConfig.swift, then rebuild."
            case .codeExpired: "Codes are valid for 15 minutes. Get a new code and try again."
            case .accessDenied: "DOTFOLIO needs read access to your repos to create projects. You can try again anytime."
            case .signedOut: "The token was revoked or expired. Sign in again."
            case .network: "Check your internet connection and try again."
            case .other(let detail): detail
            }
        }

        var retryTitle: String {
            switch self {
            case .codeExpired: "Get New Code"
            case .signedOut: "Sign In Again"
            default: "Try Again"
            }
        }
    }

    var step: Step
    private(set) var host: Host = .github
    /// GitLab sign-in form. The token is only held until it's saved to the
    /// Keychain, then cleared.
    var gitLabHost = ""
    var gitLabToken = ""

    // Repo picker state
    private(set) var account: GitHubUser?
    private(set) var repos: [GitHubRepo] = []
    var selectedRepoIDs: Set<GitHubRepo.ID> = []
    var repoFilter = ""

    // Import progress (shown live on the importing screen)
    private(set) var importLog: [ImportLogEntry] = []
    private(set) var inFlight: [String] = []
    private(set) var importStats = ImportSummary()
    private static let parallelImports = 4

    private let client = GitHubClient(clientID: GitHubConfig.clientID)
    private var gitLabClient: GitLabClient? {
        if case .gitlab(let url) = host { GitLabClient(baseURL: url) } else { nil }
    }
    private var context: ModelContext?
    private var tokens: (any SecretStore)?
    private var secrets: (any SecretStore)?

    /// What signing out would delete; the root view asks to confirm.
    struct SignOutPlan: Identifiable {
        let id = UUID()
        let host: Host
        let login: String
        let projects: [Project]
    }
    var pendingSignOut: SignOutPlan?
    private(set) var isPreparingSignOut = false
    private var task: Task<Void, Never>?
    /// Shows a result dialog (set by the root view).
    var onReport: ((ResultReport) -> Void)?

    init(step: Step = .idle) {
        self.step = step
    }

    /// Called once by the root view with the app's store and Keychain.
    func configure(context: ModelContext, tokens: any SecretStore, secrets: any SecretStore) {
        self.context = context
        self.tokens = tokens
        self.secrets = secrets
    }

    var isWideStep: Bool {
        switch step {
        case .choosingRepos, .importing, .importFinished: true
        default: false
        }
    }

    // MARK: GitHub

    /// Signed in already → straight to the repo picker. Otherwise device flow.
    func connectGitHub() {
        task?.cancel()
        host = .github
        task = Task { await runGitHubFlow() }
    }

    private func runGitHubFlow() async {
        do {
            if let token = storedToken() {
                do {
                    try await loadRepos(token: token)
                    step = .choosingRepos
                    return
                } catch GitHubError.unauthorized {
                    forget() // revoked/expired: fall through to a fresh sign-in
                }
            }

            step = .loading("Contacting GitHub…")
            let code = try await client.requestDeviceCode()
            step = .waitingForGitHub(DeviceCode(
                userCode: code.userCode,
                verificationURL: code.verificationUri,
                expiresAt: .now.addingTimeInterval(TimeInterval(code.expiresIn))
            ))
            // The user code is not secret; copying it saves typing.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code.userCode, forType: .string)
            NSWorkspace.shared.open(code.verificationUri)

            let token = try await client.pollForToken(code)
            // SECURITY: the token lives only in the Keychain.
            try tokens?.setString(token, for: host.tokenRef)
            try await loadRepos(token: token)
            if let account {
                step = .connected(ConnectedAccount(
                    provider: .github, username: account.login, email: account.email, avatarURL: account.avatarUrl,
                    repoCount: repos.count, privateRepoCount: repos.filter(\.isPrivate).count
                ))
                onReport?(.success("Signed in to GitHub", "Connected as @\(account.login), with \(repos.count) \(repos.count == 1 ? "repository" : "repositories") you can import (read-only)."))
            }
        } catch is CancellationError {
            // Cancelled by the user.
        } catch {
            if Task.isCancelled { return }
            step = .failed(Self.failure(for: error))
            onReport?(.failed("Couldn’t sign in to GitHub", ResultReport.describe(error)))
        }
    }

    private func loadRepos(token: String) async throws {
        step = .loading("Loading your repositories…")
        let user: GitHubUser
        let list: [GitHubRepo]
        if let gitLab = gitLabClient {
            user = try await gitLab.currentUser(token: token)
            list = try await gitLab.repositories(token: token)
        } else {
            user = try await client.currentUser(token: token)
            list = try await client.repositories(token: token)
        }
        account = user
        repos = list
        selectedRepoIDs = []
        repoFilter = ""
        UserDefaults.standard.set(user.login, forKey: host.userKey)
    }

    func refreshRepos() {
        guard let token = storedToken() else { retry(); return }
        task?.cancel()
        task = Task {
            do {
                try await loadRepos(token: token)
                step = .choosingRepos
            } catch {
                if !Task.isCancelled { step = .failed(Self.failure(for: error)) }
            }
        }
    }

    /// Works out which projects belong to the signed-in account (asking the
    /// host for its repo list while the token still works), then asks the
    /// user to confirm before anything is deleted.
    func requestSignOutGitHub() { requestSignOut(of: .github) }

    func requestSignOutGitLab() {
        requestSignOut(of: .gitlab(RepoConnections.gitLabHost ?? GitLabClient.gitLabCom))
    }

    /// Sign out of the host the picker is showing.
    func requestSignOut() { requestSignOut(of: host) }

    private func requestSignOut(of target: Host) {
        guard let context, !isPreparingSignOut else { return }
        if target != host { host = target; account = nil; repos = [] }
        let login = account?.login ?? UserDefaults.standard.string(forKey: target.userKey) ?? ""
        isPreparingSignOut = true
        Task {
            var names = Set(repos.map(\.fullName))
            if names.isEmpty, let token = storedToken() {
                let list: [GitHubRepo]? = if let gitLab = gitLabClient {
                    try? await gitLab.repositories(token: token)
                } else {
                    try? await client.repositories(token: token)
                }
                names = Set((list ?? []).map(\.fullName))
            }
            let projects = login.isEmpty ? [] : AccountSignOut.projects(provider: target.provider, login: login, repoFullNames: names, context: context)
            isPreparingSignOut = false
            pendingSignOut = SignOutPlan(host: target, login: login, projects: projects)
        }
    }

    /// Deletes the account's projects (Keychain values first), then the token.
    func confirmSignOut() {
        guard let plan = pendingSignOut, let context, let secrets else { return }
        pendingSignOut = nil
        task?.cancel()
        host = plan.host
        do {
            try AccountSignOut.deleteProjects(plan.projects, context: context, secrets: secrets)
            try context.save()
        } catch {
            // Keep the token too: the account's projects still exist, and the
            // user can retry signing out.
            step = .failed(.other("Some stored values couldn’t be removed from the Keychain, so sign-out stopped. \((error as? KeychainError)?.userMessage ?? error.localizedDescription)"))
            onReport?(.failed("Couldn’t sign out of \(plan.host.name)", "Some stored values couldn’t be removed from the Keychain, so sign-out stopped."))
            return
        }
        forget()
        step = .idle
        onReport?(.success("Signed out of \(plan.host.name)",
                           plan.projects.isEmpty
                               ? "DOTFOLIO forgot @\(plan.login). No projects came from it."
                               : "DOTFOLIO forgot @\(plan.login) and deleted the \(plan.projects.count) projects imported from it, with their Keychain values.",
                           groups: plan.projects.isEmpty ? [] : [.init(title: "Deleted", names: plan.projects.map(\.name))]))
    }

    /// Forgets the current host's token and account.
    private func forget() {
        try? tokens?.delete(host.tokenRef)
        UserDefaults.standard.removeObject(forKey: host.userKey)
        if host != .github { UserDefaults.standard.removeObject(forKey: RepoConnections.gitLabHostKey) }
        account = nil
        repos = []
    }

    private func storedToken() -> String? {
        try? tokens?.string(for: host.tokenRef)
    }

    // MARK: Repo picker

    var filteredRepos: [GitHubRepo] {
        let q = repoFilter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.fullName.localizedStandardContains(q) || ($0.description?.localizedStandardContains(q) ?? false) }
    }

    func isImported(_ repo: GitHubRepo) -> Bool {
        guard let context else { return false }
        return RepoImporter.existingProject(for: repo.fullName, provider: host.provider, context: context) != nil
    }

    /// Imports the picked repos, reading up to `parallelImports` .env.example
    /// files at a time. Projects imported before a cancel are kept.
    func importSelected() {
        guard let context, let token = storedToken() else { return }
        var pending = ArraySlice(repos.filter { selectedRepoIDs.contains($0.id) })
        let total = pending.count
        guard total > 0 else { return }

        importLog = []
        inFlight = []
        importStats = ImportSummary()
        step = .importing(done: 0, total: total)
        let client = client
        let gitLab = gitLabClient
        let provider = host.provider
        let source = (account?.login).map { AccountSignOut.source(provider: provider, login: $0) }

        task?.cancel()
        task = Task {
            await withTaskGroup(of: (GitHubRepo, GitHubFile?, Bool).self) { group in
                // Child tasks only fetch; all model updates happen back here on the main actor.
                let fetch: @Sendable (GitHubRepo) async -> (GitHubRepo, GitHubFile?, Bool) = { repo in
                    do {
                        let file = if let gitLab {
                            try await gitLab.file(".env.example", in: repo.fullName, ref: repo.defaultBranch, token: token)
                        } else {
                            try await client.file(".env.example", in: repo.fullName, ref: repo.defaultBranch, token: token)
                        }
                        return (repo, file, false)
                    } catch {
                        return (repo, nil, true)
                    }
                }
                for _ in 0..<min(Self.parallelImports, pending.count) {
                    let repo = pending.removeFirst()
                    inFlight.append(repo.fullName)
                    group.addTask { await fetch(repo) }
                }

                var done = 0
                while let (repo, file, unreadable) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    inFlight.removeAll { $0 == repo.fullName }
                    let project = RepoImporter.importRepo(
                        .init(provider: provider, fullName: repo.fullName, url: repo.htmlUrl,
                              defaultBranch: repo.defaultBranch, description: repo.description),
                        envExample: file?.text, envExampleSHA: file?.sha, source: source, context: context
                    )
                    let keys = file == nil ? 0 : project.envExampleKeys.count
                    importStats.projects += 1
                    if unreadable {
                        importStats.unreadable += 1
                        importLog.append(.init(repo: repo.fullName, outcome: .unreadable))
                    } else if file == nil {
                        importLog.append(.init(repo: repo.fullName, outcome: .noEnvExample))
                    } else {
                        importStats.withEnvExample += 1
                        importStats.variables += keys
                        importLog.append(.init(repo: repo.fullName, outcome: .keys(keys)))
                    }
                    done += 1
                    step = .importing(done: done, total: total)
                    if !pending.isEmpty {
                        let next = pending.removeFirst()
                        inFlight.append(next.fullName)
                        group.addTask { await fetch(next) }
                    }
                }
            }
            try? context.save()
            selectedRepoIDs = []
            inFlight = []
            importStats.cancelled = Task.isCancelled
            if !Task.isCancelled {
                step = .importFinished(importStats)
                onReport?(Self.report(importStats, from: host.name))
            }
        }
    }

    /// Stop importing but keep what was imported, and show the summary.
    func stopImport() {
        task?.cancel()
        try? context?.save()
        inFlight = []
        var summary = importStats
        summary.cancelled = true
        step = .importFinished(summary)
        onReport?(Self.report(summary, from: host.name))
    }

    /// The dialog after importing repositories.
    private static func report(_ s: ImportSummary, from hostName: String) -> ResultReport {
        let projects = "\(s.projects) \(s.projects == 1 ? "project" : "projects")"
        if s.projects == 0 {
            return .nothing(s.cancelled ? "Import stopped" : "Nothing imported", "No repository was imported.")
        }
        var message = "Imported \(projects) with \(s.variables) variables from \(hostName)."
        if s.unreadable > 0 { message += " \(s.unreadable) .env.example \(s.unreadable == 1 ? "file" : "files") couldn’t be read." }
        if s.cancelled { message += " You stopped the import; what finished is kept." }
        return s.unreadable > 0
            ? ResultReport(outcome: .nothingNew, title: "Imported with warnings", message: message)
            : .success("Repositories imported", message)
    }

    // MARK: GitLab

    /// gitlab.com, or the instance signed in to before. Signed in already →
    /// straight to the repo picker; otherwise the token form.
    func connectGitLab() {
        startGitLab(at: RepoConnections.gitLabHost ?? GitLabClient.gitLabCom)
    }

    /// Token form with an empty address, for a company or client server.
    func showGitLabHost() {
        task?.cancel()
        gitLabHost = ""
        gitLabToken = ""
        step = .gitLabHost
    }

    private func startGitLab(at url: URL) {
        task?.cancel()
        host = .gitlab(url)
        guard let token = storedToken() else {
            gitLabHost = url.absoluteString
            gitLabToken = ""
            step = .gitLabHost
            return
        }
        task = Task {
            do {
                try await loadRepos(token: token)
                step = .choosingRepos
            } catch GitHubError.unauthorized {
                forget() // revoked or expired: ask for a new token
                gitLabHost = url.absoluteString
                step = .gitLabHost
            } catch {
                if !Task.isCancelled { step = .failed(Self.failure(for: error)) }
            }
        }
    }

    /// Checks the token against the instance, then keeps it in the Keychain.
    func signInToGitLab() {
        guard let url = Self.validatedGitLabHost(gitLabHost) else { return }
        let token = gitLabToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        task?.cancel()
        host = .gitlab(url)
        task = Task {
            do {
                step = .loading("Contacting \(host.name)…")
                _ = try await GitLabClient(baseURL: url).currentUser(token: token)
                // SECURITY: the token lives only in the Keychain.
                try tokens?.setString(token, for: host.tokenRef)
                gitLabToken = ""
                UserDefaults.standard.set(url.absoluteString, forKey: RepoConnections.gitLabHostKey)
                try await loadRepos(token: token)
                if let account {
                    step = .connected(ConnectedAccount(
                        provider: .gitlab, username: account.login, email: account.email, avatarURL: account.avatarUrl,
                        repoCount: repos.count, privateRepoCount: repos.filter(\.isPrivate).count
                    ))
                    onReport?(.success("Signed in to \(host.name)", "Connected as @\(account.login), with \(repos.count) \(repos.count == 1 ? "project" : "projects") you can import (read-only)."))
                }
            } catch is CancellationError {
            } catch {
                if Task.isCancelled { return }
                let failure: Failure = switch error {
                case GitHubError.unauthorized: .other("GitLab didn’t accept this token. Check it’s still valid and has the read_api scope.")
                case GitHubError.accessDenied: .other("This token can’t read the API. Create one with the read_api scope.")
                default: Self.failure(for: error)
                }
                step = .failed(failure)
                onReport?(.failed("Couldn’t sign in to \(host.name)", failure.message))
            }
        }
    }

    // MARK: Navigation

    func openVerificationPage() {
        if case .waitingForGitHub(let code) = step { NSWorkspace.shared.open(code.verificationURL) }
    }

    func retry() {
        switch host {
        case .github: connectGitHub()
        case .gitlab(let url): startGitLab(at: url)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        step = .idle
    }

    /// "Later" after connecting: back to the project list.
    func dismiss() {
        step = .idle
    }

    func chooseRepos() {
        step = .choosingRepos
    }

    // MARK: Helpers

    private static func failure(for error: Error) -> Failure {
        switch error {
        case GitHubError.notConfigured: .notConfigured
        case GitHubError.expiredCode: .codeExpired
        case GitHubError.accessDenied: .accessDenied
        case GitHubError.unauthorized: .signedOut
        case is URLError: .network
        case let keychain as KeychainError: .other(keychain.userMessage)
        case GitHubError.http(let status): .other("The server returned HTTP \(status).")
        default: .other(error.localizedDescription)
        }
    }

    /// Accepts only https URLs with a host. SECURITY: plain http would send the
    /// token in clear text.
    static func validatedGitLabHost(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}
