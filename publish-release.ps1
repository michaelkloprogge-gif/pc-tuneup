# Publishes a new PC Tune-Up release. GitHub Actions does the building, testing and releasing;
# every installed copy then offers the update.
#   1. Bump $AppVersion in pc-tuneup.ps1
#   2. Add a "## <version>" section at the top of CHANGELOG.md (or pass -Notes and it is added for you)
#   3. Run:  .\publish-release.ps1
param([string]$Notes)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
if ((Get-Content .\pc-tuneup.ps1 -Raw) -notmatch "\`$AppVersion = '(\d+\.\d+\.\d+)'") { throw 'No $AppVersion in pc-tuneup.ps1' }
$version = $Matches[1]; $tag = "v$version"
if (git tag --list $tag) { throw "$tag already exists - bump `$AppVersion in pc-tuneup.ps1 first." }

$log = Get-Content .\CHANGELOG.md -Raw
if ($log -notmatch "(?m)^## $([regex]::Escape($version))\s*$") {
    if (-not $Notes) { throw "CHANGELOG.md has no '## $version' section - add one, or pass -Notes." }
    $log = $log -replace '^# Changelog\s*', "# Changelog`r`n`r`n## $version`r`n`r`n- $Notes`r`n`r`n"
    Set-Content .\CHANGELOG.md $log -Encoding UTF8 -NoNewline
}

# Same checks as the GitHub build, so a broken release never gets tagged.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Upgrades.ps1 -Check | Out-Null
if ($LASTEXITCODE) { throw 'Upgrade advice tests failed - run .\tests\Test-Upgrades.ps1 -Check' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Translation.ps1 | Out-Null
if ($LASTEXITCODE) { throw 'Translation tests failed - run .\tests\Test-Translation.ps1' }

git add -A
git diff --cached --quiet
if ($LASTEXITCODE) { git commit -m "Release $tag" }
git tag $tag
git push origin HEAD --tags
if ($LASTEXITCODE) { throw 'git push failed (signed in? run: gh auth setup-git)' }

# Follow the GitHub build until the release is out.
Start-Sleep 8
$run = gh run list --workflow release.yml --branch $tag --limit 1 --json databaseId --jq '.[0].databaseId'
if (-not $run) { $run = gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId' }
gh run watch $run --exit-status
if ($LASTEXITCODE) { throw "The GitHub build failed - see: gh run view $run --log-failed" }
"Published $tag"
