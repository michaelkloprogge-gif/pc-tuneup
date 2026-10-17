# Measures where PC Tune-Up spends its time: loading, the window's own work (which freezes it),
# and each background check. Runs off-screen without taking focus; changes nothing.
# Usage: powershell -STA -File .\tests\Profile.ps1 [-Language nl]
param([string]$App, [int]$TimeoutSec = 300)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
$src = [IO.File]::ReadAllText($App)
function Patch([string]$Old, [string]$New) {
    foreach ($nl in "`r`n", "`n") { $o = $Old -replace "`r?`n", $nl; if ($script:src.Contains($o)) { $script:src = $script:src.Replace($o, ($New -replace "`r?`n", $nl)); return } }
    throw "profile hook not found: $Old"
}
# Clock from the very first line
$script:src = '$script:Clock = [Diagnostics.Stopwatch]::StartNew(); $script:Marks = New-Object System.Collections.ArrayList' + "`r`n" +
    'function Mark($What, $Ms) { [void]$script:Marks.Add([pscustomobject]@{ At = $script:Clock.ElapsedMilliseconds; What = $What; Ms = [int]$Ms }) }' + "`r`n" + $src
# Background jobs: remember when each started, log how long it took and how long its Done block blocked the window
Patch '[void]$script:Jobs.Add(@{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke();' '[void]$script:Jobs.Add(@{ Clock = [Diagnostics.Stopwatch]::StartNew(); PS = $ps; RS = $rs; Handle = $ps.BeginInvoke();'
Patch '        & $j.Done $result $j.State' '        $bgMs = $j.Clock.ElapsedMilliseconds; $sw = [Diagnostics.Stopwatch]::StartNew()
        & $j.Done $result $j.State
        Mark "bg  $(if ($j.Label) { $j.Label } else { ''(unlabelled)'' })" $bgMs; Mark "ui  done: $(if ($j.Label) { $j.Label } else { ''(unlabelled)'' })" $sw.ElapsedMilliseconds'
$harness = @'
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { 'No' }
Mark 'load: script ready to show the window' $script:Clock.ElapsedMilliseconds
Add-Type -Namespace Prof -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);'
$form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-4000, 40)
[void][Prof.Win]::ShowWindow($form.Handle, 4)
foreach ($step in 'Update-Health', 'Update-Startup', 'Update-History') {
    $sw = [Diagnostics.Stopwatch]::StartNew(); & $step; Mark "ui  $step" $sw.ElapsedMilliseconds
}
Start-Everything; $script:LoadQueue.Clear(); [void]$script:LoadQueue.AddRange(@('Security', 'Stability', 'Upgrades', 'Drivers', 'Network', 'Updates', 'Programs', 'Browsers', 'Backup', 'Services', 'Bloatware', 'Tasks', 'Right-click', 'Privacy', 'Clean'))
# Longest freeze: the biggest gap between two passes through the message loop
$gap = 0; $last = $script:Clock.ElapsedMilliseconds
$deadline = (Get-Date).AddSeconds(__TIMEOUT__)
do {
    [Windows.Forms.Application]::DoEvents()
    $now = $script:Clock.ElapsedMilliseconds; if ($now - $last -gt $gap) { $gap = $now - $last }; $last = $now
    Start-Sleep -Milliseconds 20
} while (($script:Jobs.Count -or $script:LoadQueue.Count) -and (Get-Date) -lt $deadline)
Mark 'everything loaded' $script:Clock.ElapsedMilliseconds
foreach ($p in $script:Pages) { $sw = [Diagnostics.Stopwatch]::StartNew(); Show-Page $p; [Windows.Forms.Application]::DoEvents(); Mark "ui  open page $($p.Name)" $sw.ElapsedMilliseconds }
"{0,8} {1,8}  {2}" -f 'at (ms)', 'took', 'what'
$script:Marks | ForEach-Object { "{0,8} {1,8}  {2}" -f $_.At, $_.Ms, $_.What }
"`nLongest freeze of the window: $gap ms"
$form.Close()
'@
$script:src = $script:src.Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec))
$tmp = Join-Path $env:TEMP "pctuneup-profile-$PID.ps1"
[IO.File]::WriteAllText($tmp, $script:src, (New-Object Text.UTF8Encoding($true)))
try { & $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

