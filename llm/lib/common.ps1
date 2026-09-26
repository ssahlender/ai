# Shared helpers for the local-LLM scripts on this box.
#
# Dot-source it, adjusting the relative depth to your own location:
#     . (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')
#
# Deliberately PowerShell 5.1-safe: no `??`, no inline if-expression, no ternary, no classes.
# Every one of these exists because a review found the same mistake duplicated in several
# scripts - fix it once here instead of in three places.

function Get-ScriptDir {
    # $PSScriptRoot is EMPTY inside a param() default on PS 5.1, which silently produced a
    # Join-Path error at least once. Use this instead of trusting it in a default.
    param([string]$MyCommandPath)
    if ($MyCommandPath) { return (Split-Path $MyCommandPath -Parent) }
    return $PSScriptRoot
}

function Get-LlmRoot {
    # The data root for engines, models and logs. Explicit override wins; otherwise the
    # conventional box layout. Never derived from $env:USERPROFILE - under a SYSTEM scheduled
    # task that resolves to C:\windows\system32\config\systemprofile and writes land in the
    # wrong profile while still reporting success.
    param([string]$Override)
    if ($Override) { return $Override }
    return 'C:\data\llm'
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
        $msg = "$($_.Exception.Message)"
        if ($msg -match 'refused|Unable to connect|No connection could be made|no such host') { return $false }
        return $true
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
