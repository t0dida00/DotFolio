import Foundation
import LocalAuthentication
import Observation

/// Holds one authenticated LAContext for the session, so a single Touch ID /
/// password prompt unlocks reveal & copy until the session locks again.
///
/// SECURITY: the context is dropped after `timeout` without use (auto-lock)
/// or on `lock()`. Keychain items are created with `.userPresence`, so the
/// Keychain itself refuses to return values without a live context.
@Observable
@MainActor
public final class SessionLock {
    public private(set) var isUnlocked = false
    public var timeout: TimeInterval

    private var context: LAContext?
    private var lastUse: Date = .distantPast
    private let now: () -> Date

    public init(timeout: TimeInterval = 5 * 60, now: @escaping () -> Date = Date.init) {
        self.timeout = timeout
        self.now = now
    }

    /// Returns a live authenticated context, prompting for Touch ID / the Mac
    /// password if the session is locked or has timed out.
    public func authenticatedContext(reason: String) async throws -> LAContext {
        if let context, !hasExpired {
            lastUse = now()
            return context
        }
        lock()
        let fresh = LAContext()
        try await fresh.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        context = fresh
        lastUse = now()
        isUnlocked = true
        return fresh
    }

    public func lock() {
        context?.invalidate()
        context = nil
        isUnlocked = false
    }

    /// Call periodically (or on app activity) to enforce auto-lock.
    public func lockIfExpired() {
        if context != nil, hasExpired { lock() }
    }

    var hasExpired: Bool { now().timeIntervalSince(lastUse) > timeout }
}
