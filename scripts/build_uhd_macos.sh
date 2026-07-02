#!/usr/bin/env bash
# Build UHD (libuhd + Python API) from source on macOS.
#
# PyPI ships uhd wheels for Windows only; Homebrew's python bindings target whatever
# python@3.x UHD currently depends on (often 3.14), which is outside BioView's
# tested range. Building from source against python@3.13/3.12 is the reliable path.
#
# Usage: build_uhd_macos.sh <venv_python> <build_dir>
# Writes <build_dir>/uhd-prefix.path with the install prefix.
set -euo pipefail

PYTHON_BIN="${1:?venv python interpreter required}"
BUILD_DIR="${2:?build dir required}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UHD_GIT="$("$PYTHON_BIN" "$HERE/buildcfg.py" get uhd.git)"
UHD_REF="$("$PYTHON_BIN" "$HERE/buildcfg.py" get uhd.ref)"

UHD_SRC="$BUILD_DIR/uhd-src"
UHD_PREFIX="$BUILD_DIR/uhd-prefix"
BOOST_PREFIX="$BUILD_DIR/boost-prefix"
BOOST_VERSION="1.83.0"
BOOST_TARBALL="$BUILD_DIR/boost_1_83_0.tar.bz2"
BOOST_SRC="$BUILD_DIR/boost_1_83_0"

NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Homebrew CMake 3.31+ breaks UHD 4.6 (FindBoost spelling, old cmake_minimum_required in
# CMakeRC.cmake, removed <3.5 compat). Use a pinned CMake from the build venv instead.
resolve_cmake() {
    local cmake_bin
    cmake_bin="$(dirname "$PYTHON_BIN")/cmake"
    if [ ! -x "$cmake_bin" ]; then
        echo "ERROR: pinned cmake not found at $cmake_bin" >&2
        echo "       prepare_env.sh must run: pip install 'cmake>=3.22,<3.31'" >&2
        exit 1
    fi
    local ver
    ver="$("$cmake_bin" --version | awk '/version/ {print $3}')"
    case "$ver" in
        3.3[1-9]*|3.[4-9]*|4.*)
            echo "ERROR: cmake $ver is too new for UHD 4.6 (need >=3.22, <3.31)" >&2
            exit 1
            ;;
    esac
    echo "$cmake_bin"
}

# UHD 4.6 expects classic Boost component packages (e.g. boost_system). Homebrew
# ships Boost 1.90 where system is header-only. Use the official 1.83 tarball (the git
# meta-repo needs submodules; a shallow clone is missing tools/build).
ensure_boost() {
    if [ -f "$BOOST_PREFIX/lib/cmake/Boost-1.83.0/BoostConfig.cmake" ]; then
        echo "=== Using cached Boost $BOOST_VERSION at $BOOST_PREFIX ==="
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
    if [ ! -f "$BOOST_PREFIX/lib/cmake/Boost-1.83.0/BoostConfig.cmake" ]; then
        echo "ERROR: Boost install did not produce BoostConfig.cmake" >&2
        exit 1
    fi
}

uhd_package_dir() {
    "$PYTHON_BIN" -c 'import site, pathlib; print(pathlib.Path(site.getsitepackages()[0]) / "uhd")'
}

uhd_library_path() {
    local paths=()
    local pkg_dir libusb_prefix
    if pkg_dir="$(uhd_package_dir 2>/dev/null)" && [ -d "$pkg_dir" ]; then
        paths+=("$pkg_dir")
    fi
    paths+=("$UHD_PREFIX/lib" "$BOOST_PREFIX/lib")
    libusb_prefix="$(brew --prefix libusb 2>/dev/null || true)"
    [ -n "$libusb_prefix" ] && [ -d "$libusb_prefix/lib" ] && paths+=("$libusb_prefix/lib")
    if [ -n "${DYLD_LIBRARY_PATH:-}" ]; then
        paths+=("$DYLD_LIBRARY_PATH")
    fi
    local IFS=:
    printf '%s' "${paths[*]}"
}

verify_uhd_import() {
    DYLD_LIBRARY_PATH="$(uhd_library_path)" "$PYTHON_BIN" -c "import uhd; print(uhd.__file__)"
}

stage_runtime_libs() {
    local dest="$1"
    local libusb_prefix dest_abs uhd_lib_abs
    mkdir -p "$dest"
    dest_abs="$(cd "$dest" && pwd -P)"
    uhd_lib_abs="$(cd "$UHD_PREFIX/lib" && pwd -P)"
    if [ "$dest_abs" != "$uhd_lib_abs" ] && [ -f "$UHD_PREFIX/lib/libuhd.dylib" ]; then
        cp -f "$UHD_PREFIX/lib/libuhd.dylib" "$dest/"
    fi
    cp -f "$BOOST_PREFIX/lib"/libboost_*.dylib "$dest/"
    libusb_prefix="$(brew --prefix libusb)"
    if compgen -G "$libusb_prefix/lib/libusb-1.0"*.dylib >/dev/null; then
        cp -f "$libusb_prefix/lib"/libusb-1.0*.dylib "$dest/"
    fi
}

fix_loader_paths() {
    local binary="$1"
    local dep base
    while IFS= read -r dep; do
        dep="${dep//$'\t'/}"
        dep="${dep%% (*}"
        case "$dep" in
            ""|*":"*) continue ;;
            @loader_path/*|@executable_path/*|/usr/lib/*|/System/*|/Library/*) continue ;;
        esac
        base="$(basename "$dep")"
        install_name_tool -change "$dep" "@loader_path/$base" "$binary" 2>/dev/null || true
    done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')
}

bundle_uhd_native_libs() {
    # libpyuhd links libuhd + Boost via @rpath; copy deps beside the module and
    # rewrite load paths so import/PyInstaller work without a global Boost install.
    local pkg_dir binary
    pkg_dir="$(uhd_package_dir)"
    echo "=== Bundling native libs into $pkg_dir ==="
    stage_runtime_libs "$pkg_dir"
    stage_runtime_libs "$UHD_PREFIX/lib"

    shopt -s nullglob
    for _ in 1 2; do
        for binary in "$pkg_dir"/*.dylib "$pkg_dir"/*.so; do
            fix_loader_paths "$binary"
        done
        for binary in "$UHD_PREFIX/lib"/*.dylib; do
            fix_loader_paths "$binary"
        done
    done
    shopt -u nullglob
}

install_uhd_python_bindings() {
    # UHD detects the venv and runs `setup.py install` from cmake --install, but that
    # often fails silently on Python 3.13 (deprecated install path). The compiled module
    # always lands in the CMake build tree; install it with pip instead.
    local py_build="$UHD_SRC/host/build/python"
    local setup_py="$py_build/setup.py"
    local venv_site
    venv_site="$("$PYTHON_BIN" -c 'import site; print(site.getsitepackages()[0])')"

    if [ ! -f "$setup_py" ]; then
        echo "ERROR: missing $setup_py after UHD build" >&2
        find "$UHD_SRC/host/build" -name setup.py 2>/dev/null || true
        exit 1
    fi
    if [ ! -d "$py_build/uhd" ]; then
        echo "ERROR: missing built python package at $py_build/uhd" >&2
        ls -la "$py_build" 2>/dev/null || true
        exit 1
    fi

    echo "=== Installing UHD python bindings via pip ==="
    if ! DYLD_LIBRARY_PATH="$(uhd_library_path)" \
        "$PYTHON_BIN" -m pip install --no-build-isolation --force-reinstall "$py_build"; then
        echo "=== pip install failed; copying build tree into venv ==="
        rm -rf "$venv_site/uhd"
        mkdir -p "$venv_site/uhd"
        rsync -a "$py_build/uhd/" "$venv_site/uhd/"
    fi

    if [ ! -d "$venv_site/uhd" ]; then
        echo "ERROR: uhd package not present under $venv_site" >&2
        exit 1
    fi
    if ! find "$venv_site/uhd" -name '*.so' -print -quit | grep -q .; then
        echo "ERROR: no pyuhd extension module under $venv_site/uhd" >&2
        ls -la "$venv_site/uhd" 2>/dev/null || true
        exit 1
    fi
}

CMAKE_BIN="$(resolve_cmake)"

rm -rf "$UHD_SRC" "$UHD_PREFIX"
mkdir -p "$UHD_SRC" "$UHD_PREFIX"

ensure_boost

echo "=== Cloning UHD $UHD_REF ==="
git clone --depth 1 --branch "$UHD_REF" "$UHD_GIT" "$UHD_SRC"

LIBUSB_PREFIX="$(brew --prefix libusb)"
CMAKE_PREFIX_PATH="$BOOST_PREFIX:$LIBUSB_PREFIX"

echo "=== Configuring UHD (Python API) with $("$CMAKE_BIN" --version | head -1) ==="
"$CMAKE_BIN" -S "$UHD_SRC/host" -B "$UHD_SRC/host/build" -G Ninja \
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
    -DBOOST_NO_SYSTEM_PATHS=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -Wno-dev

echo "=== Building UHD (-j $NPROC) ==="
"$CMAKE_BIN" --build "$UHD_SRC/host/build" -j "$NPROC"
"$CMAKE_BIN" --install "$UHD_SRC/host/build"

if [ ! -f "$UHD_PREFIX/lib/libuhd.dylib" ]; then
    echo "ERROR: libuhd.dylib not found under $UHD_PREFIX/lib" >&2
    ls -la "$UHD_PREFIX/lib" 2>/dev/null || true
    exit 1
fi

echo "=== Verifying UHD Python bindings ==="
install_uhd_python_bindings
bundle_uhd_native_libs
if ! verify_uhd_import; then
    echo "ERROR: uhd import failed after install" >&2
    "$PYTHON_BIN" -c "import sys, site; print('prefix', sys.prefix); print('site', site.getsitepackages())"
    find "$("$PYTHON_BIN" -c 'import site; print(site.getsitepackages()[0])')/uhd" -maxdepth 2 -type f 2>/dev/null || true
    DYLD_LIBRARY_PATH="$(uhd_library_path)" "$PYTHON_BIN" -c "import uhd" 2>&1 || true
    exit 1
fi

echo "=== Downloading UHD FPGA/firmware images ==="
DYLD_LIBRARY_PATH="$(uhd_library_path)" "$UHD_PREFIX/bin/uhd_images_downloader" \
    || echo "WARNING: uhd_images_downloader failed (USRP may need manual image download)"

printf '%s\n' "$UHD_PREFIX" > "$BUILD_DIR/uhd-prefix.path"
echo "=== UHD ready at $UHD_PREFIX ==="
