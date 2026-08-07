#!/usr/bin/env bash
#
# Builds a release of adb_files for the host platform and packages it.
#
# Flutter desktop builds are host-only — there is no cross-compilation — so
# this script always targets the machine it runs on. Producing all three
# platforms means running it on all three, which is what
# .github/workflows/release.yml does.
#
# The version is not maintained by hand. `pubspec.yaml` owns the semantic
# version; the build number is the git commit count, so it advances on its own
# with every commit, and the commit hash is compiled in so any build can be
# traced back to a tree.
#
#   ./tool/release.sh                 # build + package for this OS
#   ./tool/release.sh --no-sign       # skip macOS code signing
#   ./tool/release.sh --identity "…"  # use a specific signing identity
#
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$PWD"
OUT_DIR="$APP_DIR/build/release"

SIGN=true
IDENTITY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sign)  SIGN=false; shift ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --output)   OUT_DIR="$2"; shift 2 ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- metadata --

# Only the line that starts with `version:` — comments above it must not match.
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//' | cut -d+ -f1)

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMIT=$(git rev-parse --short HEAD)
  # Commit count is monotonic on a linear history and needs no state file,
  # no CI counter, and no commit of its own to increment.
  BUILD_NUMBER=$(git rev-list --count HEAD)
  if git diff --quiet HEAD -- . 2>/dev/null; then DIRTY=false; else DIRTY=true; fi
else
  COMMIT=""; BUILD_NUMBER=1; DIRTY=true
fi
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "==> adb_files $VERSION ($BUILD_NUMBER) ${COMMIT:-no-git}$([[ $DIRTY == true ]] && echo ' [dirty]')"
[[ $DIRTY == true ]] && echo "    warning: working tree has uncommitted changes"

DEFINES=(
  --dart-define=GIT_COMMIT="$COMMIT"
  --dart-define=GIT_DIRTY="$DIRTY"
  --dart-define=BUILD_TIME="$BUILD_TIME"
)
COMMON=(--release --build-name="$VERSION" --build-number="$BUILD_NUMBER" "${DEFINES[@]}")

mkdir -p "$OUT_DIR"

# ------------------------------------------------------------------- macOS --

release_macos() {
  flutter build macos "${COMMON[@]}"
  local app="build/macos/Build/Products/Release/adb_files.app"
  [[ -d $app ]] || { echo "build produced no .app" >&2; exit 1; }

  if [[ $SIGN == true ]]; then
    if [[ -z $IDENTITY ]]; then
      # Prefer a Developer ID (distributable) over Apple Development (local).
      IDENTITY=$(security find-identity -v -p codesigning \
        | grep -m1 'Developer ID Application' | sed 's/.*"\(.*\)"/\1/' || true)
      [[ -z $IDENTITY ]] && IDENTITY=$(security find-identity -v -p codesigning \
        | grep -m1 'Apple Development' | sed 's/.*"\(.*\)"/\1/' || true)
    fi
    if [[ -z $IDENTITY ]]; then
      echo "    no signing identity found; falling back to ad-hoc"
      IDENTITY="-"
    fi
    echo "==> signing as: $IDENTITY"

    # Nested code must be signed before the bundle that contains it, so the
    # outer signature covers final inner signatures. --deep is deprecated and
    # skips entitlements on nested code, hence the explicit walk.
    while IFS= read -r -d '' item; do
      codesign --force --options runtime --timestamp=none \
        --sign "$IDENTITY" "$item"
    done < <(find "$app/Contents/Frameworks" -maxdepth 1 \
      \( -name '*.framework' -o -name '*.dylib' \) -print0 2>/dev/null || true)

    codesign --force --options runtime --timestamp=none \
      --entitlements macos/Runner/Release.entitlements \
      --sign "$IDENTITY" "$app"
    codesign --verify --strict --verbose=2 "$app"
  fi

  # Stage so the DMG contains only the app plus the /Applications shortcut.
  local stage; stage=$(mktemp -d)
  cp -R "$app" "$stage/"
  local dmg="$OUT_DIR/adb_files-$VERSION+$BUILD_NUMBER-macos.dmg"
  rm -f "$dmg"

  # create-dmg gives a laid-out window, but it drives Finder via AppleScript
  # and so fails on a headless CI runner. hdiutil always works.
  if command -v create-dmg >/dev/null 2>&1; then
    create-dmg --volname "adb_files $VERSION" \
      --window-size 540 380 --icon-size 96 \
      --icon adb_files.app 140 180 --app-drop-link 400 180 \
      --no-internet-enable "$dmg" "$stage" >/dev/null 2>&1 || true
  fi
  if [[ ! -f $dmg ]]; then
    echo "    create-dmg unavailable or failed; using hdiutil"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "adb_files $VERSION" -srcfolder "$stage" \
      -ov -format UDZO "$dmg" >/dev/null
  fi
  rm -rf "$stage"

  # Sign the DMG too, so the container is not the weak link.
  if [[ $SIGN == true ]]; then
    codesign --force --sign "$IDENTITY" "$dmg"
  fi
  echo "==> $dmg"
}

# ------------------------------------------------------------------- Linux --

release_linux() {
  flutter build linux "${COMMON[@]}"
  local bundle; bundle=$(echo build/linux/*/release/bundle)
  [[ -d $bundle ]] || { echo "build produced no bundle" >&2; exit 1; }

  local stage; stage=$(mktemp -d)/adb_files
  mkdir -p "$stage"
  cp -R "$bundle/." "$stage/"

  # A .desktop entry and an icon, so `install.sh` produces a real menu entry
  # rather than a loose binary in a folder.
  cat > "$stage/adb_files.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ADB Files
Comment=A desktop file manager for Android devices
Exec=adb_files
Icon=adb_files
Terminal=false
Categories=Utility;FileTools;FileManager;
DESKTOP

  cat > "$stage/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Installs to ~/.local, which needs no root.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
prefix="${1:-$HOME/.local}"
mkdir -p "$prefix/lib/adb_files" "$prefix/bin" "$prefix/share/applications"
cp -R "$here/." "$prefix/lib/adb_files/"
ln -sf "$prefix/lib/adb_files/adb_files" "$prefix/bin/adb_files"
desktop="$prefix/share/applications/adb_files.desktop"
sed "s|^Exec=.*|Exec=$prefix/bin/adb_files|" "$here/adb_files.desktop" > "$desktop"
for size in 16 32 64 128 256 512; do
  src="$here/data/flutter_assets/assets/icons/icon_${size}.png"
  dir="$prefix/share/icons/hicolor/${size}x${size}/apps"
  # An explicit if, not `[[ ]] && cp`: as the last statement in the loop body
  # a failed test would abort the whole install under `set -e`.
  if [[ -f $src ]]; then
    mkdir -p "$dir"
    cp "$src" "$dir/adb_files.png"
  fi
done
command -v update-desktop-database >/dev/null && \
  update-desktop-database "$prefix/share/applications" 2>/dev/null || true
echo "Installed. Ensure $prefix/bin is on PATH."
INSTALL
  chmod +x "$stage/install.sh" "$stage/adb_files"

  local tarball="$OUT_DIR/adb_files-$VERSION+$BUILD_NUMBER-linux-x64.tar.gz"
  tar -czf "$tarball" -C "$(dirname "$stage")" adb_files
  rm -rf "$(dirname "$stage")"
  echo "==> $tarball"
}

# ----------------------------------------------------------------- Windows --

release_windows() {
  flutter build windows "${COMMON[@]}"
  local bundle; bundle=$(echo build/windows/*/runner/Release)
  [[ -d $bundle ]] || { echo "build produced no Release dir" >&2; exit 1; }

  local zip="$OUT_DIR/adb_files-$VERSION+$BUILD_NUMBER-windows-x64.zip"
  rm -f "$zip"
  # No code signing: an Authenticode certificate is a paid, identity-verified
  # purchase. SmartScreen will warn on first run.
  powershell -NoProfile -Command \
    "Compress-Archive -Path '$(cygpath -w "$bundle" 2>/dev/null || echo "$bundle")\\*' \
     -DestinationPath '$(cygpath -w "$zip" 2>/dev/null || echo "$zip")' -Force"
  echo "==> $zip"
}

case "$(uname -s)" in
  Darwin)             release_macos ;;
  Linux)              release_linux ;;
  MINGW*|MSYS*|CYGWIN*) release_windows ;;
  *) echo "unsupported host: $(uname -s)" >&2; exit 1 ;;
esac
