#!/bin/bash
set -e

# ==========================================
# Douzi Updater — Seamless Update
# Usage: bash update.sh
#         douzi update  (via CLI integration)
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
echo -e "${BLUE}      🫘  Updating Douzi...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}❌  Douzi is not installed.${NC}"
    echo "    Install it first:"
    echo "    curl -fsSL https://raw.githubusercontent.com/seuwangcy/Douzi/main/install.sh | bash"
    exit 1
fi

# 2. Save current commit for rollback info
cd "$INSTALL_DIR"
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo -e "${BLUE}📦  Current version: $CURRENT_COMMIT${NC}"

# 3. Stash any local changes (user customizations)
STASHED=false
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo -e "${YELLOW}📦  Stashing local changes (worktree + staged)...${NC}"
    if git stash push --include-untracked -m "douzi-update-auto-stash-$(date +%s)"; then
        STASHED=true
    else
        echo -e "${RED}❌  Failed to stash local changes!${NC}"
        echo -e "${RED}    Your local modifications may be lost.${NC}"
        echo -e "${YELLOW}    Continuing update anyway...${NC}"
    fi
fi

# 4. Pull latest
echo -e "${BLUE}📥  Fetching latest version...${NC}"
git fetch --quiet origin
LATEST_COMMIT=$(git rev-parse --short origin/main 2>/dev/null || echo "unknown")

# Use explicit remote/branch instead of @{upstream} for reliability
if ! git rev-parse --abbrev-ref @{upstream} &>/dev/null; then
    echo -e "${YELLOW}⚠️  No upstream configured; forcing update...${NC}"
elif git diff --quiet @{upstream} 2>/dev/null; then
    echo -e "${GREEN}✅  Already up to date (${CURRENT_COMMIT}).${NC}"
    # Apply stash if we stashed
    if git stash list 2>/dev/null | grep -q "douzi-update-auto-stash"; then
        echo -e "${YELLOW}📦  Restoring local changes...${NC}"
        git stash apply 2>/dev/null || true
    fi
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}      ✅  Douzi is already the latest!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi

git pull --quiet origin main 2>/dev/null || {
    echo -e "${RED}❌  Git pull failed. Trying reset...${NC}"
    git fetch origin
    git reset --hard origin/main 2>/dev/null || {
        echo -e "${RED}❌  Update failed. Please check network or git state.${NC}"
        exit 1
    }
}

NEW_COMMIT=$(git rev-parse --short HEAD)
echo -e "${GREEN}✅  Updated: ${CURRENT_COMMIT} → ${NEW_COMMIT}${NC}"

# 5. Rebuild macOS menu bar app
echo -e "${BLUE}🔨  Rebuilding macOS menu bar app...${NC}"
cd "$INSTALL_DIR/macos-tray"
swift build --quiet 2>&1 || {
    echo -e "${RED}❌  Build failed.${NC}"
    echo "    Try rebuilding manually: cd ~/.douzi/macos-tray && swift build"
    exit 1
}
echo -e "${GREEN}✅  Menu bar app rebuilt${NC}"

# 6. Update CLI launcher (in case it changed)
echo -e "${BLUE}🖥️   Updating CLI launcher...${NC}"
mkdir -p "$BIN_DIR"
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
echo -e "${GREEN}✅  CLI launcher updated${NC}"

# 7. Update Douzi.app bundle
echo -e "${BLUE}📱  Updating Launchpad entry...${NC}"
APP_BUNDLE="$APP_DIR/Douzi.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

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
echo -e "${GREEN}✅  Launchpad entry updated${NC}"

# 8. Restart DouziMenuBar if it was running
RESTART=false
if pgrep -xq "DouziMenuBar"; then
    RESTART=true
    echo -e "${YELLOW}🔄  Restarting DouziMenuBar...${NC}"
    pkill -x "DouziMenuBar" 2>/dev/null || true
    sleep 1
fi

# Restart Node.js server if it was running (based on port check)
DOUZI_SERVER_PID=""
if command -v lsof &> /dev/null; then
    DOUZI_SERVER_PID=$(lsof -ti :5000 -sTCP:LISTEN 2>/dev/null || true)
fi
if [ -n "$DOUZI_SERVER_PID" ]; then
    SERVER_CWD=$(lsof -p "$DOUZI_SERVER_PID" -Fn 2>/dev/null | grep "^fcwd" | head -1 | cut -c5- || true)
    if [ "$SERVER_CWD" = "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}🔄  Restarting Node.js server...${NC}"
        kill "$DOUZI_SERVER_PID" 2>/dev/null || true
        sleep 1
        cd "$INSTALL_DIR"
        nohup node server.mjs > /dev/null 2>&1 &
        echo -e "${GREEN}✅  Server restarted${NC}"
    fi
fi

if [ "$RESTART" = true ]; then
    cd "$INSTALL_DIR/macos-tray"
    nohup ./.build/debug/DouziMenuBar > /dev/null 2>&1 &
    echo -e "${GREEN}✅  DouziMenuBar restarted${NC}"
fi

# 9. Pop stash if we stashed
cd "$INSTALL_DIR"
if [ "$STASHED" = true ]; then
    if git stash list 2>/dev/null | grep -q "douzi-update-auto-stash"; then
        echo -e "${YELLOW}📦  Restoring local changes...${NC}"
        if ! git stash pop; then
            echo -e "${RED}❌  Failed to restore stashed changes!${NC}"
            echo -e "${YELLOW}    Run manually: cd ~/.douzi && git stash pop${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}      ✅  Douzi updated successfully!${NC}"
echo -e "${GREEN}      ${CURRENT_COMMIT} → ${NEW_COMMIT}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "🔄  You can now use Douzi as usual:"
echo "    • douzi       (re-launch menu bar app)"
echo "    • open -a Douzi  (via Launchpad)"
echo ""
