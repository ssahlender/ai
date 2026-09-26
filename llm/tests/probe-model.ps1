# Probe a GGUF before trusting it: does the engine load it, what architecture does it report, and does
# it carry a tool-calling template?
#
# WHY THIS EXISTS: a downloaded model is unverified until the engine has actually loaded it. Size
# checks prove the bytes arrived, not that llama.cpp understands the tensors. The architecture line in
# the load log is also the ground truth for what the model IS - model cards are marketing, and we have
# already been burned once by believing a claim (a vendor benchmark) that the local stack contradicted.
#
# Read-only: loads the model on loopback, reads /props, stops the server. No writes outside the log dir.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ModelFile,
    [string]$LlmRoot = 'C:\data\llm',
    [string]$Label = '',
    [int]$Port = 9077,
    [int]$WaitSeconds = 180,
    [int]$Ctx = 4096,
    # Several Qwen templates enable reasoning-preservation by default, which prepends reasoning tokens
    # and roughly doubles time-per-answer. Serving with and without it is a real measurement, not a
    # tweak, so the switch is explicit and the label records which way the run went.
    [switch]$NoReasoningPreserve
)

$ErrorActionPreference = 'Continue'
$mainline = Join-Path $LlmRoot 'llama.cpp-cpu'
$server = Join-Path $mainline 'llama-server.exe'
$model = Join-Path (Join-Path $LlmRoot 'models') $ModelFile
$logDir = Join-Path $LlmRoot 'logs'
if (-not (Test-Path $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
if (-not $Label) { $Label = [IO.Path]::GetFileNameWithoutExtension($ModelFile) }
if ($NoReasoningPreserve -and $Label -notlike '*-norp') { $Label = "$Label-norp" }
$logFile = Join-Path $logDir ("probe-$Label-$stamp.log")
# Results also go to a small text file: this runs as a child process (a scheduled task), where stdout
# is not guaranteed to reach the caller. The file is the evidence, and it survives the run.
$resultFile = Join-Path $logDir ("probe-$Label-$stamp.txt")
function Emit {
    param([string]$Line)
    Write-Output $Line
    Add-Content -Path $resultFile -Value $Line -ErrorAction SilentlyContinue
}
"PROBE $Label probe started at $stamp" | Set-Content -Path $resultFile -ErrorAction SilentlyContinue

if (-not (Test-Path $server)) { Emit "PROBE $Label load=NO-ENGINE reason=llama-server.exe missing at $server"; exit 1 }
if (-not (Test-Path $model)) { Emit "PROBE $Label load=NO-MODEL reason=$model missing"; exit 1 }

# Stop anything already on the port so we never read a different model's /props.
try {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 700
} catch { }

# -ngl 0: this box has no usable GPU. --jinja: use the template carried by the GGUF.
$argList = @('-m', $model, '--jinja', '-c', "$Ctx", '-ngl', '0', '-t', '8', '-np', '1',
             '--host', '127.0.0.1', '--port', "$Port")
if ($NoReasoningPreserve) { $argList += '--no-reasoning-preserve' }
$p = Start-Process -FilePath $server -ArgumentList $argList -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $logFile -RedirectStandardError ($logFile + '.err')

$ready = $false
$waited = 0
while ($waited -lt $WaitSeconds) {
    $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/props" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
    $waited += 2
}

# A failed load is the interesting case, so report WHY rather than just "no".
if (-not $ready) {
    $errText = ''
    foreach ($f in @($logFile, ($logFile + '.err'))) {
        if (Test-Path $f) { $errText += (Get-Content $f -Raw -ErrorAction SilentlyContinue) }
    }
    $why = @($errText -split "`r?`n" | Where-Object { $_ -match 'error|unknown|not supported|unsupported|failed|incompatible' } |
        Select-Object -First 3) -join ' | '
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    if (-not $why) { $why = 'server did not answer /props within ' + $WaitSeconds + 's (no explicit error in log)' }
    Emit "PROBE $Label load=FAIL waited=${waited}s reason=$why"
    Emit "PROBE $Label log=$logFile"
    exit 2
}

$props = ($r.Content | ConvertFrom-Json)
$tmpl = ''
if ($props.PSObject.Properties.Name -contains 'chat_template') { $tmpl = "$($props.chat_template)" }
$caps = $props.PSObject.Properties.Name -contains 'chat_template_caps'
$capsJson = ''
if ($caps) { $capsJson = ($props.chat_template_caps | ConvertTo-Json -Compress -Depth 6) }

# The load log is the only place the architecture is stated plainly.
# llama-server writes its log to STDERR: the .log file stays 0 bytes while .log.err carries the load
# log, the architecture line and the reasoning-preserve warning. Read BOTH, always - reading only
# .log made a successfully loaded model look like a silent failure.
$logText = ''
foreach ($lf in @($logFile, ($logFile + '.err'))) {
    if (Test-Path $lf) { $logText += (Get-Content $lf -Raw -ErrorAction SilentlyContinue) + "`n" }
}
$arch = ''
$m = [regex]::Match($logText, 'general\.architecture\s+str\s*=\s*([A-Za-z0-9_.\-]+)')
if ($m.Success) { $arch = $m.Groups[1].Value }
$nCtx = ''
$m2 = [regex]::Match($logText, 'n_ctx_train\s*=\s*([0-9]+)')
if ($m2.Success) { $nCtx = $m2.Groups[1].Value }
$mmproj = 'no'
if ($logText -match 'mmproj|clip model|vision') { $mmproj = 'mentioned-in-log' }
# Two signals that decide how this model must be served, both easy to miss in a long log:
# reasoning-preserve inflates per-answer time, and unused tensors usually mean an MTP block the
# engine ignores (benign) rather than corruption.
$rp = 'n/a'
if ($logText -match 'preserving reasoning') { $rp = 'ON' }
if ($NoReasoningPreserve) { $rp = 'disabled-by-flag' }
$unused = ([regex]::Matches($logText, 'has unused tensor ')).Count
$loaded = 'no'
if ($logText -match 'model loaded') { $loaded = 'yes' }

Emit ("PROBE {0} load=OK arch={1} n_ctx_train={2} templateChars={3} caps={4} vision={5} reasoningPreserve={6} unusedTensors={7} loaded={8} waited={9}s" -f `
    $Label, $(if ($arch) { $arch } else { 'unknown' }), $(if ($nCtx) { $nCtx } else { '?' }), $tmpl.Length, `
    $(if ($capsJson) { $capsJson } else { 'none' }), $mmproj, $rp, $unused, $loaded, $waited)
Emit "PROBE $Label log=$logFile"

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
exit 0
