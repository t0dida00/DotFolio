import SwiftUI

/// The SF Symbol animations used across the app, so each kind of icon moves
/// the same way everywhere (e.g. every "add" bounces, every "delete" wiggles).
enum SymbolMotion {
    /// Generic actions: add, remove, close, menus.
    case bounce
    /// Things that send something out: export, open a link.
    case bounceUp
    /// Things that bring something in: import, save.
    case bounceDown
    /// Destructive or attention-seeking: delete, errors, secrets.
    case wiggle
    /// Go on / go back.
    case wiggleForward, wiggleBackward
    /// Refresh / reload.
    case rotate
    /// Something alive in the background: Touch ID, locks.
    case pulse
}

extension View {
    /// Plays `motion` on every SF Symbol inside this view when the pointer
    /// enters it — and once when it first appears, if `onAppear` is set.
    /// Does nothing when the user turned on Reduce Motion.
    func symbolMotion(_ motion: SymbolMotion, onAppear: Bool = false) -> some View {
        modifier(SymbolMotionModifier(motion: motion, playOnAppear: onAppear))
    }

    /// Plays `motion` every time `value` changes (e.g. a status that updates).
    func symbolMotion<V: Equatable>(_ motion: SymbolMotion, value: V) -> some View {
        modifier(SymbolMotionTrigger(motion: motion, value: value))
    }
}

private struct SymbolMotionModifier: ViewModifier {
    let motion: SymbolMotion
    let playOnAppear: Bool
    @State private var trigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .symbolMotion(motion, value: trigger)
            .onHover { inside in
                if inside && !reduceMotion { trigger += 1 }
            }
            .task {
                guard playOnAppear, !reduceMotion else { return }
                // Let the view settle on screen first.
                try? await Task.sleep(for: .milliseconds(350))
                trigger += 1
            }
    }
}

private struct SymbolMotionTrigger<V: Equatable>: ViewModifier {
    let motion: SymbolMotion
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            switch motion {
            case .bounce: content.symbolEffect(.bounce, value: value)
            case .bounceUp: content.symbolEffect(.bounce.up, value: value)
            case .bounceDown: content.symbolEffect(.bounce.down, value: value)
            case .wiggle: content.symbolEffect(.wiggle, value: value)
            case .wiggleForward: content.symbolEffect(.wiggle.forward, value: value)
            case .wiggleBackward: content.symbolEffect(.wiggle.backward, value: value)
            case .rotate: content.symbolEffect(.rotate, value: value)
            case .pulse: content.symbolEffect(.pulse, value: value)
            }
        }
    }
}
