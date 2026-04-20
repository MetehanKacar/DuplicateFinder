# Architecture Overview

## Stack

- Language: PowerShell
- UI: WinForms
- Thumbnail interop: C# Add-Type wrapper over Shell APIs

## High-level flow

1. User selects folder and scan options
2. Scanner collects matching media files by extension
3. Duplicate pipeline:
   - Group by file size
   - Fast MD5 over first 8 KB
   - Full-file MD5 for final confirmation
4. UI builds grouped list view incrementally (batch timer)
5. Thumbnails are lazy-loaded for visible items
6. User reviews and deletes selected files (Recycle Bin)

## Important runtime caches

- `ThumbCache`: thumbnail cache keyed by `path|WxH`
- `MediaViewCache`: grouped duplicate view per media mode
- `ModeRenderCache`: rendered ListView state per mode
- `PathToImageIndex`: mapping from file path to image list index

## UI layout

Main form contains:

- Top panel: folder controls + language switch
- Left panel: auto-select/filter controls
- Center: grouped ListView with checkboxes and thumbnails
- Right panel: preview + group thumbnails + quick open actions
- Bottom status bar + progress bar

## Deletion pipeline

1. Gather selected target files
2. Show optional delete preview dialog
3. Confirm action
4. Send each file to Recycle Bin via shell API
5. Fallback to direct remove if shell operation fails
6. Refresh duplicates and UI caches

## Swipe review mode

- Presents one media card at a time
- Tracks per-file decision (`keep` / `delete`)
- Supports keyboard-driven workflow
- Sends selected delete list into delete preview flow

## Design constraints

- Desktop-only (Windows)
- STA thread required for WinForms
- Duplicate detection targets exact binary duplicates
