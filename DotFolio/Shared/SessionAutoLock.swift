import AppKit
import DotFolioSecurity

/// Locks the Touch ID session whenever the Mac sleeps, the screen locks or
/// the screensaver starts — on top of the inactivity timeout — so revealed
/// values never survive the user stepping away.
@MainActor
final class SessionAutoLock {
    private var tokens: [NSObjectProtocol] = []

    init(session: SessionLock) {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { session.lock() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            tokens.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { session.lock() }
            })
        }
    }
}
