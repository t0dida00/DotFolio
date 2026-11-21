import SwiftUI

/// Top-level page card: title, optional subtitle and trailing accessory.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                trailing
            }
            content
            Spacer(minLength: 0)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous).strokeBorder(.separator))
    }
}
