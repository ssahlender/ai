$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$base = "C:\data\llm"
$exe  = "$base\llama.cpp-cpu\llama-cli.exe"
$m    = "$base\models\gemma-4-26B_q4_0-it.gguf"
$mtp  = "$base\models\mtp-gemma-4-26B-A4B-it-F16.gguf"
$prompt = "Explain in detail how a bicycle works, step by step."

# Verbose run with MTP enabled: look for draft/accept/spec traffic in the log.
$log = "$base\mtp-verbose-k2.txt"
$cmdArgs = @("-m", $m, "-md", $mtp, "--spec-type", "draft-mtp", "--spec-draft-n-max", "2",
             "-ngl", "0", "-t", "8", "-n", "64", "--temp", "0", "-st", "-p", $prompt, "-v")
Write-Output "=== verbose MTP k=2 (n=64) ==="
& $exe @cmdArgs *> $log
Write-Output ("  exit = " + $LASTEXITCODE)

Write-Output "=== draft/accept/spec lines ==="
Get-Content $log -ErrorAction SilentlyContinue |
    Select-String -Pattern "draft|accept|spec|nextn|mtp" |
    Select-Object -First 25 |
    ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output "=== timing line ==="
Get-Content $log -ErrorAction SilentlyContinue |
    Select-String -Pattern "Prompt:|\| Generation:" |
    ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output "=== error/warning lines (deduped) ==="
Get-Content $log -ErrorAction SilentlyContinue |
    Select-String -Pattern "error|failed|requires" |
    Select-Object -Unique -First 8 |
    ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output "=== done ==="
