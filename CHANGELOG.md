# Changelog

## v1.0.1504 — 2026-10-01

- Redrew the Android launcher icon on the 108dp adaptive-icon canvas using the supplied 24dp design-grid specification.
- Reduced the painted bounds to the specified 42–46dp range, restored centered negative space, and standardized the 1.75/1.65/1.50dp rounded stroke hierarchy.
- Applied Android system palette roles to the launcher artwork: `system_accent1_100` for the background and `system_neutral1_700` / `system_neutral1_500` for the foreground hierarchy.

## v1.0.1503 — 2026-09-29

### Material 3 interface

- Added comfortable outer gutters for multi-column server cards on tablets.
- Balanced the mobile navigation highlight at the server edge.
- Reworked the launcher artwork as a Material 3 server line icon with Android
  dynamic-color and themed-icon support.
- Replaced the remote text-file loading dialog with an in-place glass blur and
  expressive loading animation.

### Batch commands

- Added a batch-command action beside the main server-page actions.
- Commands can target any selected servers without being saved first, while
  existing saved snippets can still be inserted and reused.
- Added live per-server output, reconnect progress, elapsed time, exit codes,
  and clear success or failure states.

### Release

- Android arm64-v8a release package.
- Package: `com.shiraka.serverbox`.

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
