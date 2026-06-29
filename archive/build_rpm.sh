#!/bin/bash
set -e  # Exit on error

# Install Build Dependencies (Requires Sudo)
echo ">>> Installing build dependencies..."
sudo dnf install -y rpm-build rpmdevtools python3-devel

# Setup RPM Build Tree
echo ">>> Setting up RPM environment..."
rpmdev-setuptree

# Load constants
CONFIG_FILE="build_config.json"
if [ ! -f "$CONFIG_FILE" ]; then echo "Error: $CONFIG_FILE not found."; exit 1; fi

get_json() { python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['$1'])"; }
get_asset_conf() { python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['assets_config']['$1'])"; }

APP_NAME=$(get_json "app_name")
VERSION=$(get_json "version")
GUI_FOLDER=$(get_json "gui_folder_name")
ASSET_REPO=$(get_asset_conf "repo_name")
ASSET_PATH_REL=$(get_asset_conf "path_inside_repo")

# Parse Repos and Entry Points
REPO_LIST=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE'))['repos']; print(' '.join([f'{k}::{v}' for k,v in d.items()]))")
ENTRY_POINTS_LIST=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE'))['gui_entry_points']; print(' '.join([f'{k}::{v}' for k,v in d.items()]))")

BUILD_DIR="build_temp"
DIST_DIR="dist"
OS="$(uname -s)"

SOURCE_DIR="${APP_NAME}-${VERSION}"
TARBALL="${APP_NAME}-${VERSION}.tar.gz"

echo ">>> Creating source tarball..."

# Move files into a temporary staging directory
rm -rf build/rpm
mkdir -p build/rpm/${SOURCE_DIR}

# Copy files into staging
cp src/app.py build/rpm/${SOURCE_DIR}/usrp_scanner.py
cp linux/bioview.desktop build/rpm/${SOURCE_DIR}/

# Create tarball in the RPM SOURCES directory
tar -C build_rpm -czf ~/rpmbuild/SOURCES/${TARBALL} ${SOURCE_DIR}

# Finally, build the RPM
echo ">>> Building RPM..."
rpmbuild -bb linux/rpm/bioview.spec

# Move the build files into the correct folder
if [ ! -d ./artifacts ]; then
    mkdir ./artifacts
fi

echo "------------------------------------------------"
echo "Build Success! Output rpm stored at $PWD/artifacts"
mv ~/rpmbuild/RPMS/noarch/*.rpm ./artifacts
# TODO: Make this use a one-liner to always get the path of file 
echo "------------------------------------------------"
