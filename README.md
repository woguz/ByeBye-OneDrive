# ByeBye-OneDrive

Safely unhijack your Windows **Desktop, Documents, Pictures, Music, and Videos** folders from OneDrive with **ZERO data loss**, repair broken Windows Registry shell paths, and optionally restore classic "This PC" folders in Windows 11.

---

## Why ByeBye-OneDrive?

Most OneDrive removal scripts online blindly delete registry keys or force-uninstall OneDrive without moving your files back. This often leads to missing Desktop icons, broken file paths, lost game saves, or corrupted application configurations.

**ByeBye-OneDrive** guarantees:
* **Zero Data Loss (Smart Merge):** Safely moves and merges files back to `%USERPROFILE%` using `robocopy` without overwriting existing local data.
* **Game & App Safe:** Stops OneDrive file locks first, migrates all app/game data, and updates Windows `User Shell Folders` & `Shell Folders` registry keys.
* **Automatic Registry Backup & Undo:** Automatically exports a `.reg` backup into `Backups/` before making changes, with a 1-click Rollback menu option.
* **Preview / Dry-Run Mode:** Inspect exactly what will be migrated before touching a single file.
* **Cloud-Only File Guard:** Detects online-only (placeholder) files and offers safe hydration before moving.
* **Restore 'This PC' Folders (Windows 11):** Companion option to bring back the 6 user folders above your drives in File Explorer.
* **Optional OneDrive Uninstaller:** Cleanly disables startup autorun and uninstalls the OneDrive app after your files are safely secured.

---

## Menu Overview

```text
====================================================================
                       ByeBye-OneDrive v2.0                         
    Safe Folder Migration, Registry Repair & Zero Data Loss Tool   
====================================================================
 [1] Unhijack Folders & Repair Registry Paths (Recommended)
 [2] Preview / Simulation Mode (Dry-Run / No Changes)
 [3] Completely Uninstall / Remove OneDrive Application
 [4] Undo / Rollback Changes (Restore from Backup)
 [5] Restore Classic 'This PC' Folders (Windows 11)
 [0] Exit
====================================================================
```

---

## How to Use

1. Download or clone this repository.
2. Double-click **`Run.bat`** (or run `ByeBye-OneDrive.ps1` in PowerShell).
3. Select **[2] Preview / Simulation Mode** first if you want to inspect your folders without making changes.
4. Select **[1] Unhijack Folders & Repair Registry Paths** to safely migrate everything and fix your paths.
