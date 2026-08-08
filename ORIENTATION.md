# Orientation

Everything about this project in one file: what it is, where it lives, how the
pieces fit, and the traps that cost real debugging time.

> Scope note: this describes **two sibling repos**. Each has its own `README.md`
> with per-repo detail. This file is the map across both.

---

## The 60-second version

You are building **Finder for Android devices** — desktop apps that browse and
manage an Android phone over ADB, plus the reusable layers underneath.

The distinguishing decision: **there is no `Process.run('adb', …)` anywhere.**
`adb_core` speaks the ADB wire protocol over a socket directly, so it returns
`mode`/`size`/`mtime` as integers and real exit codes, instead of scraping
stdout that changes between Android versions.

One app ships today: **`adb_files`**, a desktop file manager with tabs, drag and
drop, trash, and in-place preview of media and documents. Two more feature
packages (`feature_logcat`, `feature_stats`) are built and tested but not yet
composed into their own app.

| | |
|---|---|
| **Languages** | Dart / Flutter, plus Swift for macOS native bits |
| **Targets** | macOS (primary), Windows, Linux, iOS/iPad (limited) |
| **Code** | ~11,700 lines of library code, ~2,600 of tests |
| **Tests** | **243 passing** — 57 + 16 + 65 + 40 + 32 + 33 |
| **License** | MIT, holder "Venu Gopal" |

---

## Where everything lives

```
~/Developer/
├── adb_dart/          ← PUBLIC repo: the protocol layer
│   ├── packages/adb_core/     pure Dart ADB client, no Flutter
│   └── packages/adb_ui/       shared Flutter widgets + formatters
│
└── adb_suite/         ← PRODUCT repo: features and shipping apps
    ├── packages/feature_files/    file management (service + UI)
    ├── packages/feature_logcat/   log streaming (service + UI)
    ├── packages/feature_stats/    CPU/memory/battery (service + UI)
    └── apps/adb_files/            the shipping desktop app
```

Both must be checked out **as siblings** — see [Local setup](#local-setup).

> `~/Developer/adb` does **not** exist, despite some tooling defaulting its
> working directory there. Work happens in the two directories above.

### Repo identity

| | `adb_dart` | `adb_suite` |
|---|---|---|
| GitHub | `developer180527/adb_dart` | `developer180527/adb_suite` |
| Visibility | public | private |
| Contains | protocol + shared UI | features + apps |
| Versioned by | git tags (`v0.3.2`) | app version in pubspec |

**Why two repos.** The protocol layer is generally useful and publishable; the
product is not. Splitting them keeps the public surface small and forces the
dependency direction to stay honest.

---

## How the layers depend on each other

```mermaid
graph TD
    subgraph suite["adb_suite (private)"]
        APP["apps/adb_files<br/>4,306 lines"]
        FF["feature_files<br/>3,060 lines"]
        FL["feature_logcat<br/>983 lines"]
        FS["feature_stats<br/>820 lines"]
    end
    subgraph dart["adb_dart (public)"]
        CORE["adb_core<br/>2,321 lines · pure Dart"]
        UI["adb_ui<br/>225 lines"]
    end

    APP --> FF
    APP --> FS
    FF --> CORE
    FF --> UI
    FL --> CORE
    FS --> CORE
    UI --> CORE
```

**Dependencies point one way only.** Product depends on protocol, never the
reverse. `adb_core` has no Flutter dependency at all, which is what lets it be
tested with plain `dart test` and reused outside Flutter.

A feature package owns **both** its service and its widgets, and knows nothing
about which app hosts it. Adding or splitting an app is a pubspec change, not a
refactor. `feature_logcat` currently has no host app — that is the intended
state, not an oversight.

---

## Layer by layer

### `adb_core` — the protocol client

`~/Developer/adb_dart/packages/adb_core/lib/src/`

Two transports implement one `AdbTransport` interface:

| Transport | Path | How it works | Status |
|---|---|---|---|
| **Host** | `transport/host/` | Talks to the local `adb` server on TCP 5037 | Works, primary |
| **Direct** | `transport/direct/` | Speaks the device protocol itself, incl. the RSA handshake | Works, spike-quality |

*Host* is what the apps use. It requires the `adb` binary. *Direct* exists so
iOS/iPad could eventually connect over Wi-Fi without a binary, since iOS cannot
spawn processes.

```
adb_session.dart              top-level entry point
models/                       AdbDevice, AdbFileEntry, exceptions, parsers
services/
  shell_service.dart          shell v2 framing (1 id byte + 4-byte LE length)
  sync_service.dart           file push/pull: LIST/LIS2/DENT/DNT2/STAT/RECV/SEND
  remote_file.dart            range reads — the trick behind preview-without-download
transport/
  host/host_protocol.dart     4-hex length framing, OKAY/FAIL
  host/adb_binary.dart        locates the adb executable
  direct/adb_auth_key.dart    RSA-2048 PKCS#1 v1.5 signing, Android RSAPublicKey struct
  direct/adb_message.dart     24-byte header, magic = command ^ 0xFFFFFFFF
util/byte_reader.dart         resumable TCP framing
util/posix_shell.dart         shell quoting
```

**Start here:** `adb_session.dart`, then `services/sync_service.dart`.

`example/` holds runnable scripts against a real device — `smoke.dart`,
`integration.dart`, `remote_probe.dart`, `direct_spike.dart`. These need
hardware and are excluded from CI.

### `adb_ui` — shared Flutter bits

`~/Developer/adb_dart/packages/adb_ui/lib/src/` — only two files:
`device_picker.dart` and `formatters.dart` (`formatBytes`, `formatPercent`).
Deliberately thin; most UI belongs to a feature package.

### `feature_files` — the biggest feature

`~/Developer/adb_suite/packages/feature_files/lib/src/`

```
file_service.dart             listing, delete, rename, mkdir, read/write text
file_browser_controller.dart  navigation, selection, sort state
directory_walk.dart           recursive traversal
transfer_manager.dart         queued push/pull with progress
trash_service.dart            recoverable delete (moves, not unlinks)
remote_file_server.dart       local HTTP bridge — lets players stream device files
preview/                      preview_kind (type sniffing), controller, view
widgets/file_browser.dart     the main list/grid
models/                       DirectoryListing, FileAction, FileSort
remote_path.dart              POSIX path maths for device paths
```

**The interesting design:** `remote_file_server.dart` + `RemoteFile` range reads
mean a 2 GB video previews instantly. A local HTTP server translates byte-range
requests into targeted device reads, so the media player streams rather than
waiting for a full download.

### `feature_logcat` and `feature_stats`

Same shape: parsers, a service, models, one widget. `feature_logcat`'s
`log_ring_buffer.dart` keeps memory flat under sustained log volume.
`feature_stats` parses `dumpsys`/`/proc` output into typed CPU, memory, and
battery models. Both fully tested; `feature_logcat` has no host app yet.

### `adb_files` — the shipping app

`~/Developer/adb_suite/apps/adb_files/`

```
lib/
  main.dart                   entry; initialises media_kit + pdfrx, loads settings
  build_info.dart             which build is running (see Versioning)
  theme.dart                  neutral chrome, green accent from the icon
  screens/
    connect_screen.dart       device selection
    browser_screen.dart       the main window
    settings_view.dart        appearance, preview cache, About — opens in a tab
  state/
    connection_controller.dart
    tabs_controller.dart      tabs incl. the settings tab
    app_settings.dart         persisted prefs (JSON, no plugin)
    app_options.dart          command-line args — used by tab tear-off
  widgets/
    sidebar.dart, tab_bar.dart, drag_drop.dart, transfer_panel.dart
    media_viewer.dart         real audio/video via media_kit/libmpv
    document_viewer.dart      PDF via pdfrx/PDFium
    native_menu.dart          real NSMenu on macOS via method channel

macos/Runner/MainFlutterWindow.swift    window geometry, argv, NSMenu channel
tool/apply_icon.dart          regenerates icons for every platform
tool/release.sh               builds + packages a release
tool/README.md                icon and release documentation
Assets/                       icon sources (.icon bundle + 1024 PNG)
```

**Start here:** `main.dart` → `screens/browser_screen.dart`.

Desktop-class behaviours worth knowing: Cmd-T tabs, Cmd-N windows, Chrome-style
**drag a tab out to make a new window** (implemented by relaunching with
geometry args — see `app_options.dart` and the Swift file), native save panels,
and drag-and-drop to Finder using lazy virtual files so the download happens on
drop.

---

## Local setup

```bash
git clone https://github.com/developer180527/adb_dart.git  ~/Developer/adb_dart
git clone https://github.com/developer180527/adb_suite.git ~/Developer/adb_suite
```

`adb_suite/pubspec_overrides.yaml` (**gitignored**, already present on this
machine) redirects `adb_core`/`adb_ui` to the sibling checkout so edits are live:

```yaml
dependency_overrides:
  adb_core:
    path: ../adb_dart/packages/adb_core
  adb_ui:
    path: ../adb_dart/packages/adb_ui
```

The committed pubspecs pin a **git tag** instead, so CI and fresh clones are
reproducible. **This split is the single biggest source of "works locally, fails
in CI"** — see the gotchas below.

```bash
cd ~/Developer/adb_suite/apps/adb_files
flutter pub get
flutter run -d macos          # needs `adb` on PATH and a device with USB debugging
```

Run everything:

```bash
cd ~/Developer/adb_dart/packages/adb_core && dart test        # 57
cd ~/Developer/adb_dart/packages/adb_ui   && flutter test     # 16
cd ~/Developer/adb_suite/packages/feature_files  && flutter test   # 65
cd ~/Developer/adb_suite/packages/feature_logcat && flutter test   # 40
cd ~/Developer/adb_suite/packages/feature_stats  && flutter test   # 32
cd ~/Developer/adb_suite/apps/adb_files          && flutter test   # 33
```

---

## Versioning and releases

Nothing is hand-edited per build:

| Part | Source |
|---|---|
| `0.1.0` | `version:` in `apps/adb_files/pubspec.yaml` |
| build number | `git rev-list --count HEAD` — advances every commit |
| commit hash | `--dart-define=GIT_COMMIT`, compiled in |
| dirty flag | set when the tree has uncommitted changes |

Version and build number go through `--build-name`/`--build-number`, becoming
the real `CFBundleShortVersionString`/`CFBundleVersion`, then are read back at
runtime with `package_info_plus`. The About box therefore cannot disagree with
what the installer put on disk. Commit and timestamp are compile-time constants
rather than a generated file — generating one would dirty the tree and make the
dirty flag permanently true.

**Settings → About** shows all of it with a Copy button for bug reports.

```bash
cd ~/Developer/adb_suite/apps/adb_files
./tool/release.sh              # host platform only
./tool/release.sh --no-sign
```

**Flutter desktop cannot cross-compile.** `flutter build linux` on macOS fails
outright. All three platforms means all three machines, which is what
`.github/workflows/release.yml` does — one runner each, `fail-fast: false`.
Push a `v*` tag to build all three and attach them to a GitHub Release.

### Platform support

| Platform | Build | Signed | Notes |
|---|---|---|---|
| macOS | ✅ verified, DMG | Apple Development only | **Gatekeeper rejects it** — see below |
| Windows | via CI only | ❌ unsigned | Packaging never executed yet |
| Linux | via CI only | n/a | tar.gz + `install.sh` to `~/.local` |
| iOS/iPad | compiles | dev cert | Has never connected to a device |

**macOS signing, honestly.** A free Apple ID issues only an *Apple Development*
certificate. `codesign --verify --strict` passes; `spctl -a` says **rejected**.
Gatekeeper accepts only *Developer ID Application* + notarization for outside
the App Store, and a free account can get neither. The DMG runs on the build
machine and is blocked elsewhere, needing right-click → Open or:

```bash
xattr -dr com.apple.quarantine /Applications/adb_files.app
```

Hardened runtime is on (a notarization prerequisite) and verified working —
every bundled framework is signed with the same team ID during the
nested-first signing walk.

The macOS app **disables the App Sandbox** — it must exec `adb` and open a
socket to the local daemon, neither of which the sandbox permits. That rules
out Mac App Store distribution. Notarized direct distribution is unaffected.

---

## Gotchas that cost real time

Institutional knowledge. Each of these was a live bug.

### Cross-repo and CI

- **The gitignored override masks CI failures.** Local builds resolve
  `adb_core` from `../adb_dart`; CI resolves it from the pinned git tag. Code
  can compile locally against an *uncommitted* `adb_core` change and fail CI.
  Simulate CI before pushing: move `pubspec_overrides.yaml` aside, `flutter pub
  get`, `flutter analyze`, then restore it.
- **Bumping a package version can break its siblings.** `adb_ui` pins
  `adb_core: ^X`. Raising `adb_core`'s version past that range fails version
  solving in both repos. Bump the constraint in the same commit.
- **CI needs `fetch-depth: 0`.** The build number is a commit count; the
  default shallow clone makes every build `1`.

### Tests

- **`testWidgets` fake-async never completes real file I/O.** A write started
  inside a widget test completes on a microtask FakeAsync intercepts; once the
  body ends nothing pumps that zone, so awaiting it **hangs forever** (observed:
  a 9m33s stall). Assert disk persistence in a plain `test()`, not a widget
  test.
- **Windows cannot delete a directory holding an open file.** POSIX can. A
  `tearDown` that removes a temp dir while an unawaited write is in flight
  passes on macOS/Linux and fails only on Windows CI. Make the delete
  best-effort.
- **Never let tests touch real user state.** An early settings test wrote to the
  actual config and changed the developer's theme. `AppSettings.load({File?
  file})` takes an injectable path for exactly this reason — always pass a temp
  file.
- **`flutter create` regenerates `test/widget_test.dart` and
  `analysis_options.yaml`** when enabling a platform, breaking analyze. Delete
  them afterwards.

### Protocol

- **`utf8.encode`, never `ascii.encode`, for paths.** Length prefixes count
  bytes, and filenames are not ASCII. A decode-only test will not catch this.
- **`DNT2` entries are 72 bytes**, with namelen at offset 68. Getting this wrong
  hangs against any modern device.
- **`#` starts a shell comment.** A `###DELIM###` marker silently emptied every
  section of a stats command. Quoted `===DELIM===` now, with regression tests.
- **`.` and `..` filtering is load-bearing**, not defensive — without it,
  recursive walks never terminate.
- **`LIS2` reports symlinks as mode 0**, so they were being skipped invisibly.
  They are now recorded in `unsupported`.
- **Cancel the reader before closing the stream.** A paused `StreamQueue` makes
  `await close()` deadlock.

### Platform

- **First `PlatformMenu` is absorbed as the macOS app menu** — a literal "File"
  first entry vanishes.
- **macOS restores window frames after `awakeFromNib`**, overriding geometry
  args; needs `isRestorable = false`.
- **`open -n <path> --args` silently drops the args** — use `open -a`. Flutter
  macOS also needs `dartEntrypointArguments` for argv to arrive.
- **`TextTheme.apply(fontSizeFactor:)` asserts non-null `fontSize`**, which
  Material 2021 typography violates — a full-screen red error, not a fallback.
  Set sizes explicitly.
- **iOS re-masks app icons**, so flattening transparent corners to white makes a
  white halo peek out. Needs full-bleed artwork.
- **`[[ cond ]] && cmd` as the last statement in a bash function or loop aborts
  under `set -e`.** Use an explicit `if`.

---

## Current state

**Working and verified:** the whole `adb_files` app against a Galaxy A71
(Android 13) — browsing, transfers both directions, multi-megabyte files, UTF-8
paths, trash, preview of media and PDFs, tabs, tab tear-off, native context
menus, theming, settings.

**Known gaps:**

- **iPad has never connected to a device.** Blocked by AP isolation on the
  router, not by code. The direct transport exists for this but is unproven
  end to end.
- **Windows and Linux have never been built.** The `release.sh` branches for
  them are syntax-checked only; `cygpath`/`Compress-Archive` and the Linux apt
  list are unexercised.
- **`feature_logcat` has no host app.** An "android debugger" app composing
  logcat + stats + shell is the obvious next one.
- **Live device tests need hardware** and are excluded from CI by design.
- Licensing for `adb_core` is still MIT; Apache-2.0 was recommended for the
  public protocol layer (patent grant) but not adopted.
