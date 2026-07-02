#!/usr/bin/env bash
# Acquire the three BioView packages and install them (plus deps + PyInstaller)
# into a fresh virtualenv. Used by the macOS PyInstaller build. The Flatpak build
# does NOT use this -- it builds its own environment inside the sandbox.
#
# Usage: prepare_env.sh <build_dir> [python_bin]
# Env:
#   WITH_UHD_SOURCE=1    build UHD from source (macOS; pip cmake + Boost tarball)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(cd "$HERE/.." && pwd)"

BUILD_DIR="${1:?build dir required}"
PYTHON_BIN="${2:-python3}"

mkdir -p "$BUILD_DIR"
SRC_DIR="$BUILD_DIR/src"
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

echo "=== Acquiring BioView packages ==="
"$PYTHON_BIN" "$HERE/buildcfg.py" packages | while IFS='|' read -r NAME GIT REF LOCAL; do
    DEST="$SRC_DIR/$NAME"
    LOCAL_ABS="$INSTALLER_DIR/$LOCAL"
    if [ -n "$LOCAL" ] && [ -d "$LOCAL_ABS" ]; then
        echo ">> Using local checkout for $NAME ($LOCAL_ABS)"
        rsync -a \
            --exclude '.git' --exclude '.venv' --exclude 'venv' \
            --exclude 'dist' --exclude 'build' --exclude '__pycache__' \
            "$LOCAL_ABS/" "$DEST/"
    else
        echo ">> Cloning $NAME from $GIT @ $REF"
        git clone --depth 1 ${REF:+--branch "$REF"} "$GIT" "$DEST"
    fi
done

echo "=== Creating virtualenv ==="
VENV="$BUILD_DIR/venv"
rm -rf "$VENV"
if [ "${VENV_SYSTEM_SITE:-0}" = "1" ]; then
    "$PYTHON_BIN" -m venv --system-site-packages "$VENV"
else
    "$PYTHON_BIN" -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"

python -m pip install --upgrade pip wheel pyinstaller

echo "=== Installing BioView packages (common -> server -> client) ==="
pip install "$SRC_DIR/bioview-common"
pip install "$SRC_DIR/bioview-server"
pip install "$SRC_DIR/bioview-client"

if [ "${WITH_UHD_SOURCE:-0}" = "1" ]; then
    echo "=== Preparing UHD build deps (pinned cmake + python modules) ==="
    pip install "cmake>=3.22,<3.31" mako numpy
    "$HERE/build_uhd_macos.sh" "$VENV/bin/python" "$BUILD_DIR"
elif [ "${WITH_UHD_PIP:-0}" = "1" ]; then
    UHD_VERSION="$("$PYTHON_BIN" "$HERE/buildcfg.py" get uhd.version)"
    echo "=== Installing uhd==$UHD_VERSION from PyPI ==="
    if [ "$(uname -s)" = "Darwin" ]; then
        UHD_PREFIX="$(brew --prefix uhd 2>/dev/null || true)"
        if [ -n "$UHD_PREFIX" ]; then
            export CMAKE_PREFIX_PATH="${UHD_PREFIX}:${CMAKE_PREFIX_PATH:-}"
            export UHD_ROOT="$UHD_PREFIX"
        fi
        BOOST_PREFIX="$(brew --prefix boost 2>/dev/null || true)"
        if [ -n "$BOOST_PREFIX" ]; then
            export CMAKE_PREFIX_PATH="${BOOST_PREFIX}:${CMAKE_PREFIX_PATH:-}"
        fi
    fi
    pip install "uhd==$UHD_VERSION" || echo "WARNING: uhd pip install failed (USRP support will be unavailable)"
fi

echo "=== Environment ready: $VENV ==="
