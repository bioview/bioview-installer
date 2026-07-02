#!/usr/bin/env bash
# Build UHD (libuhd + Python API) from source on macOS.
#
# PyPI ships uhd wheels for Windows only; Homebrew's python bindings target whatever
# python@3.x UHD currently depends on (often 3.14), which is outside BioView's
# tested range. Building from source against python@3.13/3.12 is the reliable path.
#
# Usage: build_uhd_macos.sh <python_bin> <build_dir>
# Writes <build_dir>/uhd-prefix.path with the install prefix.
set -euo pipefail

PYTHON_BIN="${1:?python interpreter required}"
BUILD_DIR="${2:?build dir required}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UHD_GIT="$("$PYTHON_BIN" "$HERE/buildcfg.py" get uhd.git)"
UHD_REF="$("$PYTHON_BIN" "$HERE/buildcfg.py" get uhd.ref)"

UHD_SRC="$BUILD_DIR/uhd-src"
UHD_PREFIX="$BUILD_DIR/uhd-prefix"
BOOST_PREFIX="$BUILD_DIR/boost-prefix"
rm -rf "$UHD_SRC" "$UHD_PREFIX"
mkdir -p "$UHD_SRC" "$UHD_PREFIX"

NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# UHD 4.6 expects classic Boost component packages (e.g. boost_system). Homebrew
# ships Boost 1.90 where system is header-only and no boost_systemConfig.cmake exists.
# Build Boost 1.83 from the official release tarball (the git meta-repo needs
# submodules; a shallow clone is missing tools/build and bootstrap fails).
BOOST_VERSION="1.83.0"
BOOST_TARBALL="$BUILD_DIR/boost_1_83_0.tar.bz2"
BOOST_SRC="$BUILD_DIR/boost_1_83_0"

ensure_boost() {
    if [ -f "$BOOST_PREFIX/lib/cmake/Boost-1.83.0/BoostConfig.cmake" ]; then
        echo "=== Using cached Boost 1.83 at $BOOST_PREFIX ==="
        return
    fi
    echo "=== Building Boost $BOOST_VERSION ==="
    if [ ! -f "$BOOST_TARBALL" ]; then
        curl -fsSL "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_1_83_0.tar.bz2" \
            -o "$BOOST_TARBALL"
    fi
    if [ ! -d "$BOOST_SRC" ]; then
        tar -xjf "$BOOST_TARBALL" -C "$BUILD_DIR"
    fi
    (
        cd "$BOOST_SRC"
        ./bootstrap.sh --prefix="$BOOST_PREFIX" \
            --with-libraries=program_options,system,filesystem,thread,date_time,chrono,atomic,regex,serialization,test
        ./b2 -j "$NPROC" install
    )
}

ensure_boost

echo "=== Cloning UHD $UHD_REF ==="
git clone --depth 1 --branch "$UHD_REF" "$UHD_GIT" "$UHD_SRC"

LIBUSB_PREFIX="$(brew --prefix libusb)"
CMAKE_PREFIX_PATH="$BOOST_PREFIX:$LIBUSB_PREFIX"

echo "=== Configuring UHD (Python API) ==="
cmake -S "$UHD_SRC/host" -B "$UHD_SRC/host/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$UHD_PREFIX" \
    -DENABLE_PYTHON_API=ON \
    -DENABLE_TESTS=OFF \
    -DENABLE_MANUAL=OFF \
    -DENABLE_DOXYGEN=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_UTILS=OFF \
    -DPYTHON_EXECUTABLE="$PYTHON_BIN" \
    -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
    -DBOOST_ROOT="$BOOST_PREFIX" \
    -DBOOST_NO_SYSTEM_PATHS=ON

echo "=== Building UHD (-j $NPROC) ==="
cmake --build "$UHD_SRC/host/build" -j "$NPROC"
cmake --install "$UHD_SRC/host/build"

echo "=== Installing UHD Python bindings into venv ==="
VENV_SITE="$("$PYTHON_BIN" -c 'import site; print(site.getsitepackages()[0])')"
PYTAG="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
INSTALLED=0
for candidate in \
    "$UHD_PREFIX/lib/python$PYTAG/site-packages/uhd" \
    "$UHD_PREFIX/lib/python$PYTAG/dist-packages/uhd"; do
    if [ -d "$candidate" ]; then
        cp -R "$candidate" "$VENV_SITE/"
        INSTALLED=1
        break
    fi
done
if [ "$INSTALLED" = "0" ]; then
    FOUND="$(find "$UHD_PREFIX" -type d -name uhd -path '*/site-packages/*' 2>/dev/null | head -1 || true)"
    if [ -n "$FOUND" ]; then
        cp -R "$FOUND" "$VENV_SITE/"
        INSTALLED=1
    fi
fi
if [ "$INSTALLED" = "0" ]; then
    echo "ERROR: could not locate UHD python package under $UHD_PREFIX" >&2
    exit 1
fi

if ! "$PYTHON_BIN" -c "import uhd" >/dev/null 2>&1; then
    echo "ERROR: UHD python module not importable after install" >&2
    exit 1
fi

echo "=== Downloading UHD FPGA/firmware images ==="
"$UHD_PREFIX/bin/uhd_images_downloader" || echo "WARNING: uhd_images_downloader failed"

printf '%s\n' "$UHD_PREFIX" > "$BUILD_DIR/uhd-prefix.path"
echo "=== UHD ready at $UHD_PREFIX ==="
