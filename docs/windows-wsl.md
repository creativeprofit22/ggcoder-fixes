# Image Support on Windows (WSL)

## The Problem

GG Coder supports sending images to Claude directly from the terminal. Claude's vision capabilities handle them perfectly — the issue is **getting the image file from your Windows filesystem into the API request**.

When you drag & drop an image file into a WSL terminal, your terminal pastes a **Windows path** like:

```
c:/Users/YourName/Downloads/screenshot.png
C:\Users\YourName\Desktop\mockup.jpg
```

But GG Coder runs on Linux (WSL), where that file lives at:

```
/mnt/c/Users/YourName/Downloads/screenshot.png
```

The unpatched version doesn't convert Windows paths → WSL paths, so it can't find the file and silently ignores it.

## The Fix

A small patch to `dist/utils/image.js` that:

1. **Detects Windows-style paths** (`C:\...`, `c:/...`, `D:\...`)
2. **Converts them to WSL mount paths** (`/mnt/c/...`, `/mnt/d/...`)
3. **Preserves backslashes** in Windows paths instead of treating them as escape characters
4. **Recognizes drive letters** (`C:`) as path indicators

## How to Apply

### Option A: One-liner (easiest)

```bash
bash <(curl -sL https://raw.githubusercontent.com/OWNER/ggcoder-fixes/main/scripts/apply-fix.sh)
```

### Option B: Clone and run

```bash
git clone https://github.com/OWNER/ggcoder-fixes.git
cd ggcoder-fixes
bash scripts/apply-fix.sh
```

### Option C: Manual patch

1. Find your ggcoder install:
   ```bash
   readlink -f $(which ggcoder)
   # Example output: /home/you/.npm-global/lib/node_modules/@kenkaiiii/ggcoder/dist/cli.js
   ```

2. Navigate to the package:
   ```bash
   cd /home/you/.npm-global/lib/node_modules/@kenkaiiii/ggcoder
   ```

3. Backup the file:
   ```bash
   cp dist/utils/image.js dist/utils/image.js.backup
   ```

4. Apply the patch:
   ```bash
   patch -p1 < /path/to/ggcoder-fixes/patches/wsl-windows-paths.patch
   ```

5. Restart ggcoder.

## How to Use Images (After Patching)

### Drag & Drop

1. Drag an image file from Windows Explorer into your terminal
2. The Windows path gets pasted into the input box
3. Wait ~300ms — GG Coder auto-detects it, reads the file, and shows an `[Image #1]` badge
4. Type your question (or just hit Enter)
5. Claude sees the image and responds

### By Path

Type or paste a path directly in your message:

```
what's in this image? c:/Users/Me/Downloads/screenshot.png
```

All these formats work after patching:

| Format | Example |
|--------|---------|
| Forward slashes | `c:/Users/Me/pic.png` |
| Backslashes | `C:\Users\Me\pic.png` |
| Quoted | `'c:/Users/Me/pic.png'` |
| WSL native | `/mnt/c/Users/Me/pic.png` |

### Supported Image Formats

`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.bmp`

You can also attach text files: `.md`, `.txt`

## After npm Update

Running `npm update -g @kenkaiiii/ggcoder` will overwrite the fix. Just re-run the apply script afterward.

## Troubleshooting

**Image not detected?**
- Make sure the path contains `/`, `\`, or starts with a drive letter. Bare filenames like `image.png` won't be picked up — use `./image.png` or the full path.

**File not found?**
- Check that the Windows drive is mounted in WSL: `ls /mnt/c/` should show your C: drive contents.
- Some custom WSL configs mount drives elsewhere — check `/etc/wsl.conf` for `[automount]` settings.

**Multiple images?**
- You can include multiple paths in one message. Each gets auto-detected and attached.
