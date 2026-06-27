# oci-cli (Chocolatey package)

Unofficial, community-maintained Chocolatey package for the **Oracle Cloud
Infrastructure CLI** (`oci`), wrapping Oracle's official Windows MSI.

> Not affiliated with Oracle. OCI CLI is open source (UPL 1.0 / Apache 2.0).

```powershell
choco install oci-cli
```

The package downloads Oracle's official Windows MSI from the
[oracle/oci-cli releases](https://github.com/oracle/oci-cli/releases) and verifies
it against Oracle's published SHA256 (see [`tools/VERIFICATION.txt`](tools/VERIFICATION.txt)).
A daily GitHub Action runs [`update.ps1`](update.ps1) to track new releases.