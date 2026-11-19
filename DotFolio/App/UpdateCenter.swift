import AppKit
import DotFolioIntegrations
import Observation

/// "Check for Updates…" and "What's New" state, shared by the menu command
/// and the links under the version number.
@Observable
@MainActor
final class UpdateCenter {
    enum State: Equatable {
        case idle
        case checking
        case finished(UpdateChecker.Result)
        case failed(String)
    }

    /// The public repo whose GitHub Releases announce new versions.
    static let releasesRepo = "t0dida00/DotFolio"

    var state: State = .idle
    var isShowingResult = false
    var isShowingWhatsNew = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// "Version 0.1.0 (1)"
    static var versionLabel: String {
        buildNumber.map { "Version \(currentVersion) (\($0))" } ?? "Version \(currentVersion)"
    }

    func checkForUpdates() {
        state = .checking
        isShowingResult = true
        Task {
            do {
                let result = try await UpdateChecker(repo: Self.releasesRepo).check(currentVersion: Self.currentVersion)
                state = .finished(result)
            } catch {
                state = .failed("Couldn’t reach GitHub. Check your connection and try again.")
            }
        }
    }

    var releasesPage: URL { URL(string: "https://github.com/\(Self.releasesRepo)/releases")! }
}
