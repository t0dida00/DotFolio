import DotFolioModels
import SwiftUI

/// A project's tile shows where it comes from: a folder on this Mac, GitHub,
/// GitLab, or made by hand. Local stands out, since only local projects can
/// read (and later sync) the .env files of their source code.
struct ProjectTile: View {
    let origin: ProjectOrigin
    var size: CGFloat = 40

    init(project: Project, size: CGFloat = 40) {
        self.origin = project.origin
        self.size = size
    }

    var body: some View {
        // The app's icon style (TintedIcon: logo proportions).
        TintedIcon(tint: tint, size: size) { glyph }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    @ViewBuilder
    private var glyph: some View {
        switch origin {
        case .github: BrandMark.github.image.resizable().scaledToFit()
        case .gitlab: BrandMark.gitlab.image.resizable().scaledToFit()
        case .local: Image(systemName: "laptopcomputer").resizable().scaledToFit().fontWeight(.medium)
        case .manual: Image(systemName: "square.and.pencil").resizable().scaledToFit().fontWeight(.medium)
        }
    }

    private var helpText: String {
        switch origin {
        case .local: "Local project: linked to a folder on this Mac"
        case .github: "Imported from GitHub"
        case .gitlab: "Imported from GitLab"
        case .manual: "Created by hand"
        }
    }

    private var tint: Color {
        switch origin {
        case .local: DS.Palette.aqua
        case .github: DS.Palette.violet
        case .gitlab: DS.Palette.orange
        case .manual: DS.Palette.blue
        }
    }
}
