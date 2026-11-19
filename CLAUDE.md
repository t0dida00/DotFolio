# DotFolio

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
- Page sections: `Card`. Light inset blocks: `.panel()`. Chips: `.chip()`.
- Tables: native `Table` with `.bordered(alternatesRowBackgrounds: true)`, height `DS.Table.height(rows:)` (no vertical scroll, sideways only), content-fit widths via `TextWidth.fit`.
- Links in tables/grids: `LinkText` (one line, left-aligned), never a bare `Link` with long text.
- Every clickable control gets `.clickableCursor()` (on the control or its container). Action buttons use `.buttonBorderShape(.capsule)`.
- Terms: **Service** = what it's for (Database, Cache…), **Provider** = who provides it (Supabase, Redis…), **Account** = a login (several providers), **Link** = console URL.
- Destructive actions: `confirmationDialog` titled "Delete X?", message ends with "This can’t be undone."; Keychain items removed before metadata.
- Unfinished features are hidden behind `FeatureFlags`, not shown as "coming soon".
- Data integrity: `IntegrityCheck` (menu **DotFolio → Verify Data…**) must stay clean after any change that writes variables or Keychain items; add a case to its tests when introducing a new invariant.

## UI changes: verify before finishing

Never report a UI change as done from reading code alone. Before ending the turn:

1. Build succeeds and `swift test` passes.
2. Launch the app and **look at every screen/state you touched** (screenshot it and read the image):
   ```bash
   open -n build/Build/Products/Debug/DotFolio.app
   # window id of DotFolio, then:
   screencapture -x -o -l <windowID> /tmp/shot.png
   ```
   Check states too: empty, one item, many items, long text, error, dark mode.
3. Check each screenshot for: overlapping or clipped text, labels wrapping unexpectedly, misaligned rows/columns, uneven heights of tiles in the same row, controls that don't span the width they should, empty gaps, wrong colors in dark mode.
4. Fix what you find and repeat steps 1–3.
5. Never `pkill`/`killall` DotFolio: the user is usually running it from Xcode, and killing it shows up there as `Thread 1: signal SIGTERM`. Launch your own copy with `open -n …` and, when done, quit only that copy by its PID (e.g. `pgrep -f "build/Build/Products/Debug/DotFolio.app"` then `kill <pid>`).
6. If you cannot capture the window (Screen Recording permission missing), say so explicitly in the reply, list exactly which screens are unverified, and ask the user for a screenshot. Do not claim the UI is correct.
