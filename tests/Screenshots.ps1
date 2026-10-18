# Opens PC Tune-Up off-screen without taking focus, runs every check, and saves a PNG of each page.
# Usage: powershell -STA -File .\tests\Screenshots.ps1 -Out <folder>
param([Parameter(Mandatory)][string]$Out, [string]$App, [int]$TimeoutSec = 240, [switch]$SimpleView)
# ($PSScriptRoot is empty in parameter defaults of advanced scripts on Windows PowerShell 5.1.)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
New-Item -ItemType Directory -Force $Out | Out-Null
$harness = @'
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { Write-Output "MSGBOX: $($Text -replace "`n", ' | ')"; 'No' }
Add-Type -Namespace Shot -Name Win -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr h, System.IntPtr dc, uint flags);
"@
$form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-4000, 40)
[void][Shot.Win]::ShowWindow($form.Handle, 4)    # SW_SHOWNOACTIVATE: visible, but never steals focus
# Same start-up as the real window: load every page in the background, then wait until all is quiet.
Start-Everything; foreach ($n in @($script:LoadQueue)) { Invoke-PageLoader $n }
$deadline = (Get-Date).AddSeconds(__TIMEOUT__)
do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while (($script:Jobs.Count -gt 0 -or $script:LoadQueue.Count -gt 0) -and (Get-Date) -lt $deadline)
$pages = if (Get-Command Show-Page -ErrorAction SilentlyContinue) { $script:Pages } else { @($tabs.TabPages) }
$i = 0
foreach ($p in $pages) {
    $i++
    if (Get-Command Show-Page -ErrorAction SilentlyContinue) { Show-Page $p } else { $tabs.SelectedTab = $p }
    1..10 | ForEach-Object { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
    # Windows doesn't repaint a window that is fully off-screen, so a screen capture would be stale.
    # DrawToBitmap asks every control to paint itself into the image instead.
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $name = if ($p.Text) { $p.Text } else { $p.Name }
    $bmp.Save((Join-Path '__OUT__' ('{0:00}-{1}.png' -f $i, $name))); $bmp.Dispose()
}
if (__SIMPLE__) {
    # The simple view too - shown by hand instead of with Set-ViewMode, which would save the setting for the real app.
    $was = $Settings.View; $Settings.View = 'simple'
    $content.Visible = $false; $sidebar.Visible = $false; $simple.Visible = $true; $simple.BringToFront(); Update-SimpleView; Show-SimpleProblems
    1..10 | ForEach-Object { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    # DrawToBitmap doesn't clip to parents, so Windows' own scroll bar (kept just outside the visible list) shows up: paint it over.
    $o = $form.PointToScreen([Drawing.Point]::Empty); $c = $sClip.PointToScreen([Drawing.Point]::Empty)
    $gx = [Drawing.Graphics]::FromImage($bmp); $br = New-Object Drawing.SolidBrush($sCol.BackColor)
    $gx.FillRectangle($br, ($c.X - $form.Left + $sClip.Width), ($c.Y - $form.Top), [Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 2, $sClip.Height); $br.Dispose(); $gx.Dispose()
    $i++; $bmp.Save((Join-Path '__OUT__' ('{0:00}-Simple view.png' -f $i))); $bmp.Dispose()
    $Settings.View = $was
}
"saved $i page(s); pending jobs: $($script:Jobs.Count)"
$form.Close()
'@
$src = [IO.File]::ReadAllText($App).Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec).Replace('__OUT__', $Out).Replace('__SIMPLE__', $(if ($SimpleView) { '$true' } else { '$false' })))
$tmp = Join-Path $env:TEMP "pctuneup-shots-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
try { & $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
