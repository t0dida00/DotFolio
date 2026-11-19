# DotFolio

A native macOS app for keeping every project's `.env` variables in one place — with the values locked in your Keychain, never on disk.

DotFolio is a portfolio of your projects and their environments (development, staging, production…). For each variable it records the name, the service it belongs to (Firebase, Stripe, a database…), the account it was created with, and a link to where you manage it. The secret value itself lives only in the macOS Keychain and needs Touch ID or your Mac password to reveal or copy.

> **Status:** early development (v0.1.0). GitHub import works; GitLab sign-in and `.env` export are coming next.

## Features

- **Projects in tabs** — browse all projects in a searchable list and open several side by side in Safari-style tabs (⌘W closes one).
- **Per-environment `.env` tables** — edit names, values, services, accounts and links inline; copy variables from one environment to another (existing keys are never overwritten).
- **Import from GitHub** — sign in with a read-only GitHub App and turn a repository plus its `.env.example` into a project, with the expected keys already listed.
- **Search everything** — find a project by name, repository, variable key, account or service.
- **Missing values at a glance** — the app shows which keys have no value yet without unlocking the Keychain.
- **Erase All Data** — removes every Keychain item first, then the metadata, so nothing is left behind.

## Security model

Security is the point of the app, so these rules are not negotiable:

- **Values only in the Keychain.** Variable values are stored as generic-password items in the data protection keychain. The database (SwiftData) holds metadata only — names, services, accounts, links — never a value.
- **User presence per item.** Every item is created with `.userPresence`, so the Keychain itself (not just the UI) refuses to return a value without Touch ID or the Mac password.
- **One unlock per session, then auto-lock.** A single authenticated `LAContext` is reused for reveal and copy, and dropped after 5 minutes of inactivity or when you lock.
- **Read-only repository access.** GitHub uses a GitHub App with *Contents: read* and *Metadata: read* only (an OAuth App's `repo` scope would grant write). GitLab will use `read_api` with PKCE.
- **Sandboxed.** App Sandbox and Hardened Runtime are on; network access is outgoing HTTPS only, and files are only written to folders you pick.
- **Delete safely.** Deleting a project or erasing data removes the Keychain items first; if that fails, the metadata is kept so no item is orphaned.

## Requirements

- macOS 26 or later
- Xcode 26 (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- An Apple ID signed in to Xcode (a free Personal Team is enough). The data protection keychain needs a signed app with a provisioning profile; ad-hoc builds fail to save values with `errSecMissingEntitlement`.

## Getting started

```sh
git clone https://github.com/t0dida00/DotFolio.git
cd DotFolio
xcodegen generate
open DotFolio.xcodeproj
```

Then in `project.yml`, set `DEVELOPMENT_TEAM` to your own Team ID (Xcode → Settings → Accounts), run `xcodegen generate` again, and build the **DotFolio** scheme.

### GitHub sign-in (optional)

To import repositories, create a GitHub App at <https://github.com/settings/apps/new>:

- Repository permissions: **Contents → Read-only**, **Metadata → Read-only**
- **Enable Device Flow** checked
- **Expire user authorization tokens** unchecked
- Webhook: not needed (uncheck *Active*)

Put its Client ID and URL name in `DotFolio/App/GitHubConfig.swift`. Neither is a secret — device flow needs no client secret.

## Project structure

```
DotFolio/                    macOS app (SwiftUI)
  App/                       entry point, navigation, GitHub config
  Features/Home/             project list, tabs, project details, .env table
  Features/Project/          full project workspace
  Shared/                    Keychain environment, clipboard, helpers
  Resources/                 assets and entitlements
Packages/DotFolioKit/        local Swift package
  DotFolioModels             SwiftData models, search
  DotFolioSecurity           Keychain store, session lock
  DotFolioCore               use cases: create, import, edit, copy, delete, erase
  DotFolioEnv                .env parsing (no dependencies)
  DotFolioIntegrations       GitHub/GitLab REST clients (read-only)
project.yml                  XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Tests

```sh
cd Packages/DotFolioKit
swift test
```

Plain `swift test` runs use the file-based keychain, because the data protection keychain needs a signed binary with entitlements.

## Releases

Every update merged into `main` is shipped as a new release, so **Check for Updates…** in the app always reflects `main`:

1. Bump `MARKETING_VERSION` (semver) and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Add the highlights to `DotFolio/App/ReleaseNotes.swift` (*What’s New* in the app).
3. Commit `Release vX.Y.Z`, tag `vX.Y.Z`, push `main` and the tag.
4. Publish a GitHub Release for the tag with the notes and the zipped `DotFolio.app`.

The full checklist with commands is in [CLAUDE.md](CLAUDE.md#releases-every-update-to-main-ships-a-release).

## Roadmap

- GitLab and self-hosted GitLab sign-in
- Sync with `.env.example` changes in the repository
- `dotfolio` command-line tool sharing the same Keychain items
