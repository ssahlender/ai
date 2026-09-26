<#
.SYNOPSIS
    Update the local inference engines (Windows) that actually work on this box.

.DESCRIPTION
    Engine-aware updater. Generalizes ik-llama/update.ps1 (kept as history) which only
    ever handled ik_llama. Resolves the newest matching release asset per engine, verifies
    the GitHub-published sha256 digest, backs up the build being replaced, extracts in
    place, and writes a .tag marker so "up to date" is a cheap comparison.

    Which engines live where (and why):
      mainline        C:\data\llm\llama.cpp-cpu   daily engine  (legacy quants / Q4_0)
      ik_llama        C:\data\llm\ik_llama        i-quant specialist (IQ4_NL/IQ4_XS)
    Not tracked on purpose: ROCm (no HIP device for gfx1103 on this box).

    Engines get separate directories because each ships its own llama.dll / ggml.dll;
    mixing them loads the wrong kernels. Models are shared in C:\data\llm\models.

.PARAMETER Engine
    One or more engine keys, or 'all'. Default: mainline, ik_llama (the working pair).

.PARAMETER ListOnly
    Resolve and report what is installed vs available; download nothing.

.PARAMETER Force
    Reinstall even when the .tag already matches the newest release.

.PARAMETER PurgeOldBackups
    After a successful install, delete every _backup-* directory except the newest one.

.PARAMETER AllowUnverifiedAsset
    Permit installation only when GitHub omitted the release sha256 digest. This is opt-in
    because the previous updater silently installed an unverifiable binary.

.EXAMPLE
    .\update-llm.ps1 -ListOnly
    .\update-llm.ps1
    .\update-llm.ps1 -Engine ik_llama -Force
    .\update-llm.ps1 -Engine all -PurgeOldBackups
#>
[CmdletBinding()]
param(
    [string[]]$Engine = @('mainline', 'ik_llama'),
    [switch]$ListOnly,
    [switch]$Force,
    [switch]$PurgeOldBackups,
    [switch]$AllowUnverifiedAsset
)

$ErrorActionPreference = 'Stop'

# Same directory: lib\common.ps1 provides Get-NativeOutput. The staged-binary acceptance check
# runs `llama-server --version`, which writes to stderr - merged into the success stream under
# 'Stop' that raises NativeCommandError and aborts the update mid-flight.
. (Join-Path $PSScriptRoot 'lib\common.ps1')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'update-llm-ps1' }

$EngineTable = @(
    [pscustomobject]@{
        Key     = 'mainline'
        Repo    = 'ggml-org/llama.cpp'
        Pattern = '^llama-(?!cudart\b).+-bin-win-cpu-x64\.zip$'
        Dest    = 'C:\data\llm\llama.cpp-cpu'
        Role    = 'daily engine (legacy quants / Q4_0)'
    }
    [pscustomobject]@{
        Key     = 'ik_llama'
        Repo    = 'Thireus/ik_llama.cpp'
        Pattern = '^ik_llama-(?!cudart\b).+-bin-win-cpu-x64-avx512_vnni_vbmi_bf16\.zip$'
        Dest    = 'C:\data\llm\ik_llama'
        Role    = 'i-quant specialist (IQ4_NL / IQ4_XS)'
    }
)

if ($Engine -contains 'all') { $Engine = $EngineTable.Key }

function Get-LatestAsset {
    param([string]$Repo, [string]$Pattern)
    $re = [regex]$Pattern
    for ($page = 1; $page -le 3; $page++) {
        $uri = "https://api.github.com/repos/$Repo/releases?per_page=5&page=$page"
        $releases = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 60
        if (-not $releases) { break }
        foreach ($r in $releases) {
            foreach ($a in $r.assets) {
                if ($re.IsMatch($a.name)) {
                    return [pscustomobject]@{
                        Tag    = $r.tag_name
                        Name   = $a.name
                        SizeMB = [math]::Round($a.size / 1MB, 1)
                        Url    = $a.browser_download_url
                        Digest = $a.digest
                    }
                }
            }
        }
    }
    return $null
}

function Install-Asset {
    param($Asset, [string]$Dest, [switch]$AllowUnverified)
    $marker = Join-Path $Dest '.tag'
    $tmp = Join-Path $env:TEMP ('llmupd-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zip = Join-Path $tmp $Asset.Name
        Write-Host ("    downloading {0} MB ..." -f $Asset.SizeMB)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        curl.exe -sS -L --retry 5 --retry-delay 3 -o $zip $Asset.Url
        $sw.Stop()
        if ($LASTEXITCODE -ne 0) { throw "download failed with curl exit code $LASTEXITCODE" }
        if (-not (Test-Path $zip)) { throw "download failed (no file at $zip)" }
        Write-Host ("    downloaded in {0:N0}s" -f $sw.Elapsed.TotalSeconds)

        if ($Asset.Digest -like 'sha256:*') {
            $want = ($Asset.Digest -split ':', 2)[1].ToLower()
            $got  = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
            if ($want -ne $got) { throw "sha256 mismatch: expected $want, got $got" }
            Write-Host "    sha256 verified"
        } else {
            if (-not $AllowUnverified) { throw 'GitHub published no sha256 digest. Re-run with -AllowUnverifiedAsset only after accepting that risk.' }
            Write-Warning "    no digest published; installing only because -AllowUnverifiedAsset was explicit"
        }

        $stage = Join-Path $tmp 'stage'
        Expand-Archive -Path $zip -DestinationPath $stage -Force
        $stagedServer = Get-ChildItem -Path $stage -Filter 'llama-server.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $stagedServer) { throw 'archive contains no llama-server.exe; live engine was left untouched' }
        $versionText = (Get-NativeOutput -Exe $stagedServer.FullName -Arguments @('--version')).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $versionText) { throw 'staged llama-server.exe did not run successfully; live engine was left untouched' }
        if ($versionText -notmatch [regex]::Escape($Asset.Tag)) { throw "staged build did not report expected release '$($Asset.Tag)'; live engine was left untouched" }
        Write-Host ("    staged binary accepted: {0}" -f ($versionText -replace "`r?`n", ' '))

        $prevTag  = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { 'unknown' }
        $backup   = Join-Path $Dest ('_backup-' + $prevTag)
        $existing = Get-ChildItem -Path $Dest -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in '.exe', '.dll' }
        if ($existing) {
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            $existing | ForEach-Object { Copy-Item $_.FullName -Destination $backup -Force }
            Write-Host ("    backed up {0} file(s) from '{1}'" -f $existing.Count, $prevTag)
        }

        # Acceptance above happens before this in-place replacement. Keep the rollback copy
        # until after it succeeds; the old updater wrote .tag before proving the binary ran.
        Expand-Archive -Path $zip -DestinationPath $Dest -Force
        Set-Content -Path $marker -Value $Asset.Tag -NoNewline

        $srv = Get-ChildItem -Path $Dest -Filter 'llama-server.exe' -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1
        Write-Host ("    installed {0}" -f $Asset.Tag)
        if ($srv) { Write-Host ("    llama-server.exe built {0}" -f $srv.LastWriteTime) }
        if ($existing) { Write-Host ("    previous build recoverable at {0}" -f $backup) }
        return $backup
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$summary = @()
foreach ($key in $Engine) {
    $e = $EngineTable | Where-Object { $_.Key -eq $key }
    if (-not $e) { throw ("unknown engine '{0}' - valid: {1}" -f $key, ($EngineTable.Key -join ', ')) }

    Write-Host ("== {0}  ({1})" -f $e.Key, $e.Role)
    Write-Host ("   dir: {0}" -f $e.Dest)
    $asset  = Get-LatestAsset -Repo $e.Repo -Pattern $e.Pattern
    if (-not $asset) { throw ("no release asset matched {0} for engine '{1}'" -f $e.Pattern, $e.Key) }

    $marker = Join-Path $e.Dest '.tag'
    $haveTag = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { $null }
    if ($haveTag) { $haveDisplay = $haveTag } else { $haveDisplay = '(none)' }
    Write-Host ("   available : {0}  ({1} MB)" -f $asset.Tag, $asset.SizeMB)
    Write-Host ("   installed : {0}" -f $haveDisplay)

    if ($ListOnly) {
        if ($haveTag -eq $asset.Tag) { $state = 'up-to-date' } else { $state = 'UPDATE' }
        $summary += [pscustomobject]@{ Engine = $e.Key; Installed = $haveTag; Available = $asset.Tag; State = $state }
        continue
    }
    if ($haveTag -eq $asset.Tag -and -not $Force) {
        Write-Host "   already up to date (use -Force to reinstall)"
        $summary += [pscustomobject]@{ Engine = $e.Key; Installed = $haveTag; Available = $asset.Tag; State = 'up-to-date' }
        continue
    }

    $backup = Install-Asset -Asset $asset -Dest $e.Dest -AllowUnverified:$AllowUnverifiedAsset
    # Record the variant separately: .tag must stay EXACTLY the release tag, or the
    # up-to-date comparison above never matches (the directory already encodes the variant).
    Set-Content -Path (Join-Path $e.Dest '.variant') -Value $e.Key -NoNewline
    if ($PurgeOldBackups -and $backup) {
        Get-ChildItem -Path $e.Dest -Directory -Filter '_backup-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $backup } |
            ForEach-Object { Write-Host ("    purging old backup {0}" -f $_.Name); Remove-Item $_.FullName -Recurse -Force }
    }
    $summary += [pscustomobject]@{ Engine = $e.Key; Installed = $asset.Tag; Available = $asset.Tag; State = 'updated' }
}

Write-Host ""
Write-Host "=== summary ==="
$summary | Format-Table -AutoSize | Out-String -Width 160
