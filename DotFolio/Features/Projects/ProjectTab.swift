import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

struct ProjectTab: View {
    let title: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(title)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, DS.Space.xxl)
            .frame(maxWidth: .infinity, minHeight: 26)
            .overlay(alignment: .leading) {
                // X sits on the left; always on the active tab, on hover otherwise.
                if isActive || isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DS.Space.s)
                    .help("Close Tab (⌘W)")
                    .symbolMotion(.bounce)
                    .accessibilityLabel("Close \(title)")
                    .clickableCursor()
                }
            }
            .background {
                if isActive {
                    Capsule()
                        .fill(.background)
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                } else if isHovering {
                    Capsule().fill(.quaternary.opacity(DS.Fill.control))
                }
            }
            .contentShape(.capsule)
            .onTapGesture(perform: onSelect)
            .onHover { isHovering = $0 }
            .clickableCursor()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
