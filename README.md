# GG Coder — Image Support Fixes & Guides

Community patches and documentation for getting image support working properly in [GG Coder](https://www.npmjs.com/package/@kenkaiiii/ggcoder) (`@kenkaiiii/ggcoder`) across all platforms.

## Why This Exists

GG Coder has built-in image support — you can send images directly to Claude from your terminal. Claude's vision handles them perfectly. But depending on your platform, **getting the image from your filesystem into the request** can be broken or non-obvious.

This repo provides:
- 🔧 **Patches** for platform-specific bugs
- 📖 **Guides** so you actually know what features exist and how to use them

## Quick Start

### Windows / WSL Users

Image drag & drop is broken because Windows paths (`C:\Users\...`) aren't converted to WSL paths (`/mnt/c/Users/...`).

**One-liner fix:**

```bash
bash <(curl -sL https://raw.githubusercontent.com/OWNER/ggcoder-fixes/main/scripts/apply-fix.sh)
```

Then restart GG Coder. Drag & drop images from Windows Explorer — they just work now.

📖 [Full guide →](docs/windows-wsl.md)

### macOS Users

Image support works out of the box. You probably don't need patches — but you might not know about these features:

- **Drag & drop** image files from Finder into the terminal
- **`Ctrl+I`** to paste an image from your clipboard (screenshots, etc.)

📖 [Full guide →](docs/macos.md)

### Linux (Native) Users

Same as macOS for drag & drop — your terminal pastes POSIX paths and GG Coder handles them. Clipboard paste (`Ctrl+I`) is macOS-only for now.

## What's in the Box

```
├── patches/
│   └── wsl-windows-paths.patch   # Diff you can apply with `patch -p1`
├── scripts/
│   └── apply-fix.sh              # Auto-detect install, backup, and patch
├── docs/
│   ├── windows-wsl.md            # Windows/WSL guide + troubleshooting
│   └── macos.md                  # macOS guide + tips
└── README.md                     # You are here
```

## How Image Support Works (All Platforms)

1. You type or paste a file path in the GG Coder input box
2. After ~300ms, GG Coder checks if the path points to a real image file
3. If yes: reads the file, base64-encodes it, shows an `[Image #1]` badge, and removes the path from your text
4. When you hit Enter, the image is sent to Claude as a vision content block
5. Claude sees the image and responds

**Supported formats:** `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.bmp`
**Also attachable:** `.md`, `.txt` (sent as text content)

## After Updating GG Coder

```bash
npm update -g @kenkaiiii/ggcoder
```

This will overwrite any patches. Re-run the apply script:

```bash
bash scripts/apply-fix.sh
```

## Tested With

- GG Coder v4.2.13
- Windows 11 + WSL2 (Ubuntu)
- Claude claude-opus-4-6 / claude-sonnet-4-6

## Contributing

Found a bug or have a fix for another platform? Open an issue or PR. Keep it simple — one patch per issue.

## Disclaimer

This is an unofficial community repo. Not affiliated with Ken Kai or the GG Coder project. If these fixes prove useful, consider suggesting them upstream.
