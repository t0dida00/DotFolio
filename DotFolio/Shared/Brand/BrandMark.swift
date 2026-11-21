import SwiftUI

/// Brand marks live in the asset catalog as template SVGs.
enum BrandMark: String {
    case github = "github-mark"
    case gitlab = "gitlab-mark"

    var image: Image { Image(rawValue) }
}
