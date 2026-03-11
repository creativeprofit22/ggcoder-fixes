#!/usr/bin/env bash
#
# apply-fix.sh — Apply all community patches to GG Coder
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
echo -e "${BLUE}║   GG Coder — Community Patches               ║${NC}"
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
PACKAGE_DIR=$(dirname "$GGCODER_REAL")
while [ ! -f "$PACKAGE_DIR/package.json" ] && [ "$PACKAGE_DIR" != "/" ]; do
    PACKAGE_DIR=$(dirname "$PACKAGE_DIR")
done

if [ ! -f "$PACKAGE_DIR/package.json" ]; then
    echo -e "${RED}✗ Could not find ggcoder package.json${NC}"
    exit 1
fi

# --- Check current version ---
VERSION=$(node -e "console.log(require('$PACKAGE_DIR/package.json').version)" 2>/dev/null || echo "unknown")
echo -e "  Package:  ${GREEN}@kenkaiiii/ggcoder@${VERSION}${NC}"
echo -e "  Location: ${BLUE}${PACKAGE_DIR}${NC}"
echo ""

APPLIED=0
SKIPPED=0
FAILED=0

# ============================================================
# Patch 1: WSL/Windows image path support (image.js)
# ============================================================
echo -e "${BLUE}[1/2] WSL/Windows image path fix${NC}"
TARGET_IMAGE="$PACKAGE_DIR/dist/utils/image.js"

if [ ! -f "$TARGET_IMAGE" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_IMAGE${NC}"
    ((FAILED++))
elif grep -q "toWslPath" "$TARGET_IMAGE" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ Already applied — skipping${NC}"
    ((SKIPPED++))
else
    cp "$TARGET_IMAGE" "${TARGET_IMAGE}.backup"
    echo -e "  ${GREEN}✓${NC} Backup: image.js.backup"

    node -e "
const fs = require('fs');
const filePath = '$TARGET_IMAGE';
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
" && {
        echo -e "  ${GREEN}✓${NC} Patch applied"
        ((APPLIED++))
    } || {
        echo -e "  ${RED}✗ Patch failed — restoring backup${NC}"
        cp "${TARGET_IMAGE}.backup" "$TARGET_IMAGE"
        ((FAILED++))
    }
fi
echo ""

# ============================================================
# Patch 2: Input area race conditions & stale cursor (InputArea.js)
#   - Stale cursor closure: uses cursorRef so setValue callbacks
#     read current cursor instead of stale closure value
#   - Async image extraction race: functional setValue update
#     preserves text typed during async extractImagePaths
#   - Dictation misdetection: raises paste threshold so voice
#     dictation isn't incorrectly treated as pasted text
# ============================================================
echo -e "${BLUE}[2/2] Input area race conditions & stale cursor fix${NC}"
TARGET_INPUT="$PACKAGE_DIR/dist/ui/components/InputArea.js"

if [ ! -f "$TARGET_INPUT" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_INPUT${NC}"
    ((FAILED++))
elif grep -q "cursorRef" "$TARGET_INPUT" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ Already applied — skipping${NC}"
    ((SKIPPED++))
else
    cp "$TARGET_INPUT" "${TARGET_INPUT}.backup"
    echo -e "  ${GREEN}✓${NC} Backup: InputArea.js.backup"

    node -e "
const fs = require('fs');
const filePath = process.argv[1];
let code = fs.readFileSync(filePath, 'utf-8');

// 1. Replace cursor state with cursorRef + setCursor wrapper
code = code.replace(
    'const [value, setValue] = useState(\"\");\n    const [cursor, setCursor] = useState(0);',
    'const [value, setValue] = useState(\"\");\n    const cursorRef = useRef(0);\n    const [cursor, setCursorState] = useState(0);\n    const setCursor = (valOrFn) => { const next = typeof valOrFn === \\'function\\' ? valOrFn(cursorRef.current) : valOrFn; cursorRef.current = next; setCursorState(next); };'
);

// 2. Fix stale cursor in setValue callbacks — newline insertion
code = code.replace(
    'setValue((v) => v.slice(0, cursor) + \"\\\\n\" + v.slice(cursor));',
    'setValue((v) => v.slice(0, cursorRef.current) + \"\\\\n\" + v.slice(cursorRef.current));'
);

// 3. Fix stale cursor in backspace handler
code = code.replace(
    'setValue((v) => v.slice(0, cursor - 1) + v.slice(cursor));',
    'setValue((v) => v.slice(0, cursorRef.current - 1) + v.slice(cursorRef.current));'
);

// 4. Fix stale cursor in text input handler
code = code.replace(
    'setValue((v) => v.slice(0, cursor) + normalized + v.slice(cursor));',
    'setValue((v) => v.slice(0, cursorRef.current) + normalized + v.slice(cursorRef.current));'
);

// 5. Fix paste offset using stale cursor
code = code.replace(
    'setPasteOffset(cursor); // record where paste starts on first chunk',
    'setPasteOffset(cursorRef.current); // record where paste starts on first chunk'
);

// 6. Fix paste detection threshold (dictation misdetection)
code = code.replace(
    'if (input.length > 1) {',
    'if (input.length > 8 || (input.length > 1 && input.includes(\"\\\\n\"))) {'
);

// 7. Fix async image extraction race condition — use functional setValue
code = code.replace(
    '                    setValue(cleanText);\n                    setCursor(Math.min(cursor, cleanText.length));',
    '                    // Use functional update to avoid overwriting text typed during async operation\n                    setValue((currentValue) => {\n                        // Only apply if the value hasn\\'t changed beyond what we extracted from\n                        if (currentValue === value) {\n                            return cleanText;\n                        }\n                        // If user typed more, try to apply the same removal\n                        const diff = currentValue.slice(value.length);\n                        return cleanText + diff;\n                    });\n                    setCursor((c) => Math.min(c, cleanText.length));'
);

// 8. Fix task toggle keybinding (tilde → Ctrl+T)
code = code.replace(
    /\/\/ Shift\+\\\`.*/,
    '// Ctrl+T toggles task overlay — works even while agent is running'
);
code = code.replace(
    'if (input === \"~\") {',
    'if (key.ctrl && input === \"t\") {'
);

fs.writeFileSync(filePath, code);
" "$TARGET_INPUT" && {
        # Verify syntax
        if node -c "$TARGET_INPUT" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Patch applied (syntax verified)"
            ((APPLIED++))
        else
            echo -e "  ${RED}✗ Patch produced invalid JS — restoring backup${NC}"
            cp "${TARGET_INPUT}.backup" "$TARGET_INPUT"
            ((FAILED++))
        fi
    } || {
        echo -e "  ${RED}✗ Patch failed — restoring backup${NC}"
        cp "${TARGET_INPUT}.backup" "$TARGET_INPUT"
        ((FAILED++))
    }
fi

echo ""
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo -e "  Applied: ${GREEN}${APPLIED}${NC}  Skipped: ${YELLOW}${SKIPPED}${NC}  Failed: ${RED}${FAILED}${NC}"
echo -e "${BLUE}────────────────────────────────────────────────${NC}"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Some patches failed.${NC} Check the output above."
    exit 1
fi

echo -e "${GREEN}Done!${NC} Restart ggcoder for changes to take effect."
echo ""
echo -e "  ${YELLOW}Note:${NC} Running 'npm update -g @kenkaiiii/ggcoder' will overwrite these fixes."
echo "  Re-run this script after updating."
