$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$base = "C:\data\llm"
$exe  = "$base\llama.cpp-cpu\llama-cli.exe"
$m    = "$base\models\gemma-4-26B_q4_0-it.gguf"
$mtp  = "$base\models\mtp-gemma-4-26B-A4B-it-F16.gguf"
$prompt = "Explain in detail how a bicycle works, step by step."

$common = @("-m", $m, "-ngl", "0", "-t", "8", "-n", "128", "--temp", "0", "-st", "-p", $prompt)

$runs = @(
    @{ tag = "BASELINE no-spec";              extra = @() },
    @{ tag = "MTP n-max=2";                   extra = @("-md", $mtp, "--spec-type", "draft-mtp", "--spec-draft-n-max", "2") },
    @{ tag = "MTP n-max=4";                   extra = @("-md", $mtp, "--spec-type", "draft-mtp", "--spec-draft-n-max", "4") },
    @{ tag = "ngram-mod self-spec (no drafter)"; extra = @("--spec-type", "ngram-mod") }
)

foreach ($r in $runs) {
    $safe = ($r.tag -replace '[^a-zA-Z0-9\-]', '_')
    $log  = "$base\mtp-$safe.txt"
    Write-Output ("=== " + $r.tag + " ===")
    & $exe @($common + $r.extra) *> $log
    Write-Output ("  exit = " + $LASTEXITCODE)
    Get-Content $log -ErrorAction SilentlyContinue |
        Select-String -Pattern "eval time|tokens per second|acceptance|accepted|n_draft|draft|error|failed|not supported" |
        Select-Object -Last 10 |
        ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
}

Write-Output "=== done ==="
