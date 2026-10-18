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
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Pages.ps1 -Language en | Out-Null
if ($LASTEXITCODE) { throw 'Page tests failed - run .\tests\Test-Pages.ps1' }
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Buttons.ps1 -Language en | Out-Null
if ($LASTEXITCODE) { throw 'Button tests failed - run .\tests\Test-Buttons.ps1' }

git add -A
git diff --cached --quiet
if ($LASTEXITCODE) { git commit -m "Release $tag" }
git push origin HEAD
if ($LASTEXITCODE) { throw 'git push failed (signed in? run: gh auth setup-git)' }
# The tag goes in its own push: GitHub doesn't always start a tag build when it arrives together with the branch.
git tag $tag
git push origin "refs/tags/$tag"
if ($LASTEXITCODE) { throw 'pushing the tag failed' }

# Follow the tag's GitHub build (not the branch build, which never publishes) until the release is out.
$run = $null
foreach ($i in 1..40) { Start-Sleep 3; $run = gh run list --workflow release.yml --branch $tag --limit 1 --json databaseId --jq '.[0].databaseId'; if ($run) { break } }
if (-not $run) { throw "No GitHub build started for $tag - check the Actions tab." }
gh run watch $run --exit-status
if ($LASTEXITCODE) { throw "The GitHub build failed - see: gh run view $run --log-failed" }
gh release view $tag --json tagName --jq .tagName | Out-Null
if ($LASTEXITCODE) { throw "The build passed but release $tag is missing." }
"Published $tag"
