param(
    # Your GarrysMod\garrysmod folder; defaults to $env:GMOD_ROOT\garrysmod.
    [string]$GameRoot = $(if ($env:GMOD_ROOT) { Join-Path $env:GMOD_ROOT 'garrysmod' } else { '' })
)
$ErrorActionPreference = 'Stop'
if (-not $GameRoot) { throw 'Pass -GameRoot <GarrysMod\garrysmod> or set GMOD_ROOT' }
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$gamePath = (Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd('\')
$addonParent = Join-Path $gamePath 'addons'
$addonPath = [IO.Path]::GetFullPath((Join-Path $addonParent 'gemu'))
if ($addonPath -ne ($addonParent + '\gemu')) { throw 'Unexpected addon path' }
if (Test-Path -LiteralPath (Join-Path $addonParent 'gemu.gma')) { throw 'Installed gemu.gma exists. Remove/archive that package before using a development junction to avoid duplicate mounts.' }
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'addon.json'))) { throw 'Source is not the addon workspace' }
if ($sourceRoot.StartsWith($addonPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Source would be inside destination' }

if (Test-Path -LiteralPath $addonPath) {
    $entry = Get-Item -LiteralPath $addonPath -Force
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $targetPath = [IO.Path]::GetFullPath([string]$entry.Target[0]).TrimEnd('\')
        if ($targetPath -ne $sourceRoot) { throw "Existing link points somewhere else: $targetPath" }
        Write-Output "Verified junction: $addonPath -> $targetPath"
        exit 0
    }
    $backupRoot = [IO.Path]::GetFullPath((Join-Path $gamePath 'gemu-backups'))
    $backupPath = [IO.Path]::GetFullPath((Join-Path $backupRoot ('installed-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))))
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    Move-Item -LiteralPath $addonPath -Destination $backupPath
    Write-Output "Preserved installed copy: $backupPath"
}
New-Item -ItemType Junction -Path $addonPath -Target $sourceRoot | Out-Null
$result = Get-Item -LiteralPath $addonPath -Force
if ($result.LinkType -ne 'Junction' -or [string]$result.Target[0] -ne $sourceRoot) { throw 'Junction verification failed' }
Write-Output "Verified junction: $addonPath -> $sourceRoot"
