$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$base = "C:\data\llm"
$ik = "$base\ik_llama\llama-bench.exe"
$ml = "$base\llama.cpp-cpu\llama-bench.exe"
$inc = "$base\models\Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf"
$gem = "$base\models\gemma-4-26B_q4_0-it.gguf"
$log = "$base\bench-ab.txt"
if (Test-Path $log) { Remove-Item $log -Force }

function Run-One($exe, $model, $tag, $extra) {
    $ts = Get-Date -Format "HH:mm:ss"
    $cmdArgs = @("-m", $model, "-ngl", "0", "-t", "8") + $extra
    & $exe @cmdArgs *> "$base\_ab_tmp.txt"
    if ($LASTEXITCODE -ne 0) {
        $detail = (Get-Content "$base\_ab_tmp.txt" -Tail 20 | Out-String).Trim()
        throw "benchmark '$tag' failed with exit code $LASTEXITCODE. No partial result is being reported. $detail"
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
