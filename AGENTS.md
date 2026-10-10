# mac-meow

Run the 貓貓谷 (MapleStory TW private server) Windows launch chain on Apple Silicon macOS via Cyder (Wine x86_64 under Rosetta 2), without a VM and without touching game or launcher files. All fixes live on the macOS/Wine side.

## Documentation map

Each fact lives in exactly one file. Link to it; do not copy it. Read the matching file before starting a task, and update that same file when its facts change. Docs are zh-TW except this file.

Docs hold reasons, contracts, invariants and procedures. Mechanics (step order, retries, timeouts, flags) belong in a comment next to the code; values the code can enumerate (defaults, allowed values, file lists) are referenced by symbol (「見 `common.sh` 的 `MACMEOW_SETTINGS`」), never copied. Prefer bullet lists over Markdown tables.

- `README.md`: anything end users see (requirements, install, usage, uninstall, one-line known-issue summaries); end users only.
- `docs/architecture.md`: launch chain, connection path, what each top-level folder holds.
- `docs/scripts.md`: user scripts in `scripts/` (role, contracts, non-obvious behavior).
- `docs/app.md`: `MacMeow.app` (source layers, adding state/progress/script calls, feature behavior, `build-app.sh` and dmg).
- `docs/external-state.md`: state changed outside the repo and how it is restored (rule 4).
- `docs/settings.md`: game settings and environment variables.
- `docs/upstream-changes.md`: what to update when the private server, Cyder, Homebrew, macOS or the repo name changes.
- `docs/development.md`: dev environment, build, tests, prek.
- `docs/debugging.md`: diagnostic tools and Rosetta debugging.
- `docs/wine-patches.md`: rebuilding prebuilt Wine DLLs, adding a Wine patch (LGPL source info: `patches/SOURCES.md`).
- `docs/repo-images.md`: README and social preview images.
- `docs/release.md`: versioning, release flow, smoke test, failed release.
- `docs/ci.md`: GitHub Actions, Dependabot, Actions secrets.
- `docs/homebrew.md`: Homebrew cask template, cask install/uninstall, tap publishing.
- `docs/signing.md`: Developer ID certificate, notarization, `.env`, signing failures.
- `docs/fixes.md`: why each fix exists, or recording a new one (root cause and evidence, numbered).
- `docs/known-issues.md`: verified user-visible issues and workarounds (the App opens it; maintainer notes in its top comment).
- `experiments/README.md`: experiment conventions and index.

## Hard rules

1. NEVER modify, patch, or redistribute game/launcher files (`MapleStory.exe`, `認證器.exe`, `貓貓TMS登入器.exe`, `HostShield.exe`, `XCGUI.dll`, `*.wz`).
2. NEVER read, print, or commit `login.txt` (game folder; may contain credentials).
3. NEVER commit `.env`, `debug/`, `build/`, `dist/`, or game/launcher files. Do not weaken `.gitignore`. Diagnostic output goes to `debug/`.
4. Every change to state outside the repo MUST be reversible: back up originals as `*.macmeow-orig`, provide a `restore` action, call it from `scripts/uninstall.sh`, and list it in `docs/external-state.md`. Anything intentionally kept must be listed there with the reason.
5. `scripts/play.sh` MUST be idempotent (check, then apply only if needed) and MUST refuse to patch the engine while Wine is running.
6. Prebuilt DLLs only apply to the CrossOver base they were built from (`patch-cyder-dlls.sh` checks `engine-manifest.json`). After a rebuild, update `patches/bin/SHA256SUMS` and `patches/SOURCES.md`.
7. Only `scripts/setup-loopback.sh install|uninstall` runs as root. Everything else stays unprivileged.
8. Ask before killing a user's running Wine or game session.
9. Release only via `tools/release/release.sh`; never edit `VERSION` or released `CHANGELOG.md` headings by hand. Ask before `release.sh publish` (CI then releases publicly). Never move or reuse a pushed tag.

## Code conventions

- Target macOS `/bin/bash` 3.2: no associative arrays, `mapfile`, or `${var,,}`.
- Under `set -u`, expand possibly-empty arrays as `${a[@]+"${a[@]}"}`.
- Brace variables next to CJK text (`"${name}：…"`); zh_TW locales otherwise read full-width characters as part of the name.
- `scripts/` is the user flow (bundled into the app) and uses macOS built-ins only (no `python3`, Homebrew, Xcode). `tools/` is dev-only and may use Homebrew, uv, Xcode and `python3`; the user flow never calls it.
- `experiments/` holds one-off, unmaintained experiments (one folder each, any third-party tool); `scripts/`, `app/` and `tools/` must never depend on it. Rules in `experiments/README.md`.
- `app/` is a SwiftUI app (macOS 13+, Swift 5 language mode) compiled by `swiftc` in `app/build-app.sh`; Xcode or Command Line Tools are needed only to build; the product links system frameworks only. It is a UI shell: every action goes through `scripts/` (`play.sh status --porcelain`, `progress` markers, `play.sh stop`, `setup-loopback.sh`). Never reimplement script logic, engine/prefix paths or game file lists in Swift; extend the scripts instead. Layers in `app/Sources/` depend downward only (App → UI → Features → Services → Core; `App/` holds the entry point and the only composition root): `Core/` is pure Foundation (no AppKit/SwiftUI) and unit-tested by `tools/dev/test-app.sh`; `scripts/` are invoked only via `Services/Scripts.swift`.
- Shared paths, constants and helpers live in `scripts/lib/common.sh` (user side) and `tools/lib.sh` (dev side). Source them; never redefine engine/prefix paths, game file lists or loopback IPs.
- Scripts that change external state expose `check|apply|restore` (`check` exits 0 when already applied; `setup-loopback.sh` uses `install|uninstall` instead) through `cmd_<sub>` functions and exit 64 via `usage` on bad arguments; call other scripts with `run_script`. Settings come from `load_settings` (`MACMEOW_SETTINGS` in `common.sh`); never hard-code their defaults elsewhere.
- Dev tool sources go in `tools/src/<name>/`, built by `tools/dev/build.sh` into `build/tools/`. Never write build output into the source tree.
- `justfile` is the single entry point for dev tools: every `tools/*/*.sh` and `experiments/build.sh` has a recipe that only forwards its arguments (`"$@"`) plus a one-line doc comment; put no logic in it. Scripts stay directly runnable (CI and prek call them directly).
- Resolve paths from the script location (`$(dirname "$0")`); never hard-code a home directory or username; honor `GAME_DIR` and `CYDER_ENGINE`.
- User-facing messages in Traditional Chinese (zh-TW); comments in zh-TW or English.

## Runtime pitfalls

- GUI Wine programs hang if started from a non-Aqua shell (agent shell, SSH). Launch via Terminal.app: `tools/diag/wgui.sh` does this by default; elsewhere use `in_terminal` from `tools/lib.sh`.
- Wine clients must use the running wineserver's sync mode: set `WINEMSYNC=1` when Cyder has `msync=true` (`export_wine_env` in `scripts/lib/common.sh` does this).

## Definition of done

1. `bash -n` passes on every edited shell script.
2. `bash app/build-app.sh` succeeds with no Swift warnings (it runs `codesign --verify`).
3. If the launch flow changed: run `dist/MacMeow.app` or `scripts/play.sh`, then `bash scripts/play.sh status` must show 4 HostShield listeners on `127.x.x.1:37601-37630` and `貓貓TMS登入器.exe` running. If you could not run this, say so.
4. Docs updated per the documentation map. `docs/fixes.md` records conclusions and evidence only (no raw logs, usernames, or personal paths).
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
