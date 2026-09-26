<#
.SYNOPSIS
    Measure installed engines without downloading, extracting, or changing their state.

.DESCRIPTION
    This deliberately does not call the updater, write .tag, or replace any engine files.
    Update engines separately, then run this read-only benchmark against the selected binary.

    The matrix covers every model verified to load on this box. Q3_K_M is deliberate for the two
    2026 candidates: same quant class on the same engine makes them comparable to each other,
    while Gemma and the incumbent keep the baselines they were measured at.

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

$jobs = @(
    @{ f = 'gemma-4-26B_q4_0-it.gguf';                                    label = 'Gemma 4 26B-A4B QAT Q4_0' },
    @{ f = 'Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf';  label = 'incumbent Qwen3.6-35B-A3B IQ4_NL' },
    @{ f = 'Kwaipilot_KAT-Coder-V2.5-Dev-Q3_K_M.gguf';                    label = 'KAT-Coder-V2.5-Dev Q3_K_M' },
    @{ f = 'Ornith-1.5-35B-A3B-Q3_K_M.gguf';                              label = 'Ornith-1.5-35B-A3B Q3_K_M' }
)

$modelDir = Join-Path $LlmRoot 'models'
foreach ($j in $jobs) {
    $modelPath = Join-Path $modelDir $j.f
    if (-not (Test-Path $modelPath)) {
        throw "model missing: $modelPath. Matrix is incomplete; no partial result is reported."
    }
    $slug = ('bench-' + ($j.label -replace '[^A-Za-z0-9]+', '-')).Trim('-')
    $log = New-RunLogPath -Name $slug -LlmRoot $LlmRoot
    Write-Output ("=== " + $j.label + " ===")
    & $BenchExe -m $modelPath -ngl 0 -p 8,128 -n 128 -r $Repeats *> $log
    if ($LASTEXITCODE -ne 0) {
        throw "benchmark failed for $($j.label) with exit code $LASTEXITCODE. Matrix is incomplete; no partial result is reported."
    }
    $metrics = Get-Content $log | Select-String -Pattern 'pp8|pp128|tg128|build:'
    if (-not $metrics) {
        throw "benchmark wrote no metrics for $($j.label). Matrix is incomplete; no partial result is reported."
    }
    $metrics | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
    Write-Output ("  log: " + $log)
}
Write-Output '=== matrix complete (read-only engine measurement) ==='
