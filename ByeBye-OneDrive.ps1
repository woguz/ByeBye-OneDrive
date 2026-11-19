<#
.SYNOPSIS
    ByeBye-OneDrive v2.1 - Windows Personal Folder Unhijacker & Path Restorer
.DESCRIPTION
    Moves Desktop, Documents, Pictures, Music and Videos from OneDrive back to the
    local user profile WITHOUT overwriting anything:
      - Files are merged one by one; identical files (SHA256) are de-duplicated,
        different files with the same name are kept side by side (renamed).
      - A source file is only removed after the copy at the destination is verified.
      - A folder's registry path is only repointed if ALL of its files moved fine.
      - Registry is backed up (both User Shell Folders and Shell Folders) and every
        file move is logged, so both registry and files can be rolled back.
    Source folders are read from the registry, so localized or business
    OneDrive paths ("OneDrive - Company", "Masaustu", ...) are handled.
.LICENSE
    MIT License
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ByeBye-OneDrive v2.1 - Windows Folder Unhijacker"

# ----------------------------------------------------------------------------
# Global paths & definitions
# ----------------------------------------------------------------------------
$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $scriptDir = $null }
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$backupDir = Join-Path $scriptDir "Backups"

$usfKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$sfKey  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"

# GUID   = legacy value name that may exist inside User Shell Folders (only touched if present)
# KFID   = real Known Folder ID used with SHSetKnownFolderPath
$targetFolders = @(
    @{ Name = "Desktop";   USFName = "Desktop";     GUID = $null;                                     KFID = "B4BFCC3A-DB2C-424C-B029-7FE99A87C641" },
    @{ Name = "Documents"; USFName = "Personal";    GUID = "{F42EE2D3-909F-4907-8871-4C22FC0BF756}";  KFID = "FDD39AD0-238F-46AF-ADB4-6C85480369C7" },
    @{ Name = "Pictures";  USFName = "My Pictures"; GUID = "{0DDD015D-B06C-45D5-8C4C-F59713854639}";  KFID = "33E28130-4E1E-4676-835A-98395C3BC3BB" },
    @{ Name = "Music";     USFName = "My Music";    GUID = "{A0C69A99-21C8-4671-8703-7934162FCF1D}";  KFID = "4BD8D571-6D19-48D3-BE97-422220080E43" },
    @{ Name = "Videos";    USFName = "My Video";    GUID = "{35286A68-3C57-41A1-BBB1-0EAE73D76C95}";  KFID = "18989B1D-99B5-455B-841C-AB7C74E4DDFC" }
)

# Cloud-only / placeholder attribute flags
$FILE_ATTRIBUTE_OFFLINE              = 0x1000
$FILE_ATTRIBUTE_RECALL_ON_OPEN       = 0x40000
$FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x400000
$cloudMask = $FILE_ATTRIBUTE_OFFLINE -bor $FILE_ATTRIBUTE_RECALL_ON_OPEN -bor $FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS

# SHSetKnownFolderPath wrapper
if (-not ("KnownFolderNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class KnownFolderNative {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, [MarshalAs(UnmanagedType.LPWStr)] string pszPath);
}
"@
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Pause-Console {
    param([string]$Message = "Press Enter to return to menu...")
    Write-Host "`n$Message" -ForegroundColor Yellow
    try { $null = Read-Host } catch {}
}

function Ask-YesNo {
    param([string]$Question)
    $a = Read-Host "$Question (Y/N)"
    return ($a -eq 'Y' -or $a -eq 'y')
}

function Get-OneDriveRoots {
    $roots = @()
    foreach ($p in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial, (Join-Path $userProfile "OneDrive"))) {
        if ($p -and (Test-Path -LiteralPath $p) -and ($roots -notcontains $p)) { $roots += $p }
    }
    return $roots
}

function Test-InOneDrive {
    param([string]$Path)
    if (-not $Path) { return $false }
    foreach ($r in (Get-OneDriveRoots)) {
        if ($Path.TrimEnd('\') -like ($r.TrimEnd('\') + "\*") -or $Path.TrimEnd('\') -ieq $r.TrimEnd('\')) { return $true }
    }
    return ($Path -match '\\OneDrive[^\\]*(\\|$)')
}

function Show-Header {
    Clear-Host
    $roots = (Get-OneDriveRoots) -join "; "
    if (-not $roots) { $roots = "(not found)" }
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "                       ByeBye-OneDrive v2.1                         " -ForegroundColor White
    Write-Host "    Safe Folder Migration, Registry Repair & No-Overwrite Merge     " -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " User Profile : $userProfile" -ForegroundColor Gray
    Write-Host " OneDrive     : $roots" -ForegroundColor Gray
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Restart-Explorer {
    Write-Host "`n[*] Refreshing Windows Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }
}

# Returns the list of folders that are currently redirected into OneDrive.
function Get-MigrationPlan {
    $plan = @()
    foreach ($f in $targetFolders) {
        $raw = (Get-ItemProperty -Path $usfKey -Name $f.USFName -ErrorAction SilentlyContinue).($f.USFName)
        if (-not $raw) { continue }
        $src = [Environment]::ExpandEnvironmentVariables($raw)
        $dst = Join-Path $userProfile $f.Name
        if ($src.TrimEnd('\') -ieq $dst.TrimEnd('\')) { continue }
        if (-not (Test-InOneDrive $src)) { continue }
        $plan += [pscustomobject]@{ Folder = $f; Source = $src; Dest = $dst }
    }
    return $plan
}

# ----------------------------------------------------------------------------
# Backup
# ----------------------------------------------------------------------------
function Create-RegistryBackup {
    param([string]$Stamp)
    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }

    Write-Host "`n[*] Creating registry backup..." -ForegroundColor Yellow
    $usfFile = Join-Path $backupDir "Registry_Backup_${Stamp}_USF.reg"
    $sfFile  = Join-Path $backupDir "Registry_Backup_${Stamp}_SF.reg"

    & reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" "$usfFile" /y | Out-Null
    $ok1 = ($LASTEXITCODE -eq 0) -and (Test-Path $usfFile)
    & reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" "$sfFile" /y | Out-Null
    $ok2 = ($LASTEXITCODE -eq 0) -and (Test-Path $sfFile)

    if ($ok1 -and $ok2) {
        Write-Host "[+] Registry backups saved:" -ForegroundColor Green
        Write-Host "    $usfFile" -ForegroundColor Gray
        Write-Host "    $sfFile" -ForegroundColor Gray
        return $true
    }
    Write-Host "[!] Could not create the registry backup." -ForegroundColor Red
    return (Ask-YesNo "Continue WITHOUT a registry backup?")
}

# ----------------------------------------------------------------------------
# Cloud-only file handling
# ----------------------------------------------------------------------------
function Get-CloudFiles {
    param([string[]]$Paths)
    $result = @()
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $result += Get-ChildItem -LiteralPath $p -Force -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { (([int]$_.Attributes) -band $cloudMask) -ne 0 }
    }
    return $result
}

# Returns $true if it is safe to continue.
function Check-CloudFiles {
    param([string[]]$Paths)
    Write-Host "`n[*] Inspecting OneDrive files status..." -ForegroundColor Cyan

    $total = 0
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p) {
            $total += (Get-ChildItem -LiteralPath $p -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        }
    }
    $cloudOnly = @(Get-CloudFiles $Paths)
    $cloudCount = $cloudOnly.Count

    Write-Host "    Total Files Found: $total" -ForegroundColor Gray
    if ($cloudCount -gt 0) { $col = "Yellow" } else { $col = "Green" }
    Write-Host "    Cloud-Only Files : $cloudCount" -ForegroundColor $col

    if ($cloudCount -eq 0) {
        Write-Host "[+] All files are available locally. Safe to migrate!" -ForegroundColor Green
        return $true
    }

    Write-Host "`n[!] $cloudCount file(s) exist only in the cloud and are NOT on your disk!" -ForegroundColor Yellow
    Write-Host "  [1] Download them now and verify (Recommended)" -ForegroundColor Cyan
    Write-Host "  [2] Abort migration" -ForegroundColor Yellow
    Write-Host "  [3] Proceed anyway (cloud-only files will be left behind in OneDrive)" -ForegroundColor Red
    $c = Read-Host "`nSelect an option (1/2/3)"

    if ($c -eq '1') {
        Write-Host "`n[*] Downloading cloud files, please wait..." -ForegroundColor Cyan
        $i = 0
        foreach ($cf in $cloudOnly) {
            $i++
            Write-Progress -Activity "Downloading cloud files" -Status "$i / $cloudCount" -PercentComplete (($i / $cloudCount) * 100)
            try {
                $fs = [System.IO.File]::Open($cf.FullName, 'Open', 'Read', 'ReadWrite')
                try { $fs.CopyTo([System.IO.Stream]::Null) } finally { $fs.Close() }
            } catch {}
        }
        Write-Progress -Activity "Downloading cloud files" -Completed
        $still = @(Get-CloudFiles $Paths).Count
        if ($still -eq 0) {
            Write-Host "[+] All files downloaded to your local disk!" -ForegroundColor Green
            return $true
        }
        Write-Host "[!] $still file(s) could not be downloaded (check connection / OneDrive state)." -ForegroundColor Red
        Write-Host "    Migration halted to prevent data loss." -ForegroundColor Yellow
        return $false
    }
    elseif ($c -eq '3') {
        return $true
    }
    return $false
}

# ----------------------------------------------------------------------------
# Safe merge (never overwrites, verifies before deleting)
# ----------------------------------------------------------------------------
function Get-UniqueTargetPath {
    param([string]$Path)
    $dir  = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [System.IO.Path]::GetExtension($Path)
    $n = 1
    do {
        if ($n -eq 1) { $suffix = " (OneDrive)" } else { $suffix = " (OneDrive $n)" }
        $candidate = Join-Path $dir ($base + $suffix + $ext)
        $n++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Write-MoveLog {
    param([string]$LogFile, [string]$Type, [string]$Source, [string]$Target)
    [pscustomobject]@{ Type = $Type; Source = $Source; Target = $Target } |
        Export-Csv -Path $LogFile -Append -NoTypeInformation -Encoding UTF8
}

function Merge-Folder {
    param([string]$Source, [string]$Dest, [string]$LogFile)

    $stats = [pscustomobject]@{ Moved = 0; Duplicates = 0; Renamed = 0; Failed = 0 }
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -Path $Dest -ItemType Directory -Force | Out-Null }

    $srcFull = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $srcFull -Force -Recurse -File -ErrorAction SilentlyContinue)
    $i = 0
    foreach ($file in $files) {
        $i++
        if ($i % 25 -eq 0 -or $i -eq $files.Count) {
            Write-Progress -Activity "Merging $(Split-Path -Leaf $Dest)" -Status "$i / $($files.Count)" -PercentComplete (($i / [math]::Max(1,$files.Count)) * 100)
        }

        $rel    = $file.FullName.Substring($srcFull.Length).TrimStart('\')
        $target = Join-Path $Dest $rel
        $tDir   = Split-Path -Parent $target

        try {
            if (-not (Test-Path -LiteralPath $tDir)) { New-Item -Path $tDir -ItemType Directory -Force | Out-Null }

            if (-not (Test-Path -LiteralPath $target)) {
                Move-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop
                if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $file.FullName)) {
                    $stats.Moved++
                    Write-MoveLog $LogFile "MOVE" $file.FullName $target
                } else { throw "Move verification failed" }
                continue
            }

            # Target exists: compare
            $tItem = Get-Item -LiteralPath $target -Force
            $same = $false
            if ($tItem.Length -eq $file.Length) {
                $h1 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $h2 = (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
                $same = ($h1 -eq $h2)
            }

            if ($same -or $file.Name -ieq "desktop.ini") {
                # identical copy already exists locally (or just a folder-config file)
                Write-MoveLog $LogFile "DUP" $file.FullName $target
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $stats.Duplicates++
            } else {
                # same name, different content: keep BOTH
                $newTarget = Get-UniqueTargetPath $target
                Move-Item -LiteralPath $file.FullName -Destination $newTarget -ErrorAction Stop
                if ((Test-Path -LiteralPath $newTarget) -and -not (Test-Path -LiteralPath $file.FullName)) {
                    $stats.Renamed++
                    Write-MoveLog $LogFile "MOVE" $file.FullName $newTarget
                } else { throw "Move verification failed" }
            }
        } catch {
            $stats.Failed++
            Write-Host "    [!] Could not move: $($file.FullName)" -ForegroundColor Red
            Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    }
    Write-Progress -Activity "Merging" -Completed

    # Remove only EMPTY leftover directories (deepest first); never recurse-delete
    $dirs = @(Get-ChildItem -LiteralPath $srcFull -Directory -Force -Recurse -ErrorAction SilentlyContinue |
              Sort-Object { $_.FullName.Length } -Descending)
    foreach ($d in $dirs) {
        if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return $stats
}

# ----------------------------------------------------------------------------
# Registry / known folder repointing
# ----------------------------------------------------------------------------
function Set-LocalFolderPath {
    param($Folder, [string]$LocalPath)

    if (-not (Test-Path -LiteralPath $LocalPath)) { New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null }

    # Preferred: official API (also updates Shell Folders and notifies the shell)
    $hr = -1
    try {
        $g = [Guid]$Folder.KFID
        $hr = [KnownFolderNative]::SHSetKnownFolderPath([ref]$g, 0, [IntPtr]::Zero, $LocalPath)
    } catch {}

    # Verify; fall back to direct registry writes if needed
    $cur = (Get-ItemProperty -Path $usfKey -Name $Folder.USFName -ErrorAction SilentlyContinue).($Folder.USFName)
    $curExpanded = ""
    if ($cur) { $curExpanded = [Environment]::ExpandEnvironmentVariables($cur) }
    $expandPath = "%USERPROFILE%\$($Folder.Name)"

    if ($hr -ne 0 -or ($curExpanded.TrimEnd('\') -ine $LocalPath.TrimEnd('\'))) {
        Set-ItemProperty -Path $usfKey -Name $Folder.USFName -Value $expandPath -Type ExpandString -Force
        Set-ItemProperty -Path $sfKey  -Name $Folder.USFName -Value $LocalPath  -Type String -Force
    }

    # Legacy GUID value: only fix it if it already exists
    if ($Folder.GUID) {
        $existing = Get-ItemProperty -Path $usfKey -Name $Folder.GUID -ErrorAction SilentlyContinue
        if ($existing) {
            Set-ItemProperty -Path $usfKey -Name $Folder.GUID -Value $expandPath -Type ExpandString -Force
        }
    }
    Write-Host "    [OK] Repointed: $($Folder.Name) -> $LocalPath" -ForegroundColor Green
}

# ----------------------------------------------------------------------------
# Dry run
# ----------------------------------------------------------------------------
function Invoke-DryRun {
    Show-Header
    Write-Host "`n>>> PREVIEW / SIMULATION MODE (No changes will be made) <<<" -ForegroundColor Yellow

    $plan = @(Get-MigrationPlan)
    if ($plan.Count -eq 0) {
        Write-Host "`n[+] No personal folder is currently redirected into OneDrive. Nothing to do." -ForegroundColor Green
        Pause-Console
        return
    }

    foreach ($p in $plan) {
        Write-Host "`n[+] Folder: $($p.Folder.Name)" -ForegroundColor White
        if (-not (Test-Path -LiteralPath $p.Source)) {
            Write-Host "    Source path does not exist: $($p.Source)" -ForegroundColor Red
            continue
        }
        $items = @(Get-ChildItem -LiteralPath $p.Source -Force -Recurse -File -ErrorAction SilentlyContinue)
        $sizeMB = [math]::Round((($items | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
        $conflicts = 0
        $srcFull = (Resolve-Path -LiteralPath $p.Source).ProviderPath.TrimEnd('\')
        foreach ($it in $items) {
            $rel = $it.FullName.Substring($srcFull.Length).TrimStart('\')
            if (Test-Path -LiteralPath (Join-Path $p.Dest $rel)) { $conflicts++ }
        }
        $cloud = @($items | Where-Object { (([int]$_.Attributes) -band $cloudMask) -ne 0 }).Count

        Write-Host "    Source : $($p.Source) ($($items.Count) files, $sizeMB MB)" -ForegroundColor Cyan
        Write-Host "    Target : $($p.Dest)" -ForegroundColor Green
        Write-Host "    Name conflicts (will be de-duplicated or kept side by side): $conflicts" -ForegroundColor Gray
        Write-Host "    Cloud-only files: $cloud" -ForegroundColor Gray
        $sub = Get-ChildItem -LiteralPath $p.Source -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($sub) { Write-Host "    Subfolders: $($sub -join ', ')" -ForegroundColor DarkCyan }
    }

    foreach ($r in (Get-OneDriveRoots)) {
        $extra = Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue |
                 Where-Object { $plan.Source -notcontains $_.FullName }
        if ($extra) {
            Write-Host "`n[i] Other folders in $r (will NOT be touched):" -ForegroundColor White
            Write-Host "    $($extra.Name -join ', ')" -ForegroundColor DarkCyan
        }
    }

    Write-Host "`nSimulation completed. No files or registry keys were modified." -ForegroundColor Yellow
    Pause-Console
}

# ----------------------------------------------------------------------------
# Uninstall
# ----------------------------------------------------------------------------
function Invoke-UninstallOneDrive {
    param([bool]$Silent = $false)

    if (-not $Silent) {
        Show-Header
        Write-Host "`n>>> UNINSTALL / DISABLE ONEDRIVE APPLICATION <<<" -ForegroundColor Red
        Write-Host "This does NOT delete your local files; it only removes the application." -ForegroundColor Gray
        if (-not (Ask-YesNo "`nUninstall OneDrive from this system?")) { return }
    }

    Write-Host "`n[*] Stopping OneDrive..." -ForegroundColor Cyan
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue

    Write-Host "[*] Removing OneDrive from Windows startup..." -ForegroundColor Cyan
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

    if ([Environment]::Is64BitOperatingSystem) {
        $uninstallPaths = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe")
    } else {
        $uninstallPaths = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe")
    }

    $found = $false
    foreach ($up in $uninstallPaths) {
        if (Test-Path -LiteralPath $up) {
            Write-Host "[*] Launching uninstaller: $up" -ForegroundColor Yellow
            Start-Process $up -ArgumentList "/uninstall" -Wait
            $found = $true
            break
        }
    }

    if ($found) {
        Write-Host "[+] OneDrive application uninstalled." -ForegroundColor Green
        # Hide the orphan OneDrive entry in the Explorer sidebar
        $clsidPath = "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        if (-not (Test-Path $clsidPath)) { New-Item -Path $clsidPath -Force | Out-Null }
        Set-ItemProperty -Path $clsidPath -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force
        Write-Host "[+] Hidden orphan OneDrive icon from Explorer sidebar." -ForegroundColor Green
    } else {
        Write-Host "[!] Uninstaller not found; startup autorun was disabled only." -ForegroundColor Yellow
    }

    if (-not $Silent) { Pause-Console }
}

# ----------------------------------------------------------------------------
# Migration
# ----------------------------------------------------------------------------
function Invoke-Migration {
    Show-Header
    Write-Host "`n>>> SAFE FOLDER MIGRATION & REGISTRY REPAIR <<<" -ForegroundColor Green

    $plan = @(Get-MigrationPlan)
    if ($plan.Count -eq 0) {
        Write-Host "`n[+] No personal folder is currently redirected into OneDrive. Nothing to do." -ForegroundColor Green
        Pause-Console
        return
    }

    Write-Host "`nFolders that will be moved back to the local profile:" -ForegroundColor White
    foreach ($p in $plan) { Write-Host "  $($p.Folder.Name): $($p.Source)  ->  $($p.Dest)" -ForegroundColor Cyan }

    $existing = @($plan | Where-Object { Test-Path -LiteralPath $_.Source })
    if ($existing.Count -eq 0) {
        Write-Host "`n[!] None of the source folders exist on disk. Aborting." -ForegroundColor Red
        Pause-Console
        return
    }

    # 1. Cloud files pre-check
    if (-not (Check-CloudFiles ($existing | ForEach-Object { $_.Source }))) {
        Pause-Console
        return
    }

    # 2. Confirmation
    Write-Host "`nNothing will be overwritten. Conflicting files are de-duplicated or kept side by side." -ForegroundColor White
    if (-not (Ask-YesNo "Are you ready to proceed?")) {
        Write-Host "[!] Operation cancelled by user." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    # 3. Stop OneDrive so it releases file locks
    Write-Host "`n[*] Stopping OneDrive background process..." -ForegroundColor Cyan
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # 4. Backup (abort if it failed and the user does not want to continue)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    if (-not (Create-RegistryBackup -Stamp $stamp)) {
        Write-Host "[!] Aborted: no backup." -ForegroundColor Yellow
        Pause-Console
        return
    }
    $logFile = Join-Path $backupDir "Moves_$stamp.csv"

    # 5. Merge folders and repoint only the ones that fully succeeded
    Write-Host "`n[*] Moving and merging folders..." -ForegroundColor Cyan
    $allOk = $true
    foreach ($p in $plan) {
        $name = $p.Folder.Name
        Write-Host "`n    -> $name" -ForegroundColor White

        if (Test-Path -LiteralPath $p.Source) {
            $s = Merge-Folder -Source $p.Source -Dest $p.Dest -LogFile $logFile
            Write-Host "       Moved: $($s.Moved)  Duplicates removed: $($s.Duplicates)  Kept side-by-side: $($s.Renamed)  Failed: $($s.Failed)" -ForegroundColor Gray
            if ($s.Failed -gt 0) {
                $allOk = $false
                Write-Host "    [!] '$name' had errors. Registry path NOT changed; remaining files stay in OneDrive." -ForegroundColor Red
                continue
            }
        } else {
            Write-Host "       Source folder missing; only the registry path will be fixed." -ForegroundColor Yellow
        }
        Set-LocalFolderPath -Folder $p.Folder -LocalPath $p.Dest
    }

    # 6. Refresh Explorer
    Restart-Explorer

    if ($allOk) {
        Write-Host @"

====================================================================
                     MIGRATION COMPLETED SUCCESSFULLY
====================================================================
  [+] Files merged to the local profile (nothing overwritten).
  [+] Folder paths no longer point to OneDrive.
  [+] Backup and move log: $backupDir
====================================================================
"@ -ForegroundColor Green
        Write-Host "Other folders in OneDrive were not touched." -ForegroundColor Gray
        if (Ask-YesNo "`nUninstall the OneDrive app now?") {
            Invoke-UninstallOneDrive -Silent $true
        }
    } else {
        Write-Host "`n[!] Migration finished WITH ERRORS. Fix the issues above and run it again;" -ForegroundColor Yellow
        Write-Host "    already moved files are skipped safely. OneDrive was NOT uninstalled." -ForegroundColor Yellow
    }
    Pause-Console
}

# ----------------------------------------------------------------------------
# Rollback
# ----------------------------------------------------------------------------
function Invoke-RestoreBackup {
    Show-Header
    Write-Host "`n>>> ROLLBACK / RESTORE FROM BACKUP <<<" -ForegroundColor Yellow

    if (-not (Test-Path $backupDir)) {
        Write-Host "[!] No backups directory found at: $backupDir" -ForegroundColor Red
        Pause-Console
        return
    }

    $backups = @(Get-ChildItem -Path $backupDir -Filter "Registry_Backup_*_USF.reg" | Sort-Object LastWriteTime -Descending)
    if ($backups.Count -eq 0) {
        Write-Host "[!] No backups found in: $backupDir" -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host "Available Backups:" -ForegroundColor White
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host "  [$($i+1)] $($backups[$i].Name) ($($backups[$i].LastWriteTime))" -ForegroundColor Cyan
    }

    $sel = Read-Host "`nEnter the backup number to restore (0 to cancel)"
    $num = 0
    if (-not [int]::TryParse($sel, [ref]$num) -or $num -lt 1 -or $num -gt $backups.Count) {
        Write-Host "[!] Cancelled / invalid selection." -ForegroundColor Yellow
        Pause-Console
        return
    }

    $usfFile = $backups[$num - 1].FullName
    $stamp   = $backups[$num - 1].Name -replace '^Registry_Backup_(\d{8}_\d{6})_USF\.reg$', '$1'
    $sfFile  = Join-Path $backupDir "Registry_Backup_${stamp}_SF.reg"
    $logFile = Join-Path $backupDir "Moves_$stamp.csv"

    # Move files back first (optional)
    if (Test-Path $logFile) {
        if (Ask-YesNo "A move log exists for this backup. Also move the files back to OneDrive?") {
            Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
            $entries = @(Import-Csv -Path $logFile)
            [array]::Reverse($entries)
            $restored = 0; $failed = 0
            foreach ($e in $entries) {
                try {
                    if (-not (Test-Path -LiteralPath $e.Target)) { continue }
                    if (Test-Path -LiteralPath $e.Source) { continue }
                    $sDir = Split-Path -Parent $e.Source
                    if (-not (Test-Path -LiteralPath $sDir)) { New-Item -Path $sDir -ItemType Directory -Force | Out-Null }
                    if ($e.Type -eq "DUP") {
                        Copy-Item -LiteralPath $e.Target -Destination $e.Source -ErrorAction Stop
                    } else {
                        Move-Item -LiteralPath $e.Target -Destination $e.Source -ErrorAction Stop
                    }
                    $restored++
                } catch { $failed++ }
            }
            Write-Host "[+] Files restored: $restored  Failed: $failed" -ForegroundColor Green
        }
    } else {
        Write-Host "[i] No move log for this backup; only the registry will be restored." -ForegroundColor Gray
    }

    Write-Host "`n[*] Restoring registry..." -ForegroundColor Yellow
    & reg.exe import "$usfFile" | Out-Null
    if (Test-Path $sfFile) { & reg.exe import "$sfFile" | Out-Null }

    Restart-Explorer
    Write-Host "[+] Registry restored to its previous state!" -ForegroundColor Green
    Pause-Console
}

# ----------------------------------------------------------------------------
# Restore classic This PC folders (Windows 11)
# ----------------------------------------------------------------------------
function Invoke-RestoreThisPC {
    Show-Header
    Write-Host "`n>>> RESTORE CLASSIC 'THIS PC' FOLDERS (WINDOWS 11) <<<" -ForegroundColor Cyan
    $regFile = Join-Path $scriptDir "Restore-ThisPC-Folders.reg"
    if (Test-Path -LiteralPath $regFile) {
        Write-Host "[*] Requesting administrator elevation (UAC prompt)..." -ForegroundColor Yellow
        try {
            $proc = Start-Process -FilePath "reg.exe" -ArgumentList "import `"$regFile`"" -Verb RunAs -Wait -PassThru -ErrorAction Stop
            if ($proc.ExitCode -eq 0) {
                Restart-Explorer
                Write-Host "[+] Classic folders restored to 'This PC' successfully!" -ForegroundColor Green
            } else {
                Write-Host "[!] reg.exe returned exit code $($proc.ExitCode). Nothing was changed." -ForegroundColor Red
            }
        } catch {
            Write-Host "[!] Elevation was cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "[!] Error: 'Restore-ThisPC-Folders.reg' not found in: $scriptDir" -ForegroundColor Red
    }
    Pause-Console
}

# ----------------------------------------------------------------------------
# MAIN INTERACTIVE LOOP
# ----------------------------------------------------------------------------
while ($true) {
    Show-Header
    Write-Host ""
    Write-Host " [1] Unhijack Folders & Repair Registry Paths (Recommended)" -ForegroundColor Green
    Write-Host " [2] Preview / Simulation Mode (Dry-Run / No Changes)" -ForegroundColor Yellow
    Write-Host " [3] Completely Uninstall / Remove OneDrive Application" -ForegroundColor Magenta
    Write-Host " [4] Undo / Rollback Changes (Registry + Files)" -ForegroundColor White
    Write-Host " [5] Restore Classic 'This PC' Folders (Windows 11)" -ForegroundColor Cyan
    Write-Host " [0] Exit" -ForegroundColor Red
    Write-Host "====================================================================" -ForegroundColor Cyan

    $choice = Read-Host " Select an option"
    switch ($choice) {
        '1' { Invoke-Migration }
        '2' { Invoke-DryRun }
        '3' { Invoke-UninstallOneDrive }
        '4' { Invoke-RestoreBackup }
        '5' { Invoke-RestoreThisPC }
        '0' { return }
        default { Write-Host "Invalid option, please choose between 0 and 5." -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}
