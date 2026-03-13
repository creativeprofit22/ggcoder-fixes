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
echo -e "${BLUE}[1/4] WSL/Windows image path fix${NC}"
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
echo -e "${BLUE}[2/4] Input area race conditions & stale cursor fix${NC}"
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
//    Snapshot cursorRef.current BEFORE setCursor mutates it, so the
//    setValue functional updater (which runs later during React render)
//    uses the correct pre-mutation position.
code = code.replace(
    'setValue((v) => v.slice(0, cursor) + \"\\\\n\" + v.slice(cursor));\n            setCursor((c) => c + 1);',
    'const pos = cursorRef.current;\n            setValue((v) => v.slice(0, pos) + \"\\\\n\" + v.slice(pos));\n            setCursor((c) => c + 1);'
);

// 3. Fix stale cursor in backspace handler
code = code.replace(
    'setValue((v) => v.slice(0, cursor - 1) + v.slice(cursor));\n                setCursor((c) => c - 1);',
    'const pos = cursorRef.current;\n                setValue((v) => v.slice(0, pos - 1) + v.slice(pos));\n                setCursor((c) => c - 1);'
);

// 4. Fix stale cursor in text input handler + paste offset
code = code.replace(
    'setValue((v) => v.slice(0, cursor) + normalized + v.slice(cursor));\n            setCursor((c) => c + normalized.length);',
    'const pos = cursorRef.current;\n            setValue((v) => v.slice(0, pos) + normalized + v.slice(pos));\n            setCursor((c) => c + normalized.length);'
);

// 5. Fix paste offset using stale cursor
code = code.replace(
    'setPasteOffset(cursor); // record where paste starts on first chunk',
    'setPasteOffset(pos); // record where paste starts on first chunk'
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

# ============================================================
# Patch 3: Sub-agent spawning flags (cli.js)
#   - cli.js didn't accept --json, --provider, --model,
#     --max-turns, --system-prompt flags that the subagent tool
#     passes when spawning child processes.
#   - Adds these flags to parseArgs and wires up runJsonMode().
# ============================================================
echo -e "${BLUE}[3/4] Sub-agent spawning flags fix${NC}"
TARGET_CLI="$PACKAGE_DIR/dist/cli.js"

if [ ! -f "$TARGET_CLI" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_CLI${NC}"
    ((FAILED++))
elif grep -q "runJsonMode" "$TARGET_CLI" 2>/dev/null; then
    # Check if this is our patch or an upstream fix
    if grep -q 'import { runJsonMode }' "$TARGET_CLI" 2>/dev/null && \
       grep -q '"system-prompt"' "$TARGET_CLI" 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ Already applied — skipping${NC}"
    else
        echo -e "  ${GREEN}⚠ Upstream fixed natively — skipping (no patch needed)${NC}"
    fi
    ((SKIPPED++))
elif grep -q '"--json"' "$TARGET_CLI" 2>/dev/null || \
     grep -qE 'json.*:.*\{.*type.*boolean' "$TARGET_CLI" 2>/dev/null; then
    # Author fixed it differently — --json is handled but not via runJsonMode import
    echo -e "  ${GREEN}⚠ Upstream already handles --json natively — skipping${NC}"
    echo -e "  ${YELLOW}  → You can remove this patch from apply-fix.sh if this persists across updates${NC}"
    ((SKIPPED++))
else
    cp "$TARGET_CLI" "${TARGET_CLI}.backup"
    echo -e "  ${GREEN}✓${NC} Backup: cli.js.backup"

    node -e "
const fs = require('fs');
const filePath = process.argv[1];
let code = fs.readFileSync(filePath, 'utf-8');

// 1. Add runJsonMode import after checkAndAutoUpdate import
code = code.replace(
    /import \{ checkAndAutoUpdate \}[^\n]+\n/,
    (m) => m + 'import { runJsonMode } from \"./modes/json-mode.js\";\n'
);

// 2. Replace parseArgs block to accept new flags
code = code.replace(
    'const { values } = parseArgs({\n        options: {\n            version: { type: \"boolean\", short: \"v\" },\n        },\n        allowPositionals: false,\n        strict: true,\n    });',
    'const { values, positionals } = parseArgs({\n        options: {\n            version: { type: \"boolean\", short: \"v\" },\n            json: { type: \"boolean\" },\n            provider: { type: \"string\" },\n            model: { type: \"string\" },\n            \"max-turns\": { type: \"string\" },\n            \"system-prompt\": { type: \"string\" },\n        },\n        allowPositionals: true,\n        strict: true,\n    });'
);

// 3. Insert JSON mode handler after the version check block
code = code.replace(
    /if \(values\.version\) \{[^}]+\}\n/,
    (m) => m + '    if (values.json) {\n        runJsonMode({\n            provider: values.provider ?? \"anthropic\",\n            model: values.model ?? \"claude-opus-4-6\",\n            maxTurns: values[\"max-turns\"] ? parseInt(values[\"max-turns\"], 10) : 10,\n            systemPrompt: values[\"system-prompt\"],\n            message: positionals.join(\" \"),\n            cwd: process.cwd(),\n        }).catch((err) => {\n            process.stderr.write(formatUserError(err) + \"\\\\n\");\n            process.exit(1);\n        });\n        return;\n    }\n'
);

fs.writeFileSync(filePath, code);
" "$TARGET_CLI" && {
        # Verify syntax
        if node -c "$TARGET_CLI" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Patch applied (syntax verified)"
            ((APPLIED++))
        else
            echo -e "  ${RED}✗ Patch produced invalid JS — restoring backup${NC}"
            cp "${TARGET_CLI}.backup" "$TARGET_CLI"
            ((FAILED++))
        fi
    } || {
        echo -e "  ${RED}✗ Patch failed — restoring backup${NC}"
        cp "${TARGET_CLI}.backup" "$TARGET_CLI"
        ((FAILED++))
    }
fi

# ============================================================
# Patch 4: Resilience — token refresh retry & connection errors
#   - oauth/anthropic.js: RefreshTokenInvalidError class + retry
#     loop with exponential backoff (3 attempts) for token refresh.
#     Immediate throw on invalid_grant (no retry).
#   - auth-storage.js: imports RefreshTokenInvalidError, clears
#     stored credentials when refresh token is permanently invalid.
#   - error-handler.js: adds handler for RefreshTokenInvalidError
#     before other auth checks.
#   - gg-agent/index.js: adds isConnectionError() function and
#     connection error retry with exponential backoff (1s/2s/4s).
# ============================================================
echo -e "${BLUE}[4/4] Resilience — token refresh retry & connection errors${NC}"

PATCH4_APPLIED=0
PATCH4_FAILED=0
PATCH4_SKIPPED=0
PATCH4_PARTS=4

# --- 4a: oauth/anthropic.js ---
TARGET_OAUTH="$PACKAGE_DIR/dist/core/oauth/anthropic.js"

if [ ! -f "$TARGET_OAUTH" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_OAUTH${NC}"
    ((PATCH4_FAILED++))
elif grep -q "RefreshTokenInvalidError" "$TARGET_OAUTH" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ oauth/anthropic.js — already applied${NC}"
    ((PATCH4_SKIPPED++))
else
    cp "$TARGET_OAUTH" "${TARGET_OAUTH}.backup"

    node -e "
const fs = require('fs');
const filePath = process.argv[1];
let code = fs.readFileSync(filePath, 'utf-8');

// Replace the simple refreshAnthropicToken with retry version + RefreshTokenInvalidError class
const oldFn = \`export async function refreshAnthropicToken(refreshToken) {
    const response = await fetch(TOKEN_URL, {
        method: \"POST\",
        headers: { \"Content-Type\": \"application/json\" },
        body: JSON.stringify({
            grant_type: \"refresh_token\",
            client_id: CLIENT_ID,
            refresh_token: refreshToken,
        }),
    });
    if (!response.ok) {
        const text = await response.text();
        throw new Error(\\\`Anthropic token refresh failed (\\\${response.status}): \\\${text}\\\`);
    }
    const data = (await response.json());
    return {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresAt: Date.now() + data.expires_in * 1000 - 5 * 60 * 1000,
    };
}\`;

const newFn = \`/**
 * Error thrown when the refresh token itself is invalid or revoked.
 * Callers should clear stored credentials and prompt re-login.
 */
export class RefreshTokenInvalidError extends Error {
    constructor(message) {
        super(message);
        this.name = \"RefreshTokenInvalidError\";
    }
}
const REFRESH_MAX_RETRIES = 3;
const REFRESH_BASE_DELAY_MS = 1_000;
export async function refreshAnthropicToken(refreshToken) {
    let lastError;
    for (let attempt = 0; attempt < REFRESH_MAX_RETRIES; attempt++) {
        try {
            const response = await fetch(TOKEN_URL, {
                method: \"POST\",
                headers: { \"Content-Type\": \"application/json\" },
                body: JSON.stringify({
                    grant_type: \"refresh_token\",
                    client_id: CLIENT_ID,
                    refresh_token: refreshToken,
                }),
            });
            if (!response.ok) {
                const text = await response.text();
                // invalid_grant means the refresh token is revoked/invalid — no point retrying
                if (response.status === 400 && text.includes(\"invalid_grant\")) {
                    throw new RefreshTokenInvalidError(\\\`Refresh token is invalid or revoked. Run \"ggcoder login\" to re-authenticate.\\\`);
                }
                // Server errors (5xx) and 429 are retryable
                if (response.status >= 500 || response.status === 429) {
                    lastError = new Error(\\\`Anthropic token refresh failed (\\\${response.status}): \\\${text}\\\`);
                    const delay = REFRESH_BASE_DELAY_MS * Math.pow(2, attempt);
                    await new Promise((r) => setTimeout(r, delay));
                    continue;
                }
                throw new Error(\\\`Anthropic token refresh failed (\\\${response.status}): \\\${text}\\\`);
            }
            const data = (await response.json());
            return {
                accessToken: data.access_token,
                refreshToken: data.refresh_token,
                expiresAt: Date.now() + data.expires_in * 1000 - 5 * 60 * 1000,
            };
        }
        catch (err) {
            // RefreshTokenInvalidError should not be retried
            if (err instanceof RefreshTokenInvalidError)
                throw err;
            lastError = err instanceof Error ? err : new Error(String(err));
            // Network errors (fetch failed, ECONNREFUSED, etc.) are retryable
            const msg = lastError.message.toLowerCase();
            const isNetworkError =
                msg.includes(\"fetch failed\") ||
                msg.includes(\"econnrefused\") ||
                msg.includes(\"enotfound\") ||
                msg.includes(\"etimedout\") ||
                msg.includes(\"network\") ||
                msg.includes(\"socket\");
            if (isNetworkError && attempt < REFRESH_MAX_RETRIES - 1) {
                const delay = REFRESH_BASE_DELAY_MS * Math.pow(2, attempt);
                await new Promise((r) => setTimeout(r, delay));
                continue;
            }
            throw lastError;
        }
    }
    throw lastError ?? new Error(\"Anthropic token refresh failed after retries\");
}\`;

if (code.includes(oldFn)) {
    code = code.replace(oldFn, newFn);
    fs.writeFileSync(filePath, code);
} else {
    process.exit(1);
}
" "$TARGET_OAUTH" && {
        echo -e "  ${GREEN}✓${NC} oauth/anthropic.js — patched"
        ((PATCH4_APPLIED++))
    } || {
        echo -e "  ${RED}✗ oauth/anthropic.js — patch failed, restoring${NC}"
        cp "${TARGET_OAUTH}.backup" "$TARGET_OAUTH"
        ((PATCH4_FAILED++))
    }
fi

# --- 4b: auth-storage.js ---
TARGET_AUTH="$PACKAGE_DIR/dist/core/auth-storage.js"

if [ ! -f "$TARGET_AUTH" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_AUTH${NC}"
    ((PATCH4_FAILED++))
elif grep -q "RefreshTokenInvalidError" "$TARGET_AUTH" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ auth-storage.js — already applied${NC}"
    ((PATCH4_SKIPPED++))
else
    cp "$TARGET_AUTH" "${TARGET_AUTH}.backup"

    node -e "
const fs = require('fs');
const filePath = process.argv[1];
let code = fs.readFileSync(filePath, 'utf-8');

// 1. Add RefreshTokenInvalidError to the import
code = code.replace(
    'import { refreshAnthropicToken } from \"./oauth/anthropic.js\";',
    'import { refreshAnthropicToken, RefreshTokenInvalidError } from \"./oauth/anthropic.js\";'
);

// 2. Replace the inline IIFE refresh with try/catch version
const oldRefresh = \`        const refreshPromise = (async () => {
            const refreshFn = provider === \"anthropic\" ? refreshAnthropicToken : refreshOpenAIToken;
            const refreshed = await refreshFn(creds.refreshToken);
            if (!refreshed.accountId && creds.accountId) {
                refreshed.accountId = creds.accountId;
            }
            this.data[provider] = refreshed;
            await this.save();
            return refreshed;
        })();\`;

const newRefresh = \`        const refreshPromise = (async () => {
            const refreshFn = provider === \"anthropic\" ? refreshAnthropicToken : refreshOpenAIToken;
            let refreshed;
            try {
                refreshed = await refreshFn(creds.refreshToken);
            }
            catch (err) {
                // If the refresh token is permanently invalid, clear stored credentials
                // so the user gets a clean \"not logged in\" error instead of repeated
                // refresh failures on every subsequent request.
                if (err instanceof RefreshTokenInvalidError) {
                    delete this.data[provider];
                    await this.save();
                }
                throw err;
            }
            if (!refreshed.accountId && creds.accountId) {
                refreshed.accountId = creds.accountId;
            }
            this.data[provider] = refreshed;
            await this.save();
            return refreshed;
        })();\`;

if (code.includes(oldRefresh)) {
    code = code.replace(oldRefresh, newRefresh);
    fs.writeFileSync(filePath, code);
} else {
    process.exit(1);
}
" "$TARGET_AUTH" && {
        echo -e "  ${GREEN}✓${NC} auth-storage.js — patched"
        ((PATCH4_APPLIED++))
    } || {
        echo -e "  ${RED}✗ auth-storage.js — patch failed, restoring${NC}"
        cp "${TARGET_AUTH}.backup" "$TARGET_AUTH"
        ((PATCH4_FAILED++))
    }
fi

# --- 4c: error-handler.js ---
TARGET_ERR="$PACKAGE_DIR/dist/utils/error-handler.js"

if [ ! -f "$TARGET_ERR" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_ERR${NC}"
    ((PATCH4_FAILED++))
elif grep -q "refresh token is invalid" "$TARGET_ERR" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ error-handler.js — already applied${NC}"
    ((PATCH4_SKIPPED++))
else
    cp "$TARGET_ERR" "${TARGET_ERR}.backup"

    node -e "
const fs = require('fs');
const filePath = process.argv[1];
let code = fs.readFileSync(filePath, 'utf-8');

// Insert RefreshTokenInvalidError check before the 'not logged in' check
code = code.replace(
    '    // Auth: not logged in\n    if (lowerMsg.includes(\"not logged in\")',
    '    // Auth: refresh token invalid/revoked (specific error from our OAuth flow)\n    if ((err instanceof Error && err.name === \"RefreshTokenInvalidError\") ||\n        lowerMsg.includes(\"refresh token is invalid or revoked\")) {\n        return chalk.red(\\'Session expired. Run \"ggcoder login\" to re-authenticate.\\');\n    }\n    // Auth: not logged in\n    if (lowerMsg.includes(\"not logged in\")'
);

fs.writeFileSync(filePath, code);
" "$TARGET_ERR" && {
        echo -e "  ${GREEN}✓${NC} error-handler.js — patched"
        ((PATCH4_APPLIED++))
    } || {
        echo -e "  ${RED}✗ error-handler.js — patch failed, restoring${NC}"
        cp "${TARGET_ERR}.backup" "$TARGET_ERR"
        ((PATCH4_FAILED++))
    }
fi

# --- 4d: gg-agent/index.js ---
TARGET_AGENT="$PACKAGE_DIR/node_modules/@kenkaiiii/gg-agent/dist/index.js"

if [ ! -f "$TARGET_AGENT" ]; then
    echo -e "  ${RED}✗ Target file not found: $TARGET_AGENT${NC}"
    ((PATCH4_FAILED++))
elif grep -q "isConnectionError" "$TARGET_AGENT" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ gg-agent/index.js — already applied${NC}"
    ((PATCH4_SKIPPED++))
else
    cp "$TARGET_AGENT" "${TARGET_AGENT}.backup"

    node -e "
const fs = require('fs');
const filePath = process.argv[1];
let code = fs.readFileSync(filePath, 'utf-8');

// 1. Add isConnectionError function after isOverloaded
const isConnectionFn = \`function isConnectionError(err) {
  if (!(err instanceof Error)) return false;
  const msg = err.message.toLowerCase();
  const name = err.name?.toLowerCase() ?? \"\";
  return name.includes(\"connectionerror\") || msg.includes(\"connection error\") || msg.includes(\"fetch failed\") || msg.includes(\"econnrefused\") || msg.includes(\"econnreset\") || msg.includes(\"enotfound\") || msg.includes(\"etimedout\") || msg.includes(\"socket hang up\") || msg.includes(\"network\");
}\`;

code = code.replace(
    'async function* agentLoop(messages, options) {',
    isConnectionFn + '\nasync function* agentLoop(messages, options) {'
);

// 2. Add connectionRetries counter
code = code.replace(
    '  let overloadRetries = 0;',
    '  let overloadRetries = 0;\n  let connectionRetries = 0;'
);

// 3. Add MAX_CONNECTION_RETRIES constant and base delay
code = code.replace(
    '  const OVERLOAD_RETRY_DELAY_MS = 3e3;',
    '  const OVERLOAD_RETRY_DELAY_MS = 3e3;\n  const MAX_CONNECTION_RETRIES = 3;\n  const CONNECTION_RETRY_BASE_MS = 1e3;'
);

// 4. Add connection error retry block after overload retry
code = code.replace(
    '      if (overloadRetries < MAX_OVERLOAD_RETRIES && isOverloaded(err)) {\n        overloadRetries++;\n        await new Promise((r) => setTimeout(r, OVERLOAD_RETRY_DELAY_MS));\n        turn--;\n        continue;\n      }\n      throw err;',
    '      if (overloadRetries < MAX_OVERLOAD_RETRIES && isOverloaded(err)) {\n        overloadRetries++;\n        await new Promise((r) => setTimeout(r, OVERLOAD_RETRY_DELAY_MS));\n        turn--;\n        continue;\n      }\n      if (connectionRetries < MAX_CONNECTION_RETRIES && isConnectionError(err)) {\n        connectionRetries++;\n        const delay = CONNECTION_RETRY_BASE_MS * Math.pow(2, connectionRetries - 1);\n        await new Promise((r) => setTimeout(r, delay));\n        turn--;\n        continue;\n      }\n      throw err;'
);

// 5. Reset connectionRetries alongside other counters
code = code.replace(
    '    overflowRetries = 0;\n    overloadRetries = 0;',
    '    overflowRetries = 0;\n    overloadRetries = 0;\n    connectionRetries = 0;'
);

fs.writeFileSync(filePath, code);
" "$TARGET_AGENT" && {
        echo -e "  ${GREEN}✓${NC} gg-agent/index.js — patched"
        ((PATCH4_APPLIED++))
    } || {
        echo -e "  ${RED}✗ gg-agent/index.js — patch failed, restoring${NC}"
        cp "${TARGET_AGENT}.backup" "$TARGET_AGENT"
        ((PATCH4_FAILED++))
    }
fi

# Roll up patch 4 results
if [ "$PATCH4_FAILED" -gt 0 ]; then
    echo -e "  ${RED}✗ Patch 4: ${PATCH4_APPLIED}/${PATCH4_PARTS} sub-patches applied, ${PATCH4_FAILED} failed${NC}"
    ((FAILED++))
elif [ "$PATCH4_APPLIED" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Patch 4: all ${PATCH4_APPLIED} sub-patches applied"
    ((APPLIED++))
else
    echo -e "  ${YELLOW}⚠ Patch 4: already applied — skipping${NC}"
    ((SKIPPED++))
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
