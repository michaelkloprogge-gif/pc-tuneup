# Publishes a new PC Tune-Up release to GitHub so every copy of the app offers the update.
#   1. Bump $AppVersion in pc-tuneup.ps1
#   2. Run:  .\publish-release.ps1 -Notes "What changed"
# Builds the exe, commits, tags v<version>, pushes, and attaches the exe to a GitHub release.
param([Parameter(Mandatory)][string]$Notes)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
if ((Get-Content .\pc-tuneup.ps1 -Raw) -notmatch "\`$AppVersion = '(\d+\.\d+\.\d+)'") { throw 'No $AppVersion in pc-tuneup.ps1' }
$tag = "v$($Matches[1])"
if (git tag --list $tag) { throw "$tag already exists - bump `$AppVersion in pc-tuneup.ps1 first." }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-exe.ps1
if ($LASTEXITCODE) { throw 'Build failed' }

git add -A
git diff --cached --quiet
if ($LASTEXITCODE) { git commit -m "Release $tag" -m $Notes }
git tag $tag
git push origin HEAD --tags
gh release create $tag .\dist\PC-TuneUp.exe --title "PC Tune-Up $tag" --notes $Notes
if ($LASTEXITCODE) { throw 'gh release create failed' }
"Published $tag"
