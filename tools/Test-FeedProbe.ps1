#requires -Version 5.1
# Check for the feed probe in .github/workflows/update.yml.
#
# Extracts Get-FeedState verbatim from the workflow and exercises it, so the
# thing under test is the code that actually ships. Run from the repo root:
#
#   pwsh -File tools/Test-FeedProbe.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$wf   = Get-Content (Join-Path $root '.github/workflows/update.yml') -Raw

$fn = [regex]::Match($wf, '(?s)          function Get-FeedState \{.*?\r?\n          \}').Value
if (-not $fn) { throw "Could not find Get-FeedState in update.yml. Did the step get renamed?" }
Invoke-Expression ($fn -replace '(?m)^          ', '')

$fail = 0
function Check($label, $actual, $expected) {
    $ok = $actual -eq $expected
    if (-not $ok) { $script:fail++ }
    "{0,-46} expected={1,-8} got={2,-8} {3}" -f $label, $expected, $actual, $(if ($ok) { 'PASS' } else { 'FAIL' })
}

# Live feed. 3.90.3 is the current published version.
Check 'published version resolves'        (Get-FeedState '3.90.3')   'present'
Check 'never-published version is absent' (Get-FeedState '99.99.99') 'absent'

# A reachable host that answers non-404 stands in for the feed's 503s, which is
# the case that must NOT be read as 'absent'.
$real = Get-Item function:Get-FeedState
$src  = $real.Definition -replace 'https://community\.chocolatey\.org/api/v2/Packages\(Id=''oci-cli'',Version=''\$Version''\)', 'https://community.chocolatey.org/api/v2/$Version'
Set-Item function:Get-FeedStateStub -Value ([ScriptBlock]::Create($src))
Check 'server error is unknown, not absent' (Get-FeedStateStub 'Packages(Id=%27oci-cli%27)') 'unknown'

if ($fail) { throw "$fail check(s) failed." }
"`nAll checks passed."
