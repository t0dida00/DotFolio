import AppKit
import DotFolioCore
import DotFolioModels
import DotFolioSecurity
import SwiftData
import SwiftUI

/// Accordion for one project (or the Library) in an account's "Used by":
/// a header row (chevron, tile, name, key count, Open Project) that toggles
/// the editable key tables.
struct AccountKeysSection<Content: View>: View {
    let title: String
    let count: Int
    let icon: AnyView
    @Binding var isExpanded: Bool
    let onOpen: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.m) { content }
                    .padding(DS.Space.m)
                    .transition(.opacity)
            }
        }
        .panel(radius: DS.Radius.medium, bordered: true)
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 16)
            icon
            Text(title).font(DS.Font.sectionTitle).lineLimit(1)
            Text("\(count) \(count == 1 ? "key" : "keys")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Space.s)
            if let onOpen {
                Button("Open Project", action: onOpen)
                    .buttonStyle(.link)
                    .font(.callout)
                    .opacity(isHovering || isExpanded ? 1 : 0)
                    .clickableCursor()
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .contentShape(Rectangle())
        .background {
            Rectangle().fill(isHovering ? AnyShapeStyle(.quaternary.opacity(DS.Fill.control)) : AnyShapeStyle(Color.clear))
        }
        .onTapGesture { isExpanded.toggle() }
        .onHover { isHovering = $0 }
        .clickableCursor()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAction { isExpanded.toggle() }
    }
}

/// The shared `VariableTable` for a set of keys: read-only until Edit is on
/// (double-click a row to copy its .env line), with a footer for deleting the
/// selection and showing errors.
struct AccountKeysTable: View {
    let keys: [Variable]

    @Environment(SessionLock.self) private var session
    @State private var selection: Set<Variable.ID> = []
    @State private var pendingDeletion: [Variable] = []
    @State private var errorMessage: String?
    @State private var showsValues = false
    /// The Edit switch: off = read-only.
    @State private var editUnlocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Spacer()
                ShowValuesButton(isOn: $showsValues, isEnabled: keys.contains(where: \.hasValue))
                EditSwitch(isOn: $editUnlocked)
            }
            VariableTable(
                variables: keys,
                selection: $selection,
                pendingDeletion: $pendingDeletion,
                errorMessage: $errorMessage,
                showsValues: $showsValues,
                isEditable: editUnlocked,
                emptyText: "No keys"
            )
            HStack(spacing: DS.Space.s) {
                Button {
                    pendingDeletion = keys.filter { selection.contains($0.id) }
                } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty || !editUnlocked)
                    .help(editUnlocked ? "Delete selected" : "Turn on Edit to delete keys")
                    .accessibilityLabel("Delete selected keys")
                    .clickableCursor()
                Spacer()
                Text(errorMessage ?? (editUnlocked ? " " : "Double-click a key to copy it as a .env line · turn on Edit to change it"))
                    .font(.caption)
                    .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DS.Status.danger))
                    .lineLimit(2)
            }
        }
        // Locking the session puts the table back to read-only.
        .onChange(of: session.isUnlocked) { _, unlocked in if !unlocked { editUnlocked = false } }
    }
}
