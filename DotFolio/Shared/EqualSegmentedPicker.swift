import AppKit
import SwiftUI

/// A segmented control whose segments all have the same width and fill the
/// space given. SwiftUI's `.segmented` picker sizes each segment to its title,
/// and the selected title is bolder, so the segments shift sideways every time
/// the selection changes. AppKit's `.fillEqually` keeps them still.
struct EqualSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    var controlSize: NSControl.ControlSize = .regular

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.title), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.controlSize = controlSize
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        update(control)
    }

    private func update(_ control: NSSegmentedControl) {
        if let index = options.firstIndex(where: { $0.value == selection }), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: EqualSegmentedPicker

        init(parent: EqualSegmentedPicker) { self.parent = parent }

        @objc func changed(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}
