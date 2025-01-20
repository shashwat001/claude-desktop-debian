#!/bin/bash
set -e

# Check if being run as root
if [ "$EUID" -eq 0 ]; then
    echo "Please do not run this script with sudo"
    echo "It will ask for sudo permissions when needed"
    exit 1
fi

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# Check for Debian-based system
if [ ! -f "/etc/debian_version" ]; then
    echo "❌ This script requires a Debian-based Linux distribution"
    exit 1
fi

# Print system information
echo "System Information:"
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
echo "Debian version: $(cat /etc/debian_version)"


# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Function to install system dependencies
install_dependencies() {
    local deps="$1"
    echo "Installing system dependencies: $deps"
    sudo apt update
    sudo apt install -y $deps
}

# Check and install dependencies
echo "Checking Node.js environment..."
for cmd in node npm; do
    if ! check_command "$cmd"; then
        echo "❌ Node.js/npm not found. Please install Node.js"
        exit 1
    fi
done

echo "Checking system dependencies..."
DEPS_TO_INSTALL=""

# Check system package dependencies
for cmd in p7zip wget wrestool icotool convert dpkg-deb; do
    if ! check_command "$cmd"; then
        case "$cmd" in
            "p7zip")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip-full"
                ;;
            "wget")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL wget"
                ;;
            "wrestool"|"icotool")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL icoutils"
                ;;
            "convert")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL imagemagick"
                ;;
            "dpkg-deb")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL dpkg-dev"
                ;;
        esac
    fi
done

# Install system dependencies if any
if [ ! -z "$DEPS_TO_INSTALL" ]; then
    install_dependencies "$DEPS_TO_INSTALL"
    echo "System dependencies installed successfully"
fi

echo "Checking npm dependencies..."
# Install electron globally via npm if not present
if ! check_command "electron"; then
    echo "Installing electron..."
    npm install -g electron
fi

# Install asar if needed
if ! check_command "asar"; then
    echo "Installing @electron/asar..."
    npm install -g @electron/asar
fi

# Extract version from the installer filename
VERSION=$(basename "$CLAUDE_DOWNLOAD_URL" | grep -oP 'Claude-Setup-x64\.exe' | sed 's/Claude-Setup-x64\.exe/0.7.8/')
PACKAGE_NAME="claude-desktop"
ARCHITECTURE="amd64"
MAINTAINER="Claude Desktop Linux Maintainers"
DESCRIPTION="Claude Desktop for Linux"

# Create working directories
WORK_DIR="$(pwd)/build"
DEB_ROOT="$WORK_DIR/deb-package"
INSTALL_DIR="$DEB_ROOT/usr"

# Clean previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop installer..."
CLAUDE_EXE="$WORK_DIR/Claude-Setup-x64.exe"
if ! wget -O "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$WORK_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

if ! 7z x -y "AnthropicClaude-$VERSION-full.nupkg"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi
echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
if ! wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico; then
    echo "❌ Failed to extract icons from exe"
    exit 1
fi

if ! icotool -x claude.ico; then
    echo "❌ Failed to convert icons"
    exit 1
fi
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons
for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/claude-desktop.png"
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

# Process app.asar
mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

cd electron-app

# Check for asar installation and install if needed
if ! command -v asar &> /dev/null; then
    echo "Installing @electron/asar package..."
    npm install @electron/asar
    PATH="$PATH:$(pwd)/node_modules/.bin"
fi

asar extract app.asar app.asar.contents

# Replace native module with stub implementation
echo "Creating stub native module..."
cat > app.asar.contents/node_modules/claude-native/index.js << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy Tray icons
mkdir -p app.asar.contents/resources
cp ../lib/net45/resources/Tray* app.asar.contents/resources/

# Repackage app.asar
asar pack app.asar.contents app.asar

# Create native module with keyboard constants
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native"
cp app.asar.contents/node_modules/claude-native/index.js "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/"

# Copy app files
cp app.asar "$INSTALL_DIR/lib/$PACKAGE_NAME/"
cp -r app.asar.unpacked "$INSTALL_DIR/lib/$PACKAGE_NAME/"

# Create desktop entry
cat > "$INSTALL_DIR/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
EOF

# Create launcher script
cat > "$INSTALL_DIR/bin/claude-desktop" << EOF
#!/bin/bash

# Source NVM
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"  # This loads nvm

electron /usr/lib/claude-desktop/app.asar "\$@"
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"

# Create control file
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: claude-desktop
Version: $VERSION
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Depends: p7zip-full
Recommends: nodejs, npm
Description: $DESCRIPTION
 Claude is an AI assistant from Anthropic.
 This package provides the desktop interface for Claude.
 .
 Supported on Debian-based Linux distributions (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
 Note: Requires Node.js (>= 12.0.0) and npm, either system-installed or via version managers like nvm
EOF

# Build .deb package
echo "📦 Building .deb package..."
DEB_FILE="$(pwd)/claude-desktop_${VERSION}_${ARCHITECTURE}.deb"
if ! dpkg-deb --build "$DEB_ROOT" "$DEB_FILE"; then
    echo "❌ Failed to build .deb package"
    exit 1
fi

if [ -f "$DEB_FILE" ]; then
    echo "✓ Package built successfully at: $DEB_FILE"
    echo "🎉 Done! You can now install the package with: sudo dpkg -i $DEB_FILE"
else
    echo "❌ Package file not found at expected location: $DEB_FILE"
    exit 1
fi