# ServerBox Android

[繁體中文](README_zh.md)

An Android-focused personal fork of
[lollipopkit/flutter_server_box](https://github.com/lollipopkit/flutter_server_box),
built for stable SSH sessions, practical two-pane file management, and a
modern Material 3 Expressive interface.

> [!IMPORTANT]
> This is an independent, unofficial fork maintained for personal use. It is
> not an official ServerBox release and does not follow the upstream app
> release channel automatically.

## Download

Signed Android builds are published on the
[GitHub Releases](https://github.com/qcxg/flutter_server_box/releases) page.

- Android 7.0 or newer (`minSdk 24`)
- Android 16 / API 36 target
- Current release artifact: `arm64-v8a`
- Package name: `tech.lolli.toolbox`

Release signing certificate SHA-256:

```text
7B:CA:1D:11:65:A9:78:FB:F8:EA:F2:E3:1D:2D:F8:4A:B9:A2:A3:6D:B4:A7:CE:04:DF:33:49:31:36:41:31:D8
```

Verify the fingerprint before installing an APK obtained from anywhere other
than this repository.

## What this fork changes

- More reliable background SSH sessions on Android through a foreground
  service, wake locks, reconnect handling, and explicit clean shutdown.
- Improved Android terminal input, including IME learning support, stabilized
  delete-key behavior, connection status indicators, and a local command
  composer with whole-buffer or line-by-line sending.
- MT-style two-pane file workspace with local and remote panes visible at the
  same time, editable paths, multi-select operations, contextual menus, direct
  upload/download, retained per-server SFTP sessions, and transfer completion
  system toasts.
- A more capable text editor with additional syntax formats, theme-aware
  highlighting, external-app opening, background upload after save, and
  temporary-file cleanup.
- Material 3 Expressive server cards, selectors, settings, snippets, loading
  indicators, responsive tablet navigation, and compact glass navigation.
- Shared server availability state across the home, SSH, and SFTP screens.
- Upstream app update checks removed; releases for this fork are managed only
  through this repository.

## SSH and SFTP

SFTP is the SSH File Transfer Protocol. It runs inside the same encrypted SSH
connection and normally uses the same host, port, account, key, and host-key
verification. Directory listings already include common attributes such as
size and modification time, so showing those values does not require a
separate request for every remote file.

## Build

The maintained target is Android only.

```bash
git clone --recurse-submodules https://github.com/qcxg/flutter_server_box.git
cd flutter_server_box
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi \
  --target-platform android-arm64
```

A release build requires `android/key.properties` and a private keystore.
Private signing material is intentionally not included in Git. Tagged releases
are built by [GitHub Actions](.github/workflows/release-android.yml) with
encrypted repository secrets.

## Fork and upstream policy

This repository preserves the upstream Git history and GitHub fork
relationship. Upstream changes can be fetched from
`lollipopkit/flutter_server_box`, but they are merged deliberately in a
separate branch because this fork substantially changes Android lifecycle,
terminal, file-manager, and UI code.

Two modified submodules are also maintained as forks:

- [qcxg/fl_lib](https://github.com/qcxg/fl_lib)
- [qcxg/xterm.dart](https://github.com/qcxg/xterm.dart)

Unmodified submodules continue to use their original upstream repositories.

## Credits and license

ServerBox was created by
[lollipopkit and contributors](https://github.com/lollipopkit/flutter_server_box).
This fork keeps the original copyright and attribution.

Licensed under the [GNU Affero General Public License v3.0](LICENSE).
