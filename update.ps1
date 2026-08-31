#requires -Version 5.1
# Automated updater for the community oci-cli Chocolatey package.
#
# Resolves the newest oracle/oci-cli release that actually ships the official
# Windows MSI, and reads its SHA256 from the checksum list Oracle publishes in
# the release notes (no large download needed). It rewrites the package files,
# packs, and with -Push also publishes.
#
# Not simply 'releases/latest': Oracle uploads the MSI roughly a day after
# publishing a release, and sometimes skips it altogether (3.90.2, 3.91.0), so
# 'latest' regularly points at a release with nothing for us to package.
#
#   .\update.ps1               # update + pack only
#   .\update.ps1 -Push         # update + pack + push (needs CHOCO_API_KEY)
#   .\update.ps1 -ResolveOnly  # just show the latest GitHub release

[CmdletBinding()]
param(
    [switch]$Push,
    [switch]$ResolveOnly,
    [string]$ApiKey     = $env:CHOCO_API_KEY,
    [string]$PushSource = 'https://push.chocolatey.org/',
    # How long Oracle is allowed to take over the MSI upload before a newer
    # MSI-less release counts as skipped rather than merely pending. Observed
    # lag is 18-22h across 3.89.3, 3.90.0, 3.90.1 and 3.90.3.
    [int]$MsiGraceHours = 48
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$nuspecPath  = Join-Path $PSScriptRoot 'oci-cli.nuspec'
$installPath = Join-Path $PSScriptRoot 'tools\chocolateyinstall.ps1'
$verifyPath  = Join-Path $PSScriptRoot 'tools\VERIFICATION.txt'

function Save-XmlNoBom([xml]$Xml, [string]$Path) {
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $settings.OmitXmlDeclaration = $false

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try { $Xml.Save($writer) } finally { $writer.Close() }
}

function Resolve-OciRelease {
    $headers = @{ 'User-Agent' = 'chocolatey-oci-cli-updater'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

    # Assign before filtering: in Windows PowerShell 5.1 Invoke-RestMethod emits a
    # JSON array as a single pipeline item, so piping it straight into Where-Object
    # binds $_ to the whole array and every element test silently fails.
    $all = Invoke-RestMethod -Uri 'https://api.github.com/repos/oracle/oci-cli/releases?per_page=15' -Headers $headers
    $releases = @($all | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^v\d+\.\d+\.\d+$' })
    if (-not $releases) { throw "No usable releases returned for oracle/oci-cli." }

    $newest = $releases[0]
    $rel = $releases | Where-Object {
        $_.assets | Where-Object { $_.name -like '*Windows-Server-Installer.msi' }
    } | Select-Object -First 1
    if (-not $rel) { throw "None of the last $($releases.Count) oracle/oci-cli releases carries a Windows MSI asset." }

    $version = $rel.tag_name -replace '^v', ''
    $asset   = $rel.assets | Where-Object { $_.name -like '*Windows-Server-Installer.msi' } | Select-Object -First 1

    # Oracle lists each asset's SHA256 in the release body under "File Checksums (SHA256)".
    $sha = [regex]::Match($rel.body, [regex]::Escape($asset.name) + '\s+([0-9a-fA-F]{64})').Groups[1].Value
    if (-not $sha) { throw "Could not find a published SHA256 for $($asset.name) in the release notes." }

    # A newer release without an MSI is normal for about a day. Past the grace
    # window it means Oracle skipped Windows for that release, which is worth
    # saying out loud, since from here on the package silently stands still.
    $skipped = $null
    if ($rel.tag_name -ne $newest.tag_name) {
        $published = ([datetime]$newest.published_at).ToUniversalTime()
        if (([datetime]::UtcNow - $published).TotalHours -gt $MsiGraceHours) {
            $skipped = $newest.tag_name -replace '^v', ''
        }
    }

    [pscustomobject]@{
        Version    = $version
        Url        = $asset.browser_download_url
        Sha256     = $sha.ToLower()
        SkippedMsi = $skipped
    }
}

$rel = Resolve-OciRelease

if ($rel.SkippedMsi) {
    Write-Warning "Oracle release $($rel.SkippedMsi) has shipped no Windows MSI more than $MsiGraceHours h after publication. Packaging $($rel.Version) instead; the package stands still until Oracle ships an MSI again."
    if ($env:GITHUB_OUTPUT) { "msi_missing=$($rel.SkippedMsi)" | Add-Content -Path $env:GITHUB_OUTPUT }
}

if ($ResolveOnly) { return $rel }   # returned, not formatted, so callers can assert on it

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
Save-XmlNoBom $nuspec $nuspecPath
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
