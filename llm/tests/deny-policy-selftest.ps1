# Regression self-test for the code-execution policy gate in quality-tasks.ps1.
#
# Why this exists: the gate once denied Set-Content, Out-File, Rename-Item and 'Format-' outright, so
# every multifile task (which REQUIRES editing files) was impossible to pass for any model - and the
# deny reason read like a model failure. Checks were self-tested, the gate path was not.
#
# Run before trusting any suite result: a failing instrument and a failing model look identical.
#   powershell -ExecutionPolicy Bypass -File deny-policy-selftest.ps1
#
# Each case is: input code, and whether it must be ALLOWED (inside the fixture) or DENIED.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')

$cases = @(
    # --- must be ALLOWED: legitimate work inside the fixture ------------------
    @{ code = "Set-Content -Path 'out.txt' -Value 'x'";                     deny = $false; why = 'write a file in the fixture' }
    @{ code = "\$rows | Out-File report.txt";                               deny = $false; why = 'Out-File in the fixture' }
    @{ code = "Format-Table -AutoSize";                                     deny = $false; why = 'Format-Table is not Format-Volume' }
    @{ code = "Rename-Item old.txt new.txt";                                deny = $false; why = 'rename inside the fixture' }
    @{ code = "Copy-Item 'a.txt' 'b.txt'";                                  deny = $false; why = 'copy inside the fixture' }
    @{ code = "Get-Content '..\shared\a.txt'";                              deny = $false; why = 'READING a parent path is harmless' }
    @{ code = "(Get-Content 'f.txt') -replace 'a','b' | Set-Content 'f.txt'"; deny = $false; why = 'in-place edit, the precision pattern' }
    @{ code = "Remove-Item 'temp.txt'";                                     deny = $false; why = 'delete inside the fixture' }
    @{ code = "Get-Content 'big/app-12k.log' | Select-String 'ERROR'";      deny = $false; why = 'the context task' }
    @{ code = "Get-CimInstance Win32_OperatingSystem | Select-Object -First 1"; deny = $false; why = 'harmless read' }
    @{ code = "\$n = 0; foreach (\$l in Get-Content 'x.txt') { \$n++ }";     deny = $false; why = 'plain computation' }
    @{ code = "# curl; net user; HKLM; shutdown`nSet-Content -Path 'out.txt' -Value 'x'"; deny = $false; why = 'dangerous words in a comment are prose' }
    @{ code = "\$note = 'curl net user HKLM shutdown'; Set-Content -Path 'out.txt' -Value \$note"; deny = $false; why = 'dangerous words in a data string are not commands' }
    # --- must be DENIED: effects outside the fixture or system-level ----------
    @{ code = "Set-Content -Path 'C:\Windows\x.txt' -Value 'x'";            deny = $true;  why = 'write to a drive path' }
    @{ code = "Out-File '..\..\outside.txt'";                               deny = $true;  why = 'write climbing out of the fixture' }
    @{ code = "Copy-Item 'a.txt' '\\server\share\'";                        deny = $true;  why = 'write to a UNC path' }
    @{ code = "Remove-Item -Recurse 'C:\'";                                 deny = $true;  why = 'destructive drive-wide delete' }
    @{ code = "Format-Volume -DriveLetter C";                               deny = $true;  why = 'the real Format- danger' }
    @{ code = "Stop-Computer";                                              deny = $true;  why = 'system shutdown' }
    @{ code = "Invoke-RestMethod 'http://example.com'";                     deny = $true;  why = 'network egress' }
    @{ code = "Set-ExecutionPolicy Bypass";                                 deny = $true;  why = 'policy change' }
    @{ code = "schtasks /create /tn x /tr y";                               deny = $true;  why = 'scheduled task creation' }
    @{ code = "'data' | Set-Content 'C:\data\out.txt'";                     deny = $true;  why = 'write outside via pipeline' }
    @{ code = "\$p = 'C:\x'; Set-Content \$p -Value 'x'";                    deny = $true;  why = 'variable-held write path fails closed' }
    @{ code = "'x' > ~/outside.txt";                                            deny = $true;  why = 'home-directory redirect fails closed' }
    @{ code = "'x' > \$env:TEMP\\outside.txt";                                deny = $true;  why = 'environment redirect fails closed' }
)

$fail = 0
foreach ($c in $cases) {
    $reason = Get-CodeDenyReason -Code $c.code
    $isDenied = ("$reason".Trim() -ne '')
    $ok = ($isDenied -eq $c.deny)
    if (-not $ok) { $fail++ }
    $want = 'ALLOW'
    if ($c.deny) { $want = 'DENY ' }
    $got = 'ALLOW'
    if ($isDenied) { $got = 'DENY ' }
    $mark = 'FAIL'
    if ($ok) { $mark = 'ok  ' }
    Write-Output ("  $mark want=$want got=$got  " + $c.why)
    if (-not $ok) { Write-Output ("        reason: " + $reason) }
}

Write-Output ""
if ($fail -eq 0) {
    Write-Output ("DENY-POLICY SELFTEST: PASS (" + $cases.Count + "/" + $cases.Count + ")")
    exit 0
} else {
    Write-Output ("DENY-POLICY SELFTEST: FAIL (" + $fail + " of " + $cases.Count + " wrong)")
    exit 1
}
