import SwiftUI

/// Logo, name and slogan, stacked and centered at the top of the left column.
struct BrandHeader: View {
    @Environment(UpdateCenter.self) private var updates

    var body: some View {
        VStack(spacing: DS.Space.s) {
            AppMark(size: 64)
                .padding(.bottom, DS.Space.xs)
            Text("Dotfolio")
                .font(.title3.weight(.semibold))
            Text("Every .env, safe in your Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(UpdateCenter.versionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            VStack(spacing: DS.Space.xxs) {
                Button("Check for Updates…", action: updates.checkForUpdates)
                Button("What’s New in \(UpdateCenter.currentVersion)") { updates.isShowingWhatsNew = true }
            }
            .buttonStyle(.link)
            .font(.callout)
            .clickableCursor()
            .padding(.top, DS.Space.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.m)
        .accessibilityElement(children: .combine)
    }
}
