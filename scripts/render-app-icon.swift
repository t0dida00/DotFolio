// Renders the app icon master (1024×1024 PNG) from the same design as
// AppMark (DotFolio/Shared/Brand/AppMark.swift). Regenerate the icon set:
//
//   swift scripts/render-app-icon.swift /tmp/icon-1024.png
//   S=DotFolio/Resources/Assets.xcassets/AppIcon.appiconset
//   for pt in 16 32 128 256 512; do
//     sips -z $pt $pt /tmp/icon-1024.png --out $S/icon_${pt}x${pt}.png
//     sips -z $((pt*2)) $((pt*2)) /tmp/icon-1024.png --out $S/icon_${pt}x${pt}@2x.png
//   done
//
// Colors and ratios match AppMark (glyph 72% × 76% of the tile): macOS 26
// scales every icon to the same tile, so the glyph is what makes it read as
// big as Calendar or Notes in the Dock. Keep both in sync.
// Check what macOS shows with NSWorkspace.shared.icon(forFile:).
import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xFF)/255, green: Double((hex >> 8) & 0xFF)/255, blue: Double(hex & 0xFF)/255) }
}
/// Same proportions as AppMark (DotFolio/Shared/Brand/AppMark.swift), laid
/// a 1024 canvas: a 904 pt tile centered (60 pt margins), a bit larger than
/// Apple's 824 pt grid so it reads as big as other icons in the Dock.
struct Icon: View {
    let tileSize: CGFloat = 904
    var tile: RoundedRectangle { RoundedRectangle(cornerRadius: tileSize * 0.225, style: .continuous) }
    var body: some View {
        tile.fill(LinearGradient(colors: [Color(hex: 0x8A7CF4), Color(hex: 0x5543D0)], startPoint: .top, endPoint: .bottom))
            .frame(width: tileSize, height: tileSize)
            .overlay(tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 9))
            .overlay {
                Image(systemName: "lock.doc.fill").resizable().scaledToFit().fontWeight(.medium)
                    .frame(width: tileSize * 0.72, height: tileSize * 0.76)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xE4DFFF)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(hex: 0x2E2290).opacity(0.35), radius: 16, y: 10)
            }
            // Shadows that stay inside the 60 pt margin.
            .shadow(color: .black.opacity(0.28), radius: 8, y: 6)
            .shadow(color: .black.opacity(0.16), radius: 16, y: 10)
            .frame(width: 1024, height: 1024)
    }
}
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Icon()); r.scale = 1
    guard let cg = r.cgImage else { print("fail"); exit(1) }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("ok", cg.width, cg.height)
}
