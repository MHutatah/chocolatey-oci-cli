$ErrorActionPreference = 'Stop'

$packageName  = 'oci-cli'
$softwareName = 'oci-cli*'   # matches the MSI ProductName in Add/Remove Programs

[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName

if ($key.Count -eq 1) {
    $key | ForEach-Object {
        $packageArgs = @{
            packageName    = $packageName
            fileType       = 'msi'
            # PSChildName is the MSI ProductCode; Chocolatey runs 'msiexec /x <code>'.
            silentArgs     = "$($_.PSChildName) /qn /norestart"
            validExitCodes = @(0, 3010, 1605, 1614, 1641)
            file           = ''
        }
        Uninstall-ChocolateyPackage @packageArgs
    }
} elseif ($key.Count -eq 0) {
    Write-Warning "$packageName has already been uninstalled by other means."
} elseif ($key.Count -gt 1) {
    Write-Warning "$($key.Count) matches found for '$softwareName'. Skipping auto-uninstall to be safe."
    $key | ForEach-Object { Write-Warning "- $($_.DisplayName)" }
}
