# Makes the screenshots for the website (docs/screenshots): runs tests\Screenshots.ps1 in every language, light and dark,
# and copies the chosen pages. English goes in docs/screenshots, the others in docs/screenshots/<language>.
# Usage: powershell -STA -File .\tools\Update-SiteScreenshots.ps1 [-Languages en,nl,de,fr]   (takes a while; changes nothing on the PC)
param([string[]]$Languages = @('en', 'nl', 'de', 'fr'))
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp = Join-Path $env:TEMP "pctuneup-site-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$env:PCTUNEUP_LANGDIR = Join-Path $root 'lang'   # the patched copies live in $tmp, so tell them where German and French are
# Light: these pages (plus the simple view). Dark: Health and the simple view.
$pick = @{ 'Health' = 'health.png'; 'Space savers' = 'space-savers.png'; 'Privacy' = 'privacy.png'; 'Battery' = 'battery.png'; 'Simple view' = 'simple.png' }
$pickDark = @{ 'Health' = 'health-dark.png'; 'Simple view' = 'simple-dark.png' }
foreach ($lang in $Languages) {
    $out = if ($lang -eq 'en') { Join-Path $root 'docs\screenshots' } else { Join-Path $root "docs\screenshots\$lang" }
    New-Item -ItemType Directory -Force $out | Out-Null
    foreach ($dark in $false, $true) {
        $code = [IO.File]::ReadAllText((Join-Path $root 'pc-tuneup.ps1')).Replace('$Lang = switch ($Settings.Language)', "`$Lang = '$lang'; `$null = switch (`$Settings.Language)")
        if ($dark) { $code = $code.Replace('$Dark = switch ($Settings.Theme)', '$Dark = $true; $null = switch ($Settings.Theme)') }
        $name = "$lang-$(if ($dark) { 'dark' } else { 'light' })"
        $app = Join-Path $tmp "pc-tuneup-$name.ps1"; [IO.File]::WriteAllText($app, $code, (New-Object Text.UTF8Encoding($true)))
        $o = Join-Path $tmp $name
        & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Screenshots.ps1') -Out $o -App $app -SimpleView | Out-Null
        $map = if ($dark) { $pickDark } else { $pick }
        foreach ($k in $map.Keys) {
            $f = Get-ChildItem $o -Filter "*-$k.png" | Select-Object -First 1
            if ($f) { Copy-Item $f.FullName (Join-Path $out $map[$k]) -Force; "saved $lang/$($map[$k])" } else { Write-Warning "no $k screenshot for $name" }
        }
    }
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
