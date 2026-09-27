<#
.SYNOPSIS
  Installs a persistent local ShilpiDB server for AccelDraw development.

.DESCRIPTION
  Builds shilpid/shilpi from a local ShilpiDB checkout (release mode), installs the
  binaries to %LOCALAPPDATA%\ShilpiDB\bin, points them at a persistent data file under
  %LOCALAPPDATA%\ShilpiDB\data\accel.vdb, adds the install dir to the user PATH, sets
  ACCELDRAW_SHILPID_ADDR so AccelDraw.Plugin/Manager pick it up automatically, and adds a
  Startup-folder shortcut so shilpid starts at login (a plain per-user shortcut rather than
  a Scheduled Task or Windows Service — registering a Scheduled Task needs Task Scheduler
  access this could be run without, e.g. inside a sandboxed session).

  Safe to re-run: rebuilds/recopies the binaries, leaves the existing .vdb data file alone,
  and no-ops the PATH/env var/shortcut steps if already present.

.PARAMETER ShilpiDbRepo
  Path to a local clone of https://github.com/HolagundiWorks/shilpidb. Defaults to a
  'shilpidb' sibling of this repo's parent directory (D:\...\Repos\shilpidb next to
  D:\...\Repos\archidb) — clone it first if it's not already there:
  gh repo clone HolagundiWorks/shilpidb

.PARAMETER Bind
  Address shilpid listens on. Default 127.0.0.1:7420 (matches AccelDraw's own default).

.EXAMPLE
  .\install-shilpid-local.ps1
  .\install-shilpid-local.ps1 -ShilpiDbRepo "D:\Code\shilpidb" -Bind "127.0.0.1:7500"
#>
param(
    [string]$ShilpiDbRepo = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "..\shilpidb" | Resolve-Path -ErrorAction SilentlyContinue),
    [string]$Bind = "127.0.0.1:7420"
)

$ErrorActionPreference = "Stop"

if (-not $ShilpiDbRepo -or -not (Test-Path (Join-Path $ShilpiDbRepo "Cargo.toml"))) {
    throw "Could not find a shilpidb checkout. Clone it first (gh repo clone HolagundiWorks/shilpidb) and pass -ShilpiDbRepo <path>."
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo not found on PATH. Install Rust first — see docs/PLAN-OF-ACTION.md in the AccelDraw repo for the Windows GNU-host install steps this project needed."
}

Write-Host "Building shilpid + shilpi (release) from $ShilpiDbRepo ..."
Push-Location $ShilpiDbRepo
try {
    cargo build --release -p shilpid -p shilpi
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
} finally {
    Pop-Location
}

$installDir = "$env:LOCALAPPDATA\ShilpiDB\bin"
$dataDir = "$env:LOCALAPPDATA\ShilpiDB\data"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

Copy-Item (Join-Path $ShilpiDbRepo "target\release\shilpid.exe") "$installDir\shilpid.exe" -Force
Copy-Item (Join-Path $ShilpiDbRepo "target\release\shilpi.exe") "$installDir\shilpi.exe" -Force
Write-Host "Installed shilpid.exe / shilpi.exe to $installDir"

# --- Start script (also used by the Startup shortcut below) ---
$startScript = @"
# Starts the local ShilpiDB server with a persistent data file, autosaving every 30s.
`$installDir = "$installDir"
`$dataFile = "$dataDir\accel.vdb"
`$logFile = "$dataDir\shilpid.log"
`$outFile = "$dataDir\shilpid.out.log"

if (Get-Process shilpid -ErrorAction SilentlyContinue) { exit 0 }

Start-Process -FilePath "`$installDir\shilpid.exe" ``
  -ArgumentList "--bind","$Bind","--data",`$dataFile,"--autosave-secs","30","--log-level","info" ``
  -RedirectStandardOutput `$outFile -RedirectStandardError `$logFile -WindowStyle Hidden
"@
Set-Content -Path "$installDir\start-shilpid.ps1" -Value $startScript
Write-Host "Wrote $installDir\start-shilpid.ps1"

# --- PATH + env var (user-level, persists across sessions) ---
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$installDir", "User")
    Write-Host "Added $installDir to the User PATH (restart shells to pick it up)"
}
[Environment]::SetEnvironmentVariable("ACCELDRAW_SHILPID_ADDR", $Bind, "User")
Write-Host "Set ACCELDRAW_SHILPID_ADDR=$Bind (User)"

# --- Start at login (Startup-folder shortcut; no Task Scheduler access required) ---
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = "$startupDir\ShilpiDB.lnk"
$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installDir\start-shilpid.ps1`""
$shortcut.WorkingDirectory = $installDir
$shortcut.Description = "Start the local ShilpiDB server for AccelDraw"
$shortcut.Save()
Write-Host "Added login shortcut: $shortcutPath"

# --- Start it now for this session too ---
& "$installDir\start-shilpid.ps1"
Start-Sleep -Seconds 1
if (Get-Process shilpid -ErrorAction SilentlyContinue) {
    Write-Host "shilpid is running on $Bind"
} else {
    Write-Warning "shilpid did not appear to start — check $dataDir\shilpid.log"
}
