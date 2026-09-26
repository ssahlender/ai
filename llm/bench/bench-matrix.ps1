<#
.SYNOPSIS
    Measure installed engines without downloading, extracting, or changing their state.

.DESCRIPTION
    This deliberately does not call the updater, write .tag, or replace any engine files.
    Update engines separately, then run this read-only benchmark against the selected binary.
#>
[CmdletBinding()]
param(
    [string]$LlmRoot = 'C:\data\llm',
    [string]$BenchExe = '',
    [int]$Repeats = 3
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $BenchExe) { $BenchExe = Join-Path $LlmRoot 'llama.cpp-cpu\llama-bench.exe' }
if (-not (Test-Path $BenchExe)) { throw "installed benchmark executable not found: $BenchExe. Run update-llm.ps1 separately; this script will not install it." }

$jobs = @(
    @{ m = (Join-Path $LlmRoot 'models\gemma-4-26B_q4_0-it.gguf'); log = (Join-Path $LlmRoot 'bench-gemma-mlcpu.txt'); label = 'Gemma 4 26B-A4B QAT' },
    @{ m = (Join-Path $LlmRoot 'models\Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf'); log = (Join-Path $LlmRoot 'bench-inc-mlcpu.txt'); label = 'incumbent Qwen3.6-35B-A3B' }
)

foreach ($j in $jobs) {
    if (-not (Test-Path $j.m)) { throw "model missing: $($j.m). Matrix is incomplete; no partial result is reported." }
    Write-Output ("=== installed engine / " + $j.label + " ===")
    & $BenchExe -m $j.m -ngl 0 -p 8,128 -n 128 -r $Repeats *> $j.log
    if ($LASTEXITCODE -ne 0) { throw "benchmark failed for $($j.label) with exit code $LASTEXITCODE. Matrix is incomplete; no partial result is reported." }
    $metrics = Get-Content $j.log | Select-String -Pattern 'pp8|pp128|tg128|build:'
    if (-not $metrics) { throw "benchmark wrote no metrics for $($j.label). Matrix is incomplete; no partial result is reported." }
    $metrics | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
}
Write-Output '=== matrix complete (read-only engine measurement) ==='
