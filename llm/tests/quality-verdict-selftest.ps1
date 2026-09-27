# Regression test: invalid references are excluded and failed request durations do not enter means.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('quality-verdict-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $results = @(
        @{ id = 'code-a'; family = 'code'; pass = $true; reason = 'output matched'; ms = 1000 },
        @{ id = 'code-b'; family = 'code'; pass = $false; reason = 'request failed: timeout'; ms = 900000 },
        @{ id = 'fix-a'; family = 'fix'; pass = $false; reason = 'request failed: timeout'; ms = 900000 },
        @{ id = 'tool-a'; family = 'tool'; pass = $false; reason = 'request failed: timeout'; ms = 900000 },
        @{ id = 'tool-b'; family = 'tool'; pass = $false; reason = 'request failed: timeout'; ms = 900000 }
    )
    $ref = Join-Path $root 'reference.json'; $cand = Join-Path $root 'candidate.json'
    @{ mode = 'reference'; stamp = 'test'; results = $results } | ConvertTo-Json -Depth 5 | Set-Content $ref
    @{ mode = 'candidate'; stamp = 'test'; results = @(@{ id = 'code-a'; family = 'code'; pass = $true; reason = 'output matched'; ms = 2000 }) } | ConvertTo-Json -Depth 5 | Set-Content $cand
    $out = & (Join-Path $PSScriptRoot 'quality-verdict.ps1') -Reference $ref -Candidates $cand -LlmRoot $root 2>&1 | Out-String
    if ($out -notmatch 'invalid reference run: 4 request failures') { throw 'FAIL: invalid reference was scored instead of excluded' }
    if ($out -notmatch 'mean 1s/answer; 4 failed-request timing\(s\) excluded') { throw 'FAIL: failed-request durations entered the reference mean' }
    Write-Output 'QUALITY-VERDICT SELFTEST: PASS'
} finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
