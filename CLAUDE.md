# DOTFOLIO

The app’s name is written **DOTFOLIO** (all caps) everywhere users see it: the app bundle, menus, UI text, release titles. Code identifiers, the scheme, the repo and the bundle ID `app.dotfolio.DotFolio` keep `DotFolio`.

Native macOS app (Swift 6, SwiftUI, SwiftData, macOS 26) that stores project secrets in the Keychain and remembers where each one comes from (account, service, repo).

## Layout

- `DotFolio/` — app target (SwiftUI views). Generated Xcode project: run `xcodegen generate` after adding/removing files; never edit `DotFolio.xcodeproj` by hand.
- `Packages/DotFolioKit/` — logic, all unit-tested:
  - `DotFolioModels` (SwiftData models, search, overview stats)
  - `DotFolioSecurity` (Keychain store, Touch ID session lock)
  - `DotFolioEnv` (.env parser/exporter, .gitignore check)
  - `DotFolioIntegrations` (GitHub client, read-only)
  - `DotFolioCore` (use cases: create/import/export/delete)

## Commands

- Tests: `cd Packages/DotFolioKit && swift test`
- Build: `xcodebuild -project DotFolio.xcodeproj -scheme DotFolio -configuration Debug -derivedDataPath build build`
- Run for real: open the project in Xcode and press ⌘R. The CLI build in `build/` has no provisioning profile, so the Keychain refuses to save values there.

## Rules

- App UI text is English. Replies to the user are in Vietnamese.
- Security: secret values live only in the Keychain, never in SwiftData, logs or UserDefaults. Repo access is read-only (GET only). Keychain items are removed before the metadata that references them.
- Put logic in `DotFolioKit` with tests; keep views thin.

## Consistency (use `DotFolio/Shared/DesignSystem.swift`)

- Corner radius: only `DS.Radius.small / .medium / .large` — no literal numbers.
- Spacing/padding: `DS.Space` (4pt grid: 2·4·8·12·16·20·24·32); only window-chrome/hero insets ≥ 40 may be literal.
- Type: `DS.Font.pageTitle` (screen/full-window step), `.sheetTitle`, `.sectionTitle`, `.panelTitle`, `.label` (column headers). Body text uses `.callout`/`.caption` for secondary lines.
- Color: accent is the brand violet (asset `AccentColor`). Icon tiles: `TintedIcon` with a `DS.Palette` hue (soft tint background, same-hue icon) — no gray tiles. Tiles share the logo’s proportions (`DS.IconTile`: 22.5% corners, glyph 60% of the tile); give custom icons `.resizable().scaledToFit()`, never a fixed font size or frame. Environments: `DS.Env` (development aqua, staging amber, production red) with `EnvLabel`. States: `DS.Status` (danger/warning/success), always with an icon or text. Fills: `DS.Fill`. Hues come from the validated palette — run the dataviz validator before adding new ones.
- Window layout is not responsive: minimum window `HomeView.minSize` (1200×760), list column fixed at `ProjectBrowser.sidebarWidth` (320). Never size columns as a fraction of the window.
- Page sections: `Card`. Light inset blocks: `.panel()`. Chips: `.chip()`.
- Tables: native `Table` with `.bordered(alternatesRowBackgrounds: true)`, height `DS.Table.height(rows:)` (no vertical scroll, sideways only), content-fit widths via `TextWidth.fit`.
- Inputs: no placeholder text anywhere (forms, table cells, add cards). Explain a form field with a caption line under it, `.fieldHint("…")` (red with `isError: true`). Field titles use `Text.fieldTitle(_:required:optional:)` (or `LabeledField(_:required:optional:)`): a required field ends with a red `*`, an optional one with "(optional)". Mark every field whose emptiness blocks saving as required. Search/filter fields are the only exception.
- Links in tables/grids: `LinkText` (one line, left-aligned), never a bare `Link` with long text.
- Every clickable control gets `.clickableCursor()` (on the control or its container). Action buttons use `.buttonBorderShape(.capsule)`.
- Terms: **Service** = what it's for (Database, Cache…), **Provider** = who provides it (Supabase, Redis…), **Account** = a login (several providers), **Link** = console URL, **Library key** = a `Variable` with `inLibrary == true` and no environment (reusable, not in any project; names unique per provider).
- Results: every button-triggered action (add, save, delete, import, copy to, sign in/out, erase) ends with a result dialog via `navigation.show(ResultReport…)` — green success, amber nothing changed, red failure (`DS.Status`, always with icon + title). Inline cell edits that save on Return/blur don't open one.
- Destructive actions: `confirmationDialog` titled "Delete X?", message ends with "This can’t be undone."; Keychain items removed before metadata.
- Unfinished features are hidden behind `FeatureFlags`, not shown as "coming soon".
- Data integrity: `IntegrityCheck` (menu **DotFolio → Verify Data…**) must stay clean after any change that writes variables or Keychain items; add a case to its tests when introducing a new invariant.

## Releases: every update to `main` ships a release

Whenever new work lands on `main` (a merge or a push), publish a new version in the same session — the app's **Check for Updates…** reads GitHub Releases, so an unreleased `main` is invisible to users.

1. **Pick the version** (semver, `MAJOR.MINOR.PATCH`): new feature → MINOR, fix only → PATCH, breaking data/behavior change → MAJOR.
2. **Bump** in `project.yml`: `MARKETING_VERSION` to the new version and `CURRENT_PROJECT_VERSION` +1 (build numbers only go up). Run `xcodegen generate`.
3. **Release notes**: add an entry at the top of `DotFolio/App/ReleaseNotes.swift` (shown in *What’s New*), with the same highlights you will put on GitHub.
4. **Verify**: `swift test` passes, the app builds, and the release notes read correctly in *What’s New*.
5. **Commit** `Release vX.Y.Z` on `main`, **tag** it and push both:
   ```bash
   git tag -a vX.Y.Z -m "DOTFOLIO X.Y.Z"
   git push origin main vX.Y.Z
   ```
6. **Build the app** (Release configuration) and zip it:
   ```bash
   xcodebuild -project DotFolio.xcodeproj -scheme DotFolio -configuration Release -derivedDataPath build/release build
   ditto -c -k --keepParent build/release/Build/Products/Release/DOTFOLIO.app build/DOTFOLIO-X.Y.Z.zip
   ```
7. **Publish the GitHub Release** for the tag with the notes and the zip (tag format `vX.Y.Z` — `UpdateChecker` strips the `v`):
   ```bash
   gh release create vX.Y.Z build/DOTFOLIO-X.Y.Z.zip --title "DOTFOLIO X.Y.Z" --notes-file <notes.md>
   ```
8. **Check**: an older build’s *Check for Updates…* now offers X.Y.Z.

Never skip a release after changing `main`, and never re-use or move a published tag. Pushing tags and publishing releases are outward-facing: confirm with the user before running steps 5–7.

Until the app is signed with a paid Developer ID and notarized, the zip is for the owner’s own Macs (Gatekeeper will warn elsewhere) and updates are manual (download, replace the app).

## UI changes: verify before finishing

Never report a UI change as done from reading code alone. Before ending the turn:

1. Build succeeds and `swift test` passes.
2. Launch the app and **look at every screen/state you touched** (screenshot it and read the image):
   ```bash
   open -n build/Build/Products/Debug/DOTFOLIO.app
   # window id of DotFolio, then:
   screencapture -x -o -l <windowID> /tmp/shot.png
   ```
   Check states too: empty, one item, many items, long text, error, dark mode.
3. Check each screenshot for: overlapping or clipped text, labels wrapping unexpectedly, misaligned rows/columns, uneven heights of tiles in the same row, controls that don't span the width they should, empty gaps, wrong colors in dark mode.
4. Fix what you find and repeat steps 1–3.
5. Never `pkill`/`killall` DOTFOLIO: the user is usually running it from Xcode, and killing it shows up there as `Thread 1: signal SIGTERM`. Launch your own copy with `open -n …` and, when done, quit only that copy by its PID (e.g. `pgrep -f "build/Build/Products/Debug/DOTFOLIO.app"` then `kill <pid>`).
6. If you cannot capture the window (Screen Recording permission missing), say so explicitly in the reply, list exactly which screens are unverified, and ask the user for a screenshot. Do not claim the UI is correct.
