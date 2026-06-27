# Security Policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.x     | ✅         |

TerminalPad is distributed as source. You build and install it yourself with
`./install.sh`, so the binary you run is the code you can read in this repo.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's
[**Report a vulnerability**](https://github.com/git-abhisar-singh/TerminalPad/security/advisories/new)
form (Security → Advisories), or email **abhisar.s.work@gmail.com**. Either way
the report stays confidential until a fix ships.

Please include:

- affected version / commit
- steps to reproduce
- impact and, if known, a suggested fix

You can expect an initial response within a few days. Confirmed issues will be
fixed and credited in the [CHANGELOG](CHANGELOG.md) unless you ask otherwise.

## Scope notes

- TerminalPad runs the commands **you** configure in **your** terminal as **you**.
  Launching a command is the app's intended function, not a vulnerability.
- The app makes only two anonymous HTTPS requests (logos + update check) and
  sends no personal data — see [PRIVACY.md](PRIVACY.md).
- Builds are ad-hoc signed (no Apple Developer ID). This is intentional for a
  build-from-source tool; the trust anchor is the source you compiled, not a
  notarization ticket.
