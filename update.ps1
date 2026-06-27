#requires -Version 5.1
# Automated updater for the community oci-cli Chocolatey package.
#
# Resolves the latest release from the oracle/oci-cli GitHub releases API, finds
# the official Windows MSI asset, and reads its SHA256 from the checksum list
# Oracle publishes in the release notes (no large download needed). It rewrites
# the package files, packs, and with -Push also publishes.
#
#   .\update.ps1               # update + pack only
#   .\update.ps1 -Push         # update + pack + push (needs CHOCO_API_KEY)
#   .\update.ps1 -ResolveOnly  # just show the latest GitHub release

[CmdletBinding()]
param(
    [switch]$Push,
    [switch]$ResolveOnly,
    [string]$ApiKey     = $env:CHOCO_API_KEY,
    [string]$PushSource = 'https://push.chocolatey.org/'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$nuspecPath  = Join-Path $PSScriptRoot 'oci-cli.nuspec'
$installPath = Join-Path $PSScriptRoot 'tools\chocolateyinstall.ps1'
$verifyPath  = Join-Path $PSScriptRoot 'tools\VERIFICATION.txt'

function Resolve-OciRelease {
    $headers = @{ 'User-Agent' = 'chocolatey-oci-cli-updater'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/oracle/oci-cli/releases/latest' -Headers $headers
    $version = $rel.tag_name -replace '^v', ''
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Unexpected release tag: '$($rel.tag_name)'." }

    $asset = $rel.assets | Where-Object { $_.name -like '*Windows-Server-Installer.msi' } | Select-Object -First 1
    if (-not $asset) { throw "No Windows MSI asset found in release $version." }

    # Oracle lists each asset's SHA256 in the release body under "File Checksums (SHA256)".
    $sha = [regex]::Match($rel.body, [regex]::Escape($asset.name) + '\s+([0-9a-fA-F]{64})').Groups[1].Value
    if (-not $sha) { throw "Could not find a published SHA256 for $($asset.name) in the release notes." }

    [pscustomobject]@{
        Version = $version
        Url     = $asset.browser_download_url
        Sha256  = $sha.ToLower()
    }
}

$rel = Resolve-OciRelease

if ($ResolveOnly) { $rel | Format-List; return }

$nuspec  = [xml](Get-Content $nuspecPath -Raw)
$current = $nuspec.package.metadata.version
Write-Host "Current package version: $current   GitHub latest: $($rel.Version)"
if ([version]$rel.Version -le [version]$current) {
    Write-Host "Already up to date; nothing to do."
    return
}

# Parse the current URL + checksum from the install script so replacement is exact.
$installText = Get-Content $installPath -Raw
$oldUrl = [regex]::Match($installText, "url64bit\s*=\s*'([^']+\.msi)'").Groups[1].Value
$oldSha = [regex]::Match($installText, "checksum64\s*=\s*'([0-9a-fA-F]{64})'").Groups[1].Value
if (-not ($oldUrl -and $oldSha)) { throw "Could not parse the current URL/checksum from chocolateyinstall.ps1." }

foreach ($path in $installPath, $verifyPath) {
    $t = Get-Content $path -Raw
    $t = $t.Replace($oldUrl, $rel.Url).Replace($oldSha, $rel.Sha256)
    # VERIFICATION.txt also references the version-tagged release page.
    $t = $t -replace '/releases/tag/v\d+\.\d+\.\d+', "/releases/tag/v$($rel.Version)"
    Set-Content -Path $path -Value $t -Encoding Ascii -NoNewline
}

$nuspec.package.metadata.version = $rel.Version
$nuspec.Save($nuspecPath)
Write-Host "Updated nuspec, chocolateyinstall.ps1, and VERIFICATION.txt to $($rel.Version)."

Write-Host "Packing..."
& choco pack $nuspecPath --out $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "choco pack failed." }

if ($Push) {
    if (-not $ApiKey) { throw "No API key. Pass -ApiKey or set CHOCO_API_KEY." }
    $nupkg = Join-Path $PSScriptRoot "oci-cli.$($rel.Version).nupkg"
    Write-Host "Pushing $nupkg ..."
    & choco push $nupkg --source $PushSource --api-key $ApiKey
    if ($LASTEXITCODE -ne 0) { throw "choco push failed." }
    Write-Host "Pushed oci-cli $($rel.Version). It now enters Chocolatey moderation."
} else {
    Write-Host "Done. Built oci-cli.$($rel.Version).nupkg (run with -Push to publish)."
}
