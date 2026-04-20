# DuplicateFinder

A Windows desktop duplicate finder built with PowerShell and WinForms.

It scans images, videos, and audio files, groups true duplicates by hash, and helps you review and delete safely via Recycle Bin.

## Why this project

Many duplicate cleaners are either paid, overcomplicated, or not transparent about detection logic.
This tool is intentionally simple, local, and inspectable:

- No cloud upload
- No hidden service
- Clear duplicate logic (size + hash)
- Safe delete flow with preview and Recycle Bin

## Highlights

- Multi-media support: image, video, audio
- True duplicate detection (not name-based)
- Fast scan pipeline:
  - Size grouping
  - Fast MD5 on first 8 KB
  - Full-file MD5 verification
- Grouped visual browsing with thumbnails
- Bulk selection strategies:
  - Select 1 per group
  - Keep 1 per group
  - Select by specific folder
  - Select all / clear selection
- Swipe review mode for quick keep/delete decisions
- Pre-delete review dialog
- Recycle Bin delete support
- Responsive WinForms layout
- Turkish and English UI support (runtime switch)

## Supported formats

- Images: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif`, `.tiff`, `.tif`, `.webp`, `.ico`
- Videos: `.mp4`, `.avi`, `.mkv`, `.mov`, `.wmv`, `.flv`, `.webm`, `.m4v`, `.mpg`, `.mpeg`, `.3gp`, `.ts`
- Audio: `.mp3`, `.wav`, `.flac`, `.m4a`, `.aac`, `.ogg`, `.wma`, `.opus`, `.aiff`, `.amr`

## Requirements

- Windows 10/11
- Windows PowerShell 5.1+ (recommended)
- Script must run in STA mode for WinForms

## Quick start

1. Clone this repository.
2. Open Windows PowerShell.
3. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\DuplicateFinder.ps1
```

Notes:

- If started without STA, the script relaunches itself in STA mode when possible.
- If your execution policy blocks scripts, use the command above as-is.

## Usage

1. Click Select Folder.
2. Choose whether to include subfolders.
3. Click Scan.
4. Review duplicate groups.
5. Use filters or swipe review mode.
6. Delete selected files (sent to Recycle Bin).

## Language support

- Use the top-right language selector (`TR` / `EN`) at runtime.
- Static and dynamic UI texts are localized.
- Strategy and media filter logic is language-independent internally.

## Duplicate logic (important)

A file is considered duplicate only if:

1. File size matches
2. Fast MD5 (first 8 KB) matches
3. Full-file MD5 matches

This avoids false positives from filename-only checks.

## Safety model

- Delete flow includes preview and explicit confirmation.
- Files are sent to Recycle Bin first (best effort).
- If Recycle Bin API fails for a file, direct delete fallback is attempted.

## Known limitations

- This tool finds exact duplicates, not visually similar files.
- Different re-encodings or metadata-only variations may look similar but are not exact duplicates.
- Perceptual similarity mode (pHash/aHash) is not implemented yet.

## Repository structure

- `DuplicateFinder.ps1`: Main app
- `docs/ARCHITECTURE.md`: Technical design overview
- `docs/LOCALIZATION.md`: Localization system and how to extend
- `docs/RELEASE_CHECKLIST.md`: Pre-release and publishing checklist
- `.github/`: CI and contribution templates

## CI

GitHub Actions validates script syntax on each push and pull request.

## Contributing

Contributions are welcome.
Please read:

- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`

## Roadmap ideas

- Similarity mode for near-duplicates (perceptual hash)
- Export/import session decisions
- Saved scan profiles
- Optional metadata columns (duration, resolution, bitrate)

## License

MIT License. See `LICENSE`.
