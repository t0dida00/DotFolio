# Dotfolio

The app’s name is written **Dotfolio** (capital D, the rest lower case; not DOTFOLIO or DotFolio) everywhere users see it: the app bundle, menus, UI text, release titles. Code identifiers, the scheme, the repo and the bundle ID `app.dotfolio.DotFolio` keep `DotFolio`.

Native macOS app (Swift 6, SwiftUI, SwiftData, macOS 26) that stores project secrets in the Keychain and remembers where each one comes from (account, service, repo).

## Layout

- `DotFolio/` — app target (SwiftUI views only). Generated Xcode project: run `xcodegen generate` after adding/removing files; never edit `DotFolio.xcodeproj` by hand.
  - `App/` — entry point, root view, menu commands (`AppNavigation`), updates, release notes.
  - `Features/<Feature>/` — one folder per area: `Home` (window shell: `ProjectBrowser`, toolbar, brand), `Projects`, `Variables`, `Library`, `Accounts`, `Overview`, `GitHub`, `Import`, `Maintenance`.
  - `Shared/` — used by several features: `DesignSystem/` (tokens and components), `Brand/` (logo, provider/project/account tiles and styles), `Platform/` (AppKit/SwiftUI helpers), `Services/` (Keychain env, clipboard, folders, pickers).
  - One main view per file, ~350 lines max (a file that must stay bigger says why in a "Size note" comment). A view used by more than one feature goes to `Shared/`. Logic that can be tested goes to `DotFolioKit` (e.g. `TabStrip`, `Library.groups`).
- `Packages/DotFolioKit/` — logic, all unit-tested:
  - `DotFolioModels` (SwiftData models, search, overview stats, source guessing, tab rules)
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

## Consistency (use `DotFolio/Shared/DesignSystem/`)

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

## Pull requests and commits: `type(scope): summary`

Every PR title (and the squash-merge commit it becomes) follows Conventional Commits, like:

```
feat(library): filter keys by environment
fix(tab-strip): keep the active tab when closing tabs to the right
refactor(projects): split ProjectBrowser into column views
```

- **Format:** `type(scope): summary`. Lower case, imperative mood ("add", "keep", "split"), no trailing period, at most ~72 characters. Say what changes for the user or the code, not how ("show provider icons by service", not "update AccountViews.swift").
- **Types:** `feat` (new behavior), `fix` (bug fix), `refactor` (no behavior change), `perf`, `docs` (README, CLAUDE.md, comments), `test`, `build` (project.yml, XcodeGen, signing), `ci`, `chore` (tooling, housekeeping), `revert`.
- **Scopes** (one, the area that changes): `projects`, `variables`, `library`, `accounts`, `overview`, `import`, `github`, `sources` (Smart sources, `SourceGuesser`), `keychain` (DotFolioSecurity, Touch ID session), `env` (DotFolioEnv), `models`, `core`, `design-system`, `tab-strip`, `updates`, `icon`, `readme`. Use a component name in kebab-case when it's narrower (`value-editor`, `folder-import`). Drop the scope only for changes that span the whole app.
- **Breaking changes** (data model or behavior users rely on): add `!`, as in `feat(models)!: one variable for every environment`, and explain the migration in the PR body. It ships as a MAJOR release.
- **Body:** what changed and why, how it was checked (tests, build, screens looked at), and anything not verified. End with the attribution lines the session asks for.
- **Branches:** `type/short-topic`, as in `feat/encrypted-backup`, `fix/library-empty-state`, `refactor/version-2`.
- **Labels:** a fix that must also reach an older release line gets `backport release/X.Y`.
- **Exception:** release commits keep the exact form `Release vX.Y.Z` (see below).

## Releases: every update to `main` ships a release

Whenever new work lands on `main` (a merge or a push), publish a new version in the same session — the app's **Check for Updates…** reads GitHub Releases, so an unreleased `main` is invisible to users.

1. **Pick the version** (semver, `MAJOR.MINOR.PATCH`): new feature → MINOR, fix only → PATCH, breaking data/behavior change → MAJOR.
2. **Bump** in `project.yml`: `MARKETING_VERSION` to the new version and `CURRENT_PROJECT_VERSION` +1 (build numbers only go up). Run `xcodegen generate`.
3. **Release notes**: add an entry at the top of `DotFolio/App/ReleaseNotes.swift` (shown in *What’s New*), with the same highlights you will put on GitHub.
4. **Verify**: `swift test` passes, the app builds, and the release notes read correctly in *What’s New*.
5. **Commit** `Release vX.Y.Z` on `main`, **tag** it and push both:
   ```bash
   git tag -a vX.Y.Z -m "Dotfolio X.Y.Z"
   git push origin main vX.Y.Z
   ```
6. **Build the app** (Release configuration), then pack it as a disk image and a zip:
   ```bash
   xcodebuild -project DotFolio.xcodeproj -scheme DotFolio -configuration Release -derivedDataPath build/release -allowProvisioningUpdates build
   scripts/make-dmg.sh X.Y.Z        # → build/Dotfolio-X.Y.Z.dmg (app + Applications link)
   ditto -c -k --keepParent build/release/Build/Products/Release/Dotfolio.app build/Dotfolio-X.Y.Z.zip
   ```
7. **Publish the GitHub Release** for the tag with the notes, the DMG and the zip (tag format `vX.Y.Z` — `UpdateChecker` strips the `v`):
   ```bash
   gh release create vX.Y.Z build/Dotfolio-X.Y.Z.dmg build/Dotfolio-X.Y.Z.zip --title "Dotfolio X.Y.Z" --notes-file <notes.md>
   ```
8. **Check**: an older build’s *Check for Updates…* now offers X.Y.Z.

Never skip a release after changing `main`, and never re-use or move a published tag. Pushing tags and publishing releases are outward-facing: confirm with the user before running steps 5–7.

Until the app is signed with a paid Developer ID and notarized, the DMG and zip are for the owner’s own Mac only: the free Personal Team profile lists one device and expires after 7 days, so a downloaded build may stop opening after that (rebuild, or run from Xcode). Updates are manual (download, replace the app).

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main`: `swift test` in `Packages/DotFolioKit`, then `xcodegen generate` and an unsigned Debug build. Wait for it to pass before merging. It doesn't sign, package or publish anything.

## After every change: restart the app once

When a change is done (any code change, not only UI), restart Dotfolio once so the user sees it right away:

1. Build the signed Debug app: `xcodebuild -project DotFolio.xcodeproj -scheme DotFolio -configuration Debug build` (default DerivedData — the `-derivedDataPath build` copy has no provisioning profile and can't save to the Keychain).
2. If you launched a copy earlier in the session, quit **only that PID**, then `open -n ~/Library/Developer/Xcode/DerivedData/DotFolio-*/Build/Products/Debug/Dotfolio.app` and note the new PID.
3. If the user's own copy is running from Xcode (parent process `debugserver`), don't touch it and don't open a second copy: tell the user to press ⌘R in Xcode to restart with the change.

## UI changes: verify before finishing

Never report a UI change as done from reading code alone. Before ending the turn:

1. Build succeeds and `swift test` passes.
2. Launch the app and **look at every screen/state you touched** (screenshot it and read the image):
   ```bash
   open -n ~/Library/Developer/Xcode/DerivedData/DotFolio-*/Build/Products/Debug/Dotfolio.app
   # window id of DotFolio, then:
   screencapture -x -o -l <windowID> /tmp/shot.png
   ```
   Check states too: empty, one item, many items, long text, error, dark mode.
3. Check each screenshot for: overlapping or clipped text, labels wrapping unexpectedly, misaligned rows/columns, uneven heights of tiles in the same row, controls that don't span the width they should, empty gaps, wrong colors in dark mode.
4. Fix what you find and repeat steps 1–3.
5. Never `pkill`/`killall` Dotfolio: the user is usually running it from Xcode, and killing it shows up there as `Thread 1: signal SIGTERM`. Xcode's ⌘R runs the same DerivedData binary, so `pgrep` finds the user's copy too: quit only the PID that `open -n` gave you, and never one whose parent is `debugserver` (`ps -o ppid= -p <pid>`).
6. If you cannot capture the window (Screen Recording permission missing), say so explicitly in the reply, list exactly which screens are unverified, and ask the user for a screenshot. Do not claim the UI is correct.
