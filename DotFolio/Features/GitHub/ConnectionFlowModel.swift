import AppKit
import DotFolioCore
import DotFolioIntegrations
import DotFolioModels
import DotFolioSecurity
import Foundation
import Observation
import SwiftData

/// "Connect your repo host" flow: GitHub device-flow sign-in, picking repos,
/// and importing them as projects.
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
            case .signedOut: "Your GitHub session ended."
            case .network: "Couldn’t reach GitHub."
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
    var gitLabHost = ""

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
    private var context: ModelContext?
    private var tokens: (any SecretStore)?
    private var secrets: (any SecretStore)?

    /// What signing out would delete; the root view asks to confirm.
    struct SignOutPlan: Identifiable {
        let id = UUID()
        let login: String
        let projects: [Project]
    }
    var pendingSignOut: SignOutPlan?
    private(set) var isPreparingSignOut = false
    private var task: Task<Void, Never>?
    private static let tokenRef = "github"
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
                    forgetGitHub() // revoked/expired: fall through to a fresh sign-in
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
            try tokens?.setString(token, for: Self.tokenRef)
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
        let user = try await client.currentUser(token: token)
        let list = try await client.repositories(token: token)
        account = user
        repos = list
        selectedRepoIDs = []
        repoFilter = ""
        UserDefaults.standard.set(user.login, forKey: RepoConnections.gitHubUserKey)
    }

    func refreshRepos() {
        guard let token = storedToken() else { connectGitHub(); return }
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

    /// Works out which projects belong to the signed-in account (asking
    /// GitHub for its repo list while the token still works), then asks the
    /// user to confirm before anything is deleted.
    func requestSignOutGitHub() {
        guard let context, !isPreparingSignOut else { return }
        let login = account?.login ?? UserDefaults.standard.string(forKey: RepoConnections.gitHubUserKey) ?? ""
        isPreparingSignOut = true
        Task {
            var names = Set(repos.map(\.fullName))
            if names.isEmpty, let token = storedToken() {
                names = Set(((try? await client.repositories(token: token)) ?? []).map(\.fullName))
            }
            let projects = login.isEmpty ? [] : AccountSignOut.projects(provider: .github, login: login, repoFullNames: names, context: context)
            isPreparingSignOut = false
            pendingSignOut = SignOutPlan(login: login, projects: projects)
        }
    }

    /// Deletes the account's projects (Keychain values first), then the token.
    func confirmSignOut() {
        guard let plan = pendingSignOut, let context, let secrets else { return }
        pendingSignOut = nil
        task?.cancel()
        do {
            try AccountSignOut.deleteProjects(plan.projects, context: context, secrets: secrets)
            try context.save()
        } catch {
            // Keep the token too: the account's projects still exist, and the
            // user can retry signing out.
            step = .failed(.other("Some stored values couldn’t be removed from the Keychain, so sign-out stopped. \((error as? KeychainError)?.userMessage ?? error.localizedDescription)"))
            onReport?(.failed("Couldn’t sign out of GitHub", "Some stored values couldn’t be removed from the Keychain, so sign-out stopped."))
            return
        }
        forgetGitHub()
        step = .idle
        onReport?(.success("Signed out of GitHub",
                           plan.projects.isEmpty
                               ? "DOTFOLIO forgot @\(plan.login). No projects came from it."
                               : "DOTFOLIO forgot @\(plan.login) and deleted the \(plan.projects.count) projects imported from it, with their Keychain values.",
                           groups: plan.projects.isEmpty ? [] : [.init(title: "Deleted", names: plan.projects.map(\.name))]))
    }

    private func forgetGitHub() {
        try? tokens?.delete(Self.tokenRef)
        UserDefaults.standard.removeObject(forKey: RepoConnections.gitHubUserKey)
        account = nil
        repos = []
    }

    private func storedToken() -> String? {
        try? tokens?.string(for: Self.tokenRef)
    }

    // MARK: Repo picker

    var filteredRepos: [GitHubRepo] {
        let q = repoFilter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.fullName.localizedStandardContains(q) || ($0.description?.localizedStandardContains(q) ?? false) }
    }

    func isImported(_ repo: GitHubRepo) -> Bool {
        guard let context else { return false }
        return RepoImporter.existingProject(for: repo.fullName, provider: .github, context: context) != nil
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
        let source = (account?.login).map { AccountSignOut.source(provider: .github, login: $0) }

        task?.cancel()
        task = Task {
            await withTaskGroup(of: (GitHubRepo, GitHubFile?, Bool).self) { group in
                // Child tasks only fetch; all model updates happen back here on the main actor.
                let fetch: @Sendable (GitHubRepo) async -> (GitHubRepo, GitHubFile?, Bool) = { repo in
                    do {
                        let file = try await client.file(".env.example", in: repo.fullName, ref: repo.defaultBranch, token: token)
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
                        .init(provider: .github, fullName: repo.fullName, url: repo.htmlUrl,
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
                onReport?(Self.report(importStats))
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
        onReport?(Self.report(summary))
    }

    /// The dialog after importing repositories.
    private static func report(_ s: ImportSummary) -> ResultReport {
        let projects = "\(s.projects) \(s.projects == 1 ? "project" : "projects")"
        if s.projects == 0 {
            return .nothing(s.cancelled ? "Import stopped" : "Nothing imported", "No repository was imported.")
        }
        var message = "Imported \(projects) with \(s.variables) variables from GitHub."
        if s.unreadable > 0 { message += " \(s.unreadable) .env.example \(s.unreadable == 1 ? "file" : "files") couldn’t be read." }
        if s.cancelled { message += " You stopped the import; what finished is kept." }
        return s.unreadable > 0
            ? ResultReport(outcome: .nothingNew, title: "Imported with warnings", message: message)
            : .success("Repositories imported", message)
    }

    // MARK: GitLab (not wired yet)

    func connectGitLab() {
        step = .failed(.other("GitLab sign-in is coming next. GitHub works now."))
    }

    func showGitLabHost() {
        step = .gitLabHost
    }

    func connectSelfHostedGitLab() {
        guard Self.validatedGitLabHost(gitLabHost) != nil else { return }
        step = .failed(.other("Self-hosted GitLab sign-in is coming next. GitHub works now."))
    }

    // MARK: Navigation

    func openVerificationPage() {
        if case .waitingForGitHub(let code) = step { NSWorkspace.shared.open(code.verificationURL) }
    }

    func retry() {
        connectGitHub()
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
        case GitHubError.http(let status): .other("GitHub returned HTTP \(status).")
        default: .other(error.localizedDescription)
        }
    }

    /// Accepts only https URLs with a host. SECURITY: plain http would send the
    /// OAuth code and token in clear text.
    static func validatedGitLabHost(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}
