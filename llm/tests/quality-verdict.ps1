# Score quality-run evidence and decide, mechanically.
#
#   quality-verdict.ps1 -Reference <incumbent.json> -Candidates <a.json>,<b.json>
#
# Nothing here is a judgement call: task outcomes come from the checks in quality-tasks.ps1, and the
# decision rule was pre-registered in arena issue #23 before any quality number existed:
#
#   * A challenger must clear the tool-calling gate (>= 2 of 3 tool tasks pass; a model that cannot
#     emit valid tool calls is unusable for agent work whatever else it does).
#   * Task difficulty varies far more than the effect we are looking for, so RAW pass rates are not
#     comparable. Only DISCORDANT pairs count - tasks the two models did not agree on.
#   * Exact one-sided sign test over the discordant pairs; adopt the challenger only at p < 0.05.
#   * Exact ties keep the incumbent. Switching costs are real and the incumbent already works.
#
# Replicates: temperature 0 makes repeated greedy runs identical, so repeats add cost without
# information. n comes from task breadth instead. Outcome per task = majority of its replicates.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Reference,
    [Parameter(Mandatory = $true)][string[]]$Candidates,
    [string]$LlmRoot
)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')

function Import-Evidence {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "evidence file not found: $Path" }
    $doc = Get-Content $Path -Raw | ConvertFrom-Json
    $outcomes = @{}
    $families = @{}
    $ms = @{}
    foreach ($r in @($doc.results)) {
        $key = "$($r.id)"
        if (-not $outcomes.ContainsKey($key)) { $outcomes[$key] = @() }
        $outcomes[$key] += [bool]$r.pass
        $families[$key] = "$($r.family)"
        if (-not $ms.ContainsKey($key)) { $ms[$key] = @() }
        $ms[$key] += [int]$r.ms
    }
    $final = @{}
    foreach ($k in $outcomes.Keys) {
        $vals = @($outcomes[$k])
        $t = @($vals | Where-Object { $_ }).Count
        $final[$k] = ($t * 2 -ge $vals.Count)   # majority (ties count as pass for 1 replicate only)
    }
    $reqFail = @($doc.results | Where-Object { "$($_.reason)" -like 'request failed*' }).Count
    $valid = ($reqFail -le 3)
    return [pscustomobject]@{
        Path     = $Path
        Mode     = "$($doc.mode)"
        Stamp    = "$($doc.stamp)"
        Outcomes = $final
        Families = $families
        Ms       = $ms
        ReqFail  = $reqFail
        Valid    = $valid
        Doc      = $doc
    }
}

function Get-MeanSec {
    # Mean SECONDS per answer - the number a user actually feels. A model with a great decode rate
    # can still be slow here, because it spends tokens on reasoning before it answers. Speed was
    # stated as a decision criterion, so the verdict reports it rather than leaving it in the log.
    param($Evidence)
    $all = @()
    foreach ($k in $Evidence.Ms.Keys) { $all += $Evidence.Ms[$k] }
    if ($all.Count -eq 0) { return 0 }
    return [Math]::Round((($all | Measure-Object -Sum).Sum) / $all.Count / 1000, 1)
}

function Get-BinomialTail {
    # exact one-sided p = P(X >= W) for X ~ Binomial(n, 0.5)
    param([int]$W, [int]$N)
    if ($N -le 0) { return 1.0 }
    $sum = 0.0
    for ($k = $W; $k -le $N; $k++) {
        $c = 1.0
        for ($i = 1; $i -le $k; $i++) { $c = $c * ($N - $k + $i) / $i }
        $sum += $c * [Math]::Pow(0.5, $N)
    }
    if ($sum -gt 1.0) { return 1.0 }
    return $sum
}

function Get-FamilyScore {
    param($Evidence)
    $res = [ordered]@{}
    foreach ($fam in @('code', 'fix', 'tool')) {
        $ids = @($Evidence.Outcomes.Keys | Where-Object { $Evidence.Families[$_] -eq $fam })
        $pass = @($ids | Where-Object { $Evidence.Outcomes[$_] }).Count
        $res[$fam] = "$pass/$($ids.Count)"
    }
    $all = @($Evidence.Outcomes.Keys)
    $passAll = @($all | Where-Object { $Evidence.Outcomes[$_] }).Count
    $res['total'] = "$passAll/$($all.Count)"
    return $res
}

$ref = Import-Evidence -Path $Reference
$refScore = Get-FamilyScore -Evidence $ref
$refTool = [int]("$($refScore['tool'])".Split('/')[0])
$refMean = Get-MeanSec -Evidence $ref

Write-Output ''
Write-Output "=== quality verdict ==="
Write-Output ("  reference: {0}  (code {1}, fix {2}, tool {3}, total {4} | mean {5}s/answer)" -f `
    $ref.Mode, $refScore['code'], $refScore['fix'], $refScore['tool'], $refScore['total'], $refMean)
Write-Output ''

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# Quality verdict')
$report.Add('')
$report.Add("Reference (incumbent): **$($ref.Mode)** - code $($refScore['code']), fix $($refScore['fix']), tool $($refScore['tool']), total $($refScore['total']), mean $($refMean)s/answer")
$report.Add('')
$report.Add('| model | code | fix | tool | total | mean s/answer | tool gate | discordant W/L | p (one-sided) | decision |')
$report.Add('|---|---|---|---|---|---|---|---|---|---|')

$decisions = @()
foreach ($cPath in $Candidates) {
    $cand = Import-Evidence -Path $cPath
    $cs = Get-FamilyScore -Evidence $cand
    $toolPass = [int]("$($cs['tool'])".Split('/')[0])
    $gateOk = ($toolPass -ge 2)

    $W = 0; $L = 0; $ties = 0
    $detail = @()
    foreach ($id in @($ref.Outcomes.Keys | Sort-Object)) {
        $r = [bool]$ref.Outcomes[$id]
        $c = [bool]$cand.Outcomes[$id]
        if ($r -eq $c) { $ties++; continue }
        if ($c -and -not $r) { $W++ ; $detail += "+$id" } else { $L++ ; $detail += "-$id" }
    }
    $n = $W + $L
    $p = Get-BinomialTail -W $W -N $n

    $candMean = Get-MeanSec -Evidence $cand
    $valid = [bool]$cand.Valid

    $decision = 'keep incumbent (no evidence)'
    if (-not $valid) {
        # A run whose server died mid-way measures the crash, not the model. Scoring the dead tail
        # as failures would read as "challenger worse", which is the opposite of what happened.
        $decision = "EXCLUDED (invalid run: $($cand.ReqFail) request failures - server died mid-run)"
    } elseif (-not $gateOk) {
        $decision = 'rejected (tool gate failed)'
    } elseif ($W -ge 10 -and $L -le 2) {
        $decision = 'ADOPT (rule met: W >= 10 with L <= 2)'
    } elseif ($p -lt 0.05) {
        $decision = ('ADOPT (p = {0:N3})' -f $p)
    } elseif ($L -gt $W) {
        $decision = 'keep incumbent (challenger worse)'
    } elseif ($n -eq 0) {
        $decision = 'keep incumbent (exact tie on every task)'
    }

    $gateLabel = 'pass'
    if (-not $gateOk) { $gateLabel = 'FAIL' }

    Write-Output ("  {0,-14} code {1,-5} fix {2,-5} tool {3,-5} total {4,-6} mean {5,-7} gate {6,-5} W/L {7}/{8}  p={9:N3}  {10}" -f `
        $cand.Mode, $cs['code'], $cs['fix'], $cs['tool'], $cs['total'], ("$($candMean)s"), $gateLabel, $W, $L, $p, $decision)

    $report.Add("| $($cand.Mode) | $($cs['code']) | $($cs['fix']) | $($cs['tool']) | $($cs['total']) | $($candMean)s | $gateLabel | $W/$L | $('{0:N3}' -f $p) | $decision |")

    $decisions += [pscustomobject]@{ Mode = $cand.Mode; Decision = $decision; W = $W; L = $L; P = $p; Detail = ($detail -join ' ') }
}

$report.Add('')
$report.Add('Discordant tasks: `+` = challenger passed where the reference failed, `-` = the reverse.')
$report.Add('')
foreach ($d in $decisions) {
    $report.Add("**$($d.Mode)** - $($d.Decision)")
    if ($d.Detail) { $report.Add(''); $report.Add('    ' + $d.Detail) }
    $report.Add('')
}

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$outDir = Get-RunLogDir -LlmRoot (Get-LlmRoot -Override $LlmRoot)
$outPath = Join-Path $outDir "quality-verdict-$stamp.md"
Write-Utf8NoBom -Path $outPath -Lines $report.ToArray()

Write-Output ''
Write-Output "  report: $outPath"
Write-Output '  NOTE: 12 paired tasks support a decision about this box, not a benchmark claim.'
