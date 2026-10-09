# AGENTS.md

This project is developed primarily by AI agents. This file holds the rules; `docs/` holds the knowledge. Read this file fully before changing anything.

## Project

Run the 貓貓谷 (MapleStory TW private server) Windows launch chain on Apple Silicon macOS via Cyder (Wine x86_64 under Rosetta 2), without a VM and without touching game or launcher files. All fixes live on the macOS/Wine side.

## Documentation map

Each fact lives in exactly one file. Link to it; do not copy it.

- `README.md`: end users only (zh-TW): requirements, install, usage, uninstall, known issues. No developer details.
- `docs/architecture.md`: launch chain, what each file does, external state touched, env vars, what to update when upstream changes.
- `docs/development.md`: build and test commands, Wine DLL rebuild, diagnostic tools, Rosetta debugging, release.
- `docs/technical-notes.md`: root cause and evidence for each fix.
- `docs/known-issues.md`: details of each known issue (symptom, workaround, cause, status); `README.md` keeps only a one-line user-visible summary per issue.
- `patches/SOURCES.md`: Wine source and LGPL info for prebuilt DLLs.
- `CHANGELOG.md`, `VERSION`: user-visible changes and release version.

## Hard rules

1. NEVER modify, patch, or redistribute game/launcher files (`MapleStory.exe`, `認證器.exe`, `貓貓TMS登入器.exe`, `HostShield.exe`, `XCGUI.dll`, `*.wz`).
2. NEVER read, print, or commit `login.txt` (game folder; may contain credentials).
3. NEVER commit `.env`, `debug/`, `build/`, `dist/`, or game/launcher files. Do not weaken `.gitignore`. Diagnostic output goes to `debug/`.
4. Every change to state outside the repo MUST be reversible: back up originals as `*.macmeow-orig`, provide a `restore` action, call it from `scripts/uninstall.sh`, and list it in `docs/architecture.md`.
5. `scripts/play.sh` MUST be idempotent (check, then apply only if needed) and MUST refuse to patch the engine while Wine is running.
6. Prebuilt DLLs only apply to the CrossOver base they were built from (`patch-cyder-dlls.sh` checks `engine-manifest.json`). After a rebuild, update `patches/bin/SHA256SUMS` and `patches/SOURCES.md`.
7. Only `scripts/setup-loopback.sh install|uninstall` runs as root. Everything else stays unprivileged.
8. Ask before killing a user's running Wine or game session.

## Shell conventions

- Target macOS `/bin/bash` 3.2: no associative arrays, `mapfile`, or `${var,,}`.
- Under `set -u`, expand possibly-empty arrays as `${a[@]+"${a[@]}"}`.
- Brace variables next to CJK text (`"${name}：…"`); zh_TW locales otherwise read full-width characters as part of the name.
- `scripts/` is the user flow (bundled into the app) and uses macOS built-ins only (no `python3`, Homebrew, Xcode); so does `tools/sign-debug.sh` (called by `uninstall.sh`). Other `tools/` may use them.
- `app/` is a SwiftUI app (macOS 13+, Swift 5 language mode) compiled by `swiftc` in `app/build-app.sh`; Xcode or Command Line Tools are needed to build only, the product links system frameworks only. It is a UI shell: every action goes through `scripts/` (`play.sh status --porcelain`, `progress` markers, `play.sh stop`, `setup-loopback.sh`). Never reimplement script logic, engine/prefix paths or game file lists in Swift; extend the scripts instead. Layers in `app/Sources/` depend downward only (UI → Features → Services → Core): `Core/` is pure Foundation (no AppKit/SwiftUI) and unit-tested by `tools/test-app.sh`; `scripts/` are invoked only via `Services/Scripts.swift`.
- Shared paths, constants and helpers live in `scripts/lib/common.sh` (user side) and `tools/lib.sh` (dev side). Source them; never redefine engine/prefix paths, game file lists or loopback IPs.
- Dev tool sources go in `tools/src/<name>/`, built by `tools/build.sh` into `build/tools/`. Never write build output into the source tree.
- Resolve paths from the script location (`$(dirname "$0")`); never hard-code a home directory or username; honor `GAME_DIR` and `CYDER_ENGINE`.
- User-facing messages in Traditional Chinese (zh-TW); comments in zh-TW or English.

## Runtime pitfalls

- GUI Wine programs hang if started from a non-Aqua shell (agent shell, SSH). Launch via Terminal.app: `tools/wgui.sh` does this by default; elsewhere use `in_terminal` from `tools/lib.sh`.
- Wine clients must use the running wineserver's sync mode: set `WINEMSYNC=1` when Cyder has `msync=true` (`export_wine_env` in `scripts/lib/common.sh` does this).

## Definition of done

1. `bash -n` passes on every edited shell script.
2. `bash app/build-app.sh` succeeds with no Swift warnings (it runs `codesign --verify`).
3. If the launch flow changed: run `dist/MacMeow.app` or `scripts/play.sh`, then `bash scripts/play.sh status` must show 4 HostShield listeners on `127.x.x.1:37601-37630` and `貓貓TMS登入器.exe` running. If you could not run this, say so.
4. Docs updated per the documentation map. Technical notes record conclusions and evidence only (no raw logs, usernames, or personal paths).
5. User-visible changes have a bullet under `## Unreleased` in `CHANGELOG.md` (zh-TW, one line per change).

## Commits

Small, focused commits. Add the `CHANGELOG.md` bullet in the same commit as the change; never write directly under a released version heading. Internal-only changes (dev tools, docs, refactors) need no entry.

Message format (Conventional Commits), subject and body both required:

```
<type>(<scope>): <description>

<body>
```

- `type`: `feat`, `fix`, `perf`, `refactor`, `docs`, `build`, `test`, or `chore`.
- `scope`: the main area touched, e.g. `app`, `scripts`, `patches`, `tools`, `docs`, `release`.
- `description`: imperative English, lowercase start, no trailing period; keep the whole subject line within 72 characters.
- Body: what changed and why, wrapped at 72 columns; bullets are fine. Pass it as a second `-m` (`git commit -m "<subject>" -m "<body>"`).

Releases go through `tools/release.sh check|prepare|build|publish|release X.Y.Z` only; `publish` pushes the tag and `.github/workflows/release.yml` runs `release.sh ci` to build, notarize, create a draft GitHub Release and `release` it (verify the draft's assets, then un-draft it as Latest; see `docs/development.md`, 發佈). Never edit `VERSION` or the release headings by hand, and never move or reuse a pushed tag. Ask before `publish` (it releases publicly via CI) and before un-drafting a release.
