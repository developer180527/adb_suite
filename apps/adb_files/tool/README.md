# App icon tooling

## Regenerating icons

```bash
cd apps/adb_files
dart run tool/apply_icon.dart --source Assets/<your-icon>-1024.png \
                              --icon   Assets/<Your-Icon>.icon
```

Add `--dry-run` to see what would change without writing anything.

For iOS 18+ dark and tinted variants, export those appearances from Icon
Composer and pass them too:

```bash
dart run tool/apply_icon.dart --source Assets/<icon>-Default-1024.png \
                              --dark   Assets/<icon>-Dark-1024.png \
                              --tinted Assets/<icon>-Tinted-1024.png
```

They are written as `appearances` entries in `Contents.json` alongside the
legacy per-size images, so iOS 17 and earlier keep working.

**Caveat:** appearance variants need `IPHONEOS_DEPLOYMENT_TARGET >= 18.0`.
At the current 13.0 the entries compile without error but the system never
selects them.

The tool only touches platforms that exist in the app, so adding `android/`,
`web/`, or `windows/` later needs no change to it.

| Platform | Output | Alpha |
| --- | --- | --- |
| macOS | `AppIcon.appiconset` — 16…1024 | kept |
| iOS | `AppIcon.appiconset` — sizes read from `Contents.json` | **full-bleed** |
| Android | `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` | full-bleed |
| Web | `icons/Icon{,-maskable}-{192,512}.png`, `favicon.png` | kept |
| Windows | `runner/resources/app_icon.ico` (7 sizes in one file) | kept |
| Linux | `icons/hicolor/<size>/apps/<app>.png` + `<app>.desktop` | kept |

**Why alpha differs.** iOS and Android icons must be **full-bleed**: the OS
applies its own corner mask, and the App Store rejects an alpha channel.

Icon Composer exports iOS icons already masked to a squircle, with transparent
corners. Flattening those onto white is wrong — iOS masks again with a slightly
different shape, and the white peeks out as a halo around the icon on the Home
Screen. Instead the tool fills the corners with the icon's *own* artwork: a
slightly enlarged copy goes underneath so each corner picks up the gradient
that was already beside it, then the original composites on top unchanged. The
visible design does not move; only the dead corners get filled.

macOS is the opposite — there the rounded corners *are* the artwork, so
transparency has to survive. Windows likewise keeps alpha; Explorer does not
mask.

It is pure Dart (`package:image`), so it needs no ImageMagick or `sips` and
behaves the same in CI as on a laptop.

## Linux

Linux has no in-runner icon slot the way Windows and macOS do. Desktop
environments look icons up in the **hicolor theme** by the `Icon=` name in a
`.desktop` file, so the tool emits both and the packaging step installs them:

```
install -Dm644 linux/icons/hicolor/256x256/apps/adb_files.png \
  /usr/share/icons/hicolor/256x256/apps/adb_files.png
install -Dm644 linux/adb_files.desktop \
  /usr/share/applications/adb_files.desktop
gtk-update-icon-cache /usr/share/icons/hicolor
```

(Use `~/.local/share/...` for a per-user install.) Until that runs, a
`flutter run -d linux` window shows the generic GTK icon — that is how Linux
desktop icons work, not a gap in the tool.

The `.desktop` file is written **once** and then left alone, so hand edits to
categories, keywords, or translations survive later icon runs.

## The macOS `.icon` bundle

**macOS only.** `actool` in Xcode 26.6 crashes on this `.icon` when the target
is iOS (`attempt to insert nil object`), at every deployment target from 13.0
to 26.0, so the iOS project deliberately still uses the PNG asset catalog.
Re-test on a future Xcode; iOS would then get the layered icon for free.


`Assets/Android-Finder-Icon.icon` is an Icon Composer document. On macOS it is
what actually renders the app icon — the generated PNGs are only a fallback —
because it carries the layers, glass material, and dark-appearance
specialisations that a flat PNG cannot.

The Xcode project references it **in place** at `../Assets/...`, so it has a
single source of truth. Edit it in Icon Composer and rebuild; no copying.

`apply_icon.dart` reports whether the project is still wired to it but never
edits `project.pbxproj`. Wiring a file into an Xcode project is a one-time
operation, and rewriting the project on every icon tweak is a good way to
corrupt it. If the tool says it is not wired, either drag the `.icon` into
Xcode (Runner target → General → App Icons) or set:

```
ASSETCATALOG_COMPILER_APPICON_NAME = "<Your-Icon>";
```

and add the bundle to the Resources build phase.

## After running

Rebuild the app. macOS caches icons aggressively — if the Dock still shows the
old one, `killall Dock`.

---

# release.sh

Builds and packages a release for the host platform.

```bash
./tool/release.sh              # build + package for this OS
./tool/release.sh --no-sign    # skip macOS signing
./tool/release.sh --identity "Developer ID Application: …"
```

Output lands in `build/release/`.

## Versioning

Nothing is edited by hand per build:

| Part | Source |
|---|---|
| `0.1.0` | `version:` in `pubspec.yaml` — bump when you mean to |
| build number | `git rev-list --count HEAD`, so it advances every commit |
| commit hash | `git rev-parse --short HEAD`, compiled in via `--dart-define` |
| dirty flag | set when the tree has uncommitted changes |

The first two are passed as `--build-name` / `--build-number`, so they become
`CFBundleShortVersionString` / `CFBundleVersion` on macOS and the equivalent
elsewhere. The app reads them back at runtime with `package_info_plus`, which
means the About box cannot disagree with what the installer put on disk.

The commit and timestamp are compile-time constants rather than a generated
Dart file, so a build never dirties the working tree — otherwise the dirty
flag would always read true.

Settings → About shows all of it, with a Copy button that yields a pasteable
block for bug reports.

## Cross-compilation is not possible

`flutter build linux` on macOS fails with *"build linux" only supported on
Linux hosts*, and the same is true in every other direction. All three
platforms means all three machines — which is what
`.github/workflows/release.yml` does, one runner each. Push a `v*` tag and it
builds the three and attaches them to a GitHub Release.

## macOS signing, honestly

A **free** Apple ID only issues an *Apple Development* certificate. The script
will use it, and the result is a valid signature:

```
codesign --verify --strict   →  valid on disk
spctl -a -vv                 →  rejected
```

That second line is the one that matters. Gatekeeper only accepts a
*Developer ID Application* certificate plus notarization for software
distributed outside the App Store, and neither is available on a free account.
The signed app runs on **this** Mac; on anyone else's it is blocked, and they
need right-click → Open, or:

```bash
xattr -dr com.apple.quarantine /Applications/adb_files.app
```

So the signature is worth having for local builds and tamper-evidence, but it
does **not** make the DMG distributable. That needs the $99/year Apple
Developer Program, after which `--identity "Developer ID Application: …"`
plus `xcrun notarytool submit` produces a DMG that opens with a double-click.

Hardened runtime (`--options runtime`) is enabled, which is a notarization
prerequisite. It also enforces library validation — verified working, since
every bundled framework (libmpv, PDFium, ffmpeg) is signed with the same team
ID during the nested-first signing walk.

Windows is unsigned too: Authenticode certificates are a paid, identity-checked
purchase, so SmartScreen warns on first run.
