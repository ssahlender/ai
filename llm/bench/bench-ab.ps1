# OBSOLETE (2026-09-27): this A/B compared the incumbent against gemma-4-26B on BOTH engines.
# Gemma was deleted (unverified provenance) and the ik_llama engine directory was removed, so
# neither half of the comparison is measurable here any more. Kept as the record of the method;
# the guard below refuses rather than half-reporting. For what IS installed, use bench-matrix.ps1.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# llm/bench/ -> llm/lib/common.ps1 (Invoke-NativeToFile, New-RunLogPath)
. (Join-Path (Split-Path $PSScriptRoot -Parent) "lib\common.ps1")

$base = "C:\data\llm"
$ik = "$base\ik_llama\llama-bench.exe"
$ml = "$base\llama.cpp-cpu\llama-bench.exe"
$inc = "$base\models\Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf"
$gem = "$base\models\gemma-4-26B_q4_0-it.gguf"
# gemma and ik_llama were removed 2026-09-27, so most of this A/B's inputs are gone. Refuse
# loudly rather than fail inside llama-bench with an unhelpful loader error.
foreach ($p in @($ik, $ml, $inc, $gem)) {
    if (-not (Test-Path $p)) {
        throw "bench-ab.ps1 needs $p, which is not on disk, so this A/B cannot run. It is obsolete as of 2026-09-27 (gemma deleted, ik_llama engine removed); use bench-matrix.ps1 for the installed models. llm/MODELS.md records what each file was and where to fetch it."
    }
}
# Run output belongs in logs\, and a timestamped name means a re-run keeps the previous numbers
# instead of destroying them.
$log = New-RunLogPath -Name "bench-ab" -LlmRoot $base

function Run-One($exe, $model, $tag, $extra) {
    $ts = Get-Date -Format "HH:mm:ss"
    $cmdArgs = @("-m", $model, "-ngl", "0", "-t", "8") + $extra
    $code = Invoke-NativeToFile -Exe $exe -Arguments $cmdArgs -LogPath "$base\_ab_tmp.txt"
    if ($code -ne 0) {
        $detail = (Get-Content "$base\_ab_tmp.txt" -Tail 20 | Out-String).Trim()
        throw "benchmark '$tag' failed with exit code $code. No partial result is being reported. $detail"
    }
    $line = (Get-Content "$base\_ab_tmp.txt" | Select-String -Pattern "\|\s+\S+\s+\|.*\|\s+(pp\d+|tg\d+)\s+\|" | ForEach-Object { $_.Line.Trim() })
    if (-not $line) { throw "benchmark '$tag' produced no parseable metrics. No partial result is being reported." }
    $out = "[" + $ts + "] " + $tag
    Write-Output $out
    Add-Content $log $out
    foreach ($l in $line) { Write-Output ("    " + $l); Add-Content $log ("    " + $l) }
}

Write-Output "=== controlled A/B, alternating engines (decode-only, -p 0 -n 128 -r 2) ==="
foreach ($pass in 1, 2) {
    Write-Output ("--- pass $pass : incumbent ---")
    Run-One $ik $inc "PASS$pass ik_llama/incumbent"  @("-p", "0", "-n", "128", "-r", "2")
    Run-One $ml $inc "PASS$pass mainline/incumbent" @("-p", "0", "-n", "128", "-r", "2")
    Write-Output ("--- pass $pass : gemma ---")
    Run-One $ik $gem "PASS$pass ik_llama/gemma"     @("-p", "0", "-n", "128", "-r", "2")
    Run-One $ml $gem "PASS$pass mainline/gemma"     @("-p", "0", "-n", "128", "-r", "2")
}

Write-Output "=== spec-decode gate for the winning combo: mainline + Gemma small-k ==="
Run-One $ml $gem "mainline/gemma small-k" @("-p", "2,4,8", "-n", "128", "-r", "2")

Remove-Item "$base\_ab_tmp.txt" -Force -ErrorAction SilentlyContinue
Write-Output ("=== done, log: " + $log + " ===")
