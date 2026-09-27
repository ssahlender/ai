# Regression test: publishing preserves evidence while removing host-local path provenance.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('quality-publish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $source = Join-Path $root 'quality-model-20260927-120000.json'
    $planted = 'X:\sample\fixtures'
    @{ mode = 'model'; fixtureDir = $planted; results = @(@{ id = 'task'; reason = "parse error at $planted\\gen.ps1"; answer = "see $planted\\answer.txt" }) } | ConvertTo-Json -Depth 6 | Set-Content $source
    $raw = Get-Content $source -Raw
    if ($raw -notmatch [regex]::Escape($planted)) { throw 'FAIL: negative control did not contain the planted path' }
    $dest = Join-Path $root 'published'
    & (Join-Path $PSScriptRoot 'publish-quality-evidence.ps1') -Source $source -Destination $dest | Out-Null
    $published = Get-Content (Join-Path $dest (Split-Path $source -Leaf)) -Raw
    if ($published -match 'sample|X:\\sample') { throw 'FAIL: host-local path was published from a nested result field' }
    if ($published -notmatch '\[host-local path omitted\]') { throw 'FAIL: recursive scrub marker missing' }
    Write-Output 'PUBLISH-QUALITY-EVIDENCE SELFTEST: PASS'
} finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
