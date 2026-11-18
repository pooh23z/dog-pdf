# MacWheel — Design Document

> Status: Ready for Approval  
> Target Workspace: `/Users/ppooh/.gemini/antigravity/scratch/MacWheel`  
> Reference Clip: `/Users/ppooh/Downloads/97B08009-0C8B-4F5D-82D2-65BE903FB7E5.MOV`

---

## 1. Intent & Why

Build a personal, **100% offline** macOS menu-bar utility inspired by *Tangerine: File Converter* and *NineWheel*.  
When dragging one or more files in Finder while holding a trigger key (default: `Shift`), a translucent radial wheel pops up right around the cursor with actions tailored to the dragged file types. Dropping onto a slice processes the file(s) locally and writes the output right next to the original file—with zero subscriptions, zero cloud uploads, and an added **Compress (ลดขนาดไฟล์)** capability across images, videos, and PDFs.

---

## 2. Goals, Non-Goals, Anti-Goals

### Goals
- **Finder Drag-Wheel UX:** Holding `Shift` (configurable) while dragging file(s) in Finder summons a centered radial wheel under the cursor; hovering highlights slices; releasing/dropping triggers the action.
- **Single, Multi-File & Mixed-File Support:**
  - Dragging multiple files of the same type batch-runs the selected action on all dragged files.
  - Dragging `2+ Images`, `2+ PDFs`, or `Images + PDFs` offers **`Merge PDF`**.
  - Dragging other mixed file types shows only the **strict intersection** of actions valid for *every* dragged file (or a clear "No shared actions" notice in the wheel center if none match).
- **Full Feature Parity + Compression:**
  - **Images** (`.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.tiff`, `.bmp`): Convert (`JPG`, `PNG`, `WEBP`, `PDF`), `Merge PDF` (when 2+ images), **Compress** (quality + max-dimension presets).
  - **PDF** (`.pdf`): Convert (`JPG` pages, `PNG` pages, `TXT`, `DOCX`), Translate (`→TH`, `→EN` → `.txt` output), `Merge PDF` (when 2+ PDFs or mixed with images), **Compress** (image downsampling + stream recompression). Automatic offline **Apple `Vision` OCR** fallback when a PDF has no embedded text layer (scanned PDFs).
  - **Documents** (`.docx`, `.rtf`, `.txt`, `.html`, `.md`): Convert (`PDF`, `DOCX`, `TXT`, `RTF`, `HTML`), Translate (`→TH`, `→EN` → `.txt` output, or `.srt` preserving timecodes for `.srt` files).
  - **Video / Audio** (`.mov`, `.mp4`, `.mkv`, `.m4v`, `.webm`, `.mp3`, `.m4a`, `.wav`): Convert (`MP4`, `MOV`, `MP3`, `M4A`, `GIF`), **Transcribe** (`.txt` + `.srt` subtitles in Thai/English via `whisper.cpp`), **Compress** (H.265/HEVC or H.264 size-reduction presets).
- **Menu-Bar Companion & Fallback Drop Zone:** Status-bar icon to toggle enabled state, pick trigger modifier (`Shift`, `Option`, `Control`), pick compression strength (`Balanced`, `Small`, `High Quality`), view active/recent jobs, check local dependencies (`ffmpeg`, `imagemagick`, `whisper-cli`, Whisper model, Apple Translation language packs), and open a persistent mini drop-target if needed.
- **Safe Output Placement:** Always save output right beside the source file (same directory), automatically de-duplicating filenames (`name (compressed).mp4`, `name EN.txt`, `name_pages/`, etc.).

### Non-Goals
- Cloud APIs, login/licensing, or Mac App Store sandboxing.
- Full timeline/document editing UI.
- Windows/Linux support (macOS Apple Silicon native only).
- Automatic folder-watching daemons.

### Anti-Goals
- **Never** send user files or text over the network during normal operation (100% offline execution; only an explicit user-triggered setup script may download `whisper.cpp`/models).
- **Never** overwrite or delete original source files.
- **Never** hijack normal Finder drag-and-drop when the trigger modifier key is not pressed.
- **Never** freeze the UI on large files; long jobs (video compression, Whisper transcription, long translation) must run asynchronously with a lightweight floating progress HUD.

---

## 3. Environment & Constraints

Verified on target Mac:
- **OS & Hardware:** macOS 27.0, Apple Silicon (`arm64`), 24 GB RAM.
- **Build Toolchain:** Apple Swift 6.4 (`swift` / `swiftc` via Xcode Command Line Tools; full Xcode IDE is *not* installed, so the project builds via **Swift Package Manager** and packages into a standard `.app` bundle via shell script).
- **Pre-installed CLI Tools:** `/opt/homebrew/bin/ffmpeg`, ImageMagick (`magick` / `convert`).
- **Tools Installed via Setup Script:** Homebrew `whisper.cpp` (`whisper-cli`) + GGML model (default `ggml-medium.bin` or lighter `ggml-small.bin` option for Thai+English); optional `pandoc` or `libreoffice` if installed for complex `.docx` → `.pdf` layouts (built-in macOS `textutil` / `NSAttributedString` works out of the box with no extra install).
- **Available macOS Frameworks:** `AppKit`, `SwiftUI`, `PDFKit`, `Vision`, `CoreImage`, `ImageIO`, `AVFoundation`, `Translation` (`Translation.framework`), `UserNotifications`.
- **Permissions:** Global drag + key-state observation across Finder requires **Accessibility** permission (`AXIsProcessTrusted`) and/or `CGEvent` tap / global `NSEvent` monitor.

---

## 4. Approaches Considered

| Approach | Summary | Trade-offs | Decision |
|---|---|---|---|
| **1. Native Swift/AppKit `.app` + `ffmpeg` / `imagemagick` + `whisper.cpp` + Apple `Translation`** | Pure macOS menu-bar app using SwiftPM; local CLI tools for media/compression/Whisper; macOS `Translation.framework` for offline `→TH`/`→EN`. | Requires one-time install of `whisper.cpp` + ~500MB–1.5GB Whisper model (and optionally `libreoffice` for complex `.docx`→`PDF`). Fast, native UI, accurate Thai/English transcription. | **Selected** |
| **2. Zero-Download macOS-Only (`SFSpeechRecognizer` + `textutil`)** | Avoids installing `whisper.cpp` or any extra CLI tools. | Weak Thai transcription / `.srt` timestamp quality on long videos; poor `.docx`→`PDF` layout. | Rejected |
| **3. Full Local AI Stack (`Ollama`/`MLX` LLM + `LibreOffice`)** | Replaces Apple `Translation` with a multi-GB local LLM. | Uses several GB of disk/RAM and translates much slower than Apple `Translation`. | Rejected |

---

## 5. Architecture & User Flows

### 5.1 Finder Drag Detection & Radial Wheel Overlay
```
  [Finder Drag Starts]
         │
         ▼
  Is MacWheel enabled & Trigger Key (Shift) held?
    ├── NO  ──► Do nothing (normal Finder drag)
    └── YES ──► Show translucent Floating Wheel Panel centered at cursor
                Panel acts as NSDraggingDestination ([.fileURL])
                     │
                     ▼
                draggingEntered inspects dragged file URLs & classifies wheel slices
                User drags cursor onto slice (slice lights up orange + label)
                     │
                     ├── Drops inside wheel center ("Cancel") or releases Shift / drops outside
                     │      ──► Dismiss wheel, no action
                     └── Drops on active slice
                            ──► Dismiss wheel, show compact HUD ("Processing…")
                            ──► Run Job async, write output beside source
                            ──► Notify completion + option to reveal in Finder
```

- Uses a borderless, transparent, non-activating `NSPanel` (`.floating` / `.screenSaver` level) acting as an `NSDraggingDestination` registered for `[.fileURL]`.
- Listens globally via `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .flagsChanged, .leftMouseUp])` (with Accessibility permission onboarding on first launch). When a drag is active with `Shift` held, the panel positions centered under the cursor so Finder's native drag immediately enters `draggingEntered(_:)` where `sender.draggingPasteboard` exposes the exact file URLs.

### 5.2 Radial Wheel UI Sketch
```
                [ Transcribe ]
           [ GIF ]          [ MP4 ]
               \     ●      /
     [ M4A ]  ──  ( file )  ──  [ MOV ]
               /   Cancel   \
           [ MP3 ]          [ Compress ]
```
- Translucent warm-amber/glass circular ring (~260×260 px) matching the Tangerine/NineWheel aesthetic; hovered slice highlights in bright orange with icon + label; center shows file count/type badge + `Cancel` zone.
- Slice sets (max 6–8 slices per wheel):
  - **Video (`.mov`, `.mp4`, etc.):** `MP4`, `MOV`, `MP3`, `M4A`, `GIF`, `Transcribe`, `Compress`
  - **Audio (`.mp3`, `.m4a`, `.wav`):** `MP3`, `M4A`, `WAV`, `Transcribe`, `Compress`
  - **Image (single):** `JPG`, `PNG`, `WEBP`, `PDF`, `Compress`
  - **Images (2+):** `Merge PDF`, `JPG`, `PNG`, `WEBP`, `Compress`
  - **PDF (single):** `Compress`, `JPG`, `PNG`, `DOCX`, `TXT`, `→TH`, `→EN`
  - **PDFs (2+) or Images + PDFs:** `Merge PDF`, `Compress`, `JPG`, `PNG`
  - **Document (`.docx`, `.txt`, `.rtf`, `.html`, `.md`):** `PDF`, `DOCX`, `TXT`, `RTF`, `HTML`, `→TH`, `→EN`
  - **Mixed Compatible (e.g., Video + Image):** Strict intersection of shared actions (e.g., `Compress`).

### 5.3 Processing Engines (100% Offline)

1. **Images (`CoreImage` / `ImageIO` + `ImageMagick`)**
   - `JPG` / `PNG` / `WEBP` / `PDF` conversion + `Merge PDF` (auto-oriented via `PDFKit`).
   - **Compress Image:** Re-encodes per preset (`Balanced`: quality 80, max edge 2560px; `Small`: quality 65, max edge 1920px; `High Quality`: quality 90, original size).

2. **PDF (`PDFKit` + `Vision` OCR + `CoreImage` / `ImageIO`)**
   - `JPG` / `PNG`: Renders each page at 200 DPI into `filename_pages/` (or beside original for 1-page PDFs).
   - `TXT` / `DOCX` / `→TH` / `→EN`: Extracts text via `PDFDocument.string`. If a page has no embedded text layer (scanned PDF), automatically runs offline Apple **`Vision` OCR** (`VNRecognizeTextRequest`, Thai + English).
   - **Compress PDF:** Downsamples embedded/page images per preset (`Balanced`: 150 DPI JPEG 75%; `Small`: 110 DPI JPEG 60%; `High Quality`: 220 DPI JPEG 85%) into a smaller PDF.

3. **Documents (`.docx`, `.rtf`, `.txt`, `.html`, `.md`)**
   - Converts between `DOCX`, `RTF`, `TXT`, `HTML`, `PDF` via macOS `NSAttributedString` / `/usr/bin/textutil` + `WKWebView`/PDF export (auto-upgrading to `soffice`/`pandoc` if detected).

4. **Video & Audio (`ffmpeg`)**
   - `MP4` / `MOV` / `MP3` / `M4A` / `GIF` (palette-optimized) + **Compress Video** using Apple Silicon hardware encoding (`hevc_videotoolbox` / `h264_videotoolbox`) per preset (`Balanced`: max 1080p; `Small`: max 720p; `High Quality`: original resolution).

5. **Transcribe (`whisper.cpp` / `whisper-cli`)**
   - Extracts 16 kHz mono WAV via `ffmpeg`, runs `whisper-cli` locally with Metal GPU acceleration (`-l auto` or chosen language), and writes **both** `filename.txt` and `filename.srt` beside the media file.

6. **Translate (`→TH` / `→EN` via Apple `Translation.framework`)**
   - Translates text extracted from `.txt`, `.md`, `.html`, `.rtf`, `.docx`, `.pdf`, or `.srt` (preserving timestamps for `.srt`) offline via `TranslationSession`.
   - Always writes a clean `<filename> TH.txt` or `<filename> EN.txt` (or `<filename> TH.srt` / `EN.srt` for subtitle files) beside the original so complex layouts never break.

---

## 6. Calls Made & What's Left to the Builder

### Calls Made (Please Review — Easy to Change Now)
- **Trigger key:** Hold `Shift` while dragging in Finder (configurable to `Option` or `Control` in Menu Bar settings).
- **Compression presets:** `Balanced` (default), `Small`, `High Quality`.
- **PDF translation & scanned PDFs:** `→TH` / `→EN` on PDF/DOCX outputs a clean `<name> TH.txt` / `<name> EN.txt` (like the reference clip), and scanned PDFs automatically use offline Apple `Vision` OCR when no text layer exists.
- **Multi-file & mixed-file drags:** Same-type drags run in batch; `Merge PDF` works on `2+ Images`, `2+ PDFs`, or `Images + PDFs`; other mixed drags show only actions supported by every dragged file (strict intersection).
- **Whisper output:** `Transcribe` produces both `.txt` and `.srt` files beside the media file.
- **Project location:** `/Users/ppooh/.gemini/antigravity/scratch/MacWheel`, packaged into `MacWheel.app` + `scripts/setup-deps.sh` for `whisper.cpp` & model download.

### Left to the Builder
- Exact visual styling constants (slice geometry, spring animations, glassmorphism colors, SF Symbols).
- Exact `ffmpeg` bitrate/CRF tuning per compression preset and PDF DPI thresholds.
- Chunking size and concurrency limits for `TranslationSession` and job queue.
- Automated tests for file-type routing, filename deduplication, and conversion pipelines.
