import Foundation
import Observation

/// App-wide UI requests that come from menu commands.
@Observable
@MainActor
final class AppNavigation {
    /// Set by the "Erase All Data…" menu command; RootView asks to confirm.
    var isConfirmingErase = false
    /// Set by the "Verify Data…" menu command; RootView shows the report.
    var isVerifyingData = false
    /// Set by "Suggest Sources…" (menu, Overview) and once on first launch.
    var isSuggestingSources = false
    /// A project folder dropped or chosen (File ▸ Import Project Folder…);
    /// RootView shows the import sheet.
    var folderToImport: PendingFolder?
    /// A project to show in the list once it exists (after an import).
    var projectToOpen: UUID?
    /// With `projectToOpen`: the environment to show (palette, menu bar).
    var environmentToOpen: UUID?
    /// Show the Library on this provider group ("" = Other) — a Library key
    /// picked in the palette.
    var libraryProviderToOpen: String?
    /// ⌘K: the command palette (RootView shows it).
    var isShowingPalette = false
    /// "New Project" asked for from the palette (HomeView opens the form).
    var isRequestingNewProject = false
    /// The result dialog (RootView shows it).
    var report: ResultReport?

    /// Shows the result of an action. Waits a moment so a sheet that is
    /// closing (the one the action ran in) is gone before the dialog opens.
    func show(_ report: ResultReport) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            self.report = report
        }
    }
}
