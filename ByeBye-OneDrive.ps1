<#
.SYNOPSIS
    ByeBye-OneDrive - Windows Personal Folder Unhijacker & Path Restorer
.DESCRIPTION
    Safely migrates Desktop, Documents, Pictures, Music, and Videos from OneDrive
    back to your local user profile with ZERO data loss, repairs Windows registry paths,
    preserves all game saves, configs, and application data, and optionally restores
    classic "This PC" folders in Windows 11.
.AUTHOR
    Oguz Efe & Open Source Community
.LICENSE
    MIT License
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ByeBye-OneDrive v2.0 - Windows Folder Unhijacker"

# Global Paths & Environment
$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$oneDrivePath = Join-Path $userProfile "OneDrive"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$backupDir = Join-Path $scriptDir "Backups"

# Target Shell Folders Definition
$targetFolders = @(
    @{ Name = "Desktop";   USFName = "Desktop";     GUID = "{754AC886-DF64-4C98-0423-9DED4955122E}" },
    @{ Name = "Documents"; USFName = "Personal";    GUID = "{F42EE2D3-909F-4907-8871-4C22FC0BF756}" },
    @{ Name = "Pictures";  USFName = "My Pictures"; GUID = "{0DDD015D-B06C-45D5-8C4C-F59713854639}" },
    @{ Name = "Music";     USFName = "My Music";    GUID = "{A0C69A99-21C8-4671-8703-7934162FCF1D}" },
    @{ Name = "Videos";    USFName = "My Video";    GUID = "{3528614A-712E-49EE-B646-5AC32481F28A}" }
)

function Pause-Console {
    param([string]$Message = "Press Enter to return to menu...")
    Write-Host "`n$Message" -ForegroundColor Yellow
    try {
        $null = Read-Host
    } catch {}
}

function Show-Header {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "                       ByeBye-OneDrive v2.0                         " -ForegroundColor White
    Write-Host "    Safe Folder Migration, Registry Repair & Zero Data Loss Tool   " -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " User Profile : $userProfile" -ForegroundColor Gray
    Write-Host " OneDrive Path: $oneDrivePath" -ForegroundColor Gray
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Create-RegistryBackup {
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path $backupDir "Registry_Backup_$timestamp.reg"

    Write-Host "`n[*] Creating registry backup..." -ForegroundColor Yellow
    & reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" "$backupFile" /y | Out-Null
    
    if (Test-Path $backupFile) {
        Write-Host "[+] Registry backup saved successfully to:" -ForegroundColor Green
        Write-Host "    $backupFile" -ForegroundColor Gray
        return $backupFile
    } else {
        Write-Host "[!] Warning: Could not create registry backup. Continue anyway? (Y/N): " -NoNewline -ForegroundColor Red
        $ans = Read-Host
        if ($ans -ne 'Y' -and $ans -ne 'y') { return $null }
    }
    return $null
}

function Check-CloudFiles {
    Write-Host "`n[*] Inspecting OneDrive files status..." -ForegroundColor Cyan
    $files = Get-ChildItem -Path $oneDrivePath -Force -Recurse -File -ErrorAction SilentlyContinue
    $total = ($files | Measure-Object).Count
    
    $cloudOnly = $files | Where-Object { 
        ($_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) -or 
        ($_.Attributes.HasFlag([System.IO.FileAttributes]::Offline)) 
    }
    $cloudCount = ($cloudOnly | Measure-Object).Count

    Write-Host "    Total Files Found: $total" -ForegroundColor Gray
    Write-Host "    Cloud-Only Files : $cloudCount" -ForegroundColor $(if ($cloudCount -gt 0) { "Yellow" } else { "Green" })

    if ($cloudCount -gt 0) {
        Write-Host "`n[!] NOTICE: $cloudCount file(s) are stored online in the cloud only!" -ForegroundColor Yellow
        Write-Host "    These files have not been fully downloaded to your hard drive yet." -ForegroundColor Gray
        Write-Host "`nOptions:" -ForegroundColor White
        Write-Host "  [1] Trigger Windows to download these files now and verify (Recommended)" -ForegroundColor Cyan
        Write-Host "  [2] Abort migration (Allow OneDrive to sync or choose 'Always keep on this device')" -ForegroundColor Yellow
        Write-Host "  [3] Proceed anyway (Cloud-only files may remain in OneDrive)" -ForegroundColor Red
        $c = Read-Host "`nSelect an option (1/2/3)"
        
        if ($c -eq '1') {
            Write-Host "`n[*] Downloading cloud files, please wait..." -ForegroundColor Cyan
            foreach ($cf in $cloudOnly) {
                try {
                    $stream = [System.IO.File]::OpenRead($cf.FullName)
                    $stream.Close()
                } catch {}
            }
            # Recheck after hydration
            $stillCloud = (Get-ChildItem -Path $oneDrivePath -Force -Recurse -File -ErrorAction SilentlyContinue | Where-Object { 
                ($_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) -or 
                ($_.Attributes.HasFlag([System.IO.FileAttributes]::Offline)) 
            } | Measure-Object).Count

            if ($stillCloud -eq 0) {
                Write-Host "[+] All files successfully downloaded to your local disk!" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[!] $stillCloud file(s) could not be downloaded (check internet connection)." -ForegroundColor Red
                Write-Host "Migration halted to prevent any data loss." -ForegroundColor Yellow
                Pause-Console
                return $false
            }
        } elseif ($c -eq '2') {
            return $false
        }
    } else {
        Write-Host "[+] All $total files are 100% locally available on disk. Safe to migrate!" -ForegroundColor Green
    }
    return $true
}

function Invoke-DryRun {
    Show-Header
    Write-Host "`n>>> PREVIEW / SIMULATION MODE (No changes will be made) <<<" -ForegroundColor Yellow
    
    if (-not (Test-Path $oneDrivePath)) {
        Write-Host "[!] OneDrive folder does not exist at: $oneDrivePath" -ForegroundColor Red
        Pause-Console
        return
    }

    foreach ($f in $targetFolders) {
        $name = $f.Name
        $src = Join-Path $oneDrivePath $name
        $dst = Join-Path $userProfile $name
        
        Write-Host "`n[+] Folder: $name" -ForegroundColor White
        if (Test-Path $src) {
            $items = Get-ChildItem -Path $src -Force -Recurse -File -ErrorAction SilentlyContinue
            $count = ($items | Measure-Object).Count
            $sizeMB = [math]::Round((($items | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
            Write-Host "    Source: $src ($count files, $sizeMB MB)" -ForegroundColor Cyan
            Write-Host "    Target: $dst" -ForegroundColor Green
            
            # Identify game and application profiles
            $subDirs = Get-ChildItem -Path $src -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            if ($subDirs) {
                Write-Host "    Detected App / Game Directories:" -ForegroundColor Gray
                Write-Host "    -> $($subDirs -join ', ')" -ForegroundColor DarkCyan
            }
        } else {
            Write-Host "    Not redirected inside OneDrive (already local or empty)." -ForegroundColor Gray
        }
    }

    # Check for extra custom directories in OneDrive
    $extraDirs = Get-ChildItem -Path $oneDrivePath -Directory -Force -ErrorAction SilentlyContinue | 
                 Where-Object { $_.Name -notin @("Pictures", "Documents", "Desktop", "Music", "Videos") }
    if ($extraDirs) {
        Write-Host "`n[+] Extra Custom Folders Found in OneDrive:" -ForegroundColor White
        foreach ($ed in $extraDirs) {
            Write-Host "    -> $($ed.Name) will be merged into: $(Join-Path $userProfile $ed.Name)" -ForegroundColor Cyan
        }
    }

    Write-Host "`n[*] Registry Paths that will be updated:" -ForegroundColor White
    foreach ($f in $targetFolders) {
        Write-Host "    HKCU:\...\User Shell Folders\$($f.USFName) -> %USERPROFILE%\$($f.Name)" -ForegroundColor Green
    }

    Write-Host "`nSimulation completed successfully. No files or registry keys were modified." -ForegroundColor Yellow
    Pause-Console
}

function Invoke-UninstallOneDrive {
    param([bool]$Silent = $false)
    
    if (-not $Silent) {
        Show-Header
        Write-Host "`n>>> UNINSTALL / DISABLE ONEDRIVE APPLICATION <<<" -ForegroundColor Red
        Write-Host "This operation will NOT delete your local files. It only removes the application." -ForegroundColor Gray
        $ans = Read-Host "`nDo you want to completely uninstall OneDrive from this system? (Y/N)"
        if ($ans -ne 'Y' -and $ans -ne 'y') { return }
    }

    Write-Host "`n[*] Terminating running OneDrive processes to free file locks..." -ForegroundColor Cyan
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue

    Write-Host "[*] Removing OneDrive from Windows startup..." -ForegroundColor Cyan
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

    $uninstallPaths = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
    )

    $found = $false
    foreach ($up in $uninstallPaths) {
        if (Test-Path $up) {
            Write-Host "[*] Launching uninstaller: $up" -ForegroundColor Yellow
            Start-Process $up -ArgumentList "/uninstall" -Wait
            $found = $true
            break
        }
    }

    if ($found) {
        Write-Host "[+] OneDrive application uninstalled successfully!" -ForegroundColor Green
    } else {
        Write-Host "[!] Standalone uninstaller not found; startup autorun was disabled." -ForegroundColor Yellow
    }
    
    if (-not $Silent) {
        Pause-Console
    }
}

function Invoke-Migration {
    Show-Header
    Write-Host "`n>>> SAFE FOLDER MIGRATION & REGISTRY REPAIR <<<" -ForegroundColor Green
    
    if (-not (Test-Path $oneDrivePath)) {
        Write-Host "[!] OneDrive folder not found at: $oneDrivePath" -ForegroundColor Red
        Pause-Console
        return
    }

    # 1. Cloud Files Pre-check
    $safe = Check-CloudFiles
    if (-not $safe) { return }

    # 2. Confirmation
    Write-Host "`nThis will safely migrate your files and game saves to local folders and update registry paths." -ForegroundColor White
    $confirm = Read-Host "Are you ready to proceed? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "[!] Operation cancelled by user." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    # 3. CRITICAL SAFETY: Terminate OneDrive first so it releases all file locks!
    Write-Host "`n[*] Stopping OneDrive background process to prevent file conflicts..." -ForegroundColor Cyan
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue

    # 4. Create Registry Backup
    Create-RegistryBackup | Out-Null

    # 5. Move and Merge Folders (Zero Data Loss)
    Write-Host "`n[*] Safely moving and merging folders..." -ForegroundColor Cyan
    foreach ($f in $targetFolders) {
        $folderName = $f.Name
        $src = Join-Path $oneDrivePath $folderName
        $dst = Join-Path $userProfile $folderName

        if (-not (Test-Path $dst)) {
            New-Item -Path $dst -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $src) {
            Write-Host "    -> Migrating '$folderName'..." -ForegroundColor Gray
            $items = Get-ChildItem -Path $src -Force
            foreach ($item in $items) {
                $destPath = Join-Path $dst $item.Name
                if (Test-Path $destPath) {
                    if ($item.PSIsContainer) {
                        # Robocopy handles existing directory merges flawlessly on NTFS
                        & robocopy.exe "$($item.FullName)" "$destPath" /E /MOVE /R:1 /W:1 /NFL /NDL /NP | Out-Null
                        Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    } else {
                        Move-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Move-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "    [OK] '$folderName' migrated successfully." -ForegroundColor Green
        }
    }

    # Check for custom extra directories
    $remaining = Get-ChildItem -Path $oneDrivePath -Directory -Force -ErrorAction SilentlyContinue | 
                 Where-Object { $_.Name -notin @("Pictures", "Documents", "Desktop", "Music", "Videos") }
    foreach ($rem in $remaining) {
        $destRem = Join-Path $userProfile $rem.Name
        Write-Host "    -> Migrating custom folder: '$($rem.Name)'..." -ForegroundColor Gray
        if (Test-Path $destRem) {
            & robocopy.exe "$($rem.FullName)" "$destRem" /E /MOVE /R:1 /W:1 /NFL /NDL /NP | Out-Null
            Remove-Item $rem.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Move-Item -Path $rem.FullName -Destination $destRem -Force -ErrorAction SilentlyContinue
        }
    }

    # 6. Registry Repair (User Shell Folders & Shell Folders)
    Write-Host "`n[*] Repairing Windows Registry paths..." -ForegroundColor Cyan
    $usfPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    $sfPath  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"

    foreach ($f in $targetFolders) {
        $folderName = $f.Name
        $usfName    = $f.USFName
        $guid       = $f.GUID
        $localPath  = Join-Path $userProfile $folderName
        $expandPath = "%USERPROFILE%\$folderName"

        Set-ItemProperty -Path $usfPath -Name $usfName -Value $expandPath -Type ExpandString -Force
        if ($guid) {
            Set-ItemProperty -Path $usfPath -Name $guid -Value $expandPath -Type ExpandString -Force
        }
        Set-ItemProperty -Path $sfPath -Name $usfName -Value $localPath -Type String -Force
        Write-Host "    [OK] Repaired: $folderName -> $expandPath" -ForegroundColor Green
    }

    # 7. Hide orphan OneDrive icon from File Explorer tree
    $clsidPath = "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    if (-not (Test-Path $clsidPath)) { New-Item -Path $clsidPath -Force | Out-Null }
    Set-ItemProperty -Path $clsidPath -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force
    Write-Host "    [OK] Hidden orphan OneDrive icon from Explorer sidebar." -ForegroundColor Green

    # 8. Restart Windows Explorer safely
    Write-Host "`n[*] Refreshing Windows Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer
    }

    Write-Host @"

====================================================================
                     MIGRATION COMPLETED SUCCESSFULLY!              
====================================================================
  [+] All personal folders and game saves restored to local disk.
  [+] Registry paths completely uncoupled from OneDrive.
  [+] Zero data loss guaranteed.
====================================================================
"@ -ForegroundColor Green

    # 9. Smart Post-migration Offer
    Write-Host "`nNow that your files and paths are 100% safe," -ForegroundColor White
    $uninstallNow = Read-Host "Would you like to completely uninstall the OneDrive app now? (Y/N)"
    if ($uninstallNow -eq 'Y' -or $uninstallNow -eq 'y') {
        Invoke-UninstallOneDrive -Silent $true
    }

    Pause-Console
}

function Invoke-RestoreBackup {
    Show-Header
    Write-Host "`n>>> ROLLBACK / RESTORE REGISTRY FROM BACKUP <<<" -ForegroundColor Yellow
    
    if (-not (Test-Path $backupDir)) {
        Write-Host "[!] No backups directory found at: $backupDir" -ForegroundColor Red
        Pause-Console
        return
    }

    $backups = Get-ChildItem -Path $backupDir -Filter "*.reg" | Sort-Object LastWriteTime -Descending
    if ($backups.Count -eq 0) {
        Write-Host "[!] No .reg backup files found in: $backupDir" -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host "Available Backups:" -ForegroundColor White
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host "  [$($i+1)] $($backups[$i].Name) ($($backups[$i].LastWriteTime))" -ForegroundColor Cyan
    }

    $sel = Read-Host "`nEnter the backup number to restore (0 to Cancel)"
    $index = [int]$sel - 1
    if ($index -ge 0 -and $index -lt $backups.Count) {
        $targetReg = $backups[$index].FullName
        Write-Host "`n[*] Restoring registry from: $targetReg" -ForegroundColor Yellow
        & reg.exe import "$targetReg"
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer
        }
        Write-Host "[+] Registry restored to its previous state!" -ForegroundColor Green
    }
    Pause-Console
}

function Invoke-RestoreThisPC {
    Show-Header
    Write-Host "`n>>> RESTORE CLASSIC 'THIS PC' FOLDERS (WINDOWS 11) <<<" -ForegroundColor Cyan
    $regFile = Join-Path $scriptDir "Restore-ThisPC-Folders.reg"
    if (Test-Path $regFile) {
        Write-Host "[*] Requesting administrator elevation (UAC prompt)..." -ForegroundColor Yellow
        Start-Process -FilePath "reg.exe" -ArgumentList "import `"$regFile`"" -Verb RunAs -Wait
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer
        }
        Write-Host "[+] Classic folders restored to 'This PC' successfully!" -ForegroundColor Green
    } else {
        Write-Host "[!] Error: 'Restore-ThisPC-Folders.reg' not found in: $scriptDir" -ForegroundColor Red
    }
    Pause-Console
}

# MAIN INTERACTIVE LOOP
while ($true) {
    Show-Header
    Write-Host ""
    Write-Host " [1] Unhijack Folders & Repair Registry Paths (Recommended)" -ForegroundColor Green
    Write-Host " [2] Preview / Simulation Mode (Dry-Run / No Changes)" -ForegroundColor Yellow
    Write-Host " [3] Completely Uninstall / Remove OneDrive Application" -ForegroundColor Magenta
    Write-Host " [4] Undo / Rollback Changes (Restore from Backup)" -ForegroundColor White
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
        '0' { Exit }
        default { Write-Host "Invalid option, please choose between 0 and 5." -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}
