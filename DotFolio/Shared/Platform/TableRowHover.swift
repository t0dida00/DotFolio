import AppKit
import SwiftUI

extension View {
    /// Highlights the row under the pointer in a native `Table`. SwiftUI's
    /// Table has no row hover, so this finds the NSTableView behind it and
    /// lays a faint band over the hovered row. Row views paint their own
    /// (alternating) background, so the band sits above them; it ignores the
    /// mouse, so clicks, double-clicks and menus still reach the row.
    /// Apply directly to the `Table`.
    func tableRowHover() -> some View {
        background(TableHoverInstaller())
    }
}

private struct TableHoverInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(near: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Rows may have changed: hide a band that could now be misplaced, and
        // attach again if the table was rebuilt.
        DispatchQueue.main.async {
            context.coordinator.attach(near: view)
            context.coordinator.refresh()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSResponder {
        private weak var table: NSTableView?
        private var trackingArea: NSTrackingArea?
        private let band = PassthroughView()
        private var hoveredRow = -1

        override init() {
            super.init()
            band.wantsLayer = true
            band.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            band.isHidden = true
        }

        required init?(coder: NSCoder) { nil }

        /// Finds the table this view sits behind: the NSTableView whose
        /// scroll view overlaps `anchor` most (a page may hold several tables).
        func attach(near anchor: NSView) {
            guard let window = anchor.window else { return }
            let target = anchor.convert(anchor.bounds, to: nil)
            var best: (table: NSTableView, overlap: CGFloat)?
            for table in Self.tables(in: window.contentView) {
                guard let scroll = table.enclosingScrollView else { continue }
                let frame = scroll.convert(scroll.bounds, to: nil)
                let overlap = frame.intersection(target)
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                if area > (best?.overlap ?? 0) { best = (table, area) }
            }
            guard let found = best?.table, found !== table else { return }
            detach()
            table = found
            found.addSubview(band, positioned: .above, relativeTo: nil)
            let area = NSTrackingArea(rect: .zero,
                                      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            found.addTrackingArea(area)
            trackingArea = area
        }

        func detach() {
            if let trackingArea { table?.removeTrackingArea(trackingArea) }
            trackingArea = nil
            band.removeFromSuperview()
            band.isHidden = true
            hoveredRow = -1
            table = nil
        }

        /// Re-places the band after the rows changed (or hides it).
        func refresh() {
            guard let table, hoveredRow >= 0 else { return }
            if hoveredRow < table.numberOfRows {
                band.frame = table.rect(ofRow: hoveredRow)
            } else {
                hide()
            }
        }

        override func mouseMoved(with event: NSEvent) { update(event) }
        override func mouseEntered(with event: NSEvent) { update(event) }
        override func mouseExited(with event: NSEvent) { hide() }

        private func update(_ event: NSEvent) {
            guard let table else { return }
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            guard row != hoveredRow else { return }
            hoveredRow = row
            guard row >= 0 else { band.isHidden = true; return }
            band.frame = table.rect(ofRow: row)
            // Row views added since (new rows) would cover it: keep it on top.
            if table.subviews.last !== band { table.addSubview(band, positioned: .above, relativeTo: nil) }
            band.isHidden = false
        }

        private func hide() {
            hoveredRow = -1
            band.isHidden = true
        }

        private static func tables(in view: NSView?) -> [NSTableView] {
            guard let view else { return [] }
            if let table = view as? NSTableView { return [table] }
            return view.subviews.flatMap { tables(in: $0) }
        }
    }
}

/// A view the mouse goes straight through.
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
