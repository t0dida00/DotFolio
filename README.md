<div align="center">

<img src="DotFolio/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="DOTFOLIO icon">

# DOTFOLIO

**Every `.env`, safe in your Keychain.**

A native macOS app that keeps every project's environment variables in one place: values locked in the Keychain, everything else searchable.

[![Latest release](https://img.shields.io/github/v/release/t0dida00/DotFolio?label=release)](https://github.com/t0dida00/DotFolio/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI · SwiftData](https://img.shields.io/badge/SwiftUI-SwiftData-0A84FF)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Download](https://github.com/t0dida00/DotFolio/releases/latest) · [Features](#features) · [Security](#security-model) · [Build from source](#build-from-source)

</div>

---

## Table of contents

- [Why DOTFOLIO](#why-dotfolio)
- [Features](#features)
- [Install](#install)
- [Usage](#usage)
- [Security model](#security-model)
- [Architecture](#architecture)
- [Build from source](#build-from-source)
- [Testing](#testing)
- [Releasing](#releasing)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Reporting a security issue](#reporting-a-security-issue)
- [License](#license)

## Why DOTFOLIO

Secrets usually live in `.env` files scattered across folders, copied between machines and one `git add .` away from a leak. And months later nobody remembers which Stripe account a key belongs to.

DOTFOLIO keeps the **value** in the macOS Keychain, behind Touch ID. It keeps the **context** next to it: what the key is for, who provides it, which account created it, and where to manage it.

| | `.env` files | DOTFOLIO |
|---|---|---|
| Where values live | Plain text on disk | macOS Keychain, this Mac only |
| Reading a value | Anyone with file access | Touch ID or Mac password |
| Which account / console? | Comments, memory | Service · Provider · Account · Link per key |
| Across projects | Copy-paste | Library of reusable keys, search everything |

## Features

### Projects
- **Three ways in:** create by hand, import GitHub repositories (read-only) with their `.env.example`, or **drop a project folder**. DOTFOLIO finds its `.env*` files up to three folders deep and asks which to import.
- **Environments:** development, staging and production, each as a table or as an editable `.env` file view.
- **Workspace:** projects open in Safari-style tabs; filter by **All · Git · Local**; search by name, repo, key, provider or account.

### Variables
- **Read-only by default:** double-click a row to copy it as a `.env` line (`KEY=value #Service/Provider/Account/Link`); turn on **Edit** to change it.
- **Show Values** after one Touch ID prompt. Long values open in a multi-line editor.
- **Drop `.env` files** on *Add variable*. Values already there are never overwritten.
- **Export `.env`** to the clipboard (auto-cleared), to the project folder (with a `.gitignore` check) or anywhere.

### Smart sources
- Service and Provider are guessed from the name and value: **150+ providers**, well-known names (`KV_REST_API_URL`, `AUTH_SECRET`…) and key formats (`sk-ant-`, `gsk_`, `xoxb-`…).
- **Suggest Sources** lets you review guesses before filling empty fields.
- `#Service/Provider/Account/Link` comments in `.env` files fill those columns on import.

### Library, accounts and overview
- **Library:** reusable keys next to every project's keys, filtered by All · Library · Dev · Staging · Prod.
- **Accounts:** the logins your keys come from, their provider projects and every key that uses them.
- **Overview:** missing values, keys without a source, stale values, providers and services in use, top accounts.
- **Verify Data** cross-checks the database against the Keychain and repairs what it safely can.
- **Check for Updates** and **What's New**, driven by this repository's releases.

## Install

1. Download `DOTFOLIO-x.y.z.zip` from the [latest release](https://github.com/t0dida00/DotFolio/releases/latest).
2. Unzip it and move **DOTFOLIO.app** to Applications.
3. The app isn't notarized yet, so macOS warns the first time you open it. Right-click ▸ **Open** (or allow it in System Settings ▸ Privacy & Security).

**Requirements:** macOS 26 or later, on a Mac with Touch ID or a login password.

**Updating:** **DOTFOLIO ▸ Check for Updates…** tells you when a new version is out. Download it and replace the app; your projects and Keychain values carry over.

## Usage

| To… | Do this |
|---|---|
| Add a project from a folder | Drop the folder on the project list, or **File ▸ Import Project Folder…** (⇧⌘O) |
| Import from GitHub | **Import from GitHub** at the bottom of the project list |
| Create a project by hand | **New Project** (⌘N) |
| Copy a variable | Double-click its row (table locked), or the copy button |
| Change values | Turn on **Edit** above the table |
| Fill Service / Provider | **DOTFOLIO ▸ Suggest Sources…** |
| Search | ⌘F |
| Close a tab | ⌘W |
| Check the data | **DOTFOLIO ▸ Verify Data…** |

## Security model

Security is the point of the app, so these rules are not negotiable:

- **Values only in the Keychain.** Each value is a generic-password item in the *data protection keychain*, tied to the app's signature, so other apps can't read it. SwiftData stores metadata only, never a value. Nothing is logged.
- **This Mac only, while unlocked.** Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: never synced to iCloud Keychain, never restored onto another Mac.
- **User presence enforced by the Keychain.** Items carry `.userPresence`, so the Keychain itself refuses to return a value without Touch ID or the Mac password.
- **Session lock.** One authenticated session is reused for reveal and copy. It locks after 5 minutes of inactivity, on sleep and on screen lock.
- **Safe writes and deletes.** A new value goes into a new item before the old one is removed. Keychain items are deleted before the metadata that points to them, so no secret is ever orphaned.
- **Read-only repositories.** GitHub sign-in uses a GitHub App with *Contents: read* and *Metadata: read* only. The token is kept in the Keychain.
- **Sandboxed.** App Sandbox and Hardened Runtime are on. Network access is outgoing HTTPS only. Files are touched only where you pick or drop them.
- **Clipboard.** Copied values are marked *concealed* (clipboard managers skip them) and cleared after 60 seconds.

> [!IMPORTANT]
> Because values never leave this Mac, **losing or wiping the Mac loses them**. Keep an export of what matters somewhere safe until encrypted backups ship (see [Roadmap](#roadmap)).

## Architecture

A thin SwiftUI app on top of a local Swift package that holds all the logic and its tests.

```
DotFolio/                      macOS app: SwiftUI views only
├─ App/                        entry point, menu commands, updates, release notes
├─ Features/
│  ├─ Home/                    project list, tabs, project page, tables, import, Overview, GitHub sign-in
│  ├─ Accounts/                accounts and their keys
│  └─ Libraries/               the Library
├─ Shared/                     design system, Keychain environment, clipboard, helpers
└─ Resources/                  app icon, accent color, entitlements
Packages/DotFolioKit/          logic, unit-tested
├─ DotFolioModels              SwiftData models, search, Overview stats, source guessing
├─ DotFolioSecurity            Keychain store, Touch ID session lock
├─ DotFolioEnv                 .env parsing and export, folder scan (no dependencies)
├─ DotFolioIntegrations        GitHub client (read-only)
└─ DotFolioCore                use cases: create, import, edit, copy, delete, verify, erase
scripts/render-app-icon.swift  renders the app icon from the logo design
project.yml                    XcodeGen spec (the .xcodeproj is generated)
```

| Layer | Depends on | Responsibility |
|---|---|---|
| App (SwiftUI) | DotFolioKit | Screens, navigation, design system |
| DotFolioCore | Models, Security, Env | Use cases: values go to the Keychain before metadata |
| DotFolioModels | — | SwiftData schema, search, stats, source catalog |
| DotFolioSecurity | — | `SecretStore` protocol, Keychain implementation, session lock |
| DotFolioEnv | — | `.env` parser and exporter, folder scanning |
| DotFolioIntegrations | — | Read-only GitHub client |

Conventions (design tokens, terminology, security and release rules) are documented in [CLAUDE.md](CLAUDE.md).

## Build from source

**Prerequisites**
- macOS 26, Xcode 26 or later (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple ID signed in to Xcode (a free Personal Team works). The data protection keychain needs a signed app with a provisioning profile. Unsigned builds can't save values (`errSecMissingEntitlement`).

**Steps**

```sh
git clone https://github.com/t0dida00/DotFolio.git
cd DotFolio
# set DEVELOPMENT_TEAM in project.yml to your Team ID (Xcode ▸ Settings ▸ Accounts)
xcodegen generate
open DotFolio.xcodeproj   # run the DotFolio scheme with ⌘R
```

Run `xcodegen generate` again after adding or removing files. Never edit the `.xcodeproj` by hand.

<details>
<summary><b>Using your own GitHub App (optional)</b></summary>

Create one at <https://github.com/settings/apps/new>:

- Repository permissions: **Contents → Read-only**, **Metadata → Read-only**
- **Enable Device Flow** checked
- **Expire user authorization tokens** unchecked
- Webhook: not needed (uncheck *Active*)

Put its Client ID and URL name in `DotFolio/App/GitHubConfig.swift`. Neither is a secret, since device flow needs no client secret.

</details>

## Testing

```sh
cd Packages/DotFolioKit
swift test
```

The suites cover models, security, `.env` handling, integrations and use cases. They use an in-memory secret store and an in-memory SwiftData container, so they need no signing or Keychain access. `IntegrityCheck` must stay clean after any change that writes variables or Keychain items.

## Releasing

Every update to `main` ships a release, so **Check for Updates…** always reflects `main`.

1. Bump `MARKETING_VERSION` (semver) and `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate`.
2. Add the highlights to `DotFolio/App/ReleaseNotes.swift` (shown in *What's New*).
3. Test and build, commit `Release vX.Y.Z`, tag `vX.Y.Z`, push `main` and the tag.
4. Build the Release configuration, zip `DOTFOLIO.app`, publish a GitHub Release with the notes and the zip.

Full checklist with commands: [CLAUDE.md › Releases](CLAUDE.md#releases-every-update-to-main-ships-a-release).

## Roadmap

- [ ] Encrypted, password-protected backups to restore on a new Mac
- [ ] Two-way sync between a local project and its `.env` files
- [ ] Developer ID signing and notarization
- [ ] GitLab and self-hosted GitLab sign-in
- [ ] `dotfolio` command-line tool sharing the same Keychain items

## Contributing

Issues and pull requests are welcome.

1. Fork the repo and create a branch from `main`.
2. Put logic in `DotFolioKit` with tests; keep views thin.
3. Follow the conventions in [CLAUDE.md](CLAUDE.md): design tokens, no placeholder text, required fields marked `*`, Keychain before metadata.
4. Make sure `swift test` passes and the app builds, then open a pull request describing the change and how you checked it.

## Reporting a security issue

Please **don't open a public issue** for security problems. Use GitHub's [private vulnerability reporting](https://github.com/t0dida00/DotFolio/security/advisories/new) instead, so a fix can ship before details are public.

## License

DOTFOLIO is open source under the [MIT License](LICENSE). You may use, modify and redistribute it, including commercially, as long as the copyright and license notice are kept.

The GitHub App ID in `DotFolio/App/GitHubConfig.swift` belongs to the author's GitHub App. If you ship your own build, create your own GitHub App (see [Build from source](#build-from-source)).
