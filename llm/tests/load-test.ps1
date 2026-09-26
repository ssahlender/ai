<#
.SYNOPSIS
    Load one GGUF with llama-server and report whether it comes up, how long it took and how much
    RAM it held - so a model can be verified (or a quant chosen) before anything is wired to it.

.DESCRIPTION
    Deliberately independent of start-llm.ps1's mode table: this answers "does this file load and
    what does it cost on THIS box" for a file that has no mode entry yet. It starts the server,
    polls /health (a listening port is NOT readiness - llama-server binds before the model is
    loaded), records peak working set, then stops the server it started and nothing else.

.PARAMETER Model
    Full path to the .gguf to test.

.EXAMPLE
    .\load-test.ps1 -Model C:\data\llm\models\Some-Model-Q3_K_M.gguf
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Model,
    [int]$Port = 9080,
    [int]$Ctx = 32768,
    [string]$ServerExe = 'C:\data\llm\llama.cpp-cpu\llama-server.exe',
    [int]$TimeoutSec = 900,
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\common.ps1')
if (-not $OutFile) { $OutFile = New-RunLogPath -Name 'load-test' }
$status = "$OutFile.status"

if (-not (Test-Path $Model)) { throw "model not found: $Model" }
if (-not (Test-Path $ServerExe)) { throw "server not found: $ServerExe" }

$name = Split-Path $Model -Leaf
"$name : starting" | Set-Content $status -Encoding UTF8
"=== load test: $name (ctx $Ctx, port $Port) ==="

$args = @(
    '-m', $Model, '-ngl', '0', '--threads', '8', '--threads-batch', '8', '--parallel', '1',
    '--ctx-size', "$Ctx", '-ctk', 'q8_0', '-ctv', 'q8_0', '--port', "$Port", '--host', '127.0.0.1',
    '-v', '--jinja'
)
$proc = Start-Process -FilePath $ServerExe -ArgumentList $args -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $OutFile -RedirectStandardError "$OutFile.err" -ErrorAction SilentlyContinue
if (-not $proc) { throw "failed to start $ServerExe" }

$peak = 0
$health = Wait-ServerHealth -Port $Port -TimeoutSec $TimeoutSec -IntervalSec 3 -Process $proc -OnTick {
    param($waited)
    $proc.Refresh()
    if ($proc.WorkingSet64 -gt $peak) { $peak = $proc.WorkingSet64 }
    "$name : waiting ${waited}s, ws $([Math]::Round($peak / 1GB, 1)) GB" |
        Set-Content $status -Encoding UTF8
}

if ($health.Ok) {
    $proc.Refresh()
    $ws = [Math]::Round($proc.WorkingSet64 / 1GB, 1)
    $res = "LOADED in $($health.Waited)s, working set $ws GB (peak seen $([Math]::Round($peak / 1GB, 1)) GB)"
    $res | Set-Content $status -Encoding UTF8
    $res
    "  health: ok   pid $($proc.Id)"
} else {
    $why = 'timeout'
    if ($proc.HasExited) { $why = "exited with code $($proc.ExitCode)" }
    $res = "FAILED: $why after $($health.Waited)s ($($health.LastErr))"
    $res | Set-Content $status -Encoding UTF8
    $res
    if (Test-Path "$OutFile.err") { "  --- last 12 stderr lines ---"; Get-Content "$OutFile.err" -Tail 12 | ForEach-Object { "  | $_" } }
}

# stop ONLY the process this script started
Stop-OwnedProcess -Process $proc | Out-Null
Start-Sleep -Seconds 2
"stopped $($proc.Id)"
