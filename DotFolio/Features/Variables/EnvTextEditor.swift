import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import AppKit
import LocalAuthentication
import SwiftData
import SwiftUI

/// Plain-text editor for .env text: monospaced, no wrapping (long lines
/// scroll sideways), and no smart quotes, dashes, spelling or text
/// replacement, which would silently change values.
struct EnvTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Wrap long lines and scroll vertically (one value), instead of one
    /// line per variable that scrolls sideways (the whole file).
    var wraps = false

    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)

    /// Fits every line (at least 5) so the page scrolls, not the editor.
    static func height(lines: Int) -> CGFloat {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return lineHeight * CGFloat(max(lines, 5)) + DS.Space.l * 2
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = wraps
        scroll.hasHorizontalScroller = !wraps
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.font = Self.font
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.textContainerInset = NSSize(width: DS.Space.s, height: DS.Space.s)
        if !wraps {
            // No wrapping: the container is as wide as the longest line.
            view.isHorizontallyResizable = true
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        view.string = text
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}
