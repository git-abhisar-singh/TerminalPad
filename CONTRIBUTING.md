# Contributing to TerminalPad

Thanks for your interest! TerminalPad is a small, focused native macOS app.
Contributions that keep it fast, native, and simple are very welcome.

## Build from source

No Xcode project — just the Swift compiler from Command Line Tools.

```bash
git clone https://github.com/git-abhisar-singh/TerminalPad.git
cd TerminalPad
./build.sh        # compiles a universal (arm64 + x86_64) TerminalPad.app
./install.sh      # builds, installs to /Applications, clears quarantine
```

Requirements:

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode not needed

## Project layout

| Path | What |
| ---- | ---- |
| `Sources/*.swift` | the whole app (SwiftUI + a little AppKit) |
| `Resources/logos/` | bundled brand marks (white-on-transparent PNG) |
| `build.sh` | compiles, bundles `TerminalPad.app`, ad-hoc signs |
| `install.sh` | build + install to `/Applications` |
| `docs/` | the GitHub Pages landing site |
| `*.py` | asset generators (icons, logos, web images) — PIL |

## Guidelines

- **Match the surrounding style.** SwiftUI-first, AppKit only where SwiftUI
  can't reach (menu bar, hotkey, window config).
- **No per-tile shadows.** They are the recurring scroll-lag source — see the
  perf notes in commit history. Keep scrolling at ~0% idle CPU.
- **No telemetry, no analytics, no accounts.** Privacy is a feature; see
  [PRIVACY.md](PRIVACY.md).
- **Keep it native.** Standard macOS behaviors (hotkeys, hide-not-close, theme
  follow) over custom reinventions.

## Pull requests

1. Fork and branch from `main`.
2. Make sure `./build.sh` compiles cleanly with no new warnings.
3. Describe **what** changed and **why**. Screenshots/GIFs for UI changes.
4. One logical change per PR keeps review fast.

## Reporting bugs / ideas

Open an [issue](https://github.com/git-abhisar-singh/TerminalPad/issues). For
security problems, follow [SECURITY.md](SECURITY.md) instead.

By contributing, you agree your contributions are licensed under the project's
[MIT License](LICENSE).
