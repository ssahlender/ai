# Shared helpers for the local-LLM scripts on this box.
#
# Dot-source it, adjusting the relative depth to your own location:
#     . (Join-Path $PSScriptRoot 'lib\common.ps1')            # from llm\probook\
#     . (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')   # from probook\tests or bench
#
# Deliberately PowerShell 5.1-safe: no `??`, no inline if-expression, no ternary, no classes.
# Every one of these exists because a review found the same mistake duplicated in several
# scripts - fix it once here instead of in three places.

# Repo layout: llm\probook\lib\common.ps1, llm\models.json, llm\shared\*. Captured at dot-source
# time, where $PSScriptRoot is reliably this file's own directory.
$LlmRepoDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Get-SharedFile {
    # A file in llm\shared (local-proxy.py, qwen3-template.j2, ...), shared with the i9 scripts.
    param([Parameter(Mandatory = $true)][string]$Name)
    return (Join-Path (Join-Path $LlmRepoDir 'shared') $Name)
}

function Get-ScriptDir {
    # $PSScriptRoot is EMPTY inside a param() default on PS 5.1, which silently produced a
    # Join-Path error at least once. Use this instead of trusting it in a default.
    param([string]$MyCommandPath)
    if ($MyCommandPath) { return (Split-Path $MyCommandPath -Parent) }
    return $PSScriptRoot
}

function Get-LlmRoot {
    # The data root for engines, models and logs. Explicit override wins; otherwise under the
    # interactive user's own profile. Guarded against the one real way this breaks: a script
    # that calls this while running as a SYSTEM scheduled task (see run-as-system-task.ps1,
    # used for jobs that cannot survive a PSRP session dying, e.g. a multi-GB download).
    # $env:USERPROFILE under SYSTEM resolves to C:\windows\system32\config\systemprofile and
    # writes would land in the wrong profile while still reporting success - so refuse rather
    # than do that silently. The documented SYSTEM-task caller (download-model.ps1) already
    # requires its destination as an explicit, mandatory parameter computed by the interactive
    # caller beforehand; any script relying on this default must do the same.
    param([string]$Override)
    if ($Override) { return $Override }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -eq 'S-1-5-18') {
        throw 'Get-LlmRoot has no safe default under the SYSTEM account (S-1-5-18): $env:USERPROFILE would resolve to the system profile, not the real user''s. Pass -Override/-LlmRoot/-ModelsDir explicitly, resolved by the interactive caller before launching the SYSTEM task.'
    }
    return (Join-Path $env:USERPROFILE '.local\share\llama.cpp')
}

function Get-RunLogDir {
    # Run output belongs in one place, not scattered over the data root. Created on demand.
    param([string]$LlmRoot)
    if (-not $LlmRoot) { $LlmRoot = Get-LlmRoot }
    $dir = Join-Path $LlmRoot 'logs'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function New-RunLogPath {
    # Timestamped, so a new run never destroys yesterday's evidence. The old scripts truncated
    # a fixed filename on every start, which made "what did it say when it worked" unanswerable.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$LlmRoot
    )
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    return (Join-Path (Get-RunLogDir -LlmRoot $LlmRoot) "$Name-$stamp.log")
}

function Write-Utf8NoBom {
    # Set-Content -Encoding UTF8 writes a BOM on PS 5.1. These files get parsed by other
    # scripts and by jq/python, so the BOM is a real defect, not cosmetics.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines
    )
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Test-PortOpen {
    # Fast pre-check only. A listening port proves a socket was bound, nothing more -
    # llama-server binds BEFORE the model is loaded, so this must never be the readiness test.
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 800
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-ServerHealth {
    # The real readiness signal: llama-server answers /health with {"status":"ok"} only once
    # the model is loaded, and 503 while loading (Invoke-RestMethod throws on 503 - that is
    # exactly the "not ready yet" case).
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSec = 5
    )
    try {
        $h = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($h.status -eq 'ok') { return $true }
        return $false
    } catch {
        return $false
    }
}

function Test-EndpointReady {
    # Distinguishes "nothing there" from "something is there but this endpoint is not its job".
    # A refused connection means not ready; an HTTP answer (even an error status) means a live
    # listener, which for the proxy is as much as we can assert cheaply.
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 10
    )
    try {
        $null = Invoke-RestMethod -Uri $Url -TimeoutSec $TimeoutSec -ErrorAction Stop
        return $true
    } catch {
        # An HTTP answer carries a Response; a refused or timed-out connection does not. Do not
        # match the message text: it is localised (German on the ProBook: "Die Verbindung mit dem
        # Remoteserver kann nicht hergestellt werden"), which once made a dead port look ready.
        $resp = $null
        try { $resp = $_.Exception.Response } catch { }
        if ($resp) { return $true }
        return $false
    }
}

function Wait-ServerHealth {
    # Wait for a USABLE model, not for a socket. Returns an object so callers report honestly:
    #   .Ok       - $true when /health said ok
    #   .Waited   - seconds spent
    #   .LastErr  - last health error, useful when it never comes up
    #   .Exited   - $true if the process died while we waited (then waiting is pointless)
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSec = 300,
        [int]$IntervalSec = 3,
        [System.Diagnostics.Process]$Process,
        [scriptblock]$OnTick
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lastErr = ''
    $exited = $false
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ($Process) {
            $Process.Refresh()
            if ($Process.HasExited) { $exited = $true; break }
        }
        if (Test-ServerHealth -Port $Port -TimeoutSec 5) {
            $sw.Stop()
            return [pscustomobject]@{ Ok = $true; Waited = [Math]::Round($sw.Elapsed.TotalSeconds); LastErr = ''; Exited = $false }
        }
        $lastErr = 'health not ok yet'
        if ($OnTick) { & $OnTick ([Math]::Round($sw.Elapsed.TotalSeconds)) }
        Start-Sleep -Seconds $IntervalSec
    }
    $sw.Stop()
    return [pscustomobject]@{ Ok = $false; Waited = [Math]::Round($sw.Elapsed.TotalSeconds); LastErr = $lastErr; Exited = $exited }
}

function Stop-OwnedProcess {
    # Kill ONLY a process the caller can prove it started. The reviewed bug was
    # `Get-Process -Name llama-server | Stop-Process`, which also kills a server started by
    # something else - another mode, a colleague's session, or a run the user cares about.
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [switch]$Quiet
    )
    $result = [pscustomobject]@{ Stopped = $false; Reason = '' }
    if (-not $Process) { $result.Reason = 'no process object given'; return $result }
    try {
        $Process.Refresh()
        if ($Process.HasExited) {
            $result.Reason = "already exited (pid $($Process.Id))"
            return $result
        }
        Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        $result.Stopped = $true
        $result.Reason = "stopped pid $($Process.Id)"
    } catch {
        # A failure to stop is reported, never swallowed: the old code's silent failure left a
        # server holding the port and the next run quietly measured the wrong model.
        $result.Reason = "could not stop pid $($Process.Id): $($_.Exception.Message)"
    }
    if (-not $Quiet) { Write-Host ("  cleanup: " + $result.Reason) }
    return $result
}

function Stop-ServerOnPort {
    # Fallback for a server we did NOT start and cannot own: find whatever holds the port and
    # stop it by pid, explicitly and loudly, instead of a name-wide kill.
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [switch]$Confirm
    )
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $conn) { return $null }
    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    if (-not $Confirm) {
        Write-Warning ("port $Port is held by pid $($proc.Id) ($($proc.ProcessName)) - not ours; not stopping it")
        return $proc
    }
    return (Stop-OwnedProcess -Process $proc)
}

function Get-RelayPromptList {
    # One source of truth for the blind-comparison prompts. blind-compare.ps1 used to carry a
    # verbatim duplicate of suite-prompts.txt, which is how the two silently drift apart.
    param([string]$Path)
    if (-not $Path) { throw 'Get-RelayPromptList needs the path to suite-prompts.txt' }
    if (-not (Test-Path $Path)) { throw "prompt list not found: $Path" }
    return @(Get-Content $Path | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') })
}

function Invoke-NativeToFile {
    # Run a native tool, capturing stdout AND stderr to a file, and return its exit code.
    #
    # WHY THIS EXISTS: llama-bench writes its whole table to STDERR. Merging stderr (`*>` or `2>&1`)
    # under $ErrorActionPreference='Stop' turns the first stderr line into a NativeCommandError,
    # which terminates the script - the run aborts with a 0-byte log and the scheduled task exits 1.
    # It only reproduces in the production path (SYSTEM task); an interactive session with
    # 'Continue' hides it, which is exactly how it survived review. Relaxing the preference around
    # the call lets a native tool write to either stream without being treated as a failure, while
    # the exit code is still checked by the caller.
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments *> $LogPath
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-ProbookModeTable {
    # Reads models.json's probook entries into the shape start-llm.ps1 and
    # llama-swap-setup.ps1 both need (Short/Name/Label/Engine/File/Ctx/Cram/Template/Mmproj/Spec).
    # Shared so the two scripts can't drift on how a models.json field maps to this shape.
    param(
        [Parameter(Mandatory = $true)][string]$ModelsJson,
        [string]$ChatTemplate = ''
    )
    if (-not (Test-Path $ModelsJson)) { throw "models.json not found: $ModelsJson" }
    $modelsData = Get-Content $ModelsJson -Raw | ConvertFrom-Json
    # NOTE: never name the result after a [string]-typed parameter in the caller — assigning
    # an array to a type-constrained parameter silently coerces it to a single string.
    return @($modelsData.machines.probook | ForEach-Object {
        [pscustomobject]@{
            Short  = $_.short
            Name   = $_.desc
            # Readable display name (llama-swap web UI, OpenCode); falls back to the GGUF file name.
            Label  = $(if ($_.name) { $_.name } else { $_.file })
            Engine = $_.engine
            File   = $_.file
            Ctx    = $_.ctx; Cram = $_.cram
            # Template only matters for the 'mainline' engine branch in Get-ServerInvocation
            # (ik_llama always tries the global -ChatTemplate param unconditionally).
            Template = $(if ($_.chat_template) { $ChatTemplate } else { $null })
            Mmproj = $(if ($_.mmproj) { $_.mmproj.file } else { $null })
            Spec   = $_.spec
        }
    })
}

function Resolve-ModelsJsonPath {
    # Same resolution every script here uses: an explicit path wins; otherwise a colleague's
    # gitignored models.local.json next to models.json; otherwise the committed models.json.
    param([string]$Explicit = '', [Parameter(Mandatory = $true)][string]$ScriptDir)
    if ($Explicit) { return $Explicit }
    # ScriptDir is kept for callers' sake; the catalog always sits in llm\, above probook\.
    $localJson = Join-Path $LlmRepoDir 'models.local.json'
    if (Test-Path $localJson) { return $localJson }
    return (Join-Path $LlmRepoDir 'models.json')
}

function Get-ServerInvocation {
    # Resolves the exact engine exe + argv for one mode table entry (Short/Name/Engine/File/
    # Ctx/Cram/Template/Mmproj), exactly as start-llm.ps1 runs it. Shared so llama-swap-setup.ps1
    # can reuse this instead of a second copy of the flag-building logic drifting out of sync --
    # the Windows analog of the bash launchers' IK_LLAMA_PRINT_CMD + eval trick, except as a real
    # shared function call, since PowerShell doesn't need a text-templating workaround to share
    # logic between two scripts the way a separate bash process does.
    #
    # -Port accepts an [int] for a real launch, or the literal string '${PORT}' when generating
    # a llama-swap config.yaml entry -- llama-swap substitutes that token itself at listen time.
    param(
        [Parameter(Mandatory = $true)]$Mode,
        [Parameter(Mandatory = $true)]$Port,
        [Parameter(Mandatory = $true)][string]$ModelDir,
        [Parameter(Mandatory = $true)][hashtable]$EngineDirs,
        [string]$ChatTemplate = '',
        [int]$Threads = 8,
        [int]$ThreadsBatch = 8,
        [int]$Ctx = 0,
        [string]$BindAddress = '127.0.0.1',
        [string]$ApiKey = '',
        [string[]]$ExtraArgs = @(),
        # Thinking is off unless asked for, the same default as the i9's start.sh (-rea off).
        [switch]$Thinking
    )
    $dir = $EngineDirs[$Mode.Engine]
    if (-not $dir) { throw "Unknown engine '$($Mode.Engine)' in mode table" }
    $server = Join-Path $dir 'llama-server.exe'
    if (-not (Test-Path $server)) { throw "llama-server.exe not found for engine '$($Mode.Engine)' at $server" }

    $modelPath = Join-Path $ModelDir $Mode.File
    $effectiveCtx = $Ctx
    if (-not $effectiveCtx) { $effectiveCtx = $Mode.Ctx }

    # $args is an automatic variable in PowerShell — never assign to it.
    $serverArgs = @(
        '-m', $modelPath
        '-ngl', '0'
        '--threads', $Threads
        '--threads-batch', $ThreadsBatch
        '--parallel', 1
        '--ctx-size', $effectiveCtx
        '-ctk', 'q8_0'
        '-ctv', 'q8_0'
        '--port', $Port
        '--host', $BindAddress
        '-v'
    )

    switch ($Mode.Engine) {
        'mainline' {
            # mainline llama.cpp: --jinja + built-in template resolution; no ik_llama-only
            # flags (-cram/-crs/-sps/-dt/-rea/--context-shift do not exist here).
            $serverArgs += @('--jinja')
            if (-not $Thinking) { $serverArgs += @('--reasoning', 'off') }
            if ($Mode.Template -and (Test-Path $Mode.Template)) {
                $serverArgs += @('--chat-template-file', $Mode.Template)
            }
        }
        'ik_llama' {
            $serverArgs += @(
                '-sps', '0.5'
                '-cram', $Mode.Cram
                '-crs', '0.5'
                '-dt', '0.1'
                '--jinja'
                '--context-shift', 'on'
                '-rea', $(if ($Thinking) { 'on' } else { 'off' })
            )
            if ($ChatTemplate -and (Test-Path $ChatTemplate)) { $serverArgs += @('--chat-template-file', $ChatTemplate) }
        }
    }
    if ($Mode.Mmproj) { $serverArgs += @('--mmproj', (Join-Path $ModelDir $Mode.Mmproj)) }
    # models.json 'spec': raw speculative-decoding flags, split on whitespace (e.g. '--spec-type draft-mtp').
    if ($Mode.Spec) { $serverArgs += @($Mode.Spec -split '\s+' | Where-Object { $_ }) }
    if ($ApiKey) { $serverArgs += @('--api-key', $ApiKey) }
    if ($ExtraArgs) { $serverArgs += $ExtraArgs }

    return [pscustomobject]@{ Server = $server; ModelPath = $modelPath; Args = $serverArgs }
}

function Resolve-Python {
    # local-proxy.py (and llama-swap-setup.ps1's own proxy handoff) is pure-stdlib Python,
    # travels with the repo, and needs a real interpreter - the Microsoft Store alias for
    # `python` is not one and must be skipped explicitly.
    $candidates = @(
        (Join-Path $env:USERPROFILE '.local\bin\python3.11.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\python.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command python -ErrorAction SilentlyContinue |
           Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    throw "no real Python found (the Microsoft Store alias does not count); install uv or Python"
}

function Resolve-LocalProxyScript {
    # local-proxy.py lives in llm\shared, next to this clone's probook\ folder. Shared by
    # claude-local.ps1 and llama-swap-setup.ps1, which both hand off to the same script.
    param([string]$ScriptDir, [string]$Explicit = '')
    if ($Explicit) { return $Explicit }
    $found = Get-SharedFile 'local-proxy.py'
    if (-not (Test-Path $found)) { throw "local-proxy.py not found at $found" }
    return $found
}

function Stop-LocalProxyProcess {
    # Equivalent of the bash side's `pkill -f local-proxy.py` -- find it by command line
    # (python.exe's own process name tells us nothing about which script it's running) and
    # stop it by pid. Returns the count stopped; 0 is not an error, nothing was running.
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'python3.exe' OR Name = 'python3.11.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'local-proxy\.py' }
    $n = 0
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            $n += 1
        } catch {
            Write-Warning ("could not stop local-proxy.py pid $($p.ProcessId): $($_.Exception.Message)")
        }
    }
    return $n
}

function Get-NativeOutput {
    # Same problem, text-capture flavour: returns merged stdout+stderr as a string.
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @()
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return ((& $Exe @Arguments 2>&1 | Out-String))
    } finally {
        $ErrorActionPreference = $prev
    }
}
