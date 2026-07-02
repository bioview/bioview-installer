#!/usr/bin/env bash
# Build the macOS BioView.app and package it into a .dmg.
#
# Hybrid UHD: Homebrew provides libuhd + the `uhd` python bindings + FPGA images.
# We build the venv against Homebrew's python (with --system-site-packages) so the
# bindings are importable, then let PyInstaller collect them and we explicitly add
# libuhd.dylib and the UHD image files into the bundle.
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

# --- 1. UHD via Homebrew --------------------------------------------------
if ! brew list uhd >/dev/null 2>&1; then
    echo "=== Installing UHD via Homebrew ==="
    brew install uhd
fi
UHD_PREFIX="$(brew --prefix uhd)"

# Pick the Python that UHD's Homebrew bottle was built against. The `uhd` python
# bindings are installed into a specific `python@3.x` (a formula dependency), so
# the build venv MUST use that same interpreter or `import uhd` fails at runtime.
# This is the crux of the previous macOS failure (components disagreeing on the
# Python version); deriving it from UHD keeps us on a tested uhd+python combo.
UHD_PY_FORMULA="$(brew deps uhd 2>/dev/null | grep -E '^python@3\.[0-9]+$' | head -1 || true)"
if [ -n "$UHD_PY_FORMULA" ] && [ -x "$(brew --prefix "$UHD_PY_FORMULA")/bin/python3" ]; then
    BREW_PYTHON="$(brew --prefix "$UHD_PY_FORMULA")/bin/python3"
elif brew --prefix python@3.12 >/dev/null 2>&1 && [ -x "$(brew --prefix python@3.12)/bin/python3.12" ]; then
    BREW_PYTHON="$(brew --prefix python@3.12)/bin/python3.12"
else
    BREW_PYTHON="$(brew --prefix)/bin/python3"
fi
echo "UHD prefix: $UHD_PREFIX"
echo "Python: $BREW_PYTHON ($("$BREW_PYTHON" --version 2>&1))"

# The BioView packages require >=3.12, <3.14. If UHD forces a newer Python, fail
# early with an actionable message rather than deep in the pip install.
PY_OK="$("$BREW_PYTHON" -c 'import sys; print(1 if (3,12) <= sys.version_info < (3,14) else 0)')"
if [ "$PY_OK" != "1" ]; then
    echo "ERROR: $("$BREW_PYTHON" --version 2>&1) is outside the tested range (>=3.12, <3.14)." >&2
    echo "       UHD's Homebrew python dependency ($UHD_PY_FORMULA) is unsupported; pin a" >&2
    echo "       UHD version built against Python 3.12/3.13." >&2
    exit 1
fi

# --- 2. Environment (built against Homebrew python) -----------------------
VENV_SYSTEM_SITE=1 "$HERE/prepare_env.sh" "$BUILD_DIR" "$BREW_PYTHON"
# shellcheck disable=SC1091
source "$BUILD_DIR/venv/bin/activate"

# --- 3. PyInstaller -------------------------------------------------------
ICON_ARG=()
ICON_PATH="$INSTALLER_DIR/$(python3 "$HERE/buildcfg.py" get assets.icon_icns)"
[ -f "$ICON_PATH" ] && ICON_ARG=(--icon "$ICON_PATH")

ADD_BINARY=()
[ -f "$UHD_PREFIX/lib/libuhd.dylib" ] && ADD_BINARY=(--add-binary "$UHD_PREFIX/lib/libuhd.dylib:.")

ADD_DATA=()
[ -d "$UHD_PREFIX/share/uhd" ] && ADD_DATA=(--add-data "$UHD_PREFIX/share/uhd:share/uhd")

echo "=== Running PyInstaller ==="
pyinstaller --noconfirm --clean --windowed \
    --name "$APP_NAME" \
    --distpath "$BUILD_DIR/pyinstaller_dist" \
    --workpath "$BUILD_DIR/pyinstaller_work" \
    --specpath "$BUILD_DIR" \
    "${ICON_ARG[@]}" \
    --collect-all uhd \
    --collect-all pyqtgraph \
    --collect-submodules bioview_common \
    --collect-submodules bioview_server \
    --collect-submodules bioview_client \
    --collect-data bioview_client \
    "${ADD_BINARY[@]}" \
    "${ADD_DATA[@]}" \
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
