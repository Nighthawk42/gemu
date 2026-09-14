param(
    [Parameter(Mandatory = $true)][string]$RemoteHost,
    [Parameter(Mandatory = $true)][string]$RemotePath
)
$ErrorActionPreference = 'Stop'
$archive = Join-Path $PSScriptRoot '..\.work\gemu-web-release.tar.gz'
python (Join-Path $PSScriptRoot 'package_web.py') --out $archive
if ($LASTEXITCODE -ne 0) { throw 'Web packaging failed' }
# Upload only. Extract into an EMPTY release directory and swap it into place;
# overlay extraction would leave previously hosted, unselected ROMs public.
scp $archive "${RemoteHost}:gemu-web-release.tar.gz"
if ($LASTEXITCODE -ne 0) { throw 'Upload failed' }
Write-Host "Uploaded curated archive. Install as a fresh release at $RemotePath; archive old content outside the web root."
