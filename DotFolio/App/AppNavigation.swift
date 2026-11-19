import Observation

/// App-wide UI requests that come from menu commands.
@Observable
@MainActor
final class AppNavigation {
    /// Set by the "Erase All Data…" menu command; RootView asks to confirm.
    var isConfirmingErase = false
}
