# GG Coder — Community Fixes & Guides

Community patches and documentation for [GG Coder](https://www.npmjs.com/package/@kenkaiiii/ggcoder) (`@kenkaiiii/ggcoder`) across all platforms.

## Why This Exists

GG Coder is great, but some platform-specific bugs and input race conditions can bite you. This repo provides drop-in fixes you can re-apply after every update.

## Quick Start

**One-liner — applies all patches:**

```bash
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/apply-fix.sh)
```

Then restart GG Coder.

## What Gets Fixed

### 1. WSL/Windows Image Path Support (`image.js`)

Image drag & drop from Windows Explorer is broken in WSL because Windows paths (`C:\Users\...`) aren't converted to WSL paths (`/mnt/c/Users/...`).

📖 [Full guide →](docs/windows-wsl.md)

### 2. Input Area Race Conditions (`InputArea.js`)

Three bugs in the terminal input component:

- **Stale cursor closure** — `setValue` callbacks captured `cursor` from render scope instead of reading current value. Typing fast or during async operations could insert/delete at the wrong position. Fixed with a `cursorRef` that `setCursor` keeps in sync, **plus a snapshot pattern** (`const pos = cursorRef.current`) before each `setCursor` call — because `setCursor` synchronously mutates the ref, but `setValue`'s functional updater runs later during React's render phase. Without the snapshot, backspace/typing would use the already-mutated ref and operate on the wrong position.

- **Async image extraction race** — `extractImagePaths()` runs async with a 300ms debounce. When the promise resolved, it called `setValue(cleanText)` with text derived from the *old* value, overwriting anything typed in the interim. Fixed with a functional `setValue` update that preserves new keystrokes.

- **Dictation misdetected as paste** — Voice dictation input (e.g. macOS dictation) arrives as multi-character chunks, triggering the paste detection heuristic (`input.length > 1`). This collapsed dictated text into a `[Pasted text]` badge. Fixed by raising the threshold to `input.length > 8` and requiring newlines for shorter chunks.

### 3. Task Toggle Keybinding

Changed from `~` (Shift+backtick) to `Ctrl+T` to avoid conflicts with normal typing.

## What's in the Box

```
├── patches/
│   ├── wsl-windows-paths.patch           # image.js diff
│   └── input-area-race-conditions.patch  # InputArea.js diff
├── scripts/
│   └── apply-fix.sh                      # Auto-detect install, backup, and patch all
├── docs/
│   ├── windows-wsl.md                    # Windows/WSL guide + troubleshooting
│   └── macos.md                          # macOS guide + tips
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
# Re-apply all patches:
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/apply-fix.sh)
```

## Tested With

- GG Coder v4.2.13
- Windows 11 + WSL2 (Ubuntu)
- Claude claude-opus-4-6 / claude-sonnet-4-6

## Contributing

Found a bug or have a fix for another platform? Open an issue or PR.

## Disclaimer

Unofficial community repo. Not affiliated with Ken Kai or the GG Coder project.
