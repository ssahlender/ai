<#
.SYNOPSIS
    Update ik_llama.cpp (Thireus prebuilt) on Windows — PowerShell port of update.sh.

.DESCRIPTION
    Windows twin of ./update.sh (which covers i9, probook-in-WSL and macbook-air).
    Needed because the WSL2 path (/mnt/c/...) is only reachable as the interactive
    user, while the automation account cannot reach the WSL path.

    Difference from the bash version, deliberate:
      * same install location as the bash script: the canonical C:\data\llm\ik_llama
        (.tag marker convention preserved, so both scripts agree on "up to date").
      * never destroys the previous build — existing exe/dll files are copied to
        _backup-<previous-tag>\ before the new files land, so a bad update is one
        directory copy away from being reverted.
      * verifies the asset sha256 from the GitHub release digest when available.
      * -ListOnly resolves and reports without downloading anything.

.PARAMETER Dest
    Install directory. Default C:\data\llm\ik_llama (the canonical path start.ps1
    and the historical bash setup both use).

.PARAMETER ListOnly
    Resolve the newest matching release and exit without downloading.

.PARAMETER Force
    Re-download even if the target versioned directory already has a matching .tag.

.EXAMPLE
    .\update.ps1 -ListOnly
    .\update.ps1
    .\update.ps1 -Dest D:\llm -Force
#>
[CmdletBinding()]
param(
    [string]$Repo        = 'Thireus/ik_llama.cpp',
    [string]$ArchPattern = '^ik_llama-(?!cudart).+-bin-win-cpu-x64-avx512_vnni_vbmi_bf16\.zip$',
    [string]$Dest        = 'C:\data\llm\ik_llama',
    [switch]$ListOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'ik-llama-update-ps1' }
$re = [regex]$ArchPattern

# ── find latest release asset matching the arch pattern ─────────────
Write-Host "Querying $Repo for $ArchPattern ..."
$found = $null
for ($page = 1; $page -le 5 -and -not $found; $page++) {
    $uri = "https://api.github.com/repos/$Repo/releases?per_page=30&page=$page"
    $releases = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    if (-not $releases) { break }
    foreach ($r in $releases) {
        foreach ($a in $r.assets) {
            if ($re.IsMatch($a.name)) {
                $found = [pscustomobject]@{
                    Tag    = $r.tag_name
                    Name   = $a.name
                    SizeMB = [math]::Round($a.size / 1MB, 1)
                    Url    = $a.browser_download_url
                    Digest = $a.digest
                }
                break
            }
        }
        if ($found) { break }
    }
}
if (-not $found) { throw "No suitable release found for pattern $ArchPattern" }

Write-Host ("Found: {0}  ({1} MB, release {2})" -f $found.Name, $found.SizeMB, $found.Tag)
if ($found.Digest) { Write-Host ("Digest: {0}" -f $found.Digest) }

$target = $Dest
$marker = Join-Path $target '.tag'

if ($ListOnly) {
    Write-Host ("Install directory: {0}" -f $target)
    if (Test-Path $marker) { Write-Host ("Currently installed: {0}" -f (Get-Content $marker -Raw).Trim()) }
    exit 0
}

if ((Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $found.Tag) -and -not $Force) {
    Write-Host ("ik_llama.cpp is already up to date here: {0}" -f $found.Tag)
    exit 0
}

$tmp = Join-Path $env:TEMP ("ikllama-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp $found.Name
    Write-Host ("Downloading to {0} ..." -f $zip)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri $found.Url -OutFile $zip -Headers @{ 'User-Agent' = 'ik-llama-update-ps1' } -UseBasicParsing
    $sw.Stop()
    Write-Host ("Downloaded in {0:N0}s" -f $sw.Elapsed.TotalSeconds)

    if ($found.Digest -like 'sha256:*') {
        $want = ($found.Digest -split ':', 2)[1].ToLower()
        $got  = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
        if ($want -ne $got) { throw "sha256 mismatch: expected $want, got $got" }
        Write-Host "sha256 verified."
    } else {
        Write-Host "No digest published by the API; sha256 NOT verified."
    }

    # Back up the build being replaced — never destroy the previous state.
    $prevTag = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { 'unknown' }
    $backup  = Join-Path $target ('_backup-' + $prevTag)
    $existing = Get-ChildItem -Path $target -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.exe', '.dll' }
    if ($existing) {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        $existing | ForEach-Object { Copy-Item $_.FullName -Destination $backup -Force }
        Write-Host ("Backed up {0} file(s) from '{1}' to {2}" -f $existing.Count, $prevTag, $backup)
    }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $target -Force
    Set-Content -Path $marker -Value $found.Tag -NoNewline

    $srv = Get-ChildItem -Path $target -Filter 'llama-server.exe' -Recurse -ErrorAction SilentlyContinue |
           Select-Object -First 1
    Write-Host ("Installed ik_llama.cpp {0} to {1}" -f $found.Tag, $target)
    if ($srv) {
        Write-Host ("  llama-server.exe: {0}" -f $srv.FullName)
        Write-Host ("  built: {0}" -f $srv.LastWriteTime)
    }
    if ($existing) { Write-Host ("Previous build recoverable at {0}" -f $backup) }
}
finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
