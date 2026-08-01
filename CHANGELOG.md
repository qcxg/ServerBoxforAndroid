# Changelog

## v1.0.1501 — 2026-08-02

### Android SSH

- Redesigned the mobile SSH keyboard toolbar as a compact two-row layout.
- Added smooth IME-aware show/hide animation and removed the toolbar when the
  system keyboard is closed.
- Kept the command buffer and directional keys usable on small screens without
  a toolbar shadow.
- Opened the keyboard for the server-card SSH action only; other server actions
  keep their existing focus behavior.
- Closed the terminal keyboard before leaving through the back arrow.
- Removed the Home navigation bar's reserved height while the SSH keyboard is
  open, eliminating the blank band above the IME.

### Release

- Android arm64-v8a release package.
- Package: `com.shiraka.serverbox`.
