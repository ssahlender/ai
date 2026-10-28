<#
.SYNOPSIS
    One-time move of ProBook's local-LLM engines/models/logs from C:\data\llm to the
    user-profile layout the scripts now default to ($env:USERPROFILE\.local\share\llama.cpp).

.DESCRIPTION
    Mirrors the i9 convention (models and binaries live under the user's own home, not a
    separate data drive). Safe to re-run: it skips anything already moved or not present at
    the source, and refuses if a llama-server.exe process is running (move it out from under a
    live session and the next request fails with a confusing I/O error instead of a clear one).

    Moves only known subdirectories (ik_llama, llama.cpp-cpu, models, logs); anything else left
    under the old root is reported, not touched.

.PARAMETER From
    Old root. Default C:\data\llm.

.PARAMETER To
    New root. Default $env:USERPROFILE\.local\share\llama.cpp (what lib\common.ps1's
    Get-LlmRoot and the other scripts' defaults now point at).

.PARAMETER WhatIf
    Report what would move without moving anything.

.EXAMPLE
    .\move-to-home.ps1 -WhatIf
    .\move-to-home.ps1
#>
[CmdletBinding()]
param(
    [string]$From = 'C:\data\llm',
    [string]$To   = (Join-Path $env:USERPROFILE '.local\share\llama.cpp'),
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue) {
    throw "llama-server.exe is running. Stop it first (it may be serving a live agent session) - moving its model/binary out from under it fails confusingly instead of cleanly."
}

if (-not (Test-Path $From)) {
    Write-Output "Nothing to move: $From does not exist. Already migrated, or never used the old layout."
    exit 0
}

if (-not (Test-Path $To)) {
    if ($WhatIf) {
        Write-Output "Would create: $To"
    } else {
        New-Item -ItemType Directory -Path $To -Force | Out-Null
    }
}

$known = @('ik_llama', 'llama.cpp-cpu', 'models', 'logs')
foreach ($name in $known) {
    $src = Join-Path $From $name
    $dst = Join-Path $To $name
    if (-not (Test-Path $src)) {
        Write-Output "skip (not present): $src"
        continue
    }
    if (Test-Path $dst) {
        Write-Output "skip (already exists at destination): $dst"
        continue
    }
    if ($WhatIf) {
        Write-Output "would move: $src -> $dst"
    } else {
        Write-Output "moving: $src -> $dst"
        Move-Item -Path $src -Destination $dst
    }
}

$leftover = Get-ChildItem -Path $From -ErrorAction SilentlyContinue |
    Where-Object { $known -notcontains $_.Name }
if ($leftover) {
    Write-Output ""
    Write-Output "Left behind under $From (not one of the known subdirs, review manually):"
    $leftover | ForEach-Object { Write-Output "  $($_.FullName)" }
}

if (-not $WhatIf) {
    $remaining = Get-ChildItem -Path $From -ErrorAction SilentlyContinue
    if (-not $remaining) {
        Write-Output ""
        Write-Output "$From is now empty. Remove it manually once you've confirmed everything works: Remove-Item '$From'"
    }
}
