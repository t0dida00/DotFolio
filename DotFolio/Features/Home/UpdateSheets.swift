import DotFolioIntegrations
import SwiftUI

/// Result of "Check for Updates…".
struct UpdateResultSheet: View {
    let center: UpdateCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                AppMark(size: 52)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(title).font(DS.Font.sheetTitle)
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if center.state == .checking { ProgressView().controlSize(.small) }
            }

            if case .finished(.available(let release)) = center.state, let body = release.body, !body.isEmpty {
                ScrollView {
                    Text(body)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(DS.Space.m)
                }
                .frame(maxHeight: 220)
                .panel(radius: DS.Radius.medium, bordered: true)
            }

            HStack {
                Spacer()
                Button(primaryIsDownload ? "Later" : "OK") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                if case .finished(.available(let release)) = center.state {
                    Button("Download") {
                        NSWorkspace.shared.open(release.htmlUrl)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else if case .failed = center.state {
                    Button("Try Again", action: center.checkForUpdates)
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .clickableCursor()
        }
        .padding(DS.Space.xxl)
        .frame(width: 460)
    }

    private var primaryIsDownload: Bool {
        if case .finished(.available) = center.state { return true }
        return false
    }

    private var title: String {
        switch center.state {
        case .idle, .checking: "Checking for updates…"
        case .finished(.upToDate): "You’re up to date"
        case .finished(.available(let release)): "DOTFOLIO \(release.version) is available"
        case .finished(.noReleases): "You’re up to date"
        case .failed: "Couldn’t check for updates"
        }
    }

    private var subtitle: String {
        switch center.state {
        case .idle, .checking: "Asking GitHub for the latest release."
        case .finished(.upToDate(let current)): "DOTFOLIO \(current) is the newest version."
        case .finished(.available): "You have \(UpdateCenter.currentVersion). Download the new version from GitHub."
        case .finished(.noReleases): "DOTFOLIO \(UpdateCenter.currentVersion) — no newer release has been published."
        case .failed(let message): message
        }
    }
}

/// "What's New in x.y.z": highlights bundled with the app.
struct WhatsNewSheet: View {
    let center: UpdateCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entry = ReleaseNotes.entry(for: UpdateCenter.currentVersion)
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.m) {
                AppMark(size: 52)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("What’s New in DOTFOLIO \(UpdateCenter.currentVersion)").font(DS.Font.sheetTitle)
                    Text(UpdateCenter.versionLabel).foregroundStyle(.secondary)
                }
            }

            if let entry {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    ForEach(entry.highlights, id: \.title) { item in
                        HStack(alignment: .top, spacing: DS.Space.m) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 16))
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(item.title).fontWeight(.semibold)
                                Text(item.detail).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                Text("No notes for this version.").foregroundStyle(.secondary)
            }

            HStack {
                Button("All Releases on GitHub") { NSWorkspace.shared.open(center.releasesPage) }
                    .buttonStyle(.link)
                Spacer()
                Button("Continue") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .clickableCursor()
        }
        .padding(DS.Space.xxl)
        .frame(width: 520)
    }
}
