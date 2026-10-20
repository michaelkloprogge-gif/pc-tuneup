# Pictures of PC Tune-Up for the Microsoft Store listing: opens the app off-screen at 1500x1000, runs every check and
# saves the pages in -Pages. The Health and Updates pages get demo data (see below). Nothing on this PC is changed and the app's own settings are not used.
# Usage: powershell -STA -File .\tests\Store-Screenshots.ps1 -Out store\screenshots\en [-Language nl] [-Theme dark] [-Pages Health,Clean]
param([Parameter(Mandatory)][string]$Out, [string]$Language = 'en', [string]$Theme = 'light', [string[]]$Pages = @('Health', 'Clean', 'Privacy', 'Updates', 'Security', 'Bloatware', 'Upgrades'), [int]$TimeoutSec = 300)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$harness = @'
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { 'No' }
Add-Type -Namespace Shot -Name Win -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
"@
$form.MinimumSize = New-Object Drawing.Size(0, 0); $form.Size = New-Object Drawing.Size(1500, 1000)
$form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-4000, 40)
[void][Shot.Win]::ShowWindow($form.Handle, 4)    # SW_SHOWNOACTIVATE: visible, but never steals focus
Start-Everything; foreach ($n in @($script:LoadQueue)) { Invoke-PageLoader $n }
$deadline = (Get-Date).AddSeconds(__TIMEOUT__)
do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while (($script:Jobs.Count -gt 0 -or $script:LoadQueue.Count -gt 0) -and (Get-Date) -lt $deadline)
# Demo data where the real PC would show personal things or a bad day: a healthy-looking Health page (memory,
# disk, score history) and an ordinary set of program updates instead of this PC's own programs.
$q = $script:HealthQuick
if ($q) {
    $q.Cpu = 9; $q.FreeKB = [int64]($q.TotalKB * 0.52); $q.Boot = (Get-Date).AddHours(-27).AddMinutes(-14)
    foreach ($d in $q.Disks) { $d.Free = [int64]($d.Size * 0.41) }
}
if ($script:HealthDeep) {
    $script:HealthDeep.Lines = @($script:HealthDeep.Lines | ForEach-Object { $_ -replace 'update \d+ day\(s\)', 'update 3 day(s)' })
    $script:HealthDeep.Advice = @($script:HealthDeep.Advice | Where-Object { $_ -match 'battery' })   # the real battery, as on the Upgrades page
}
foreach ($k in @($script:ExtraAdvice.Keys)) { if ($k -ne 'Updates') { $script:ExtraAdvice.Remove($k) } }
$script:NetProblems = 0; $script:StabIndex = 9.6
$demoUpd = @(
    ,@('7-Zip', '7zip.7zip', '24.08', '24.09', 'small update', $true)
    ,@('VLC media player', 'VideoLAN.VLC', '3.0.20', '3.0.21', 'small update', $true)
    ,@('Notepad++', 'Notepad++.Notepad++', '8.6.9', '8.7.1', 'small update', $true)
    ,@('LibreOffice', 'TheDocumentFoundation.LibreOffice', '24.2.6', '24.2.7', 'small update', $true)
    ,@('Microsoft Visual C++ 2015-2022 Redistributable (x64)', 'Microsoft.VCRedist.2015+.x64', '14.38.33135', '14.40.33810', 'small update', $true)
    ,@('Mozilla Firefox', 'Mozilla.Firefox', '131.0.2', '132.0.1', 'updates itself - just restart it', $false)
    ,@('Zoom Workplace', 'Zoom.Zoom', '6.2.0', '6.2.5', 'updates itself - just restart it', $false)
    ,@('Spotify', 'Spotify.Spotify', '1.2.48', '1.2.50', 'updates itself - just restart it', $false)
    ,@('GIMP', 'GIMP.GIMP', '2.10.38', '3.0.0', 'major new version - check it still suits you', $false)
)
$lvUpd.BeginUpdate(); $lvUpd.Items.Clear()
foreach ($u in $demoUpd) {
    $it = Add-Row $lvUpd @($u[0], $u[2], $u[3], $u[4]) ([pscustomobject]@{ Name = $u[0]; Id = $u[1]; Version = $u[2]; Available = $u[3]; Pending = $false }) $u[5]
    if (-not $u[5]) { $it.ForeColor = $Theme.Muted }
}
$lvUpd.EndUpdate()
$script:UpdWaiting = $demoUpd.Count
$lblUpd.Text = "$($demoUpd.Count) program(s) can be updated, $($lvUpd.CheckedItems.Count) pre-checked."
$script:ExtraAdvice['Updates'] = "$($demoUpd.Count) program update(s) available - see the Updates tab."
$script:HealthDrawn = $null; Render-Health
$score = Get-HealthScore
$days = 30; $rnd = New-Object Random 7
$script:StabHistory = @(for ($i = $days; $i -ge 0; $i--) { [pscustomobject]@{ D = (Get-Date).Date.AddDays(-$i); V = [Math]::Round([Math]::Min(10, 6.2 + 3.4 * ($days - $i) / $days + $rnd.NextDouble() * 0.4), 1) } })
$scores = for ($i = $days; $i -ge 0; $i -= 3) { [pscustomobject]@{ Date = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd'); Score = $(if ($i -eq 0) { $score } else { [int](54 + ($score - 54) * ($days - $i) / $days + $rnd.Next(-3, 4)) }); Stability = 9; Advice = 1 } }
Set-Content -Path $ScoreFile -Value @($scores | ForEach-Object { $_ | ConvertTo-Json -Compress }) -Encoding UTF8
$script:StepsCache = $null; $script:StartDrawn = $null
Update-ScoreChart; Update-NavBadges
$want = @(__PAGES__)
foreach ($p in $script:Pages) {
    if ($want.Count -and $p.Name -notin $want) { continue }
    Show-Page $p
    1..10 | ForEach-Object { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save((Join-Path '__OUT__' "$($p.Name).png")); $bmp.Dispose()
    "saved $($p.Name)"
}
$form.Close()
'@
$pageList = ($Pages | ForEach-Object { "'$_'" }) -join ', '
$src = [IO.File]::ReadAllText((Join-Path $here '..\pc-tuneup.ps1'))
$src = $src.Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec).Replace('__OUT__', $Out).Replace('__PAGES__', $pageList))
$src = $src.Replace("`$Settings = [ordered]@{ Language = 'auto'; Theme = 'system'", "`$Settings = [ordered]@{ Language = '$Language'; Theme = '$Theme'")
$src = $src.Replace("AskedInstall = `$false;", "AskedInstall = `$true;").Replace("TourShown = `$false;", "TourShown = `$true;")
$src = $src.Replace("`$SettingsFile = Join-Path `$DataDir 'settings.json'", "`$SettingsFile = Join-Path `$env:TEMP 'pctuneup-store-settings.json'")
$src = $src.Replace("if (Test-Path `$SettingsFile) {", "if (`$false) {")
$src = $src.Replace("`$ScoreFile = Join-Path `$DataDir 'scores.jsonl'", "`$ScoreFile = Join-Path `$env:TEMP 'pctuneup-store-scores.jsonl'")   # the demo score history
$tmp = Join-Path $env:TEMP "pctuneup-store-shots-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
$env:PCTUNEUP_LANGDIR = Join-Path $here '..\lang'
try { & $tmp } finally { Remove-Item $tmp, (Join-Path $env:TEMP 'pctuneup-store-settings.json'), (Join-Path $env:TEMP 'pctuneup-store-scores.jsonl') -ErrorAction SilentlyContinue }
