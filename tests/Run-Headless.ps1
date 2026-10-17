# Loads the whole PC Tune-Up app without showing its window, runs the given checks, and prints what the tabs would show.
# Usage: powershell -STA -File .\tests\Run-Headless.ps1   (safe to run anytime - nothing is shown or changed)
param([string]$App = (Join-Path $PSScriptRoot '..\pc-tuneup.ps1'), [int]$TimeoutSec = 200)
$src = [IO.File]::ReadAllText($App)
$harness = @'
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { Write-Output "MSGBOX: $($Text -replace "`n", ' | ')"; 'No' }
Update-Health; Update-Security; Update-Stability; Start-UpdScan
$deadline = (Get-Date).AddSeconds(__TIMEOUT__)
do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while ($script:Jobs.Count -gt 0 -and (Get-Date) -lt $deadline)
"pending jobs: $($script:Jobs.Count)"
function Dump($title, $lv, [int[]]$cols) {
    "`n===== $title ($($lv.Items.Count) rows) ====="
    foreach ($it in $lv.Items) { (($(if ($lv.CheckBoxes) { if ($it.Checked) { '[x]' } else { '[ ]' } })) + ' ' + (($cols | ForEach-Object { $it.SubItems[$_].Text }) -join ' | ')) }
}
"`n===== Health =====`n$($lblHealth.Text)`n--- advice ---`n$($lblAdvice.Text)"
Dump 'Updates' $lvUpd @(0, 1, 2, 3); "status: $($lblUpd.Text)"
Dump 'Security' $lvSec @(1, 0, 2); "status: $($lblSec.Text)"
Dump 'Stability' $lvStab @(0, 1, 2); "status: $($lblStab.Text)"
'@
$src = $src.Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec))
$tmp = Join-Path $env:TEMP "pctuneup-headless-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
try { & $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
