# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hermes Windows Offline Installer — a single-exe Windows installer that bundles the official Hermes Desktop App (Electron) and a pre-built Python runtime with hermes-agent, enabling fully offline installation. No network downloads on the target machine.

The project does NOT contain its own desktop shell or agent code. It packages the upstream [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) Electron Desktop App and Python runtime into an Inno Setup installer for offline/enterprise distribution.

The upstream `AGENT_VERSION` is pinned in `.github/workflows/build-release.yml`.

## Architecture

```
CI Pipeline (single Windows runner)
├─ cleanup-artifacts       → Delete old artifacts to stay within quota
├─ build & package         → Python venv + hermes-agent + PortableGit
│   ├─ runtime bundle        + Electron Desktop App (unpacked)
│   └─ Inno Setup            → HermesSetup-x.x.x.exe (tag-only)
└─ release                 → Upload installer to GitHub Releases (tag-only)

User Install (offline, single .exe)
├─ Electron Desktop App    → {app}\
├─ hermes-agent runtime    → %LOCALAPPDATA%\hermes\hermes-agent\
├─ PortableGit             → %LOCALAPPDATA%\hermes\git\
└─ setup-hermes.ps1        → PATH, HERMES_HOME, bootstrap marker
```

**Key insight:** The upstream Electron app (`apps/desktop/`) has a first-launch bootstrap that downloads the runtime from the internet. Our installer pre-populates the runtime so the app skips bootstrap entirely. This is detected via:
- `%LOCALAPPDATA%\hermes\hermes-agent\.hermes-bootstrap-complete` marker file
- `hermes_cli/main.py` must exist in the source root
- `venv/Scripts/python.exe` must exist

**1. `installer/hermes-win.iss` — Inno Setup**
- Core component (fixed): Electron Desktop App + pre-built hermes-agent Python venv + PortableGit
- Optional: browser automation (Playwright + Chromium), voice (STT/TTS)
- Post-install runs `setup-hermes.ps1` which configures `HERMES_HOME`, PATH, writes bootstrap marker
- Uninstall runs `uninstall.ps1` which removes scheduled tasks, PATH entries, and env vars (preserves user data)

## Common Commands

```bash
# There is no local build/dev workflow — this is a packaging project.
# All builds happen in CI (GitHub Actions on windows-latest).

# To test the Inno Setup script syntax locally (requires Inno Setup 6):
iscc installer/hermes-win.iss
```

## Release Flow

Pushing a `v*` tag triggers `.github/workflows/build-release.yml`:
1. **cleanup-artifacts** (Ubuntu) — deletes all old artifacts to stay within GitHub storage quota.
2. **build** (Windows) — single job that builds runtime bundle (Python venv + hermes-agent + PortableGit) and Electron app, then packages them into `HermesSetup-*.exe` via Inno Setup (packaging step is tag-only). No intermediate artifacts are uploaded; only the final installer is uploaded.
3. **release** (Ubuntu, tag-only) — downloads installer artifact and publishes to GitHub Releases.

`ci.yml` runs on PR: validates Inno Setup script, checks PowerShell script syntax.

## Things That Will Bite You

- **Upstream workspace builds**: The Electron app requires `npm ci` from the hermes-agent **repo root** (not `apps/desktop/`). The root `package.json` defines workspaces: `apps/*`, `web`, `ui-tui`.
- **Version pinning lives in CI, not in code**: `AGENT_VERSION` in `build-release.yml` is the source of truth.
- **Bootstrap marker format**: The `.hermes-bootstrap-complete` file is JSON with `schemaVersion`, `pinnedCommit`, `pinnedBranch`, `completedAt`, `desktopVersion`. The Electron app validates its schema version and checks for `hermes_cli/main.py` + venv Python.
- **HERMES_HOME layout**: `%LOCALAPPDATA%\hermes\` with `hermes-agent/` (source + venv), `git/` (PortableGit), `logs/`, `sessions/`, `skills/`.
- **Electron app resolution order for hermes backend**: `HERMES_DESKTOP_HERMES_ROOT` → dev source → bootstrap-complete install → PATH → pip-installed → bootstrap-needed. Our installer satisfies condition 3 (bootstrap-complete).
- **Editable vs non-editable pip install**: CI uses non-editable install (`uv pip install .` not `-e .`) because the venv must be relocatable. The hermes-agent source is still bundled for `isHermesSourceRoot()` detection.
