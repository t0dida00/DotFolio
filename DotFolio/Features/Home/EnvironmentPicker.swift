import DotFolioModels
import SwiftUI

/// Environment switcher: pills with each environment's color dot, the
/// selected one raised (same look as the project tabs).
struct EnvironmentPicker<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let name: String
        let isProtected: Bool
    }

    let items: [Item]
    @Binding var selection: ID?

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(items) { item in
                EnvironmentPill(name: item.name, isProtected: item.isProtected, isSelected: item.id == selection) {
                    selection = item.id
                }
            }
        }
        .padding(DS.Space.xxs)
        .background(.quaternary.opacity(DS.Fill.tile), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Environment")
    }
}

private struct EnvironmentPill: View {
    let name: String
    let isProtected: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs + 2) {
                Circle()
                    .fill(DS.Env.color(for: name))
                    .frame(width: 8, height: 8)
                Text(name)
                    .fontWeight(isSelected ? .semibold : .regular)
                if isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help("Protected: exports ask for confirmation")
                }
            }
            .font(.callout)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, DS.Space.m)
            .frame(height: 26)
            .background {
                if isSelected {
                    Capsule().fill(.background).shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                } else if hovering {
                    Capsule().fill(.quaternary.opacity(DS.Fill.control))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickableCursor()
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension EnvironmentPicker where ID == ProjectEnvironment.ID {
    /// A project's environments.
    init(environments: [ProjectEnvironment], selection: Binding<ProjectEnvironment.ID?>) {
        self.items = environments.map { Item(id: $0.id, name: $0.name, isProtected: $0.isProtected) }
        self._selection = selection
    }
}

extension EnvironmentPicker where ID == String {
    /// Environments by name (before the project exists, e.g. New Project).
    init(names: [String], selection: Binding<String>) {
        self.items = names.map { Item(id: $0, name: $0, isProtected: $0 == "production") }
        self._selection = Binding(get: { selection.wrappedValue }, set: { if let v = $0 { selection.wrappedValue = v } })
    }
}

/// Thin reminder shown while a protected (production) environment is open.
struct ProtectedEnvironmentBanner: View {
    let name: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(DS.Env.color(for: name))
            Text("\(name.capitalized) · these values are live.")
                .fontWeight(.medium)
            Text("Changes here affect your deployed app; exports ask for confirmation.")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .background(DS.Env.color(for: name).opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .strokeBorder(DS.Env.color(for: name).opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}
