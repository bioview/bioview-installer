#!/usr/bin/env bash
# Build the macOS BioView.app and package it into a .dmg.
#
# Hybrid UHD: build libuhd + Python API from source (PyPI has no macOS wheel).
# PyInstaller bundles libuhd.dylib, the uhd python package, and FPGA images.
#
# Output: dist/<App>-<version>-<arch>.dmg
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(cd "$HERE/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$INSTALLER_DIR/build/macos}"
DIST_DIR="${DIST_DIR:-$INSTALLER_DIR/dist}"

APP_NAME="$(python3 "$HERE/buildcfg.py" get app.name)"
APP_VERSION="$(python3 "$HERE/buildcfg.py" get app.version)"
ARCH="$(uname -m)"

mkdir -p "$DIST_DIR"

select_supported_python() {
    if [ -n "${BIOVIEW_PYTHON:-}" ] && [ -x "$BIOVIEW_PYTHON" ]; then
        echo "$BIOVIEW_PYTHON"
        return
    fi
    local ver prefix py
    for ver in 3.13 3.12; do
        prefix="$(brew --prefix "python@${ver}" 2>/dev/null)" || continue
        py="${prefix}/bin/python${ver}"
        if [ -x "$py" ]; then
            echo "$py"
            return
        fi
    done
    echo "ERROR: need Homebrew python@3.13 or python@3.12 (install with: brew install python@3.13)" >&2
    exit 1
}

preflight() {
  local icon_path="$INSTALLER_DIR/$(python3 "$HERE/buildcfg.py" get assets.icon_icns)"
  if [ ! -f "$icon_path" ]; then
    echo "ERROR: app icon missing: $icon_path" >&2
    exit 1
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew is required for the macOS build" >&2
    exit 1
  fi
}

# --- 1. Native build deps (not cmake/boost — those are pinned/built in-tree) -
preflight
for formula in python@3.13 libusb ninja pkg-config; do
    if ! brew list "$formula" >/dev/null 2>&1; then
        echo "=== Installing $formula via Homebrew ==="
        brew install "$formula"
    fi
done

BREW_PYTHON="$(select_supported_python)"
echo "Python: $BREW_PYTHON ($("$BREW_PYTHON" --version 2>&1))"

PY_OK="$("$BREW_PYTHON" -c 'import sys; print(1 if (3,12) <= sys.version_info < (3,14) else 0)')"
if [ "$PY_OK" != "1" ]; then
    echo "ERROR: $("$BREW_PYTHON" --version 2>&1) is outside the tested range (>=3.12, <3.14)." >&2
    echo "       Set BIOVIEW_PYTHON to a supported interpreter (e.g. python@3.13)." >&2
    exit 1
fi

# --- 2. Environment (build UHD from source for the chosen Python) ---------
WITH_UHD_SOURCE=1 "$HERE/prepare_env.sh" "$BUILD_DIR" "$BREW_PYTHON"
# shellcheck disable=SC1091
source "$BUILD_DIR/venv/bin/activate"

if [ ! -f "$BUILD_DIR/uhd-prefix.path" ]; then
    echo "ERROR: UHD build did not produce $BUILD_DIR/uhd-prefix.path" >&2
    exit 1
fi
UHD_PREFIX="$(cat "$BUILD_DIR/uhd-prefix.path")"
echo "UHD prefix: $UHD_PREFIX"

UHD_PKG_DIR="$(python -c 'import site, pathlib, uhd; print(pathlib.Path(uhd.__file__).parent)')"
export DYLD_LIBRARY_PATH="${UHD_PKG_DIR}:${UHD_PREFIX}/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

# --- 3. PyInstaller -------------------------------------------------------
ICON_ARG=()
ICON_PATH="$INSTALLER_DIR/$(python3 "$HERE/buildcfg.py" get assets.icon_icns)"
[ -f "$ICON_PATH" ] && ICON_ARG=(--icon "$ICON_PATH")

ADD_DATA=()
[ -d "$UHD_PREFIX/share/uhd" ] && ADD_DATA=(--add-data "$UHD_PREFIX/share/uhd:share/uhd")

if ! python -c "import uhd" >/dev/null 2>&1; then
    echo "ERROR: uhd python module not importable after source build" >&2
    exit 1
fi

echo "=== Running PyInstaller ==="
pyinstaller --noconfirm --clean --windowed \
    --name "$APP_NAME" \
    --distpath "$BUILD_DIR/pyinstaller_dist" \
    --workpath "$BUILD_DIR/pyinstaller_work" \
    --specpath "$BUILD_DIR" \
    ${ICON_ARG[@]+"${ICON_ARG[@]}"} \
    --collect-all uhd \
    --collect-all pyqtgraph \
    --collect-all scipy \
    --collect-all h5py \
    --collect-all pygame \
    --collect-submodules bioview_common \
    --collect-submodules bioview_server \
    --collect-submodules bioview_client \
    --collect-data bioview_client \
    ${ADD_DATA[@]+"${ADD_DATA[@]}"} \
    "$HERE/pyinstaller_entry.py"

APP_BUNDLE="$BUILD_DIR/pyinstaller_dist/$APP_NAME.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: expected app bundle not found at $APP_BUNDLE" >&2
    exit 1
fi

# --- 4. Ad-hoc sign (real Developer ID signing happens in CI if configured) ---
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "=== Signing with $CODESIGN_IDENTITY ==="
    codesign --deep --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "=== Ad-hoc signing (unsigned distribution) ==="
    codesign --deep --force --sign - "$APP_BUNDLE" || true
fi

# --- 5. DMG ---------------------------------------------------------------
DMG_PATH="$DIST_DIR/${APP_NAME}-${APP_VERSION}-${ARCH}.dmg"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE"
cp -R "$APP_BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "=== Creating DMG ==="
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE"

echo "=== SUCCESS: $DMG_PATH ==="
