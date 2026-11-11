$ErrorActionPreference = 'Stop'

# Oracle Cloud Infrastructure CLI - official Windows MSI installer.
# Downloaded at install time directly from the oracle/oci-cli GitHub releases
# and verified against the SHA256 Oracle publishes in the release notes.
# See tools\VERIFICATION.txt for how to reproduce the checksum.
#
# The MSI is built with cx_Freeze: it bundles its own Python runtime, installs
# to "C:\Program Files (x86)\Oracle\oci_cli\", and prepends that directory to the
# system PATH (so 'oci' works in new shells). A silent /qn install applies all
# of this with no prompts; uninstalling removes the PATH entry again.

$packageArgs = @{
    packageName    = 'oci-cli'
    fileType       = 'msi'
    url64bit       = 'https://github.com/oracle/oci-cli/releases/download/v3.96.2/oci-cli-3.96.2-Windows-Server-Installer.msi'
    checksum64     = '0b4e93c33a9bb3b8631de7bc79fdee337b0b5759b96adcab75f5e6a0960e0bca'
    checksumType64 = 'sha256'
    silentArgs     = '/qn /norestart'
    validExitCodes = @(0, 3010, 1641)
    softwareName   = 'oci-cli*'
}

Install-ChocolateyPackage @packageArgs

Write-Host "Installed Oracle Cloud Infrastructure CLI (command: oci)."
Write-Host "Open a new terminal, then run 'oci setup config' (or 'oci session authenticate')."
