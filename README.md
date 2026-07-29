# ServerBox Android

[繁體中文](README_zh.md)

[![Android CI](https://github.com/qcxg/flutter_server_box/actions/workflows/analysis.yml/badge.svg)](https://github.com/qcxg/flutter_server_box/actions/workflows/analysis.yml)
[![Release](https://img.shields.io/github/v/release/qcxg/flutter_server_box)](https://github.com/qcxg/flutter_server_box/releases/latest)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)](https://github.com/qcxg/flutter_server_box/releases/latest)
[![License](https://img.shields.io/github/license/qcxg/flutter_server_box)](LICENSE)

ServerBox Android is a mobile server administration app for monitoring hosts,
opening SSH terminals, managing files, and running common server operations
from one place. This edition focuses exclusively on Android and combines the
proven ServerBox foundation with a redesigned Material 3 Expressive interface,
stronger background-session behavior, and a two-pane file workspace.

> [!IMPORTANT]
> This repository is an independently maintained, unofficial personal fork of
> [lollipopkit/flutter_server_box](https://github.com/lollipopkit/flutter_server_box).
> It is not affiliated with, maintained by, or supported by the original
> ServerBox team. Fork-specific customization was implemented with Codex.

## Highlights

### Server overview

- Monitor CPU, memory, storage, network, load, uptime, processes, systemd,
  containers, and other host information supported by ServerBox.
- Use expressive, responsive server cards with subtle availability states and
  shared online status across the home, SSH, and file screens.
- Work comfortably on phones and tablets with purpose-built navigation and
  adaptive layouts.

### Stable Android SSH workflow

- Keep active SSH sessions alive more reliably while the app is backgrounded
  through an Android foreground service, wake locks, reconnect handling, and
  explicit session cleanup.
- Use a mobile-focused xterm terminal with visible connection state, improved
  Android IME behavior, stabilized delete-key handling, and virtual keys.
- Compose commands locally before sending, then send a complete multiline
  block or execute non-empty lines sequentially.
- Resume long-running work with tmux support when tmux is installed on the
  remote host.

### Two-pane file workspace

- Browse local and remote files side by side in a compact, MT-style layout.
- Keep independent remote sessions for multiple servers and switch between
  them without resetting the local pane.
- Edit paths directly, select multiple files, use contextual menus beside the
  selected item, and transfer files between the current panes.
- Track common file types with dedicated icons and compact size/modification
  metadata.
- Receive native Android completion or failure notifications for transfer
  batches.

### Integrated editor

- Open empty and existing text files in a theme-aware editor.
- Use syntax highlighting for common configuration, markup, data, script, and
  source-code formats.
- Toggle soft wrapping and highlighting, use undo/redo, or hand a file to an
  external Android application.
- Save and leave immediately while remote upload continues in the background;
  temporary copies are cleaned after a successful upload.

### Refined interface

- Material 3 Expressive styling across server cards, selectors, settings,
  snippets, loading states, editor surfaces, and the About page.
- Layered translucent top surfaces and compact glass navigation designed to
  keep content visible without sacrificing touch targets.
- Native Android Toast messages provide one consistent feedback system.

## Download

Install the latest signed APK from
[GitHub Releases](https://github.com/qcxg/flutter_server_box/releases/latest).

| Requirement | Value |
| --- | --- |
| Android | 7.0 or newer (`minSdk 24`) |
| Target | Android 16 / API 36 |
| Published ABI | `arm64-v8a` |
| Package | `com.shiraka.serverbox` |

Release signing certificate SHA-256:

```text
7B:CA:1D:11:65:A9:78:FB:F8:EA:F2:E3:1D:2D:F8:4A:B9:A2:A3:6D:B4:A7:CE:04:DF:33:49:31:36:41:31:D8
```

APK files downloaded from anywhere else should be verified against this
fingerprint. Builds signed by the original project, debug keys, or another
fork cannot be installed as an in-place update over this edition.

## Project status

Only the Android application is maintained and released here. Upstream update
checks have been removed from the app; new builds are distributed exclusively
through this repository. Device-specific battery restrictions can still affect
background networking, so disabling battery optimization may be necessary on
some Android variants.

Issues should be reported to this fork when they concern its APK or customized
behavior. Please do not ask the original ServerBox team to support this edition.

## Build from source

Flutter `3.44.6` is used by CI and the release workflow.

```bash
git clone --recurse-submodules https://github.com/qcxg/flutter_server_box.git
cd flutter_server_box
flutter pub get --enforce-lockfile
flutter analyze lib test
flutter test
flutter build apk --release --split-per-abi \
  --target-platform android-arm64
```

A signed release additionally requires a private Android keystore and
`android/key.properties`. Signing material is never committed. Tagged releases
are built, tested, fingerprint-checked, and published by
[GitHub Actions](.github/workflows/release-android.yml) using encrypted
repository secrets.

## Technical foundation

- Flutter and Dart
- Riverpod for reactive application state
- Hive CE for local persistent data
- `dartssh2` for SSH and remote file operations
- A customized `xterm.dart` terminal
- Android platform channels for foreground-session and native integration

The repository uses Git submodules. Two customized dependencies are maintained
in separate forks:

- [qcxg/fl_lib](https://github.com/qcxg/fl_lib)
- [qcxg/xterm.dart](https://github.com/qcxg/xterm.dart)

Upstream changes are reviewed and merged deliberately because Android
lifecycle, terminal, file-management, and UI code differ substantially in this
edition.

## Credits and license

ServerBox was created by
[lollipopkit and the original contributors](https://github.com/lollipopkit/flutter_server_box).
Their attribution and contribution information remain available in the app.

This fork is distributed under the
[GNU Affero General Public License v3.0](LICENSE).
