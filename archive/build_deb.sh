#!/bin/bash
set -e  # Exit on error

## Install build dependencies
sudo apt install -y python3 python3-venv python3-pip git dpkg-deb

## Load constants from json (using Python)
CONFIG_FILE="constants.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found in current directory."
    exit 1
fi

# Helper to read JSON values safely
get_json() {
    jq -c ".\"$1\"" "$CONFIG_FILE"
}

# Load Metadata
APPNAME=$(get_json "name")
VERSION=$(get_json "version")
DESCRIPTION=$(get_json "description")
PKGNAME=$(get_json "pkgname")
LICENSE=$(get_json "license")

# Load list of repositories to clone 
SUBMODULES=$(get_json "submodules")
BASEDIR=$(get_json "basedir")

# Get GUI applications to install, as well as required assets 
APPLICATIONS=$(get_json "applications")
ASSETDIR=$(get_json "assetdir")

# Finally, get package maintainance information
MAINTAINERS=$(get_json "maintainers")
CHANGELOG=$(get_json "changelog")

## Build instructions 

# Ensure paths are relative to parent(__FILE__)
INSTALLER_DIR="$(dirname "$(readlink -f "$0")")"
DIST_DIR="dist"
BUILD_DIR="build/deb"

echo "=== Building $PKGNAME-v$APP_VERSION.deb ==="

echo "Setting up build directores..."
rm -rf "$INSTALLER_DIR/$BUILD_ROOT"
if [ ! -d "$INSTALLER_DIR/$DIST_DIR" ]; then
  mkdir -p "$INSTALLER_DIR/$DIST_DIR"
fi

# Define system paths inside the package

# Since I am placing the binaries in a subfolder of /usr/bin,
# the post-install script will need to modify $PATH
echo "Defining target paths..."
LIB_DIR="/usr/lib/$PKGNAME"    # Where source code lives
BIN_DIR="/usr/bin/$PKGNAME"    # Where the executables live
APPS_DIR="/usr/share/applications" # Desktop shortcut

# Create structure in build root
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$LIB_DIR"
mkdir -p "$BUILD_DIR/$BIN_DIR"
mkdir -p "$BUILD_DIR/$APPS_DIR"

# Git clone submodule repositories
echo "Acquiring BioView submodules"
if [ "$SUBMODULES" != "null" ]; then 
  # Iterate over repository names (keys) and remote URLs (values) 
  echo "$SUBMODULES" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do 
    git clone "$value" "$BUILD_DIR/$LIB_DIR/$key"   
  done 
else 
  echo "No submodules found." 
  exit 1 
fi

# We exclude build artifacts, git folders, and virtual envs to keep the package clean
rsync -av --progress . "$BUILD_DIR/$LIB_DIR" \
    --exclude "$BUILD_DIR" \
    --exclude "$DIST_DIR" \
    --exclude ".git" \
    --exclude ".gitignore" \
    --exclude "venv" \
    --exclude "__pycache__" \
    --exclude "*.pyc" \
    --exclude "*.spec" \
    --exclude "*.sh" \
    --exclude "constants.json"

# Create launchers to abstract away using Python 
echo "Creating launchers"

if [ "$APPLICATIONS" != "null" ]; then 
  # Iterate over repository names (keys) and remote URLs (values) 
  echo "$APPLICATIONS" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do 
    LAUNCHER="$BUILD_DIR/$BIN_DIR/$PKGNAME/$value"
    SCRIPT_PATH="$BUILD_DIR/$LIB_DIR/$BASEDIR/$value"

    cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Wrapper to launch $APPNAME using system Python
# We add the installation directory to PYTHONPATH so imports work
export PYTHONPATH="$LIB_DIR:\$PYTHONPATH"
exec python3 "$LIB_DIR/$BASEDIR/$value" "\$@"
EOF
    
    # Make launchers executable
    chmod 755 "$LAUNCHER"

    # Move .desktop files to $APPS_DIR
    mv $INSTALLER_DIR/linux/$(value).desktop $BUILD_DIR/APPS_DIR/$(value).desktop 
  done 
else 
  echo "No scripts found to create launchers for." 
  exit 1 
fi

echo "Launchers created successfully!"

# Generate control file
echo "Generating control file"
cat > "$BUILD_ROOT/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $APP_VERSION
Section: utils
Priority: optional
Architecture: all
Maintainer: $MAINTAINER
Description: $SUMMARY
Native Python package.
Depends: python3, python3-pyqt6, python3-uhd
EOF

# --- 6. BUILD PACKAGE ---
echo "--- Building .deb Package ---"
DEB_FILENAME="${PKG_NAME}_${APP_VERSION}_all.deb"
dpkg-deb --build "$BUILD_ROOT" "$DIST_DIR/$DEB_FILENAME"

# Cleanup
rm -rf "$BUILD_ROOT"

echo "=========================================="
echo "SUCCESS: Package created at:"
echo "$DIST_DIR/$DEB_FILENAME"
echo "=========================================="
