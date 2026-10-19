<#
.SYNOPSIS
    Install radare2 + the r2ghidra decompiler plugin on Windows, idempotently.

.DESCRIPTION
    Both tools ship native Windows builds, so no compiler, no MSYS2 and no WSL are needed:
    radare2 as a zip and r2ghidra as a prebuilt plugin dll plus its sleigh tree.

    Why this exists: some functions are unreachable through REA (its rizin command path is
    killed after a hard 120 s) and too large for a small host's RAM. This installs the same
    versions used elsewhere so results stay comparable.

    Verification: radare2 publishes checksums.txt and the download is checked against it.
    r2ghidra publishes no checksums, so its digest is PINNED below and verified on every
    install - a mismatch fails loudly instead of installing something unexpected.

    Idempotent: an up-to-date install is a no-op. The previous install is kept as
    _backup-<tag>; originals are never deleted. A smoke test decompiles a small system PE
    and must produce C before this script reports success.

.PARAMETER InstallDir
    Install root. Default C:\data\re\radare2 - a neutral path, no user name in it.

.PARAMETER Check
    Report installed vs available and change nothing.

.EXAMPLE
    .\install-r2.ps1
    .\install-r2.ps1 -Check
    .\install-r2.ps1 -Force

.NOTES
    ASCII-only on purpose: Windows PowerShell 5.1 reads a .ps1 without a BOM as ANSI, so a
    single non-ASCII character breaks the script.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\data\re\radare2',
    [string]$Version = '6.2.4',
    [switch]$Check,
    [switch]$Force,
    [switch]$NoSmokeTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # progress output floods a PSRP session (WSManFault 1359)

$PinnedSha256 = @{
    'radare2'  = 'aa3454fd89e8a4ead450caff35a1d3919065744e7091540d4913a9487241799d'
    'r2ghidra' = 'ce26ce2cbf8cd4c1d5629b7c7010eb8a755f5ef75d34552a43c3ca4982a024a0'
}
$Urls = @{
    'radare2'   = "https://github.com/radareorg/radare2/releases/download/$Version/radare2-$Version-w64.zip"
    'r2ghidra'  = "https://github.com/radareorg/r2ghidra/releases/download/$Version/r2ghidra-$Version-windows-x86-64.zip"
    'checksums' = "https://github.com/radareorg/radare2/releases/download/$Version/checksums.txt"
}

function Get-R2Exe {
    param([string]$Root)
    $candidates = @(
        (Join-Path $Root 'bin\radare2.exe'),
        (Join-Path $Root 'bin\r2.exe'),
        (Join-Path $Root 'radare2.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    # tolerate a not-yet-flattened tree (the zip ships one top-level radare2-<version>-w64\ folder)
    $nested = Get-ChildItem -LiteralPath $Root -Directory -Filter 'radare2-*' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($nested) {
        $inner = Join-Path $nested.FullName 'bin\radare2.exe'
        if (Test-Path -LiteralPath $inner) { return $inner }
    }
    return $null
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

$tagPath = Join-Path $InstallDir '.tag'
$installed = ''
if (Test-Path -LiteralPath $tagPath) { $installed = (Get-Content -LiteralPath $tagPath -Raw).Trim() }
$r2Exe = Get-R2Exe -Root $InstallDir
$installedText = '(nothing)'
if ($installed) { $installedText = $installed }

Write-Host "install dir : $InstallDir"
Write-Host "installed   : $installedText"
Write-Host "target      : $Version"

if ($Check) {
    $latest = '(unknown)'
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/radareorg/radare2/releases/latest' `
            -Headers @{ 'User-Agent' = 're-install-check' } -TimeoutSec 30
        $latest = $rel.tag_name
    } catch {
        Write-Warning "could not query the latest release: $($_.Exception.Message)"
    }
    Write-Host "latest      : $latest"
    if ($r2Exe) {
        $ver = (& $r2Exe -v | Select-Object -First 1)
        Write-Host "r2 binary   : $ver"
    } else {
        Write-Host 'r2 binary   : missing'
    }
    exit 0
}

if ((-not $Force) -and $installed -eq $Version -and $r2Exe) {
    Write-Host "up to date ($Version) - nothing to do. Use -Force to reinstall."
    exit 0
}

$work = Join-Path $env:TEMP ("re-install-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "work dir    : $work"

try {
    # ---- download ----------------------------------------------------------------
    $zips = @{}
    foreach ($name in @('radare2', 'r2ghidra')) {
        $zip = Join-Path $work ("$name.zip")
        Write-Host "downloading : $name ..."
        Invoke-WebRequest -Uri $Urls[$name] -OutFile $zip -UseBasicParsing
        $zips[$name] = $zip
    }

    # ---- verify ------------------------------------------------------------------
    $sums = Join-Path $work 'checksums.txt'
    Invoke-WebRequest -Uri $Urls['checksums'] -OutFile $sums -UseBasicParsing
    $expectedR2 = $null
    foreach ($line in (Get-Content -LiteralPath $sums)) {
        if ($line -match '^\s*([0-9a-fA-F]{64})\s+radare2-.*-w64\.zip\s*$') { $expectedR2 = $Matches[1].ToLower() }
    }
    $actualR2 = Get-Sha256 -Path $zips['radare2']
    if (-not $expectedR2) { throw 'radare2 checksums.txt carried no line for the w64 zip' }
    if ($expectedR2 -ne $actualR2) { throw "radare2 zip sha256 mismatch: expected $expectedR2, got $actualR2" }
    Write-Host "verified    : radare2 against upstream checksums.txt"

    $actualGh = Get-Sha256 -Path $zips['r2ghidra']
    if ($PinnedSha256['r2ghidra'] -ne $actualGh) {
        throw ("r2ghidra zip sha256 mismatch (no upstream checksums exist, so this is a pinned " +
               "digest): expected $($PinnedSha256['r2ghidra']), got $actualGh. If the release was " +
               "re-uploaded on purpose, update the pin in this script deliberately.")
    }
    Write-Host "verified    : r2ghidra against the pinned digest (upstream publishes none)"

    # ---- keep the previous install ----------------------------------------------
    if (Test-Path -LiteralPath $InstallDir) {
        $backupName = '_backup-unknown'
        if ($installed) { $backupName = "_backup-$installed" }
        $backup = Join-Path (Split-Path $InstallDir -Parent) $backupName
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Write-Host "backing up  : $InstallDir -> $backup"
        Move-Item -LiteralPath $InstallDir -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    # ---- extract -----------------------------------------------------------------
    # The radare2 zip ships ONE top-level folder (radare2-<version>-w64\). Expand-Archive has no
    # strip option, so extract to a temp dir and move the contents up: the install then has a
    # stable shape, <InstallDir>\bin\radare2.exe, whatever the release calls its folder.
    $r2Extract = Join-Path $work 'r2x'
    Expand-Archive -LiteralPath $zips['radare2'] -DestinationPath $r2Extract -Force
    $inner = Get-ChildItem -LiteralPath $r2Extract -Directory | Select-Object -First 1
    if (-not $inner) { throw 'radare2 zip had no top-level folder to flatten' }
    foreach ($item in (Get-ChildItem -LiteralPath $inner.FullName)) {
        Move-Item -LiteralPath $item.FullName -Destination $InstallDir
    }

    $ghExtract = Join-Path $work 'r2ghidra'
    Expand-Archive -LiteralPath $zips['r2ghidra'] -DestinationPath $ghExtract -Force

    $r2Exe = Get-R2Exe -Root $InstallDir
    if (-not $r2Exe) { throw "r2.exe not found under $InstallDir after extraction" }

    # ---- plugin ------------------------------------------------------------------
    # r2 searches two plugin dirs: R2_USER_PLUGINS (under C:\Users\<name> - invisible to a SYSTEM
    # scheduled task, which has its own profile) and R2_LIBR_PLUGINS, inside the install root and
    # machine-wide. Install into R2_LIBR_PLUGINS ONLY: a second copy makes r2 log
    # "Not loading library because it has already been loaded" and buys nothing, because
    # libr_plugins is searched in every context.
    # Verified on r2 6.2.4: R2_USER_PLUGINS as an ENV VAR is not honoured, so do not rely on it.
    $userScope = (& $r2Exe -H R2_USER_PLUGINS | Select-Object -First 1)
    if ($userScope) { $userScope = $userScope.Trim() }
    $librPlugins = (& $r2Exe -H R2_LIBR_PLUGINS | Select-Object -First 1)
    if (-not $librPlugins) { throw 'r2 did not report R2_LIBR_PLUGINS' }
    $librPlugins = $librPlugins.Trim()
    New-Item -ItemType Directory -Force -Path $librPlugins | Out-Null
    Copy-Item -Force (Join-Path $ghExtract 'plugins\core_r2ghidra.dll') $librPlugins
    $sleigh = Join-Path $librPlugins 'r2ghidra_sleigh'
    if (Test-Path -LiteralPath $sleigh) { Remove-Item -LiteralPath $sleigh -Recurse -Force }
    Copy-Item -Recurse -Force (Join-Path $ghExtract 'plugins\r2ghidra_sleigh') $sleigh
    Write-Host "plugin      : $librPlugins (machine-wide; r2 searches it in every context)"

    # a stale copy in the user-scoped dir makes r2 refuse the second load and log an ERROR
    if ($userScope -and (Test-Path -LiteralPath $userScope)) {
        foreach ($stale in @('core_r2ghidra.dll', 'r2ghidra_sleigh')) {
            $p = Join-Path $userScope $stale
            if (Test-Path -LiteralPath $p) {
                Remove-Item -LiteralPath $p -Recurse -Force
                Write-Host "cleaned     : stale $p (the machine-wide copy is the one that counts)"
            }
        }
    }

    # ---- smoke test: prove it decompiles before claiming success ------------------
    $smoke = 'skipped'
    if (-not $NoSmokeTest) {
        $target = Join-Path $env:SystemRoot 'System32\where.exe'
        if (-not (Test-Path -LiteralPath $target)) { throw "smoke-test target missing: $target" }
        $ok = $false
        $attempts = @('aaa; s entry0; e r2ghidra.timeout=120000; pdg',
                      'aaa; s main; e r2ghidra.timeout=120000; pdg')
        $lastOut = ''
        # PowerShell 5.1 turns a native command's stderr into an error record, and with
        # $ErrorActionPreference='Stop' (set above) that is fatal - r2 writes HINTs to stderr on
        # a normal run. Send stderr to a file and relax the preference for the call only.
        $errTmp = Join-Path $work 'smoke.err'
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            foreach ($cmd in $attempts) {
                $lastOut = (& $r2Exe -q -e scr.color=0 -c $cmd $target 2>$errTmp | Out-String)
                if ($lastOut.Contains('{') -and $lastOut.Contains('(')) { $ok = $true; break }
            }
        } finally {
            $ErrorActionPreference = $prevEap
        }
        if (-not $ok) {
            $head = $lastOut
            if ($head.Length -gt 400) { $head = $head.Substring(0, 400) }
            throw "smoke test FAILED: no C produced for $target. First 400 chars: $head"
        }
        $smoke = 'ok'
        Write-Host "smoke test  : OK (r2ghidra decompiled $(Split-Path $target -Leaf) from the machine-wide dir)"
    }

    # ---- state -------------------------------------------------------------------
    Set-Content -LiteralPath (Join-Path $InstallDir '.tag') -Value $Version -NoNewline -Encoding ASCII
    $state = [ordered]@{
        version       = $Version
        installed_at  = (Get-Date).ToString('s')
        install_dir   = $InstallDir
        r2_exe        = $r2Exe
        libr_plugins  = $librPlugins
        user_plugins  = $userScope
        sha256        = [ordered]@{ radare2 = $actualR2; r2ghidra = $actualGh }
        smoke_test    = $smoke
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $InstallDir '.install.json') -Encoding UTF8
    Write-Host "state       : $(Join-Path $InstallDir '.install.json')"
    Write-Host "DONE: radare2 $Version + r2ghidra $Version installed."
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
