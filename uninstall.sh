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

# ── 2. Choose delete mode ─────────────────────────────────────────────
DELETE_MODE=""
# Check for interactive mode: TTY check OR DOUZI_INTERACTIVE env var
IS_INTERACTIVE=false
if [ -t 0 ] || [ "$DOUZI_INTERACTIVE" = "1" ]; then
    IS_INTERACTIVE=true
fi

if [ -d "$HOME/.douzi/knowledge-base" ] && [ "$IS_INTERACTIVE" = true ]; then
    echo ""
    echo -e "${YELLOW}⚠️   Knowledge base detected: $HOME/.douzi/knowledge-base${NC}"
    echo ""
    echo "Choose uninstall mode:"
    echo "  1) ${RED}Full uninstall${NC} — Remove management platform + knowledge base (irreversible)"
    echo "  2) ${GREEN}Keep knowledge base${NC} — Only remove management platform, keep your data"
    echo ""
    echo -n "Choice [1]: "
    read -r DELETE_MODE_CHOICE

    case "$DELETE_MODE_CHOICE" in
        2|"")
            DELETE_MODE="keep_knowledge_base"
            ;;
        *)
            DELETE_MODE="full"
            ;;
    esac
else
    # Non-interactive: default to full uninstall but warn if knowledge-base exists
    if [ -d "$HOME/.douzi/knowledge-base" ]; then
        echo ""
        echo -e "${YELLOW}⚠️   Knowledge base found at $HOME/.douzi/knowledge-base${NC}"
        echo -e "${YELLOW}    Running in non-interactive mode — will perform FULL uninstall including knowledge base${NC}"
        echo -e "${YELLOW}    To keep your knowledge base, run interactively: bash $INSTALL_DIR/uninstall.sh${NC}"
    fi
    DELETE_MODE="full"
fi

KEEP_DATA=false
BACKUP_DIR=""

# If keeping knowledge base, backup first
if [ "$DELETE_MODE" = "keep_knowledge_base" ] && [ -d "$HOME/.douzi/knowledge-base" ]; then
    KEEP_DATA=true
    BACKUP_DIR="${HOME}/Douzi-data-backup"
    echo ""
    echo -e "${YELLOW}📦  Backing up knowledge base to $BACKUP_DIR/knowledge-base${NC}"
    mkdir -p "$BACKUP_DIR"
    if ! cp -R "$HOME/.douzi/knowledge-base" "$BACKUP_DIR/"; then
        echo -e "${RED}❌  Backup failed! Continuing anyway...${NC}"
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

# ── 6. Remove installation directory ──────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
    if [ "$KEEP_DATA" = true ]; then
        echo -e "${YELLOW}🗑️   Removing management platform files...${NC}"
        # Remove all except knowledge-base directory
        find "$INSTALL_DIR" -mindepth 1 -not -path "$INSTALL_DIR/knowledge-base*" -delete 2>/dev/null || true
        # Remove any empty directories left behind (except knowledge-base itself)
        find "$INSTALL_DIR" -mindepth 1 -type d -empty -not -path "$INSTALL_DIR/knowledge-base*" -delete 2>/dev/null || true
        # Remove INSTALL_DIR if it's now empty (should only contain knowledge-base or nothing)
        rmdir "$INSTALL_DIR" 2>/dev/null || true
        echo -e "${GREEN}    ✅  Management platform removed, knowledge base kept at $HOME/.douzi/knowledge-base/${NC}"
    else
        echo -e "${YELLOW}🗑️   Removing installation directory...${NC}"
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}    ✅  Installation directory removed${NC}"
    fi
fi

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
    if echo "$CURRENT_CRON" | grep -qE "^[^#].*(\\.douzi|douzi)"; then
        # Filter out douzi lines
        NEW_CRON=$(echo "$CURRENT_CRON" | grep -vE "^[^#]*(\\.douzi|douzi)" 2>/dev/null || true)
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

if [ "$DELETE_MODE" = "keep_knowledge_base" ]; then
    echo -e "${GREEN}      ✅  管理平台已卸载！知识库已保留${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}📁 知识库位置:${NC}"
    echo "    $HOME/.douzi/knowledge-base/"
    echo ""
    echo -e "${YELLOW}💡 如需重新安装:${NC}"
    echo "    curl -fsSL https://raw.githubusercontent.com/seuwangcy/Douzi/main/install.sh | bash"
    echo ""
    echo -e "${YELLOW}💡 知识库可通过 Obsidian 打开:${NC}"
    echo "    open -a Obsidian $HOME/.douzi/knowledge-base/gtd"
else
    echo -e "${GREEN}      ✅  Douzi 已完全卸载！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ "$KEEP_DATA" = true ] && [ -n "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}📦 知识库已备份到:${NC}"
        echo "    $BACKUP_DIR/knowledge-base"
        echo ""
    fi

    echo -e "${YELLOW}💡 重新安装:${NC}"
    echo "    curl -fsSL https://raw.githubusercontent.com/seuwangcy/Douzi/main/install.sh | bash"
fi
