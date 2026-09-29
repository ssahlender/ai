<#
.SYNOPSIS
    Measure installed engines without downloading, extracting, or changing their state.

.DESCRIPTION
    This deliberately does not call the updater, write .tag, or replace any engine files.
    Update engines separately, then run this read-only benchmark against the selected binary.

    The matrix covers every .gguf found in the models directory - discovered at run time rather
    than hardcoded, so it always matches what is actually installed. Labels are the file stems.
    Numbers are only comparable between models measured in the same run on the same engine.

    A failed or empty run throws - a partial matrix is never reported as a result.
#>
[CmdletBinding()]
param(
    [string]$LlmRoot = 'C:\data\llm',
    [string]$BenchExe = '',
    [int]$Repeats = 3
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# llm/bench/ -> llm/lib/common.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')

if (-not $BenchExe) { $BenchExe = Join-Path $LlmRoot 'llama.cpp-cpu\llama-bench.exe' }
if (-not (Test-Path $BenchExe)) { throw "installed benchmark executable not found: $BenchExe. Run update-llm.ps1 separately; this script will not install it." }

# Whatever is installed, whatever its quant - the list is discovered, not hardcoded, so a
# benchmark can never again be impossible to run because its model list outlived the models.
$modelDir = Join-Path $LlmRoot 'models'
$jobs = @()
foreach ($f in (Get-ChildItem -Path $modelDir -Filter *.gguf -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $jobs += @{ f = $f.Name; label = $f.BaseName }
}
if ($jobs.Count -eq 0) {
    throw "no .gguf files in $modelDir - nothing to measure. Fetch one first (llm/MODELS.md records the sources)."
}
Write-Output ("matrix over " + $jobs.Count + " installed model(s) in " + $modelDir)

foreach ($j in $jobs) {
    $modelPath = Join-Path $modelDir $j.f
    if (-not (Test-Path $modelPath)) {
        throw "model missing: $modelPath. Matrix is incomplete; no partial result is reported."
    }
    $slug = ('bench-' + ($j.label -replace '[^A-Za-z0-9]+', '-')).Trim('-')
    $log = New-RunLogPath -Name $slug -LlmRoot $LlmRoot
    Write-Output ("=== " + $j.label + " ===")
    $code = Invoke-NativeToFile -Exe $BenchExe -Arguments @('-m', $modelPath, '-ngl', '0', '-p', '8,128', '-n', '128', '-r', "$Repeats") -LogPath $log
    if ($code -ne 0) {
        throw "benchmark failed for $($j.label) with exit code $code. Matrix is incomplete; no partial result is reported."
    }
    $metrics = Get-Content $log | Select-String -Pattern 'pp8|pp128|tg128|build:'
    if (-not $metrics) {
        throw "benchmark wrote no metrics for $($j.label). Matrix is incomplete; no partial result is reported."
    }
    $metrics | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
    Write-Output ("  log: " + $log)
}
Write-Output '=== matrix complete (read-only engine measurement) ==='
