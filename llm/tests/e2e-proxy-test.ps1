<# Proves both Claude-compatible and OpenAI-compatible proxy calls. Failures are assertions,
   not informational output: the previous test printed failures but returned exit code 0. #>
[CmdletBinding()]
param(
    [string]$ModelPath = '',
    [int]$ServerPort = 9080,
    [int]$ProxyPort = 9081
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path (Split-Path -Parent $here) 'lib\common.ps1')
$root = Get-LlmRoot
if (-not $ModelPath) { $ModelPath = Join-Path $root 'models\tinystories-260k-q8_0.gguf' }
$py = Join-Path $env:USERPROFILE '.local\bin\python3.11.exe'
$llama = Join-Path $root 'llama.cpp-cpu\llama-server.exe'
$proxy = Join-Path (Split-Path (Split-Path $here -Parent) -Parent) 'ik-llama\local-proxy.py'

foreach ($p in @($py, $llama, $proxy)) { if (-not (Test-Path $p)) { throw "required file missing: $p" } }
if (-not (Test-Path $ModelPath)) {
    $modelUrl = 'https://huggingface.co/afrideva/TinyStories-260K-GGUF/resolve/main/tinystories-260k-q8_0.gguf'
    $modelDir = Split-Path $ModelPath -Parent
    if (-not (Test-Path $modelDir)) { New-Item -ItemType Directory -Path $modelDir -Force | Out-Null }
    Write-Host "test model missing; downloading the fixed public tiny model to $ModelPath"
    Invoke-WebRequest -Uri $modelUrl -OutFile $ModelPath -UseBasicParsing
    if (-not (Test-Path $ModelPath) -or (Get-Item $ModelPath).Length -eq 0) { throw "tiny-model download failed: $ModelPath" }
}
if (Test-PortOpen -Port $ServerPort -or Test-PortOpen -Port $ProxyPort) { throw 'test ports are occupied; refusing to disturb a server this test did not start' }

$srv = $null
$prx = $null
$failed = $false
try {
    $srvLog = New-RunLogPath -Name 'e2e-server' -LlmRoot $root
    $srv = Start-Process -FilePath $llama -ArgumentList @('-m', $ModelPath, '--host', '127.0.0.1', '--port', "$ServerPort", '-c', '512', '-ngl', '0') -PassThru -WindowStyle Hidden -RedirectStandardOutput $srvLog -RedirectStandardError "$srvLog.err"
    $health = Wait-ServerHealth -Port $ServerPort -TimeoutSec 60 -IntervalSec 1 -Process $srv
    if (-not $health.Ok) { throw "server did not become healthy ($($health.LastErr)); see $srvLog.err" }

    $env:LOCAL_PROXY_PORT = "$ProxyPort"
    $env:LOCAL_PROXY_UPSTREAM = "http://127.0.0.1:$ServerPort"
    $proxyLog = New-RunLogPath -Name 'e2e-proxy' -LlmRoot $root
    $prx = Start-Process -FilePath $py -ArgumentList @($proxy) -PassThru -WindowStyle Hidden -RedirectStandardOutput $proxyLog -RedirectStandardError "$proxyLog.err"
    $waited = 0
    while (-not (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health") -and $waited -lt 30) { Start-Sleep -Seconds 1; $waited++ }
    if (-not (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health")) { throw "proxy did not expose HTTP; see $proxyLog.err" }

    foreach ($path in @('/v1/messages', '/v1/chat/completions')) {
        try {
            $body = '{"model":"tiny","max_tokens":32000,"messages":[{"role":"user","content":"hi"}]}'
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:$ProxyPort$path" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 90
            if (-not $response) { throw 'empty response' }
            Write-Host "PASS $path"
        } catch {
            $failed = $true
            Write-Error "FAIL $path : $($_.Exception.Message)"
        }
    }
} catch {
    $failed = $true
    Write-Error $_
} finally {
    if ($prx) { Stop-OwnedProcess -Process $prx | Out-Null }
    if ($srv) { Stop-OwnedProcess -Process $srv | Out-Null }
}
if ($failed) { exit 1 }
Write-Host 'PASS proxy E2E assertions'
