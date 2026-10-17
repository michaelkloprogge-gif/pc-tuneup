# Writes the winget manifests for a published release, ready to submit to github.com/microsoft/winget-pkgs
# (fork it, copy the folder from winget\manifests into the same place, open a pull request - or use wingetcreate).
# Usage: .\tools\New-WingetManifest.ps1 [-Version 1.6.0]
param([string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$repo = 'michaelkloprogge-gif/pc-tuneup'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$api = if ($Version) { "https://api.github.com/repos/$repo/releases/tags/v$Version" } else { "https://api.github.com/repos/$repo/releases/latest" }
$rel = Invoke-RestMethod $api -Headers @{ 'User-Agent' = 'PC-TuneUp' }
$Version = $rel.tag_name -replace '^v', ''
$asset = @($rel.assets | Where-Object name -eq 'PC-TuneUp.exe')[0]
if (-not $asset) { throw "Release v$Version has no PC-TuneUp.exe" }
$sha = if ($asset.digest -match '^sha256:([0-9a-f]{64})$') { $Matches[1].ToUpper() } else {
    $tmp = Join-Path $env:TEMP "PC-TuneUp-$Version.exe"; Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing
    (Get-FileHash $tmp -Algorithm SHA256).Hash }
$id = 'MichaelKloprogge.PCTuneUp'
$dir = Join-Path $root "winget\manifests\m\MichaelKloprogge\PCTuneUp\$Version"
New-Item -ItemType Directory -Force $dir | Out-Null
$schema = '1.6.0'
@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.$schema.schema.json
PackageIdentifier: $id
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $schema
"@ | Set-Content (Join-Path $dir "$id.yaml") -Encoding UTF8
@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.$schema.schema.json
PackageIdentifier: $id
PackageVersion: $Version
InstallerType: portable
Commands:
- pc-tuneup
Installers:
- Architecture: x64
  InstallerUrl: $($asset.browser_download_url)
  InstallerSha256: $sha
ManifestType: installer
ManifestVersion: $schema
"@ | Set-Content (Join-Path $dir "$id.installer.yaml") -Encoding UTF8
@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.$schema.schema.json
PackageIdentifier: $id
PackageVersion: $Version
PackageLocale: en-US
Publisher: Michael Kloprogge
PublisherUrl: https://github.com/michaelkloprogge-gif
PackageName: PC Tune-Up
PackageUrl: https://github.com/$repo
License: MIT
LicenseUrl: https://github.com/$repo/blob/main/LICENSE
ShortDescription: Check, clean and speed up any Windows PC with one click, and undo anything.
Description: Clears junk, stops apps starting with Windows, removes bloatware, updates programs, and explains crashes, security settings and upgrade options in plain language. English and Dutch.
Tags:
- cleanup
- bloatware
- startup
- performance
- maintenance
ReleaseNotesUrl: https://github.com/$repo/releases/tag/v$Version
ManifestType: defaultLocale
ManifestVersion: $schema
"@ | Set-Content (Join-Path $dir "$id.locale.en-US.yaml") -Encoding UTF8
"Wrote winget manifests for $id $Version in $dir"
