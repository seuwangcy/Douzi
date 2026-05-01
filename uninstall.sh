#!/bin/bash
set -e

# ==========================================
# Douzi Uninstaller — Full Removal
# Usage: curl -fsSL https://.../uninstall.sh | bash
#         bash uninstall.sh
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

INSTALL_DIR="${HOME}/.douzi"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/Applications"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}      🫘  Uninstalling Douzi...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── 1. Kill running processes ──────────────────────────────────────────
echo -e "${YELLOW}🔍  Stopping running processes...${NC}"

if pgrep -x "DouziMenuBar" &> /dev/null; then
    echo "    Stopping DouziMenuBar..."
    pkill -x "DouziMenuBar" 2>/dev/null || true
    echo -e "${GREEN}    ✅  DouziMenuBar stopped${NC}"
fi

# Kill only server.mjs that is running FROM our install directory
# Use lsof to find the process on port 5000 and verify its working directory
SERVER_PID=""
if command -v lsof &> /dev/null; then
    SERVER_PID=$(lsof -ti :5000 -sTCP:LISTEN 2>/dev/null || true)
fi
if [ -n "$SERVER_PID" ]; then
    # Verify this process is server.mjs from our install dir
    SERVER_CWD=$(lsof -p "$SERVER_PID" -Fn 2>/dev/null | grep "^fcwd" | head -1 | cut -c5- || true)
    if [ "$SERVER_CWD" = "$INSTALL_DIR" ]; then
        echo "    Stopping Douzi server (PID $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        echo -e "${GREEN}    ✅  Douzi server stopped${NC}"
    fi
fi

sleep 1

# ── 2. Prompt: keep GTD data? ─────────────────────────────────────────
KEEP_DATA=false
BACKUP_DIR=""
if [ -d "$INSTALL_DIR/knowledge-base" ] && [ -t 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️   GTD knowledge base found at $INSTALL_DIR/knowledge-base${NC}"
    echo -e "${YELLOW}    Keep your tasks and notes? [Y/n] ${NC}"
    read -r KEEP_CONFIRM
    if [[ ! "$KEEP_CONFIRM" =~ ^[Nn]$ ]]; then
        KEEP_DATA=true
        BACKUP_DIR="${HOME}/Douzi-data-backup"
    fi
fi

# ── 3. Remove CLI launcher ─────────────────────────────────────────────
echo -e "${YELLOW}🗑️   Removing CLI launcher...${NC}"
if [ -f "$BIN_DIR/douzi" ]; then
    rm -f "$BIN_DIR/douzi"
fi
# Only remove BIN_DIR if it's inside HOME and empty
if [ -d "$BIN_DIR" ] && [ "$(dirname "$BIN_DIR")" = "$HOME" ] && [ -z "$(ls -A "$BIN_DIR" 2>/dev/null)" ]; then
    rmdir "$BIN_DIR" 2>/dev/null || true
fi
echo -e "${GREEN}    ✅  CLI launcher removed${NC}"

# ── 4. Remove Launchpad entry ─────────────────────────────────────────
echo -e "${YELLOW}🗑️   Removing Launchpad entry...${NC}"
if [ -d "$APP_DIR/Douzi.app" ]; then
    rm -rf "$APP_DIR/Douzi.app"
fi
echo -e "${GREEN}    ✅  Launchpad entry removed${NC}"

# ── 5. Backup knowledge base if requested ─────────────────────────────
if [ "$KEEP_DATA" = true ] && [ -d "$INSTALL_DIR/knowledge-base" ]; then
    echo -e "${YELLOW}📦  Backing up knowledge base to $BACKUP_DIR...${NC}"
    mkdir -p "$BACKUP_DIR"
    cp -R "$INSTALL_DIR/knowledge-base" "$BACKUP_DIR/" 2>/dev/null || true
    echo -e "${GREEN}    ✅  Backed up to $BACKUP_DIR/knowledge-base${NC}"
fi

# ── 6. Remove installation directory ──────────────────────────────────
echo -e "${YELLOW}🗑️   Removing installation directory...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi
echo -e "${GREEN}    ✅  Installation directory removed${NC}"

# ── 7. Remove PATH from shell rc files ────────────────────────────────
echo -e "${YELLOW}🔧  Cleaning up shell PATH...${NC}"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
REMOVED_RC=""

for RC in "${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.profile"; do
    if [ -f "$RC" ] && [ -r "$RC" ] && [ -w "$RC" ]; then
        # Only modify if the line actually exists
        if grep -Fxsq "$PATH_LINE" "$RC" 2>/dev/null; then
            # Remove just that line, write to temp
            grep -Fxv "$PATH_LINE" "$RC" > "${RC}.douzi-rm" 2>/dev/null || true
            # Verify temp is valid text before replacing
            if file "${RC}.douzi-rm" | grep -q "text\|empty"; then
                mv "${RC}.douzi-rm" "$RC"
                REMOVED_RC="$REMOVED_RC $RC"
            else
                rm -f "${RC}.douzi-rm" 2>/dev/null
            fi
        fi
    fi
done

if [ -n "$REMOVED_RC" ]; then
    echo -e "${GREEN}    ✅  Cleaned Douzi PATH from:$REMOVED_RC${NC}"
else
    echo -e "${GREEN}    ✅  No PATH modifications found${NC}"
fi

# ── 8. Remove crontab entries (safely) ────────────────────────────────
echo -e "${YELLOW}🔧  Cleaning up crontab entries...${NC}"
if crontab -l &>/dev/null; then
    CURRENT_CRON=$(crontab -l 2>/dev/null)
    if echo "$CURRENT_CRON" | grep -q "douzi\|\.douzi"; then
        # Filter out douzi lines
        NEW_CRON=$(echo "$CURRENT_CRON" | grep -v "douzi\|\.douzi" 2>/dev/null || true)
        if [ -n "$NEW_CRON" ]; then
            echo "$NEW_CRON" | crontab - 2>/dev/null || true
        else
            crontab -r 2>/dev/null || true
        fi
        echo -e "${GREEN}    ✅  Removed Douzi crontab entries${NC}"
    else
        echo -e "${GREEN}    ✅  No Douzi crontab entries found${NC}"
    fi
else
    echo -e "${GREEN}    ✅  No crontab to clean${NC}"
fi

# ── Done ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}      ✅  Douzi has been uninstalled!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$KEEP_DATA" = true ] && [ -n "$BACKUP_DIR" ]; then
    echo -e "${YELLOW}📦  Your GTD data has been backed up to:${NC}"
    echo "    $BACKUP_DIR/knowledge-base"
    echo ""
fi

echo -e "${YELLOW}💡  To reload your shell configuration:${NC}"
echo "    source ~/.zshrc  (or restart terminal)"
echo ""
echo -e "${YELLOW}💡  To reinstall:${NC}"
echo "    curl -fsSL https://raw.githubusercontent.com/seuwangcy/Douzi/main/install.sh | bash"
