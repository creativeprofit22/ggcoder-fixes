# Image Support on macOS

> **Good news:** macOS users likely don't need any patches. The built-in image support should work out of the box. This doc is here so you know what's available.

## What Already Works

### 1. Drag & Drop Files

Drag an image from Finder into your terminal — macOS pastes a native POSIX path like:

```
/Users/yourname/Downloads/screenshot.png
```

GG Coder auto-detects this (within ~300ms), reads the file, and shows an `[Image #1]` badge in the input area. Type your question and hit Enter — Claude sees the image.

### 2. Clipboard Paste (`Ctrl+I`)

This is a macOS-exclusive feature built into GG Coder:

1. Copy an image to your clipboard (screenshot with `Cmd+Shift+4`, copy from Preview, etc.)
2. In GG Coder, press **`Ctrl+I`**
3. The clipboard image gets captured and attached as `[Image #1]`
4. Type your question and hit Enter

This works via `osascript` under the hood — it reads `PNGf` or `TIFF` data from the system clipboard, saves to a temp file, base64-encodes it, and sends it to Claude.

### 3. Path in Message

Include an image path anywhere in your message:

```
what does this UI look like? ~/Desktop/mockup.png
```

Paths starting with `~/`, `./`, `/`, or `file://` are detected automatically.

## Supported Formats

**Images:** `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.bmp`

**Text files:** `.md`, `.txt` (attached as file content, not images)

## Multiple Images

You can attach multiple images in one message:

- Drag & drop several files (they paste as separate paths)
- Use `Ctrl+I` multiple times for clipboard images
- Mix paths and clipboard images

Each shows as `[Image #1]`, `[Image #2]`, etc.

## Tips

- **Screenshots → Claude:** The fastest workflow is `Cmd+Shift+4` (screenshot to clipboard) → switch to terminal → `Ctrl+I` → type question → Enter.

- **Retina displays:** Screenshots from retina Macs are high-res. Claude handles them fine, but if you're sending many images, be aware they use more tokens.

- **Path with spaces:** Paths like `/Users/John Smith/file.png` work — GG Coder handles the "entire input as single path" check first before splitting on spaces.

## If Something Isn't Working

**`Ctrl+I` does nothing:**
- This only works on macOS (`process.platform === "darwin"`). If you're SSH'd into a remote Linux box, you're running in a Linux context and clipboard paste won't work.

**Drag & drop path not detected:**
- Make sure the path is in the input box (not selected/highlighted elsewhere).
- The path must include `/` or `~` to be recognized. Bare filenames like `image.png` are ignored by design — use `./image.png`.

**"This model does not support image input":**
- Check which model you're using (`/model` in GG Coder). Claude models all support vision. If you've switched to a non-vision model, switch back.

## No Patch Needed (Probably)

macOS drag & drop produces POSIX paths that GG Coder handles natively. The `Ctrl+I` clipboard feature is macOS-only by design. If you're hitting an issue not covered here, please open an issue in this repo.
