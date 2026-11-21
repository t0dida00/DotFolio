import DotFolioModels
import SwiftUI

/// The second line of a palette or menu bar result. A project key reads
/// "Shop · ● production · Stripe", with the environment's color dot.
struct PaletteSubtitle: View {
    let item: CommandPalette.Item

    var body: some View {
        Group {
            if case .variable(let v) = item, let env = v.environment, let project = env.project {
                HStack(spacing: DS.Space.xs) {
                    Text("\(project.name) ·")
                    EnvLabel(name: env.name)
                    if !v.displayService.isEmpty { Text("· \(v.displayService)") }
                }
            } else {
                Text(item.subtitle)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
