# OBSOLETE (2026-09-27): the MTP drafter was gemma-4-26B-specific and both that model and the
# ik_llama engine are gone from this box. Kept as the record of the measurement (MTP was 12-26%
# slower at k=2/4); the guard below refuses rather than running half a spec-decode test.
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$base = "C:\data\llm"
$exe  = "$base\llama.cpp-cpu\llama-cli.exe"
$m    = "$base\models\gemma-4-26B_q4_0-it.gguf"
$mtp  = "$base\models\mtp-gemma-4-26B-A4B-it-F16.gguf"
# These three files were removed 2026-09-27 (gemma's provenance was unverified). Refuse loudly.
foreach ($p in @($exe, $m, $mtp)) {
    if (-not (Test-Path $p)) {
        throw "bench-mtp.ps1 needs $p, which is not on disk. Nothing is measured. llm/MODELS.md records what each file was and where to fetch it."
    }
}
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
