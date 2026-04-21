# Duplicate File Finder & Cleaner for Windows (PowerShell + WinForms)

A fast, free, and open-source **Windows duplicate file remover and cleaner** built with PowerShell and WinForms.

It helps you find and remove duplicate files (images, videos, audio, and documents) using **hash-based detection**, and safely clean your system using **Recycle Bin protection**.

---

## 🚀 Why this project

Many duplicate file cleaners are:
- Paid or subscription-based
- Overcomplicated and slow
- Not transparent about detection logic

This tool is designed to be:
- ✔ Free and open-source
- ✔ Fully local (no cloud uploads)
- ✔ Transparent duplicate detection logic
- ✔ Safe file deletion with preview and Recycle Bin support

👉 A simple and effective **Windows duplicate file remover** focused on performance and clarity.

---

## ✨ Highlights

- 📁 Multi-media duplicate detection (images, videos, audio)
- ⚡ Fast scan pipeline:
  - File size grouping
  - Fast partial MD5 (first 8 KB)
  - Full-file MD5 verification
- 🔍 True duplicate detection using hash comparison (not filename-based)
- 🖼️ Visual grouped browsing with thumbnails
- ☑️ Smart bulk selection strategies:
  - Keep 1 per group
  - Select all duplicates
  - Select by folder
  - Clear selection
- 👆 Swipe-style review mode for fast decisions
- 🧾 Pre-delete confirmation dialog
- ♻️ Safe deletion via Windows Recycle Bin
- 🪟 Responsive WinForms UI
- 🌍 Turkish & English language support (runtime switch)

---

## 📁 Supported formats

Supports **Windows duplicate file cleanup** for:

### Images
`.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif`, `.tiff`, `.tif`, `.webp`, `.ico`

### Videos
`.mp4`, `.avi`, `.mkv`, `.mov`, `.wmv`, `.flv`, `.webm`, `.m4v`, `.mpg`, `.mpeg`, `.3gp`, `.ts`

### Audio
`.mp3`, `.wav`, `.flac`, `.m4a`, `.aac`, `.ogg`, `.wma`, `.opus`, `.aiff`, `.amr`

---

## 🧠 Duplicate detection logic (important)

This tool detects **true duplicate files on Windows** using a safe and accurate algorithm:

A file is considered duplicate only if:

1. File size matches  
2. Fast MD5 hash (first 8 KB) matches  
3. Full-file MD5 hash matches  

👉 This prevents false positives and ensures accurate **duplicate file detection using hashing (MD5)**.

---

## 🛡️ Safety model

- All deletions are reviewed before execution
- Files are sent to **Recycle Bin (preferred safe delete method)**
- Fallback direct delete only if Recycle Bin API fails
- No background services or hidden processes

---

## ⚠️ Known limitations

- Detects only **exact duplicates**, not similar files
- Does not yet support perceptual image matching (pHash/aHash)
- Metadata-only differences may not be detected as duplicates

---

## ⚙️ Requirements

- Windows 10 / Windows 11
- PowerShell 5.1+
- Must run in **STA mode** (for WinForms UI)

---

## 🚀 Quick start

1. Clone this repository  
2. Open Windows PowerShell  
3. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\DuplicateFinder.ps1
````

---

## 🌐 Run without cloning (optional)

Run directly from GitHub:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -Command "irm https://raw.githubusercontent.com/MetehanKacar/DuplicateFinder/main/DuplicateFinder.ps1 | iex"
```

⚠️ Note:

* This executes the latest version from `main`
* For safer usage, pin to a commit instead of branch

---

## 🧭 How to use

1. Select a folder
2. Enable subfolder scanning (optional)
3. Click **Scan**
4. Review duplicate groups
5. Select files using smart selection tools
6. Delete safely (Recycle Bin)

---

## 🌍 Language support

* Turkish / English UI switch available at runtime
* UI text is dynamically localized
* Core logic is language-independent

---

## 🧩 Repository structure

* `DuplicateFinder.ps1` → Main application
* `docs/ARCHITECTURE.md` → System design
* `docs/LOCALIZATION.md` → Localization system
* `docs/RELEASE_CHECKLIST.md` → Release workflow
* `.github/` → CI & contribution templates

---

## 🧪 CI

GitHub Actions automatically:

* Validates PowerShell syntax
* Checks script integrity on push and PR

---

## 🧠 Roadmap

Planned improvements:

* 🔮 Perceptual similarity detection (pHash / aHash)
* 📦 Save & restore scan sessions
* 🧾 Export scan reports (CSV / JSON)
* ⚡ Performance optimizations for large datasets
* 🖼️ Advanced media metadata columns (resolution, bitrate, duration)

---

## 🔑 Keywords

Windows duplicate file remover, duplicate file finder, duplicate file cleaner, remove duplicate files Windows 10, PowerShell duplicate finder, free duplicate file remover, disk cleanup tool Windows, media duplicate remover, file deduplication tool

---

## ⭐ Support

If this project helps you manage disk space and remove duplicate files efficiently:

⭐ Star the repository to support development

---

## 📄 License

MIT License — free to use and modify.
