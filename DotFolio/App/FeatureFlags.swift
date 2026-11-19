/// Features that exist in code but aren't ready to show.
enum FeatureFlags {
    /// GitLab sign-in (gitlab.com and self-hosted) isn't wired up yet; hide
    /// its buttons instead of showing ones that only say "coming next".
    static let gitLab = false
}
