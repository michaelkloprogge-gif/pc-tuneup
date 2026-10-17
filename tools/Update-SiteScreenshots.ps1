# Makes the screenshots for the website (docs/screenshots): runs tests\Screenshots.ps1 in light and dark, copies the chosen pages.
# Usage: powershell -STA -File .\tools\Update-SiteScreenshots.ps1   (takes a few minutes; changes nothing on the PC)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp = Join-Path $env:TEMP "pctuneup-site-$PID"
$light = Join-Path $tmp 'light'; $dark = Join-Path $tmp 'dark'
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Screenshots.ps1') -Out $light | Out-Null
$src = [IO.File]::ReadAllText((Join-Path $root 'pc-tuneup.ps1')).Replace('$Dark = switch ($Settings.Theme)', '$Dark = $true; $null = switch ($Settings.Theme)')
$darkApp = Join-Path $tmp 'pc-tuneup-dark.ps1'; New-Item -ItemType Directory -Force $tmp | Out-Null
[IO.File]::WriteAllText($darkApp, $src, (New-Object Text.UTF8Encoding($true)))
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Screenshots.ps1') -Out $dark -App $darkApp | Out-Null
$pick = @{ 'Health' = 'health.png'; 'Space savers' = 'space-savers.png'; 'Privacy' = 'privacy.png'; 'Battery' = 'battery.png' }
$out = Join-Path $root 'docs\screenshots'
foreach ($k in $pick.Keys) { $f = Get-ChildItem $light -Filter "*-$k.png" | Select-Object -First 1; if ($f) { Copy-Item $f.FullName (Join-Path $out $pick[$k]) -Force; "saved $($pick[$k])" } }
$f = Get-ChildItem $dark -Filter '*-Health.png' | Select-Object -First 1; if ($f) { Copy-Item $f.FullName (Join-Path $out 'health-dark.png') -Force; 'saved health-dark.png' }
# Dutch: same pages, app in Dutch (light) and Dutch + dark
foreach ($v in @(@{ Name = 'nl'; Dark = $false }, @{ Name = 'nl-dark'; Dark = $true })) {
    $code = [IO.File]::ReadAllText((Join-Path $root 'pc-tuneup.ps1')).Replace('$Lang = switch ($Settings.Language)', '$Lang = ''nl''; $null = switch ($Settings.Language)')
    if ($v.Dark) { $code = $code.Replace('$Dark = switch ($Settings.Theme)', '$Dark = $true; $null = switch ($Settings.Theme)') }
    $app = Join-Path $tmp "pc-tuneup-$($v.Name).ps1"; [IO.File]::WriteAllText($app, $code, (New-Object Text.UTF8Encoding($true)))
    $o = Join-Path $tmp $v.Name
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Screenshots.ps1') -Out $o -App $app | Out-Null
    $nlOut = Join-Path $out 'nl'; New-Item -ItemType Directory -Force $nlOut | Out-Null
    if ($v.Dark) { $f = Get-ChildItem $o -Filter '*-Health.png' | Select-Object -First 1; if ($f) { Copy-Item $f.FullName (Join-Path $nlOut 'health-dark.png') -Force; 'saved nl/health-dark.png' } }
    else { foreach ($k in $pick.Keys) { $f = Get-ChildItem $o -Filter "*-$k.png" | Select-Object -First 1; if ($f) { Copy-Item $f.FullName (Join-Path $nlOut $pick[$k]) -Force; "saved nl/$($pick[$k])" } } }
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
