# ByeBye-OneDrive

Safely unhijack your Windows **Desktop, Documents, Pictures, Music, and Videos** folders from OneDrive with **zero data loss**, repair broken Windows Registry shell paths using the official Windows Known Folder API, and optionally restore classic "This PC" folders in Windows 11.

---

## Why ByeBye-OneDrive?

Most OneDrive removal scripts only uninstall the OneDrive client or delete registry keys without moving your files back or fixing Windows Known Folder paths — leaving your `Desktop`, `Documents`, and `Pictures` trapped inside `OneDrive\...` or broken altogether.

**ByeBye-OneDrive v2.1** is built around strict data safety:
* **No-Overwrite Smart Merge (SHA256):** Files are merged one by one. Identical files (verified via SHA256) are cleanly de-duplicated, while files with the same name but different content are preserved side by side as `filename (OneDrive).ext`.
* **Verified Before Removal:** Source files are only removed after the destination file is verified on disk.
* **Official Windows API (`SHSetKnownFolderPath`):** Uses `shell32.dll` to cleanly repoint folders back to `%USERPROFILE%`, with automatic Registry verification and fallback for both `User Shell Folders` and `Shell Folders`.
* **Atomic Per-Folder Guard:** A folder's Registry path is only repointed if **all** of its files migrated without errors.
* **Full Rollback (`Moves_*.csv` + `.reg`):** Automatically exports Registry backups (both `User Shell Folders` and `Shell Folders`) and logs every file move so you can restore both your paths and files.
* **Localized & Business OneDrive Support:** Reads source paths dynamically from the Registry — handles localized names and `"OneDrive - Company"` folders automatically.
* **Cloud-Only File Guard:** Detects online-only placeholder files before moving and lets you download & verify them locally first.
* **Preview / Dry-Run Mode:** Inspect file counts, sizes, name conflicts, and cloud-only files before touching anything.
* **Restore Classic 'This PC' Folders (Windows 11):** Optional companion tweak (`Restore-ThisPC-Folders.reg`) to bring the 6 user folders back above your drives.

---

## Menu Overview

```text
====================================================================
                       ByeBye-OneDrive v2.1                         
    Safe Folder Migration, Registry Repair & No-Overwrite Merge     
====================================================================
 [1] Unhijack Folders & Repair Registry Paths (Recommended)
 [2] Preview / Simulation Mode (Dry-Run / No Changes)
 [3] Completely Uninstall / Remove OneDrive Application
 [4] Undo / Rollback Changes (Registry + Files)
 [5] Restore Classic 'This PC' Folders (Windows 11)
 [0] Exit
====================================================================
```

---

## How to Use

1. Download the latest release ZIP from the [**Releases**](https://github.com/woguz/ByeBye-OneDrive/releases/latest) page and extract it.
2. Double-click **`Run.bat`** (or run `ByeBye-OneDrive.ps1` in PowerShell).
3. Select **[2] Preview / Simulation Mode** first to inspect what will be migrated without making any changes.
4. Select **[1] Unhijack Folders & Repair Registry Paths** to safely migrate your folders and repair your Windows paths.
