#!/usr/bin/env bash
#
# install-agents.sh — Install optimized agent definitions and CLAUDE.md
#
# Usage:
#   bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/install-agents.sh)
#   — or —
#   git clone https://github.com/creativeprofit22/ggcoder-fixes.git && cd ggcoder-fixes && bash scripts/install-agents.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   GG Coder — Agent Config Installer          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

GG_DIR="$HOME/.gg"
AGENTS_DIR="$GG_DIR/agents"
INSTALLED=0
SKIPPED=0

# --- Determine source directory ---
# If run from the repo, use local files. Otherwise, fetch from GitHub.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -d "$REPO_ROOT/agents" ]; then
    SOURCE_DIR="$REPO_ROOT/agents"
    echo -e "  Source: ${BLUE}local repo${NC} ($SOURCE_DIR)"
else
    # Download to temp dir
    SOURCE_DIR=$(mktemp -d)
    trap "rm -rf $SOURCE_DIR" EXIT
    echo -e "  Source: ${BLUE}GitHub${NC}"
    BASE_URL="https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/agents"
    for f in scout.md runner.md worker.md fork.md CLAUDE.md; do
        curl -sL "$BASE_URL/$f" -o "$SOURCE_DIR/$f"
    done
fi
echo ""

# --- Create directories ---
mkdir -p "$AGENTS_DIR"

# --- Install agent definitions ---
echo -e "${BLUE}Installing agent definitions → ${AGENTS_DIR}${NC}"
echo ""

for agent_file in scout.md runner.md worker.md fork.md; do
    src="$SOURCE_DIR/$agent_file"
    dest="$AGENTS_DIR/$agent_file"
    name="${agent_file%.md}"

    if [ ! -f "$src" ]; then
        echo -e "  ${RED}✗ Source file not found: $src${NC}"
        continue
    fi

    if [ -f "$dest" ]; then
        # Check if content differs
        if diff -q "$src" "$dest" > /dev/null 2>&1; then
            echo -e "  ${YELLOW}⚠ ${name}${NC} — already up to date, skipping"
            ((SKIPPED++))
            continue
        else
            cp "$dest" "${dest}.backup"
            echo -e "  ${GREEN}✓ ${name}${NC} — updated (backup: ${agent_file}.backup)"
        fi
    else
        echo -e "  ${GREEN}✓ ${name}${NC} — installed"
    fi

    cp "$src" "$dest"
    ((INSTALLED++))
done

echo ""

# --- Install CLAUDE.md ---
echo -e "${BLUE}Installing CLAUDE.md → ${GG_DIR}${NC} (if not present)"
echo ""

CLAUDE_SRC="$SOURCE_DIR/CLAUDE.md"
CLAUDE_DEST="$HOME/CLAUDE.md"

if [ -f "$CLAUDE_SRC" ]; then
    if [ -f "$CLAUDE_DEST" ]; then
        echo -e "  ${YELLOW}⚠ CLAUDE.md already exists${NC} at $CLAUDE_DEST"
        echo -e "    Not overwriting — your custom config is preserved."
        echo -e "    Reference template saved to: ${BLUE}${GG_DIR}/CLAUDE.md.reference${NC}"
        cp "$CLAUDE_SRC" "$GG_DIR/CLAUDE.md.reference"
        ((SKIPPED++))
    else
        cp "$CLAUDE_SRC" "$CLAUDE_DEST"
        echo -e "  ${GREEN}✓ CLAUDE.md${NC} — installed to $CLAUDE_DEST"
        ((INSTALLED++))
    fi
else
    echo -e "  ${RED}✗ CLAUDE.md template not found in source${NC}"
fi

echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "  Installed: ${GREEN}${INSTALLED}${NC}  Skipped: ${YELLOW}${SKIPPED}${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""
echo -e "${GREEN}Done!${NC} Restart ggcoder for agents to be available."
echo ""
echo -e "  Agents available via subagent tool:"
echo -e "    ${BLUE}scout${NC}  — fast read-only codebase search (Haiku)"
echo -e "    ${BLUE}runner${NC} — execute commands and report (Haiku)"
echo -e "    ${BLUE}worker${NC} — full-capability multi-step tasks"
echo -e "    ${BLUE}fork${NC}   — isolated parallel execution, structured output"
echo ""
