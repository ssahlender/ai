$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$base = "C:\data\llm"

Write-Output "=== 1) download mainline CPU-only build (b11201) ==="
$zip = "$base\llama-b11201-bin-win-cpu-x64.zip"
curl.exe -sS -L --retry 5 --retry-delay 3 -o $zip "https://github.com/ggml-org/llama.cpp/releases/download/b11201/llama-b11201-bin-win-cpu-x64.zip"
Write-Output ("cpu zip bytes = " + (Get-Item $zip).Length)
Expand-Archive -Path $zip -DestinationPath "$base\llama.cpp-cpu" -Force
"b11201-cpu" | Set-Content "$base\llama.cpp-cpu\.tag"
Get-ChildItem "$base\llama.cpp-cpu\ggml-cpu-*.dll" -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ("  dll: " + $_.Name) }
Write-Output ("  exe: " + (Test-Path "$base\llama.cpp-cpu\llama-bench.exe"))

$exe = "$base\llama.cpp-cpu\llama-bench.exe"
$jobs = @(
    @{ m = "$base\models\gemma-4-26B_q4_0-it.gguf";                                  log = "$base\bench-gemma-mlcpu.txt";  label = "Gemma 4 26B-A4B QAT" },
    @{ m = "$base\models\Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf"; log = "$base\bench-inc-mlcpu.txt";   label = "incumbent Qwen3.6-35B-A3B" }
)

foreach ($j in $jobs) {
    Write-Output ("=== 2) mainline CPU build b11201 / " + $j.label + " ===")
    & $exe -m $j.m -ngl 0 -p 8,128 -n 128 -r 3 *> $j.log
    Write-Output ("  exit = " + $LASTEXITCODE)
    Get-Content $j.log -ErrorAction SilentlyContinue |
        Select-String -Pattern "pp8|pp128|tg128|build:|error|failed" |
        ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
}

Write-Output "=== 3) ik_llama cross-check (same models, b5311) ==="
Write-Output "  (already measured; files: bench-gemma-ikllama.txt, bench-inc-pp128.txt)"
