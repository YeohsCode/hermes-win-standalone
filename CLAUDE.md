# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hermes Windows Standalone is a one-click Windows installer for the Hermes AI Agent. It bundles a Tauri desktop shell, an isolated WSL2 distribution (`HermesLinux`), and an Inno Setup installer into a single `.exe`. The installer ships all dependencies offline — no network downloads on the target machine.

The repo itself contains **no Hermes application code**. It pulls `hermes-agent` and `hermes-webui` from upstream (pinned via `AGENT_VERSION` / `WEBUI_VERSION` in `.github/workflows/build-release.yml`) and packages them into WSL rootfs images.

## Architecture

Three independent build targets that combine at install time:

```
Tauri .exe (Windows)  ──spawns──▶  wsl -d HermesLinux  ──runs──▶  hermes-agent + hermes-webui
     ▲                                    ▲
     │                                    │
   WebView2 iframe ──HTTP──▶  http://localhost:{dynamic-port}
```

**1. `tauri-app/` — Windows shell (Rust + React 19 + Vite)**
- `src-tauri/src/main.rs` exposes 4 Tauri commands: `check_wsl_ready`, `start_hermes`, `stop_hermes`, `get_hermes_status`. The frontend (`src/App.tsx`) drives a state machine: `checking → setup_required | starting → ready | error`, then embeds the WebUI as an iframe.
- `wsl.rs` shells out to `wsl.exe` — it does NOT use a WSL Rust crate. The distro name `HermesLinux` and script paths (`/opt/hermes/scripts/{start,stop,health}-services.sh`) are hardcoded constants and must stay in sync with `wsl-distro/scripts/`.
- `port.rs` finds a free port starting from 8787 (avoids conflicts when multiple instances or other apps occupy the default).
- `tray.rs` builds the system tray. Closing the window hides instead of exiting (`prevent_close` in `main.rs`); only the tray "退出" item actually quits and stops services.

**2. `wsl-distro/` — Layered rootfs (Docker → tar.gz)**
- Layers: `core` (required, ~300MB: Ubuntu 24.04 + Python 3.12 + uv + hermes-agent[all,web] + hermes-webui + git/ripgrep), `browser` (Playwright + Chromium), `voice` (faster-whisper + ffmpeg + TTS), `messaging` (Telegram/Discord/Slack/钉钉/飞书 + cloud SDKs).
- `build-rootfs.sh` builds via Docker, then `docker export | gzip` produces a flat rootfs tarball suitable for `wsl --import`. Layer tarballs are produced by `export-differential-layer.sh`, which inventories the core image's file paths, walks the full layer image, and prunes any file that already exists in core (path-based diff — fast, and correct because layer Dockerfiles only ADD files). Layers are installed by tar-extracting at `/` (see `scripts/install-layer.sh`), which uses `/opt/hermes/.layers/<name>.installed` as an idempotency marker.
- The build context is assembled in `.build-context/` by copying `${AGENT_SRC}` and `${WEBUI_SRC}` (defaults: `../../ref/hermes-agent` and `../../ref/hermes-webui`). CI bypasses this by downloading the pinned tags directly.
- `scripts/start-services.sh` launches `hermes-agent gateway` and `hermes-webui server.py` via `nohup`, writing PIDs to `/run/hermes/` and logs to `/root/.hermes/logs/`. Both run as root inside WSL — `wsl.conf` sets `default=root`.

**3. `installer/hermes-win.iss` — Inno Setup**
- Component selection (`core` is `fixed`, others optional) maps directly to which `layer-*.tar.gz` files get copied to `{app}\wsl\` and then installed by `import-distro.ps1`.
- `InitializeSetup()` (Pascal) checks `wsl --version` and, if missing, offers `wsl --install --no-distribution` and aborts for a reboot.
- Uninstall calls `uninstall.ps1`, which is expected to `wsl --unregister HermesLinux` for a clean removal.

## Common Commands

```bash
# Frontend type check (run from tauri-app/)
cd tauri-app && npm install && npx tsc --noEmit

# Rust compile check (run from tauri-app/src-tauri/)
cd tauri-app/src-tauri && cargo check

# Tauri dev mode (Windows only — needs WSL2 + HermesLinux already imported)
cd tauri-app && npm run tauri dev

# Tauri production build (Windows only)
cd tauri-app && npm run tauri build

# Build a single rootfs layer (requires Docker + sources at AGENT_SRC/WEBUI_SRC)
cd wsl-distro
export AGENT_SRC=../../ref/hermes-agent
export WEBUI_SRC=../../ref/hermes-webui
./build-rootfs.sh core         # or: browser | voice | messaging | all

# Generate Tauri icons (cross-platform Python; run before any Tauri build)
bash scripts/generate-icons.sh
```

There is no test runner in this repo. `tests/test-install.ps1` is a Windows E2E install smoke check, and `tests/test-rootfs-build.sh` is a Docker build sanity check — neither runs in CI.

## Release Flow

Pushing a `v*` tag triggers `.github/workflows/build-release.yml`:
1. **build-rootfs** (Linux, matrix over 4 layers) — downloads pinned `hermes-agent` and `hermes-webui` tarballs, builds Docker images, exports `.tar.gz` artifacts.
2. **build-tauri** (Windows) — `npm ci` + `npm run tauri build` → `hermes-desktop.exe` (the Cargo binary; this is also what gets installed on the user's machine).
3. **package-installer** (Windows, tag-only) — pulls all artifacts, runs Inno Setup → `HermesSetup-*.exe`.
4. **release** — uploads installer + raw layer tarballs to GitHub Releases.

`ci.yml` runs on PR: hadolint, shellcheck, `tsc --noEmit`, `cargo check`. Both lint steps use `|| true`, so they don't fail the build.

## Things That Will Bite You

- **Hardcoded distro name and paths**: `HermesLinux`, `/opt/hermes/scripts/*.sh`, `/opt/hermes/venv/bin/python`. Changing any of these means touching `wsl.rs`, the Dockerfiles, the `wsl-distro/scripts/*`, and `import-distro.ps1` together.
- **Version pinning lives in CI, not in code**: `AGENT_VERSION` / `WEBUI_VERSION` in `build-release.yml` are the source of truth for what gets shipped. Local builds use whatever is at `${AGENT_SRC}` / `${WEBUI_SRC}`.
- **Local dev on macOS/Linux can only validate ~70% of the stack**: `cargo check`, `tsc --noEmit`, and Docker rootfs builds work cross-platform; `wsl --import`, the actual Tauri `.exe`, the Inno Setup compile, and the system tray require Windows. See `docs/work_logs/` for the verification matrix.
- **Layer Dockerfiles assume they only ADD files** — the differential layer logic (`export-differential-layer.sh`) is path-based, so a layer that *modifies* a file already present in core would silently lose its modification. If you ever need to patch a core file from a downstream layer, switch the diff to content-hash-based or restructure to put the change in core.
- **Health check is just a TCP connect**, not an HTTP probe. `wsl.rs::reqwest_check` currently opens a TCP socket to `127.0.0.1:{port}` and returns success on connect — it constructs the `/health` URL but never fetches it.
