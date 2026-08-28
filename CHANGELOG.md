# Changelog

## v1.0.1502 — 2026-08-28

### Android SSH

- Improved IPv4/IPv6 host validation and normalized bracketed IPv6 addresses.
- Added IPv6 support for alternate SSH destinations and SSH Config imports.
- Added timeout and clearer errors for jump-server forwarding.
- Fixed `ProxyJump` aliases so imported jump servers resolve correctly.
- Added a yellow jump-server indicator beside the server-card disconnect action.

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
