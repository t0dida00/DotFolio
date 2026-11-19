import Observation
import SwiftData

/// Which "stage" the main window shows: the home screen, or a project's
/// detail workspace.
@Observable
@MainActor
final class AppNavigation {
    private(set) var openProjectID: PersistentIdentifier?
    /// Set by the "Erase All Data…" menu command; RootView asks to confirm.
    var isConfirmingErase = false

    func open(_ id: PersistentIdentifier) {
        openProjectID = id
    }

    func goHome() {
        openProjectID = nil
    }
}
