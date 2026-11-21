import SwiftUI

/// Square tile: the service's icon for single-service accounts, a person for
/// accounts used on several services.
/// An account is a login, not a provider (one login serves many), so its
/// tile is always the person symbol.
struct AccountTile: View {
    let services: [String]
    var size: CGFloat = 28

    var body: some View {
        TintedIcon(symbol: "person.crop.circle", tint: DS.Palette.violet, size: size)
    }
}
