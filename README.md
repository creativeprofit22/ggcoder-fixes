# GG Coder — Community Fixes & Guides

Community patches, optimized agent configs, and documentation for [GG Coder](https://www.npmjs.com/package/@kenkaiiii/ggcoder) (`@kenkaiiii/ggcoder`) across all platforms.

## Why This Exists

GG Coder is great, but some platform-specific bugs and input handling issues can bite you, and the default install ships with no agent definitions — meaning subagents all run on your expensive parent model with no tool restrictions. This repo provides drop-in fixes and optimized configs you can re-apply after every update.

## Quick Start

**Apply all patches (image + input fixes):**

```bash
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/apply-fix.sh)
```

**Install optimized agent configs:**

```bash
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/install-agents.sh)
```

Then restart GG Coder.

## What's Included

### 1. Optimized Agent Definitions

Four agent definitions that give GG Coder's subagent tool actual structure instead of spawning expensive clones of itself:

| Agent | Model | Tools | Purpose |
|-------|-------|-------|---------|
| **scout** | Haiku (cheapest) | read, grep, find, ls, bash | Fast read-only codebase search. 10 tool call limit. |
| **runner** | Haiku (cheapest) | bash, read | Execute commands, report results. Never modifies files. |
| **worker** | Inherits parent | all | Complex multi-step tasks — explore, edit, verify. 30 turn cap. |
| **fork** | Inherits parent | all | Parallel execution. Structured output format. 30 turn cap. |

Plus an optimized `CLAUDE.md` that cuts ~300 tokens/turn by replacing verbose routing tables with two lines.

📖 [Full guide →](docs/agents.md)

### 2. WSL/Windows Image Path Support (`image.js`)

Image drag & drop from Windows Explorer is broken in WSL because Windows paths (`C:\Users\...`) aren't converted to WSL paths (`/mnt/c/Users/...`).

📖 [Full guide →](docs/windows-wsl.md)

### 3. Input Area Fixes (`InputArea.js`)

Four bugs in the terminal input component, plus a keybinding change:

- **Stale cursor in setValue callbacks** — `setValue` functional updaters captured `cursor` from render scope, so typing fast or during async operations would insert/delete at the wrong position. Fixed by introducing a `cursorRef` that `setCursor` keeps in sync, with a **snapshot pattern** (`const pos = cursorRef.current`) taken *before* each `setCursor` call. This is critical because `setCursor` synchronously mutates the ref, but `setValue`'s functional updater runs later during React's render phase — without the snapshot, backspace deletes the wrong character, typing inserts at the wrong position, and Shift+Enter places the newline incorrectly.

- **Async image extraction race** — `extractImagePaths()` runs async with a 300ms debounce. When the promise resolved, it called `setValue(cleanText)` with text derived from the *old* value, overwriting anything typed in the interim. Fixed with a functional `setValue` update that preserves new keystrokes.

- **Dictation misdetected as paste** — Voice dictation input (e.g. macOS dictation) arrives as multi-character chunks, triggering the paste detection heuristic (`input.length > 1`). This collapsed dictated text into a `[Pasted text]` badge. Fixed by raising the threshold to `input.length > 8` and requiring newlines for shorter chunks.

- **Task toggle keybinding** — Changed from `~` (Shift+backtick) to `Ctrl+T` to avoid conflicts with normal typing.

### 4. Sub-Agent Spawning Fix (`cli.js`)

`cli.js` didn't accept the `--json`, `--provider`, `--model`, `--max-turns`, `--system-prompt` flags that the `subagent` tool passes when spawning child processes, causing all sub-agents to crash immediately with `ERR_PARSE_ARGS_UNKNOWN_OPTION`. The fix adds these flags to `parseArgs` and wires up the existing `runJsonMode()` from `modes/json-mode.js`.

### 5. Resilience: Token Refresh & Connection Retry

Two issues that cause frequent session crashes, especially on unstable networks or long sessions:

- **Token refresh has zero retries** — `refreshAnthropicToken()` uses raw `fetch()` with no retry logic. Any transient 5xx from Anthropic's OAuth server, or a brief network blip during token refresh, kills the entire session. Worse, when the refresh token is permanently revoked (`invalid_grant`), the error message is a raw JSON dump that repeats on every subsequent request since the dead token stays in `auth.json`.

- **Connection errors aren't retried in the agent loop** — The Anthropic SDK throws `ConnectionError` on network failures, but the agent loop only retries overload/rate-limit errors. A single dropped packet during a multi-turn session with dozens of tool calls kills the whole conversation.

**What the fix does:**
- `oauth/anthropic.js`: Adds `RefreshTokenInvalidError` class + retry loop (3 attempts, exponential backoff) for server/network errors. On permanent `invalid_grant`: throws immediately with clear message.
- `auth-storage.js`: Catches `RefreshTokenInvalidError` and clears the dead token from `auth.json` so subsequent requests get "not logged in" instead of repeated refresh failures.
- `error-handler.js`: Clean user-facing message: `Session expired. Run "ggcoder login" to re-authenticate.`
- `gg-agent/index.js`: Adds `isConnectionError()` detector + retry with exponential backoff (1s → 2s → 4s, 3 attempts) for connection errors during LLM streaming.

## What's in the Box

```
├── agents/
│   ├── scout.md                             # Read-only search agent (Haiku)
│   ├── runner.md                            # Command execution agent (Haiku)
│   ├── worker.md                            # Full-capability agent (inherits model)
│   ├── fork.md                              # Parallel execution agent (inherits model)
│   └── CLAUDE.md                            # Optimized CLAUDE.md template
├── patches/
│   ├── wsl-windows-paths.patch              # image.js diff
│   ├── input-area-race-conditions.patch     # InputArea.js diff
│   ├── cli-subagent-flags.patch             # cli.js diff
│   └── resilience-token-refresh-connection.patch  # oauth + agent-loop resilience
├── scripts/
│   ├── apply-fix.sh                         # Auto-detect install, backup, and patch all
│   └── install-agents.sh                    # Install agent configs to ~/.gg/agents/
├── docs/
│   ├── agents.md                            # Agent config guide + token optimization
│   ├── windows-wsl.md                       # Windows/WSL guide + troubleshooting
│   └── macos.md                             # macOS guide + tips
└── README.md
```

## How Image Support Works (All Platforms)

1. You type or paste a file path in the GG Coder input box
2. After ~300ms, GG Coder checks if the path points to a real image file
3. If yes: reads the file, base64-encodes it, shows an `[Image #1]` badge, and removes the path from your text
4. When you hit Enter, the image is sent to Claude as a vision content block

**Supported formats:** `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.bmp`
**Also attachable:** `.md`, `.txt` (sent as text content)

## After Updating GG Coder

```bash
npm update -g @kenkaiiii/ggcoder
# Re-apply patches:
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/apply-fix.sh)
# Re-install agents (only needed if you deleted ~/.gg/agents/):
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/install-agents.sh)
```

Agent configs live in `~/.gg/agents/` and survive GG Coder updates — you only need to re-run `install-agents.sh` if you deleted them or want to pull newer versions.

## Tested With

- GG Coder v4.2.24 / v4.2.25
- Windows 11 + WSL2 (Ubuntu)
- Opus 4.6 / Sonnet 4.6

## Contributing

Found a bug or have a fix for another platform? Open an issue or PR.

## Disclaimer

Unofficial community repo. Not affiliated with Ken Kai or the GG Coder project.
