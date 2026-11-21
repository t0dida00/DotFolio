import DotFolioModels
import SwiftData
import SwiftUI

/// Safari-style tab bar: equal-width tabs in one capsule track, the active
/// tab raised as a white pill. ⌘W closes the active tab. The rules for
/// opening and closing live in `TabStrip` (DotFolioKit, tested).
struct ProjectTabBar: View {
    /// Open projects, in tab order.
    let tabs: [Project]
    @Binding var strip: TabStrip<PersistentIdentifier>

    var body: some View {
        let selection = strip.active
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.persistentModelID) { index, project in
                    let id = project.persistentModelID
                    if index > 0 {
                        // Hidden next to the active tab, like Safari.
                        let nextToActive = id == selection || tabs[index - 1].persistentModelID == selection
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1, height: 16)
                            .opacity(nextToActive ? 0 : 1)
                    }
                    ProjectTab(
                        title: project.name,
                        isActive: id == selection,
                        onSelect: { strip.active = id },
                        onClose: { strip.close(id) }
                    )
                    .contextMenu {
                        Button("Close Tab") { strip.close(id) }
                        Button("Close Other Tabs") { strip.closeOthers(keeping: id) }
                            .disabled(tabs.count < 2)
                        Button("Close Tabs to the Right") { strip.closeRight(of: id) }
                            .disabled(index == tabs.count - 1)
                        Divider()
                        Button("Close All Tabs") { strip.closeAll() }
                    }
                }
            }
            .padding(DS.Space.xxs)
            .background(.quaternary.opacity(DS.Fill.tile), in: .capsule)

            if tabs.count == 1 {
                // Takes the other half, so a lone tab is at most 50% wide.
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.s)
        .padding(.bottom, DS.Space.xxs)
        .background {
            // ⌘W closes the active tab.
            Button("") { if let active = strip.active { strip.close(active) } }
                .keyboardShortcut("w")
                .hidden()
        }
    }
}
