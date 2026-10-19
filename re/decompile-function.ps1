<#
.SYNOPSIS
    Decompile ONE function with radare2 + r2ghidra directly (no REA) and prove it produced C.

.DESCRIPTION
    The Windows counterpart of r2-decompile.sh. It exists because REA kills any rizin command
    after a hard 120 s (its error envelope reports provider_timeout, timeout_ms 120000,
    SIGKILL), so a function that needs longer is unreachable through REA - while calling r2
    directly has no such ceiling. A measured case: a 132288-byte function that consumed more
    than 9 GiB and had to run on a 32 GB machine.

    Output is streamed to the file with Tee-Object so a dropped session cannot erase it.

    Exit codes: 0 = C produced, 3 = r2 ran but produced no C, 1 = r2 failed.
    Never judge a decompilation by its byte count - check the status.

.PARAMETER Binary
    Path to the binary (a Windows path when run on Windows).

.PARAMETER Address
    Function address or symbol, e.g. 0x00424280 or fcn.00424280.

.PARAMETER OutFile
    Where the C goes. Default: <binary stem>-<address>.c in the current directory.

.PARAMETER TimeoutMs
    r2ghidra's own decompiler budget in milliseconds (default 600000 = 10 min).

.PARAMETER Split
    Drop the function r2 found at this address and re-analyse a fresh one there before
    decompiling. Use when r2 lumped a large region into a single pseudo-function.

.EXAMPLE
    .\decompile-function.ps1 -Binary C:\data\target\MpC_Manager.exe -Address 0x00424280
    .\decompile-function.ps1 -Binary .\app.exe -Address entry0 -TimeoutMs 3000000 -OutFile .\entry.c

.NOTES
    ASCII-only on purpose: Windows PowerShell 5.1 reads a .ps1 without a BOM as ANSI.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Binary,
    [Parameter(Mandatory = $true)][string]$Address,
    [string]$OutFile = '',
    [int]$TimeoutMs = 600000,
    [string]$R2 = '',
    [switch]$Split
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) { throw "binary not found: $Binary" }
$Binary = (Resolve-Path -LiteralPath $Binary).Path

if (-not $R2) {
    # prefer the install's own state file (single source of truth), then the default location, then PATH
    $stateFile = 'C:\data\re\radare2\.install.json'
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $st = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($st.r2_exe) {
                if (Test-Path -LiteralPath $st.r2_exe) { $R2 = $st.r2_exe }
            }
        } catch {
            Write-Warning "could not read $stateFile : $($_.Exception.Message)"
        }
    }
}
if (-not $R2) {
    $candidates = @(
        'C:\data\re\radare2\bin\radare2.exe',
        'C:\data\re\radare2\bin\r2.exe',
        'C:\data\re\radare2\radare2.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $R2 = $c; break }
    }
}
if (-not $R2) {
    $cmd = Get-Command r2 -ErrorAction SilentlyContinue
    if ($cmd) { $R2 = $cmd.Source }
}
if (-not $R2) { throw 'radare2 not found - pass -R2 <path> or run install-r2.ps1 first' }

# The r2ghidra plugin is installed into R2_LIBR_PLUGINS (inside the radare2 install root), which
# r2 searches by itself and which is machine-wide - so an interactive run and a SYSTEM scheduled
# task load the same plugin. R2_USER_PLUGINS as an env var is NOT honoured by r2 6.2.4.
$installRoot = Split-Path (Split-Path $R2 -Parent) -Parent
$librPlugins = Join-Path $installRoot 'lib\plugins'
if (Test-Path -LiteralPath (Join-Path $librPlugins 'core_r2ghidra.dll')) {
    Write-Host "plugins     : $librPlugins"
} else {
    Write-Warning "r2ghidra not found in $librPlugins - pdg will fail. Run install-r2.ps1."
}

if (-not $OutFile) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($Binary)
    $safe = $Address -replace '[^A-Za-z0-9_]', '_'
    $OutFile = Join-Path (Get-Location).Path ("$stem-$safe.c")
}
$outDir = Split-Path $OutFile -Parent
if ($outDir -and (-not (Test-Path -LiteralPath $outDir))) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

# A SYSTEM scheduled task discards the child's stdout, so every run leaves a status file next to
# its output. That file is the only evidence a long unattended run produces; poll it, do not
# assume. It is written at start ('running') and again on every exit path.
function Write-Status {
    param(
        [string]$State,
        [int]$ExitCode,
        [int]$Bytes = 0,
        [int]$Lines = 0,
        [double]$Seconds = 0
    )
    $obj = [ordered]@{
        binary    = $Binary
        address   = $Address
        state     = $State
        exit_code = $ExitCode
        bytes     = $Bytes
        lines     = $Lines
        seconds   = [math]::Round($Seconds, 1)
        out_file  = $OutFile
        started   = $startedAt.ToString('s')
        finished  = (Get-Date).ToString('s')
        host_name = $env:COMPUTERNAME
    }
    try {
        $obj | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath ($OutFile + '.status.json') -Encoding UTF8
    } catch {
        Write-Warning "could not write status file: $($_.Exception.Message)"
    }
}
$startedAt = Get-Date
Write-Status -State 'running' -ExitCode -1

$steps = @('e scr.color=0', 'e bin.relocs.apply=true', 'aaa')
if ($Split) {
    $steps += "af- $Address"
    $steps += "af @ $Address"
}
$steps += "s $Address"
$steps += "e r2ghidra.timeout=$TimeoutMs"
$steps += 'pdg'
$r2Cmd = ($steps -join '; ')

Write-Host "binary      : $Binary"
Write-Host "address     : $Address"
Write-Host "r2          : $R2"
Write-Host "out         : $OutFile"
Write-Host "timeout ms  : $TimeoutMs"
if ($Split) { Write-Host 'split       : on (af- then af @ address)' }
Write-Host '--- r2 running ---'

$started = Get-Date
# Use the Process API instead of `& $r2 ... 2>file`: PowerShell 5.1 turns a native command's
# stderr into an error record, and r2 writes HINTs and plugin notes there on a normal run. That
# both pollutes the output and - under $ErrorActionPreference='Stop' - aborts the pipeline and
# kills r2 mid-run, which looks exactly like a decompiler failure. Streaming stdout line by line
# also means a dropped session cannot erase what has already been written.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $R2
$psi.Arguments = '-q -e scr.color=0 -e bin.relocs.apply=true -c "' + $r2Cmd + '" "' + $Binary + '"'
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
# drain stderr asynchronously: reading stdout to the end first could deadlock on a full stderr pipe
$errTask = $proc.StandardError.ReadToEndAsync()
$writer = New-Object System.IO.StreamWriter($OutFile, $false, [System.Text.Encoding]::ASCII)
try {
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        $writer.WriteLine($line)
        $writer.Flush()
    }
} finally {
    $writer.Close()
}
$errText = $errTask.Result
$proc.WaitForExit()
$rc = $proc.ExitCode
$elapsed = ((Get-Date) - $started).TotalSeconds

Write-Host ("--- r2 finished in {0:N1}s, exit code {1} ---" -f $elapsed, $rc)

if ($errText) {
    $lines = $errText -split "`r?`n" | Where-Object { $_ -and ($_ -notmatch '^(INFO|HINT|WARN|DEBUG):') }
    foreach ($l in ($lines | Select-Object -Last 5)) { Write-Host "  $l" }
}

if ($rc -ne 0) {
    Write-Host "FAILED: r2 exited $rc - no decompilation."
    Write-Status -State 'r2_failed' -ExitCode 1 -Seconds $elapsed
    exit 1
}

$bytes = 0
$body = ''
if (Test-Path -LiteralPath $OutFile) {
    $bytes = (Get-Item -LiteralPath $OutFile).Length
    $body = (Get-Content -LiteralPath $OutFile -Raw)
}
if ((-not $body) -or (-not $body.Contains('{')) -or (-not $body.Contains('('))) {
    Write-Host "FAILED: r2 exited 0 but produced no C ($bytes bytes)."
    Write-Status -State 'no_c' -ExitCode 3 -Bytes $bytes -Seconds $elapsed
    exit 3
}

$lineCount = ($body -split "`r?`n").Count
Write-Host ("OK: {0} bytes, {1} lines of C written to {2}" -f $bytes, $lineCount, $OutFile)
Write-Status -State 'ok' -ExitCode 0 -Bytes $bytes -Lines $lineCount -Seconds $elapsed
exit 0
