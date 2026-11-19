import AppKit

/// Measures text so table columns can be "just wide enough" for their content.
/// Measuring is slow (Core Text layout), and tables ask again on every redraw
/// (hover, typing, reveal), so results are memoized per string and font.
@MainActor
enum TextWidth {
    private static let regular = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let mono = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static var cache: [String: CGFloat] = [:]
    private static var monoCache: [String: CGFloat] = [:]
    /// Bound on cached strings; the cache is simply dropped when it is reached.
    private static let cacheLimit = 4000

    /// - Parameter cached: pass false for secret values: a revealed value must
    ///   not outlive the reveal (session lock clears it), so it is never memoized.
    static func of(_ text: String, monospaced: Bool = false, cached: Bool = true) -> CGFloat {
        guard cached else { return measure(text, monospaced: monospaced) }
        if let hit = monospaced ? monoCache[text] : cache[text] { return hit }
        let width = measure(text, monospaced: monospaced)
        if monospaced {
            if monoCache.count >= cacheLimit { monoCache.removeAll(keepingCapacity: true) }
            monoCache[text] = width
        } else {
            if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
            cache[text] = width
        }
        return width
    }

    private static func measure(_ text: String, monospaced: Bool) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: monospaced ? mono : regular]).width)
    }

    /// Widest of `texts` plus `extra` (cell padding, icons), clamped to min…max.
    static func fit(_ texts: [String], monospaced: Bool = false, extra: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        let widest = texts.map { of($0, monospaced: monospaced) }.max() ?? 0
        return Swift.min(max, Swift.max(min, widest + extra))
    }
}
