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
elif [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    # Empty directory
    echo -e "${BLUE}📦  Downloading Douzi...${NC}"
    git clone --quiet https://github.com/seuwangcy/Douzi.git "$INSTALL_DIR"
else
    # Directory exists but not empty and not a git repo - archive and clone
    BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}⚠️  Existing non-empty ~/.douzi found, backing up to $BACKUP_DIR${NC}"
    mv "$INSTALL_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}📦  Downloading Douzi...${NC}"
    git clone --quiet https://github.com/seuwangcy/Douzi.git "$INSTALL_DIR"
fi

# 5.1 Initialize knowledge-base directory structure
echo -e "${BLUE}📂  Initializing knowledge base...${NC}"
mkdir -p "$HOME/.douzi/knowledge-base/gtd"/{inbox,next_actions,waiting_for,projects,done,archived,reference,daily_review}

KB_DIR="$HOME/.douzi/knowledge-base/gtd"
KB_TEMPLATE_DIR="$INSTALL_DIR/docs/templates"

# Copy _README.md if not exists
if [ ! -f "$KB_DIR/_README.md" ] && [ -f "$KB_TEMPLATE_DIR/gtd-readme.md" ]; then
    cp "$KB_TEMPLATE_DIR/gtd-readme.md" "$KB_DIR/_README.md"
fi

# Copy _TEMPLATE.md if not exists
if [ ! -f "$KB_DIR/_TEMPLATE.md" ] && [ -f "$KB_TEMPLATE_DIR/gtd-template.md" ]; then
    cp "$KB_TEMPLATE_DIR/gtd-template.md" "$KB_DIR/_TEMPLATE.md"
fi

# 5.2 Check AI tool availability
echo -e "${BLUE}🤖  Checking AI CLI tools...${NC}"
HAS_GEMINI=false
HAS_CLAUDE=false

if command -v gemini &> /dev/null; then
    HAS_GEMINI=true
    echo -e "${GREEN}✅  Gemini CLI found${NC}"
fi

if command -v claude &> /dev/null; then
    HAS_CLAUDE=true
    echo -e "${GREEN}✅  Claude Code found${NC}"
fi

# Create default config
CONFIG_FILE="$HOME/.douzi/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    if $HAS_GEMINI; then
        echo "{\"aiProvider\": \"gemini\"}" > "$CONFIG_FILE"
        echo -e "${GREEN}📝  Created config with Gemini CLI${NC}"
    elif $HAS_CLAUDE; then
        echo "{\"aiProvider\": \"claude\"}" > "$CONFIG_FILE"
        echo -e "${GREEN}📝  Created config with Claude Code${NC}"
    else
        echo "{\"aiProvider\": \"gemini\"}" > "$CONFIG_FILE"
        echo -e "${YELLOW}⚠️  No AI CLI found. Install Gemini CLI or Claude Code for AI features.${NC}"
    fi
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
    *)
        # Unknown args still launch the app
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

# Set up environment for GUI app (nvm paths, AI CLI paths)
source ~/.zshrc 2>/dev/null
source ~/.bashrc 2>/dev/null
NODE_PATH=$(which node 2>/dev/null)
GEMINI_PATH=$(which gemini 2>/dev/null)
CLAUDE_PATH=$(which claude 2>/dev/null)
CONFIG="$DOUZI_DIR/config.json"
PROVIDER=gemini
[ -f "$CONFIG" ] && PROVIDER=$(grep -o '"aiProvider"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
[ "$PROVIDER" = claude ] && AI_PATH="$CLAUDE_PATH" || AI_PATH="$GEMINI_PATH"
export DOUZI_NODE_PATH="$NODE_PATH"
export DOUZI_AI_PATH="$AI_PATH"

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
# Copy custom app icon for Launchpad
if [ -f "$INSTALL_DIR/macos-tray/Resources/AppIcon.icns" ]; then
    cp "$INSTALL_DIR/macos-tray/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Launcher script - uses login shell to locate node and AI CLI, then execs the app
cat > "$APP_BUNDLE/Contents/MacOS/DouziLauncher" << 'LAUNCHSCRIPT'
#!/bin/bash
# Source login shell to inherit user's PATH (nvm, brew, etc.)
[ -f ~/.zshrc ] && source ~/.zshrc
[ -f ~/.bashrc ] && source ~/.bashrc
NODE_PATH=$(which node 2>/dev/null)
if [ -n "$NODE_PATH" ]; then export DOUZI_NODE_PATH="$NODE_PATH"; fi
# Detect AI provider from config and export the corresponding CLI path
CONFIG="${HOME}/.douzi/config.json"
if [ -f "$CONFIG" ]; then
    PROVIDER=$(grep -o '"aiProvider"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
    case "$PROVIDER" in
        claude)
            CLAUDE_PATH=$(which claude 2>/dev/null)
            if [ -n "$CLAUDE_PATH" ]; then export DOUZI_AI_PATH="$CLAUDE_PATH"; fi
            ;;
        gemini|*)
            GEMINI_PATH=$(which gemini 2>/dev/null)
            if [ -n "$GEMINI_PATH" ]; then export DOUZI_AI_PATH="$GEMINI_PATH"; fi
            ;;
    esac
fi
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
