# Regression test: publishing preserves evidence while removing host-local path provenance.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('quality-publish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $source = Join-Path $root 'quality-model-20260927-120000.json'
    @{ mode = 'model'; fixtureDir = 'X:\sample\fixtures'; results = @() } | ConvertTo-Json -Depth 4 | Set-Content $source
    $dest = Join-Path $root 'published'
    & (Join-Path $PSScriptRoot 'publish-quality-evidence.ps1') -Source $source -Destination $dest | Out-Null
    $published = Get-Content (Join-Path $dest (Split-Path $source -Leaf)) -Raw
    if ($published -match 'sample|X:\\sample') { throw 'FAIL: host-local path was published' }
    if ($published -notmatch 'Host-local fixture path omitted') { throw 'FAIL: provenance notice missing' }
    Write-Output 'PUBLISH-QUALITY-EVIDENCE SELFTEST: PASS'
} finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
