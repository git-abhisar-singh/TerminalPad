# Privacy Policy

_Last updated: 2026-06-27_

TerminalPad is a local macOS app. It does **not** collect, store, or transmit
any personal data, and it has **no analytics, no telemetry, no tracking, and no
accounts**.

## What stays on your Mac

Everything. Your configuration lives in `~/.config/terminalpad/`:

- `agents.json` — your agents and their launch commands
- `discovered.json` — a cache of CLI tools found on your `PATH`
- `logos/` — cached brand icons

TerminalPad launches the commands **you** choose in your own terminal. It never
records, uploads, or shares which commands you run.

## The only two network requests

Both are anonymous HTTPS `GET` requests. Neither sends any identifying
information about you or your machine.

1. **Brand logos** — `https://cdn.simpleicons.org/<name>/...`
   Fetches a brand icon for a tool you have installed. Only the tool's public
   name appears in the URL (e.g. `docker`, `gh`). No identity, no payload.

2. **Update check** — `https://api.github.com/repos/git-abhisar-singh/TerminalPad/releases/latest`
   An anonymous request to compare your version against the latest release.
   You can avoid it simply by not opening the "Check for updates" action.

That's it. No third-party SDKs, no ad networks, no crash reporters.

## Permissions

- **Automation / Apple Events** — to open your terminal and run the command you picked.
- **Accessibility** (only if you use Ghostty or Warp) — to type the command into terminals that lack an AppleScript API.

You grant these through macOS system prompts and can revoke them anytime in
**System Settings → Privacy & Security**.

## The app vs. the website

The **TerminalPad app** has **zero** analytics or telemetry — full stop.

The **project website** (this landing page) uses **Cloudflare Web Analytics**,
which is **cookieless** and collects **no personal data** and no cross-site
tracking — just aggregate counts like page views, referrers, and country. It
sets no cookies and needs no consent banner. It runs only on the website, never
in the app.

## Changes

Any change to this policy will be reflected in this file and the project's
[CHANGELOG](CHANGELOG.md).

## Contact

Questions? Open an issue on
[GitHub](https://github.com/git-abhisar-singh/TerminalPad/issues) or email
**abhisar.s.work@gmail.com**.
