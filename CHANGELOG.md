# Changelog

All notable changes to TerminalPad are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-27

First public release. 🚀

### Added

- **Home screen for your terminal** — a glassy Launchpad/Spotlight for AI coding
  agents and every CLI you have installed. Click a tile or type and press Enter
  to launch in a new terminal window.
- **Curated agents** — Claude Code, Gemini CLI, Ollama, OpenCode, Antigravity,
  Copilot CLI, Cursor, and more, each with per-mode variants (e.g. Skip
  Permissions, YOLO, Plan).
- **Auto-discovery** — finds the CLI tools you actually installed (Homebrew
  leaves, cargo/go/bun/pipx and user bin dirs) and gives each a real brand logo.
- **Add / edit agents in-app** — full page with live icon auto-detect, color
  picker, custom icon, SF Symbol fallback, and per-variant working directory.
- **CLI-or-app launch** — agents that ship a GUI app (Cursor, Ollama) open the
  app when no CLI is present.
- **Native macOS behavior** — global hotkey (⌥⌘Space), menu bar item,
  hide-not-close, window-frame autosave, System/Light/Dark theme that follows
  the system, mode-adaptive monochrome logos.
- **Favorites & frequency sort**, aliases, search with Spotlight-style results.
- **Settings** — terminal choice (Terminal/iTerm2/Ghostty/Warp), launch at
  login, "open apps on the current desktop," hover haptics, and more.
- **Universal binary** — Apple Silicon + Intel, macOS 14+.
- **Privacy by default** — no telemetry, no analytics, no accounts. See
  [PRIVACY.md](PRIVACY.md).

[1.0.0]: https://github.com/git-abhisar-singh/TerminalPad/releases/tag/v1.0.0
