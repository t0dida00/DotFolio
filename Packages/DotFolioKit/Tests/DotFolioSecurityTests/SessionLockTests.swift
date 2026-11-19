import Foundation
import Testing
@testable import DotFolioSecurity

/// Touch ID itself can't run in unit tests; this covers the auto-lock clock.
@MainActor
struct SessionLockTests {
    @Test func startsLockedAndExpired() {
        let lock = SessionLock(timeout: 60, now: { Date(timeIntervalSince1970: 0) })
        #expect(!lock.isUnlocked)
        #expect(lock.hasExpired)
    }

    @Test func lockIsIdempotent() {
        let lock = SessionLock()
        lock.lock()
        lock.lockIfExpired()
        #expect(!lock.isUnlocked)
    }
}
