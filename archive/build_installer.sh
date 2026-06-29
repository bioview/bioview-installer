#!/bin/bash
set -e

# --- 0. CONFIG LOADING ---
CONFIG_FILE="build_config.json"
if [ ! -f "$CONFIG_FILE" ]; then echo "Error: $CONFIG_FILE not found."; exit 1; fi

get_json() { python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['$1'])"; }
get_asset_conf() { python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['assets_config']['$1'])"; }

APP_NAME=$(get_json "app_name")
APP_VERSION=$(get_json "app_version")
GUI_FOLDER=$(get_json "gui_folder_name")
ASSET_REPO=$(get_asset_conf "repo_name")
ASSET_PATH_REL=$(get_asset_conf "path_inside_repo")

# Parse Repos
REPO_LIST=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE'))['repos']; print(' '.join([f'{k}::{v}' for k,v in d.items()]))")

# Parse Entry Points into a string "Label::Path Label2::Path2"
ENTRY_POINTS_LIST=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE'))['gui_entry_points']; print(' '.join([f'{k}::{v}' for k,v in d.items()]))")

BUILD_DIR="build_temp"
DIST_DIR="dist"
OS="$(uname -s)"
ASSETS_FULL_PATH="$BUILD_DIR/$ASSET_REPO/$ASSET_PATH_REL"

echo "=== Building $APP_NAME v$APP_VERSION for $OS ==="

# --- 1. PREREQUISITES ---
check_command() { command -v "$1" >/dev/null 2>&1; }

if [ "$OS" = "Linux" ]; then
    if ! check_command python3 || ! check_command git || ! check_command flatpak-builder; then
        echo "Missing dependencies. Installing..."
        if [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip git flatpak flatpak-builder elfutils
        elif [ -f /etc/redhat-release ]; then
            sudo dnf install -y python3 python3-pip git flatpak flatpak-builder elfutils
        fi
        flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
elif [ "$OS" = "Darwin" ]; then
    if ! check_command python3; then echo "Please install Python3"; exit 1; fi
fi

# --- 2. SETUP & CLONE ---
echo "--- Setting up Environment ---"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" && mkdir -p "$DIST_DIR"

for REPO in $REPO_LIST; do
    FOLDER="${REPO%%::*}"
    URL="${REPO##*::}"
    echo "Cloning $FOLDER..."
    git clone "$URL" "$BUILD_DIR/$FOLDER"
done

echo "Creating Virtualenv..."
python3 -m venv "$BUILD_DIR/venv"
source "$BUILD_DIR/venv/bin/activate"
pip install --upgrade pip wheel pyinstaller

# --- 3. INSTALL PACKAGES ---
echo "--- Installing Python Packages ---"
for REPO in $REPO_LIST; do
    FOLDER="${REPO%%::*}"
    if [ -f "$BUILD_DIR/$FOLDER/requirements.txt" ]; then
        pip install -r "$BUILD_DIR/$FOLDER/requirements.txt"
    fi
    pip install "$BUILD_DIR/$FOLDER"
done

# --- 4. BUILD LOOP ---
echo "--- Building Executables ---"
cd "$BUILD_DIR/$GUI_FOLDER"

# Resolve Icon
PYINSTALLER_ICON_FLAG=""
if [ "$OS" = "Darwin" ] && [ -f "../../$ASSET_REPO/$ASSET_PATH_REL/icon.icns" ]; then
    PYINSTALLER_ICON_FLAG="--icon=../../$ASSET_REPO/$ASSET_PATH_REL/icon.icns"
fi

# Initialize array for Linux install commands
LINUX_INSTALL_CMDS=""
LINUX_SOURCES=""

# Loop through every entry point
for ENTRY in $ENTRY_POINTS_LIST; do
    LABEL="${ENTRY%%::*}"
    FILE_PATH="${ENTRY##*::}"
    
    echo ">> Building $LABEL from $FILE_PATH..."
    
    # Resolve Path
    if [ ! -f "$FILE_PATH" ]; then
        echo "Warning: $FILE_PATH not found. Skipping."
        continue
    fi

    # Run PyInstaller
    # We use --distpath to separate outputs slightly or just dump them all in dist
    pyinstaller --noconsole --windowed --onefile --clean --name "$LABEL" $PYINSTALLER_ICON_FLAG "$FILE_PATH"

    # Move Output
    SRC_DIST="dist" # PyInstaller defaults to local dist folder
    
    if [ "$OS" = "Darwin" ]; then
        # Check for .app
        if [ -d "$SRC_DIST/$LABEL.app" ]; then
            # Move to global dist
            rm -rf "../../$DIST_DIR/$LABEL.app"
            mv "$SRC_DIST/$LABEL.app" "../../$DIST_DIR/"
        else
            mv "$SRC_DIST/$LABEL" "../../$DIST_DIR/"
        fi
    else
        # Linux Binary
        mv "$SRC_DIST/$LABEL" "../../$DIST_DIR/"
        
        # Prepare Flatpak command string for this binary
        LINUX_INSTALL_CMDS="$LINUX_INSTALL_CMDS \"install -D $LABEL /app/bin/$LABEL\","
        # We need to tell flatpak builder where to find this source file (which is now in global dist)
        # However, flatpak-builder resolves paths relative to where it runs.
        # We will handle sources dynamically in Step 5.
    fi
done

cd ../..

# --- 5. PACKAGING ---
if [ "$OS" = "Darwin" ]; then
    echo "--- Creating DMG ---"
    DMG_NAME="$DIST_DIR/${APP_NAME}_${APP_VERSION}.dmg"
    rm -f "$DMG_NAME"
    DMG_SRC="$DIST_DIR/dmg_source"
    rm -rf "$DMG_SRC" && mkdir -p "$DMG_SRC"
    
    # Copy ALL .app bundles from dist to DMG source
    cp -R "$DIST_DIR"/*.app "$DMG_SRC/"
    
    ln -s /Applications "$DMG_SRC/Applications"
    
    hdiutil create -volname "${APP_NAME}" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG_NAME"
    rm -rf "$DMG_SRC"
    
elif [ "$OS" = "Linux" ]; then
    echo "--- Creating Flatpak ---"
    flatpak install --user -y org.freedesktop.Sdk//23.08 org.freedesktop.Platform//23.08
    APP_ID="org.local.$(echo $APP_NAME | tr '[:upper:]' '[:lower:]')"
    MANIFEST="$DIST_DIR/manifest.json"
    REPO_DIR="$DIST_DIR/repo"
    
    # Construct Source JSON dynamically for all generated binaries in DIST_DIR
    # We find all executable files in DIST_DIR that don't have an extension (standard linux binary)
    SOURCES_JSON=""
    for EXE in "$DIST_DIR"/*; do
        if [ -f "$EXE" ] && [ -x "$EXE" ] && [[ "$EXE" != *.flatpak ]] && [[ "$EXE" != *.json ]] && [[ "$EXE" != *.iss ]]; then
            FILENAME=$(basename "$EXE")
            SOURCES_JSON="$SOURCES_JSON {\"type\": \"file\", \"path\": \"$(readlink -f $EXE)\"},"
        fi
    done
    # Remove trailing comma
    SOURCES_JSON="${SOURCES_JSON%,}"
    
    # Remove trailing comma from commands
    LINUX_INSTALL_CMDS="${LINUX_INSTALL_CMDS%,}"

    # Pick the FIRST label as the primary command (arbitrary, but required by Manifest)
    PRIMARY_CMD=$(echo $ENTRY_POINTS_LIST | head -n1 | cut -d: -f1)

    cat > "$MANIFEST" <<EOF
{
  "app-id": "$APP_ID",
  "runtime": "org.freedesktop.Platform",
  "runtime-version": "23.08",
  "sdk": "org.freedesktop.Sdk",
  "command": "$PRIMARY_CMD",
  "finish-args": ["--share=ipc", "--socket=x11", "--socket=wayland", "--device=all", "--filesystem=host"],
  "modules": [{
      "name": "$APP_NAME",
      "buildsystem": "simple",
      "build-commands": [
          $LINUX_INSTALL_CMDS
      ],
      "sources": [
          $SOURCES_JSON
      ]
  }]
}
EOF
    flatpak-builder --force-clean --user --repo="$REPO_DIR" build_dir "$MANIFEST"
    flatpak build-bundle "$REPO_DIR" "$DIST_DIR/${APP_NAME}_${APP_VERSION}.flatpak" "$APP_ID"
fi

echo "=== SUCCESS: ${APP_NAME} v${APP_VERSION} Built ==="
