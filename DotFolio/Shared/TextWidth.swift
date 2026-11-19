import AppKit

/// Measures text so table columns can be "just wide enough" for their content.
enum TextWidth {
    static func of(_ text: String, monospaced: Bool = false) -> CGFloat {
        let size = NSFont.systemFontSize
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Widest of `texts` plus `extra` (cell padding, icons), clamped to min…max.
    static func fit(_ texts: [String], monospaced: Bool = false, extra: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        let widest = texts.map { of($0, monospaced: monospaced) }.max() ?? 0
        return Swift.min(max, Swift.max(min, widest + extra))
    }
}
