<#
.SYNOPSIS
    Starts the ProBook's default chain: local-proxy (9081) -> llama-swap (9082, web UI) -> llama-server.

.DESCRIPTION
    Windows counterpart to llm/llama-swap-setup.sh (i9, Mac). Generates a llama-swap config.yaml
    from models.json (via Get-ProbookModeTable / Get-ServerInvocation in lib\common.ps1,
    shared with start-llm.ps1), starts llama-swap.exe, and
    repoints local-proxy.py's upstream at it -- same stack as the bash version:

        harness -> local-proxy.py (9081, keep-alive) -> llama-swap (9082, routing/lifecycle)
                -> llama-server.exe (one at a time, port picked by llama-swap)

    Install llama-swap.exe first: .\update-llm.ps1 -Engine llama-swap

    Do not run both start-llm.ps1 (manual, port 9080) and this at once against the same
    model -- two independent supervisors; llama-swap doesn't know about a manually-started
    llama-server.exe, so the same GGUF could get loaded twice.

    Verified end to end on the ProBook 2026-10-28 (llama-swap v268). Run -WhatIf first and read
    the generated config.yaml. Thinking is off in every generated entry (Get-ServerInvocation's
    default, same as start-llm.ps1).

.PARAMETER WhatIf
    Generate and print config.yaml; start nothing.

.PARAMETER Lan
    LAN mode for the fleet gateway: creates a key in %USERPROFILE%\.config\llm\llama-swap.key once.
    While that file exists, llama-swap listens on all interfaces and every request needs the key;
    local-proxy adds it itself, so local agents keep their 'dummy' key. Back to local-only: delete the
    file and re-run.

.PARAMETER AllowFrom
    With LAN mode: the gateway host's address. Creates (or updates) an inbound firewall rule for the
    llama-swap port from that address only, Private profile only (needs an elevated session). Not stored
    anywhere in the repository.

.EXAMPLE
    .\llama-swap-setup.ps1 -WhatIf
    .\llama-swap-setup.ps1
    .\llama-swap-setup.ps1 -Lan -AllowFrom <gateway-ip>
#>
[CmdletBinding()]
param(
    [string]$ModelsJson   = '',
    [string]$ModelDir     = '',
    [string]$MainlineDir  = '',
    [string]$IkLlamaDir   = '',
    [string]$ChatTemplate = '',   # default: llm\shared\qwen3-template.j2
    [string]$LlamaSwapExe = '',
    [int]$SwapPort        = 9082,
    [int]$AgentPort       = 9081,
    [string]$ConfigPath   = '',
    [string]$ProxyScript  = '',
    [switch]$Lan,
    [string]$AllowFrom    = '',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'lib\common.ps1')
if (-not $ChatTemplate) { $ChatTemplate = Get-SharedFile 'qwen3-template.j2' }

$ModelsJson = Resolve-ModelsJsonPath -Explicit $ModelsJson -ScriptDir $here
if (-not $ModelDir)    { $ModelDir    = Join-Path (Get-LlmRoot) 'models' }
if (-not $MainlineDir) { $MainlineDir = Join-Path (Get-LlmRoot) 'llama.cpp-cpu' }
if (-not $IkLlamaDir)  { $IkLlamaDir  = Join-Path (Get-LlmRoot) 'ik_llama' }
if (-not $LlamaSwapExe) { $LlamaSwapExe = Join-Path (Get-LlmRoot) 'llama-swap\llama-swap.exe' }
if (-not (Test-Path $LlamaSwapExe)) { throw "llama-swap.exe not found at $LlamaSwapExe. Install: .\update-llm.ps1 -Engine llama-swap" }
if (-not $ConfigPath) { $ConfigPath = Join-Path (Get-LlmRoot) 'llama-swap\config.yaml' }

# ── LAN mode: a key file outside the repo turns it on ────────────────
$keyFile = Join-Path $env:USERPROFILE '.config\llm\llama-swap.key'
if ($Lan -and -not (Test-Path $keyFile)) {
    New-Item -ItemType Directory -Path (Split-Path $keyFile -Parent) -Force | Out-Null
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $newKey = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    Write-Utf8NoBom -Path $keyFile -Lines @($newKey)
    Write-Host "LAN mode: created $keyFile (give its content to the gateway)"
}
$key = ''
if (Test-Path $keyFile) { $key = (Get-Content $keyFile -Raw).Trim() }
$listen = if ($key) { "0.0.0.0:$SwapPort" } else { "127.0.0.1:$SwapPort" }
$env:LLAMA_SWAP_API_KEY = $key          # read by llama-swap's ${env.LLAMA_SWAP_API_KEY}; inherited by Start-Process

$engineDirs = @{ 'mainline' = $MainlineDir; 'ik_llama' = $IkLlamaDir }
$modeTable  = Get-ProbookModeTable -ModelsJson $ModelsJson -ChatTemplate $ChatTemplate
if ($modeTable.Count -eq 0) { throw "models.json has zero probook modes ($ModelsJson)" }

# ── resolve each mode's exact exe + argv via the function start-llm.ps1 itself uses ──
# Port is the literal string '${PORT}' on purpose: llama-swap substitutes that token itself
# at listen time, the same templating the bash config.yaml uses (its ${PORT} is llama-swap's
# own syntax, not a bash variable).
$entries = @()
foreach ($mode in $modeTable) {
    $modelPath = Join-Path $ModelDir $mode.File
    if (-not (Test-Path $modelPath)) {
        Write-Host ("  - {0,-14} SKIPPED (model not present: {1})" -f $mode.Short, $modelPath)
        continue
    }
    try {
        $inv = Get-ServerInvocation -Mode $mode -Port '${PORT}' -ModelDir $ModelDir -EngineDirs $engineDirs -ChatTemplate $ChatTemplate
    } catch {
        Write-Host ("  - {0,-14} SKIPPED ({1})" -f $mode.Short, $_.Exception.Message)
        continue
    }
    $entries += [pscustomobject]@{ Short = $mode.Short; Id = $mode.Id; Desc = $mode.Name; Server = $inv.Server; Args = $inv.Args }
    Write-Host ("  + {0}" -f $mode.Id)
}
if ($entries.Count -eq 0) { throw "no usable probook modes (model + engine both present) found via $ModelsJson" }

# ── build config.yaml ──────────────────────────────────────────────
function ConvertTo-YamlSingleQuoted {
    # Minimal and deliberate: single-quote with '' doubling, exactly what a Windows path or
    # flag value here ever needs -- not a general-purpose YAML emitter. Used for YAML keys only;
    # cmd tokens go through ConvertTo-WindowsArg.
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-WindowsArg {
    # llama-swap on Windows splits cmd Windows-style, NOT like a POSIX shell: single quotes stay
    # literal, so 'C:\...\llama-server.exe' was looked up as a file whose name includes the quotes
    # ("file does not exist", measured 2026-10-28 on llama-swap v268). Double quotes, with embedded
    # quotes escaped and trailing backslashes doubled so they cannot escape the closing quote.
    param([string]$Value)
    $v = $Value -replace '"', '\"'
    $v = $v -replace '(\\+)$', '$1$1'
    return '"' + $v + '"'
}

$lines = @()
if ($key) { $lines += @('apiKeys:', '  - "${env.LLAMA_SWAP_API_KEY}"') }   # the key itself never enters the file
$lines += @(
    '# Generated by llama-swap-setup.ps1 -- do not edit by hand, re-run the script instead.'
    'healthCheckTimeout: 600'
    'logLevel: info'
    'metricsMaxInMemory: 1000'
    'sendLoadingState: true'
    'models:'
)
foreach ($e in $entries) {
    $quotedServer = ConvertTo-WindowsArg $e.Server
    $quotedArgs   = $e.Args | ForEach-Object { ConvertTo-WindowsArg "$_" }
    $cmdLine = (@($quotedServer) + $quotedArgs) -join ' '
    $lines += ("  {0}:" -f (ConvertTo-YamlSingleQuoted $e.Id))
    # the id is the model's one name; the description is shown under it in llama-swap's UI
    if ($e.Desc)  { $lines += ("    description: {0}" -f (ConvertTo-YamlSingleQuoted $e.Desc)) }
    # Block scalar, not a plain value: a plain scalar that starts with a quote is parsed as one
    # quoted string, so "'C:\...exe' '-m' ..." was a YAML syntax error. Inside a block scalar the
    # quotes are literal text, left for llama-swap's own (Windows-style) argument splitting.
    $lines += '    cmd: |'
    $lines += ("      {0}" -f $cmdLine)
    $lines += '    proxy: "http://127.0.0.1:${PORT}"'
    $lines += '    ttl: 0'
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "Would write $ConfigPath :"
    $lines | ForEach-Object { Write-Host $_ }
    exit 0
}

$configDir = Split-Path $ConfigPath -Parent
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
Write-Utf8NoBom -Path $ConfigPath -Lines $lines
Write-Host ""
Write-Host "Wrote $ConfigPath"

& $LlamaSwapExe -config $ConfigPath -validate
if ($LASTEXITCODE -ne 0) { throw "llama-swap -validate rejected the generated config (exit $LASTEXITCODE)" }

$running = Get-Process -Name 'llama-swap' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "llama-swap is already running (pid $($running.Id -join ', ')); restart it by hand to pick up changes: Stop-Process -Name llama-swap -Force"
} else {
    Write-Host ("Starting llama-swap on {0} ({1}) ..." -f $listen, $(if ($key) { 'LAN mode, key required' } else { 'local only' }))
    $log = New-RunLogPath -Name 'llama-swap'
    Start-Process -FilePath $LlamaSwapExe -ArgumentList @('-config', $ConfigPath, '-listen', $listen) `
        -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    Write-Host ("  log: {0}" -f $log)
}

Write-Host ("Pointing local-proxy.py (agent-facing port {0}) at llama-swap ..." -f $AgentPort)
$stopped = Stop-LocalProxyProcess
if ($stopped -gt 0) { Write-Host ("  stopped {0} previous local-proxy.py process(es)" -f $stopped) }
Start-Sleep -Milliseconds 300

$proxyScriptPath = Resolve-LocalProxyScript -ScriptDir $here -Explicit $ProxyScript
$py = Resolve-Python
$env:LOCAL_PROXY_PORT = "$AgentPort"
$env:LOCAL_PROXY_UPSTREAM = "http://127.0.0.1:$SwapPort"
$env:LOCAL_PROXY_API_KEY = $key         # replaces the agents' 'dummy' key towards llama-swap
$proxyLog = New-RunLogPath -Name 'local-proxy'
Start-Process -FilePath $py -ArgumentList @($proxyScriptPath) -WindowStyle Hidden `
    -RedirectStandardOutput $proxyLog -RedirectStandardError "$proxyLog.err"
$waited = 0
while (-not (Test-EndpointReady -Url "http://127.0.0.1:$AgentPort/health") -and $waited -lt 30) { Start-Sleep -Seconds 1; $waited += 1 }
if (-not (Test-EndpointReady -Url "http://127.0.0.1:$AgentPort/health")) { throw "local-proxy did not expose an HTTP endpoint on $AgentPort (see $proxyLog.err)" }
Write-Host ("  proxy up, log {0}" -f $proxyLog)

if ($key -and $AllowFrom) {
    $rule = 'llama-swap gateway (llm/probook)'
    Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort $SwapPort `
        -RemoteAddress $AllowFrom -Profile Private -Action Allow | Out-Null
    Write-Host ("Firewall: port {0} open to {1} only, Private profile only" -f $SwapPort, $AllowFrom)
} elseif ($key) {
    Write-Host ("Note: no firewall rule set; pass -AllowFrom <gateway-ip> (elevated) to open {0} to the gateway only" -f $SwapPort)
} else {
    # local-only again: a rule left from LAN mode would keep the port open for nothing
    $old = Get-NetFirewallRule -DisplayName 'llama-swap gateway (llm/probook)' -ErrorAction SilentlyContinue
    if ($old) { $old | Remove-NetFirewallRule; Write-Host "Firewall: removed the LAN-mode rule (local only now)" }
}

Write-Host ""
Write-Host ("Agents pointed at http://localhost:{0}/v1 can now request any of the modes above by name;" -f $AgentPort)
Write-Host "llama-swap starts/stops the matching llama-server.exe automatically. Point OpenCode at it with"
Write-Host ("  .\setup-agents.ps1   (once; agents then use http://127.0.0.1:{0}/v1)" -f $AgentPort)
