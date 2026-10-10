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
- `docs/fixes.md`: why each fix exists, or recording a new one (root cause and evidence, numbered; conclusions and evidence only, no raw logs, usernames, or personal paths).
- `docs/known-issues.md`: verified user-visible issues and workarounds (the App opens it; maintainer notes in its top comment).
- `experiments/README.md`: experiment conventions and index.

## Hard rules

1. NEVER modify, patch, or redistribute game/launcher files (`MapleStory.exe`, `認證器.exe`, `貓貓TMS登入器.exe`, `HostShield.exe`, `XCGUI.dll`, `*.wz`).
2. NEVER read, print, or commit `login.txt` (game folder; may contain credentials).
3. Every change to state outside the repo MUST be reversible: back up replaced files as `*.macmeow-orig` (other state: record the original value or how to restore it) and list it in `docs/external-state.md`. Anything intentionally kept must be listed there with the reason.
4. `scripts/play.sh` MUST be idempotent (check, then apply only if needed) and MUST refuse to patch the engine while Wine is running.
5. Ask before killing a user's running Wine or game session.
6. Release only via `tools/release/release.sh`. Ask before `release.sh publish` (CI then releases publicly). Never move or reuse a pushed tag.

## Code conventions

Rules that can be checked mechanically live in `prek.toml` and `tools/dev/lint.sh`, not here; fix the code instead of skipping the hook.

- Target macOS `/bin/bash` 3.2. Under `set -u`, expand possibly-empty arrays as `${a[@]+"${a[@]}"}`.
- Folder roles: `scripts/` is the user flow (bundled into the app); `tools/` is dev-only and may use Homebrew, uv, Xcode and `python3`; `experiments/` holds one-off experiments (rules in `experiments/README.md`).
- `app/` is a SwiftUI UI shell (macOS 13+, Swift 5 mode, system frameworks only): every action goes through `scripts/`. Never reimplement script logic, engine/prefix paths or game file lists in Swift; extend the scripts instead. Layers in `app/Sources/` depend downward only (App → UI → Features → Services → Core); `App/` holds the entry point and the only composition root.
- Shared paths, constants and helpers live in `scripts/lib/common.sh` (user side) and `tools/lib.sh` (dev side). Source them; never redefine them. Settings come from `load_settings` (`MACMEOW_SETTINGS` in `common.sh`); never hard-code their defaults elsewhere.
- Scripts that change external state expose `check|apply|restore` (`check` exits 0 when already applied; the root-only `setup-loopback.sh` uses `install|uninstall|check`); call other scripts with `run_script`.
- Dev tool sources go in `tools/src/<name>/`, built by `tools/dev/build.sh` into `build/tools/`; diagnostic output goes to `debug/`.
- Resolve paths from the script location (`$(dirname "$0")`); honor `GAME_DIR` and `CYDER_ENGINE`.
- User-facing messages in Traditional Chinese (zh-TW); comments in zh-TW or English.

## Runtime pitfalls

- GUI Wine programs hang if started from a non-Aqua shell (agent shell, SSH). Launch via Terminal.app: `tools/diag/wgui.sh` does this by default; elsewhere use `in_terminal` from `tools/lib.sh`.
- Wine clients must use the running wineserver's sync mode: `WINEMSYNC=1` or `WINEESYNC=1` per Cyder's `msync`/`esync` setting (`export_wine_env` in `scripts/lib/common.sh` does this).
- After changing the launch flow, run `dist/MacMeow.app` or `scripts/play.sh`; `bash scripts/play.sh status` must then show 4 HostShield listeners on `127.x.x.1:37601-37630` and `貓貓TMS登入器.exe` running. If you could not run this, say so.

## Commits

Small, focused commits: `git commit -m "<type>(<scope>): <description>" -m "<body>"`.

- `type`: `feat`, `fix`, `perf`, `refactor`, `docs`, `build`, `test`, or `chore`; `scope`: the main area touched (`app`, `scripts`, `patches`, `tools`, `docs`, `release`).
- Subject: imperative English, lowercase start, no trailing period, within 72 characters. Body (required): what changed and why, wrapped at 72 columns.

User-visible changes: one zh-TW line under `## Unreleased`, in the same commit. Never touch `VERSION` or released headings (`release.sh` does).

## Done means

`prek` passes.
