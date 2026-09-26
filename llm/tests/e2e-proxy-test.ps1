# E2E: does the Claude Code chain work? llama-server + local-proxy, tiny model.
# Proves: (a) llama-server answers /v1/messages (what claude actually sends),
#         (b) the proxy relays it, (c) the proxy caps max_tokens=32000.
$ErrorActionPreference = "Continue"

$py     = "$env:USERPROFILE\.local\bin\python3.11.exe"
$llama  = "C:\data\llm\llama.cpp-cpu\llama-server.exe"
$model  = "C:\data\llm\models\tiny-stories260K.gguf"
$proxy  = "C:\data\git\ai-tools\ik-llama\local-proxy.py"
foreach ($p in @($py, $llama, $model, $proxy)) { if (-not (Test-Path $p)) { "MISSING: $p"; exit 1 } }
"binaries ok"

function Wait-Port([int]$Port, [int]$Seconds) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        $c = New-Object System.Net.Sockets.TcpClient
        try { $c.Connect('127.0.0.1', $Port); $c.Close(); return $true } catch { $c.Close(); Start-Sleep -Milliseconds 500 }
    }
    return $false
}

# ── llama-server on 9080 (tiny model: loads instantly) ─────────────
$srvOut = "$env:TEMP\e2e-srv.log"
$srv = Start-Process -FilePath $llama `
        -ArgumentList @("-m", $model, "--host", "127.0.0.1", "--port", "9080", "-c", "512", "-ngl", "0") `
        -PassThru -WindowStyle Hidden -RedirectStandardOutput $srvOut -RedirectStandardError "$srvOut.err"
if (-not (Wait-Port 9080 60)) { "SERVER FAILED to bind 9080"; Get-Content "$srvOut.err" -Tail 15; exit 1 }
"server up on 9080 (pid $($srv.Id))"

# ── local-proxy on 9081 ────────────────────────────────────────────
$env:LOCAL_PROXY_PORT = "9081"
$env:LOCAL_PROXY_UPSTREAM = "http://127.0.0.1:9080"
$pxOut = "$env:TEMP\e2e-prx.log"
$prx = Start-Process -FilePath $py -ArgumentList @($proxy) `
        -PassThru -WindowStyle Hidden -RedirectStandardOutput $pxOut -RedirectStandardError "$pxOut.err"
if (-not (Wait-Port 9081 30)) { "PROXY FAILED to bind 9081"; Get-Content "$pxOut.err" -Tail 15; Stop-Process -Id $srv.Id -Force; exit 1 }
"proxy up on 9081 (pid $($prx.Id))"

# ── THE test: what claude sends, max_tokens=32000 ──────────────────
$body = '{"model":"tiny","max_tokens":32000,"messages":[{"role":"user","content":"Once upon a time"}]}'
"--- POST /v1/messages via proxy (max_tokens=32000) ---"
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:9081/v1/messages" -Method Post `
            -ContentType "application/json" -Body $body -TimeoutSec 90
    $txt = ($r.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
    "  RESPONSE OK (anthropic shape): " + ($txt -replace "`r?`n", " ").Substring(0, [Math]::Min(120, $txt.Length))
} catch {
    "  /v1/messages FAILED: " + $_.Exception.Message
}

"--- POST /v1/chat/completions via proxy ---"
try {
    $b2 = '{"model":"tiny","max_tokens":32000,"messages":[{"role":"user","content":"hi"}]}'
    $r2 = Invoke-RestMethod -Uri "http://127.0.0.1:9081/v1/chat/completions" -Method Post `
            -ContentType "application/json" -Body $b2 -TimeoutSec 90
    "  RESPONSE OK (openai shape): " + (($r2.choices[0].message.content -replace "`r?`n", " "))
} catch {
    "  /v1/chat/completions FAILED: " + $_.Exception.Message
}

"--- did the proxy cap max_tokens? ---"
foreach ($f in @($pxOut, "$pxOut.err")) {
    if (Test-Path $f) { Get-Content $f | Where-Object { $_ -match 'capped|max_tokens|port=' } | ForEach-Object { "  $_" } }
}

# ── cleanup ────────────────────────────────────────────────────────
Stop-Process -Id $prx.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
"cleanup: server+proxy stopped; 9080 free = $(-not (Wait-Port 9080 2)); 9081 free = $(-not (Wait-Port 9081 2))"
