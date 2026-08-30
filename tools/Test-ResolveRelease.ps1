#requires -Version 5.1
# Checks for Resolve-OciRelease in update.ps1, run against the live GitHub API.
#
# Oracle uploads the Windows MSI ~20h after publishing a release and sometimes
# skips it entirely, so these assert the two properties that must hold whatever
# Oracle does next, rather than pinning today's version numbers.
#
#   pwsh -File tools/Test-ResolveRelease.ps1

$ErrorActionPreference = 'Stop'
$update = Join-Path (Split-Path $PSScriptRoot -Parent) 'update.ps1'

$fail = 0
function Check($label, $ok, $detail) {
    if (-not $ok) { $script:fail++ }
    "{0,-52} {1}  {2}" -f $label, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail
}

$r = & $update -ResolveOnly 3>$null

# 1. Whatever it picks must actually carry the MSI this package installs.
$headers = @{ 'User-Agent' = 'oci-cli-updater-test'; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
$tag = "v$($r.Version)"
$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/oracle/oci-cli/releases/tags/$tag" -Headers $headers
$msi = @($rel.assets | Where-Object { $_.name -like '*Windows-Server-Installer.msi' })
Check 'resolved release carries a Windows MSI' ($msi.Count -eq 1) "$tag"
Check 'resolved URL is that asset'             ($r.Url -eq $msi[0].browser_download_url) ''
Check 'checksum looks like a SHA256'           ($r.Sha256 -match '^[0-9a-f]{64}$') ''

# 2. The grace window is what separates "Oracle is slow" from "Oracle skipped it".
#    A huge grace must silence the warning; a zero grace must raise it whenever a
#    newer release exists, which is the normal state during the upload lag.
$all    = Invoke-RestMethod -Uri 'https://api.github.com/repos/oracle/oci-cli/releases?per_page=15' -Headers $headers
$newest = @($all | Where-Object { -not $_.draft -and -not $_.prerelease })[0].tag_name
$lenient = & $update -ResolveOnly -MsiGraceHours 1000000 3>$null
$strict  = & $update -ResolveOnly -MsiGraceHours 0 3>$null
Check 'huge grace suppresses the warning' ([string]::IsNullOrEmpty($lenient.SkippedMsi)) ''
if ($newest -eq $tag) {
    Check 'zero grace is quiet when nothing is newer' ([string]::IsNullOrEmpty($strict.SkippedMsi)) "newest=$newest"
} else {
    Check 'zero grace flags the newer MSI-less release' ($strict.SkippedMsi -eq ($newest -replace '^v','')) "newest=$newest"
}

if ($fail) { throw "$fail check(s) failed." }
"`nAll checks passed."
