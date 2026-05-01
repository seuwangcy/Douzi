#!/bin/bash
set -e

# ==========================================
# Douzi Installer — macOS Menu Bar App
# Usage: curl -fsSL https://.../install.sh | bash
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.douzi"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/Applications"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}      🫘  Installing Douzi...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Check macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}❌  Douzi currently supports macOS only.${NC}"
    exit 1
fi

# 2. Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌  Node.js is not installed.${NC}"
    echo "    Please install Node.js 18+ first:"
    echo "    https://nodejs.org/"
    exit 1
fi
NODE_VER=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if (( NODE_VER < 18 )); then
    echo -e "${YELLOW}⚠️  Node.js version is $(node -v). Recommended: 18+${NC}"
fi

# 3. Check Swift
if ! command -v swift &> /dev/null; then
    echo -e "${RED}❌  Swift is not installed.${NC}"
    echo "    Please install Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
fi

echo -e "${GREEN}✅  Prerequisites satisfied${NC}"
echo ""

# 4. Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$APP_DIR"

# 5. Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${BLUE}📦  Updating Douzi...${NC}"
    cd "$INSTALL_DIR"
    git pull --quiet
else
    echo -e "${BLUE}📦  Downloading Douzi...${NC}"
    git clone --quiet https://github.com/seuwangcy/Douzi.git "$INSTALL_DIR"
fi

# 6. Build menu bar app
echo -e "${BLUE}🔨  Building macOS menu bar app...${NC}"
cd "$INSTALL_DIR/macos-tray"
swift build --quiet 2>&1 || {
    echo -e "${RED}❌  Build failed. See errors above.${NC}"
    exit 1
}

# 7. Create 'douzi' CLI command
echo -e "${BLUE}🖥️   Creating command-line shortcut...${NC}"
cat > "$BIN_DIR/douzi" << 'CMDSCRIPT'
#!/bin/bash
# Douzi CLI — Launcher & management
DOUZI_DIR="${HOME}/.douzi"
EXEC="$DOUZI_DIR/macos-tray/.build/debug/DouziMenuBar"

case "${1:-}" in
    update|upgrade)
        exec bash "$DOUZI_DIR/update.sh"
        ;;
    uninstall|remove)
        exec bash "$DOUZI_DIR/uninstall.sh"
        ;;
    help|--help|-h)
        echo "🫘  Douzi — AI-driven GTD Manager"
        echo ""
        echo "Usage:"
        echo "  douzi              Launch menu bar app"
        echo "  douzi update       Update to latest version"
        echo "  douzi uninstall    Remove Douzi completely"
        echo "  douzi help         Show this help message"
        exit 0
        ;;
esac

if [ ! -f "$EXEC" ]; then
    echo "❌  Douzi not found. Run: curl -fsSL ... | bash"
    exit 1
fi

if pgrep -xq "DouziMenuBar"; then
    echo "🫘  Douzi is already running. Look for the icon in your menu bar."
    exit 0
fi

nohup "$EXEC" > /dev/null 2>&1 &
echo "🚀  Douzi started! Look for the ⦿ icon in your menu bar."
CMDSCRIPT
chmod +x "$BIN_DIR/douzi"

# 8. Create Douzi.app bundle for Launchpad
echo -e "${BLUE}📱  Creating Launchpad entry...${NC}"
APP_BUNDLE="$APP_DIR/Douzi.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DouziLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>com.douzi.menubar</string>
    <key>CFBundleName</key>
    <string>Douzi</string>
    <key>CFBundleDisplayName</key>
    <string>Douzi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Launcher script
cat > "$APP_BUNDLE/Contents/MacOS/DouziLauncher" << 'LAUNCHSCRIPT'
#!/bin/bash
exec "${HOME}/.douzi/macos-tray/.build/debug/DouziMenuBar"
LAUNCHSCRIPT
chmod +x "$APP_BUNDLE/Contents/MacOS/DouziLauncher"

# 9. Ensure PATH contains ~/.local/bin
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    SHELL_RC="${HOME}/.zshrc"
    [ -f "${HOME}/.bashrc" ] && SHELL_RC="${HOME}/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo -e "${YELLOW}⚠️  Added ~/.local/bin to PATH in $SHELL_RC${NC}"
    echo "    Run: source $SHELL_RC"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}      ✅  Douzi installed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "🚀  Launch Douzi:"
echo "    • Terminal:    douzi"
echo "    • Launchpad:   Douzi"
echo ""
echo "📖  Documentation: ~/.douzi/docs/macos-menu-bar.md"
echo ""
