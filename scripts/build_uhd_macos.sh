#!/usr/bin/env bash
# Build UHD (libuhd + Python API) from source on macOS.
#
# PyPI ships uhd wheels for Windows only. We compile UHD 4.10 against Homebrew
# Boost/libusb and python@3.13, then stage native dylibs beside the Python module
# for PyInstaller.
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

NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

resolve_cmake() {
    local cmake_bin
    cmake_bin="$(brew --prefix cmake 2>/dev/null)/bin/cmake"
    if [ ! -x "$cmake_bin" ]; then
        cmake_bin="$(command -v cmake)"
    fi
    if [ ! -x "$cmake_bin" ]; then
        echo "ERROR: cmake not found (brew install cmake)" >&2
        exit 1
    fi
    echo "$cmake_bin"
}

uhd_package_dir() {
    "$PYTHON_BIN" -c 'import site, pathlib; print(pathlib.Path(site.getsitepackages()[0]) / "uhd")'
}

uhd_library_path() {
    local paths=() pkg_dir boost_prefix libusb_prefix
    boost_prefix="$(brew --prefix boost 2>/dev/null || true)"
    if pkg_dir="$(uhd_package_dir 2>/dev/null)" && [ -d "$pkg_dir" ]; then
        paths+=("$pkg_dir")
    fi
    paths+=("$UHD_PREFIX/lib")
    [ -n "$boost_prefix" ] && [ -d "$boost_prefix/lib" ] && paths+=("$boost_prefix/lib")
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

verify_uhd_import_bundled() {
    # Bundled libs must load via @loader_path without DYLD_LIBRARY_PATH (PyInstaller / CI).
    env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
        "$PYTHON_BIN" -c "import uhd; print(uhd.__file__)"
}

stage_runtime_libs() {
    local dest="$1"
    local boost_prefix libusb_prefix dest_abs uhd_lib_abs
    boost_prefix="$(brew --prefix boost)"
    mkdir -p "$dest"
    dest_abs="$(cd "$dest" && pwd -P)"
    uhd_lib_abs="$(cd "$UHD_PREFIX/lib" && pwd -P)"
    if [ "$dest_abs" != "$uhd_lib_abs" ]; then
        # libpyuhd links to @loader_path/libuhd.X.Y.Z.dylib; copy versioned files, not just the symlink.
        shopt -s nullglob
        local lib
        for lib in "$UHD_PREFIX/lib"/libuhd*.dylib; do
            cp -fL "$lib" "$dest/"
        done
        shopt -u nullglob
    fi
    cp -f "$boost_prefix/lib"/libboost_*.dylib "$dest/"
    libusb_prefix="$(brew --prefix libusb)"
    if compgen -G "$libusb_prefix/lib/libusb-1.0"*.dylib >/dev/null; then
        cp -f "$libusb_prefix/lib"/libusb-1.0*.dylib "$dest/"
    fi
}

should_rewrite_dep() {
    case "$1" in
        libboost_*|libuhd*.dylib|libusb*.dylib) return 0 ;;
        *) return 1 ;;
    esac
}

fix_loader_paths() {
    local binary="$1" dep base
    while IFS= read -r dep; do
        dep="${dep//$'\t'/}"
        dep="${dep%% (*}"
        case "$dep" in
            ""|*":"*) continue ;;
            @loader_path/*|@executable_path/*|/usr/lib/*|/System/*|/Library/*) continue ;;
        esac
        base="$(basename "$dep")"
        should_rewrite_dep "$base" || continue
        install_name_tool -change "$dep" "@loader_path/$base" "$binary" 2>/dev/null || true
    done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')
}

python_dylib_path() {
    "$PYTHON_BIN" -c '
import pathlib, sys
prefix = pathlib.Path(sys.base_prefix)
for path in (
    prefix / "Frameworks/Python.framework/Versions" / f"{sys.version_info.major}.{sys.version_info.minor}" / "Python",
    prefix / "Python",
    prefix / "lib" / f"libpython{sys.version_info.major}.{sys.version_info.minor}.dylib",
):
    if path.exists():
        print(path.resolve())
        break
'
}

repair_pyuhd_python_link() {
    local pyuhd python_lib dep
    pyuhd="$(find "$(uhd_package_dir)" -maxdepth 1 -name 'libpyuhd*.so' | head -1)"
    [ -n "$pyuhd" ] || return 0
    python_lib="$(python_dylib_path)"
    [ -n "$python_lib" ] || return 0
    while IFS= read -r dep; do
        dep="${dep//$'\t'/}"
        dep="${dep%% (*}"
        case "$dep" in
            *Python*|*libpython*) ;;
            *) continue ;;
        esac
        install_name_tool -change "$dep" "$python_lib" "$pyuhd" 2>/dev/null || true
    done < <(otool -L "$pyuhd" | tail -n +2 | awk '{print $1}')
}

bundle_uhd_native_libs() {
    local pkg_dir
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
    repair_pyuhd_python_link
    shopt -u nullglob
}

install_uhd_python_bindings() {
    # UHD 4.10 installs the venv module via `pip install .` during cmake --install.
    # Fall back to an explicit pip install from the build tree if needed.
    local py_build="$UHD_SRC/host/build/python"
    local venv_site
    venv_site="$("$PYTHON_BIN" -c 'import site; print(site.getsitepackages()[0])')"

    if DYLD_LIBRARY_PATH="$(uhd_library_path)" "$PYTHON_BIN" -c "import uhd" >/dev/null 2>&1; then
        echo "=== UHD python module already importable after cmake install ==="
        return
    fi

    if [ ! -f "$py_build/setup.py" ]; then
        echo "ERROR: missing $py_build/setup.py after UHD build" >&2
        exit 1
    fi

    echo "=== Installing UHD python bindings via pip (fallback) ==="
    DYLD_LIBRARY_PATH="$(uhd_library_path)" \
        "$PYTHON_BIN" -m pip install --no-build-isolation --force-reinstall "$py_build"

    if [ ! -d "$venv_site/uhd" ]; then
        echo "ERROR: uhd package not present under $venv_site" >&2
        exit 1
    fi
    if ! find "$venv_site/uhd" -name '*.so' -print -quit | grep -q .; then
        echo "ERROR: no pyuhd extension module under $venv_site/uhd" >&2
        exit 1
    fi
}

CMAKE_BIN="$(resolve_cmake)"
BOOST_PREFIX="$(brew --prefix boost)"
LIBUSB_PREFIX="$(brew --prefix libusb)"

rm -rf "$UHD_SRC" "$UHD_PREFIX"
mkdir -p "$UHD_SRC" "$UHD_PREFIX"

echo "=== Cloning UHD $UHD_REF ==="
git clone --depth 1 --branch "$UHD_REF" "$UHD_GIT" "$UHD_SRC"

echo "=== Configuring UHD (Python API) with $("$CMAKE_BIN" --version | head -1) ==="
"$CMAKE_BIN" -S "$UHD_SRC/host" -B "$UHD_SRC/host/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$UHD_PREFIX" \
    -DENABLE_PYTHON_API=ON \
    -DENABLE_TESTS=OFF \
    -DENABLE_MANUAL=OFF \
    -DENABLE_DOXYGEN=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_UTILS=ON \
    -DPYTHON_EXECUTABLE="$PYTHON_BIN" \
    -DCMAKE_PREFIX_PATH="$BOOST_PREFIX:$LIBUSB_PREFIX" \
    -DBOOST_ROOT="$BOOST_PREFIX" \
    -DBOOST_NO_SYSTEM_PATHS=ON \
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
    otool -L "$(find "$(uhd_package_dir)" -name 'libpyuhd*.so' | head -1)" 2>/dev/null || true
    DYLD_LIBRARY_PATH="$(uhd_library_path)" "$PYTHON_BIN" -c "import uhd" 2>&1 || true
    exit 1
fi
if ! verify_uhd_import_bundled; then
    echo "ERROR: uhd import failed without DYLD_LIBRARY_PATH (bundled dylibs incomplete)" >&2
    pkg_dir="$(uhd_package_dir)"
    ls -la "$pkg_dir"/libuhd*.dylib 2>/dev/null || echo "(no libuhd*.dylib in $pkg_dir)"
    otool -L "$(find "$pkg_dir" -name 'libpyuhd*.so' | head -1)" 2>/dev/null || true
    exit 1
fi

echo "=== Downloading UHD FPGA/firmware images ==="
DYLD_LIBRARY_PATH="$(uhd_library_path)" "$UHD_PREFIX/bin/uhd_images_downloader" \
    || echo "WARNING: uhd_images_downloader failed (USRP may need manual image download)"

printf '%s\n' "$UHD_PREFIX" > "$BUILD_DIR/uhd-prefix.path"
echo "=== UHD ready at $UHD_PREFIX ==="
