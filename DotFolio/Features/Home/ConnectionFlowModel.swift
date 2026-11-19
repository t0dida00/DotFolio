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
        case failed(Failure)
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
            case .accessDenied: "DotFolio needs read access to your repos to create projects. You can try again anytime."
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

    private let client = GitHubClient(clientID: GitHubConfig.clientID)
    private var context: ModelContext?
    private var tokens: (any SecretStore)?
    private var task: Task<Void, Never>?
    private static let tokenRef = "github"

    init(step: Step = .idle) {
        self.step = step
    }

    /// Called once by the root view with the app's store and Keychain.
    func configure(context: ModelContext, tokens: any SecretStore) {
        self.context = context
        self.tokens = tokens
    }

    var isWideStep: Bool { step == .choosingRepos }

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
            }
        } catch is CancellationError {
            // Cancelled by the user.
        } catch {
            if Task.isCancelled { return }
            step = .failed(Self.failure(for: error))
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

    func signOutGitHub() {
        task?.cancel()
        forgetGitHub()
        step = .idle
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

    func importSelected() {
        guard let context, let token = storedToken() else { return }
        let picked = repos.filter { selectedRepoIDs.contains($0.id) }
        guard !picked.isEmpty else { return }
        task?.cancel()
        task = Task {
            for (index, repo) in picked.enumerated() {
                if Task.isCancelled { return }
                step = .importing(done: index, total: picked.count)
                // A missing or unreadable .env.example still imports the repo.
                let file = try? await client.file(".env.example", in: repo.fullName, ref: repo.defaultBranch, token: token)
                RepoImporter.importRepo(
                    .init(provider: .github, fullName: repo.fullName, url: repo.htmlUrl,
                          defaultBranch: repo.defaultBranch, description: repo.description),
                    envExample: file?.text, envExampleSHA: file?.sha, context: context
                )
            }
            try? context.save()
            selectedRepoIDs = []
            step = .idle
        }
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
