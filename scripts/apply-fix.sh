#!/usr/bin/env bash
#
# apply-fix.sh — Apply the WSL/Windows image path fix to GG Coder
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/apply-fix.sh | bash
#   — or —
#   git clone https://github.com/creativeprofit22/ggcoder-fixes.git && cd ggcoder-fixes && bash scripts/apply-fix.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   GG Coder — WSL/Windows Image Path Fix     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# --- Find the ggcoder install ---
GGCODER_BIN=$(which ggcoder 2>/dev/null || true)

if [ -z "$GGCODER_BIN" ]; then
    echo -e "${RED}✗ ggcoder not found in PATH.${NC}"
    echo "  Install it first:  npm install -g @kenkaiiii/ggcoder"
    exit 1
fi

# Resolve symlink to find the actual package directory
GGCODER_REAL=$(readlink -f "$GGCODER_BIN" 2>/dev/null || realpath "$GGCODER_BIN" 2>/dev/null || echo "")

if [ -z "$GGCODER_REAL" ]; then
    echo -e "${RED}✗ Could not resolve ggcoder path.${NC}"
    exit 1
fi

# Navigate up from bin to the package root
# Typical structure: .../node_modules/@kenkaiiii/ggcoder/dist/cli.js (bin target)
# or:               .../node_modules/.bin/ggcoder -> ../../../@kenkaiiii/ggcoder/dist/cli.js
PACKAGE_DIR=$(dirname "$GGCODER_REAL")
# Walk up until we find package.json
while [ ! -f "$PACKAGE_DIR/package.json" ] && [ "$PACKAGE_DIR" != "/" ]; do
    PACKAGE_DIR=$(dirname "$PACKAGE_DIR")
done

if [ ! -f "$PACKAGE_DIR/package.json" ]; then
    echo -e "${RED}✗ Could not find ggcoder package.json${NC}"
    exit 1
fi

TARGET="$PACKAGE_DIR/dist/utils/image.js"

if [ ! -f "$TARGET" ]; then
    echo -e "${RED}✗ Target file not found: $TARGET${NC}"
    exit 1
fi

# --- Check current version ---
VERSION=$(node -e "console.log(require('$PACKAGE_DIR/package.json').version)" 2>/dev/null || echo "unknown")
echo -e "  Package:  ${GREEN}@kenkaiiii/ggcoder@${VERSION}${NC}"
echo -e "  Location: ${BLUE}${PACKAGE_DIR}${NC}"
echo ""

# --- Check if already patched ---
if grep -q "toWslPath" "$TARGET" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Already patched! The WSL fix is already applied.${NC}"
    echo "  Nothing to do."
    exit 0
fi

# --- Backup ---
BACKUP="${TARGET}.backup"
cp "$TARGET" "$BACKUP"
echo -e "  ${GREEN}✓${NC} Backup created: ${BLUE}image.js.backup${NC}"

# --- Apply the patch inline ---
# We use node to do the patching since sed doesn't handle multiline well across platforms.

node -e "
const fs = require('fs');
const filePath = '$TARGET';
let code = fs.readFileSync(filePath, 'utf-8');

// 1. Add toWslPath function after isAttachablePath
const toWslFn = \`
/**
 * Detect a Windows-style absolute path (e.g. \"C:\\\\foo\", \"c:/foo\", \"D:\\\\bar\")
 * and convert it to the WSL mount point (/mnt/c/foo) when running on Linux.
 */
function toWslPath(p) {
    // Match drive letter patterns: C:\\\\, C:/, c:\\\\, c:/
    const winAbsRe = /^([A-Za-z]):[/\\\\\\\\]/;
    const m = winAbsRe.exec(p);
    if (m && process.platform === \"linux\") {
        const drive = m[1].toLowerCase();
        const rest = p.slice(3).replace(/\\\\\\\\/g, \"/\");
        return \\\`/mnt/\\\${drive}/\\\${rest}\\\`;
    }
    return p;
}\`;

code = code.replace(
    'function resolvePath(filePath, cwd) {',
    toWslFn + '\nfunction resolvePath(filePath, cwd) {'
);

// 2. Add toWslPath call + guard backslash unescape in resolvePath
code = code.replace(
    '    // Unescape backslash-escaped characters (e.g. \"\\\\ \" → \" \")\n    resolved = resolved.replace(/\\\\\\\\(.)/g, \"\\\$1\");',
    '    // Convert Windows paths to WSL paths (e.g. C:\\\\Users\\\\... → /mnt/c/Users/...)\n    resolved = toWslPath(resolved);\n    // Unescape backslash-escaped characters (e.g. \"\\\\ \" → \" \")\n    // Only do this if not a Windows-style path (already handled by toWslPath)\n    if (!(/^[A-Za-z]:[/\\\\\\\\]/.test(filePath.trim().replace(/^[\\'\\\"]/, \"\")))) {\n        resolved = resolved.replace(/\\\\\\\\(.)/g, \"\\\$1\");\n    }'
);

// 3. Add Windows drive letter detection to looksLikePath
code = code.replace(
    '        stripped.startsWith(\"file://\"));',
    '        stripped.startsWith(\"file://\") ||\n        /^[A-Za-z]:/.test(stripped));'
);

fs.writeFileSync(filePath, code);
console.log('  Patch applied successfully.');
"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "  ${GREEN}✓${NC} Patch applied successfully!"
    echo ""
    echo -e "${GREEN}Done!${NC} Restart ggcoder for changes to take effect."
    echo ""
    echo "  To undo:  cp \"${BACKUP}\" \"${TARGET}\""
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Running 'npm update -g @kenkaiiii/ggcoder' will overwrite this fix."
    echo "  Re-run this script after updating."
else
    echo -e "${RED}✗ Patch failed. Restoring backup...${NC}"
    cp "$BACKUP" "$TARGET"
    echo -e "  ${GREEN}✓${NC} Original file restored."
    exit 1
fi
