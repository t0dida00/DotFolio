import AppKit
import DotFolioCore
import DotFolioEnv
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

extension View {
    /// Accepts a project folder dragged from Finder or an editor and opens the
    /// import sheet for it. Files are ignored (they go to New Project / Library).
    func projectFolderDropTarget(_ navigation: AppNavigation) -> some View {
        modifier(ProjectFolderDrop(navigation: navigation))
    }
}

struct ProjectFolderDrop: ViewModifier {
    let navigation: AppNavigation
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .overlay {
                            Label("Drop to import this project folder", systemImage: "folder.badge.plus")
                                .font(DS.Font.panelTitle)
                                .padding(.horizontal, DS.Space.m)
                                .padding(.vertical, DS.Space.s)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .padding(DS.Space.s)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let folder = urls.first(where: Self.isFolder) else { return false }
                navigation.folderToImport = PendingFolder(url: folder)
                return true
            } isTargeted: { isTargeted = $0 }
    }

    private static func isFolder(_ url: URL) -> Bool {
        url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

@MainActor
enum ProjectFolderPicker {
    /// File ▸ Import Project Folder…
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Import"
        panel.message = "Choose a project folder. DOTFOLIO finds its .env files and asks which to import."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
