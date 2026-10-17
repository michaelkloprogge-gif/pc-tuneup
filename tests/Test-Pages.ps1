# Opens every page of PC Tune-Up in a hidden window - in English or Dutch - runs every check, clicks through each list,
# saves a report, and fails when something is wrong: an error inside the app, a page that never finishes loading,
# a long freeze, or a report section that is missing. Uses its own empty data folder; changes nothing on the PC.
# Usage: powershell -STA -File .\tests\Test-Pages.ps1 [-Language en|nl] [-TimeoutSec 360] [-MaxFreezeMs 3000]
param([ValidateSet('en', 'nl', 'de', 'fr')][string]$Language = 'en', [int]$TimeoutSec = 360, [int]$MaxFreezeMs = 3000, [string]$App)
# ($PSScriptRoot is empty in parameter defaults of advanced scripts on Windows PowerShell 5.1.)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
$src = [IO.File]::ReadAllText($App)
function Patch([string]$Old, [string]$New) {
    foreach ($nl in "`r`n", "`n") { $o = $Old -replace "`r?`n", $nl; if ($script:src.Contains($o)) { $script:src = $script:src.Replace($o, ($New -replace "`r?`n", $nl)); return } }
    throw "test hook not found: $Old"
}
$data = Join-Path $env:TEMP "pctuneup-pagetest-$PID"
$env:PCTUNEUP_LANGDIR = Join-Path (Split-Path -Parent $App) 'lang'   # the copy runs from TEMP, so point it at the language files
Patch "`$DataDir = Join-Path `$env:LOCALAPPDATA 'PCTuneUp'" "`$DataDir = '$data'"
Patch '$Lang = switch ($Settings.Language)' "`$Lang = '$Language'; `$null = switch (`$Settings.Language)"
$harness = @'
$script:Failures = New-Object System.Collections.ArrayList
function Fail([string]$Why) { [void]$script:Failures.Add($Why); Write-Output "FAIL  $Why" }
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { if ($Text -like 'Something went wrong*') { Fail "message box: $($Text -replace "`n", ' ')" }; 'No' }
$Error.Clear()
$clock = [Diagnostics.Stopwatch]::StartNew(); $gap = 0; $last = 0
function Pump([int]$Ms = 0) {
    $until = $clock.ElapsedMilliseconds + $Ms
    do { [Windows.Forms.Application]::DoEvents(); $now = $clock.ElapsedMilliseconds; if ($now - $script:last -gt $script:gap) { $script:gap = $now - $script:last }; $script:last = $now; Start-Sleep -Milliseconds 20 } while ($clock.ElapsedMilliseconds -lt $until)
}
# 1. Load everything, as the real window does
Start-Everything; $last = $clock.ElapsedMilliseconds
$deadline = (Get-Date).AddSeconds(__TIMEOUT__)
do { Pump } while (($script:Jobs.Count -or $script:LoadQueue.Count) -and (Get-Date) -lt $deadline)
if ($script:Jobs.Count -or $script:LoadQueue.Count) { Fail "still loading after __TIMEOUT__ s: $((@($script:Jobs | ForEach-Object Label) + @($script:LoadQueue)) -join ', ')" }
Write-Output ("      everything loaded in {0:N1} s; longest freeze {1} ms" -f ($clock.ElapsedMilliseconds / 1000), $gap)
if ($gap -gt __FREEZE__) { Fail "the window froze for $gap ms (limit __FREEZE__ ms)" }
# 2. Open every page and select rows in its lists (runs the details panes and buttons' enabled state)
foreach ($p in $script:Pages) {
    Show-Page $p; Pump 50
    if ($p.Controls.Count -lt 2) { Fail "page $($p.Name) is empty" }
    foreach ($lv in @($p.Controls | Where-Object { $_ -is [Windows.Forms.ListView] -and $_.Visible })) {
        foreach ($it in @($lv.Items) | Select-Object -First 25) { $lv.SelectedItems.Clear(); $it.Selected = $true; [Windows.Forms.Application]::DoEvents() }
    }
    $rows = (@($p.Controls | Where-Object { $_ -is [Windows.Forms.ListView] }) | ForEach-Object { $_.Items.Count } | Measure-Object -Sum).Sum
    Write-Output ("      {0,-14} {1,4} row(s)" -f $p.Name, $rows)
}
# Every page in the sidebar list has a button that is really in the sidebar
foreach ($name in @($NavGroups | ForEach-Object { $_.Pages } | Where-Object { $_ })) {
    $b = $script:NavButtons[$name]
    if (-not $b -or -not ($nav.Controls.Contains($b) -or $navBottom.Controls.Contains($b))) { Fail "sidebar has no button for $name" }
}
foreach ($name in $script:PageLoaders.Keys) { if (-not $script:Loaded[$name] -and $name -ne 'Battery') { Fail "page $name never loaded its data" } }
# Layout: the page must start where the sidebar ends (both after start-up and after switching views)
function Test-Layout([string]$When) {
    $form.PerformLayout()
    if ($sidebar.Right -gt $content.Left) { Fail "layout ($When): the page starts at x=$($content.Left), under the sidebar (ends at x=$($sidebar.Right))" }
    if ($content.Right -gt $form.ClientSize.Width) { Fail "layout ($When): the page is wider than the window" }
}
Test-Layout 'start'
# Simple view: the status, the list of problems and the help screen
Set-ViewMode 'simple'; Pump 50
if (-not $sHead.Text -or $sHead.Text -eq (T 'Checking your PC...')) { Fail "simple view status still says: $($sHead.Text)" }
Show-SimpleProblems; Pump 50   # (buttons can't be clicked in a hidden window, so call what they call)
if (-not $sList.Controls.Count) { Fail 'simple view: "Check for problems" shows nothing' }
Show-SimpleHelp; Pump 50
if ($sList.Controls.Count -lt 3) { Fail 'simple view: "Get help" shows too little' }
[void](Get-PlainSummary)
Write-Output "      simple view: $($sHead.Text)"
Set-ViewMode 'full'; Pump 50
Test-Layout 'after switching back from simple view'
# 3. The report has every section
$rep = Join-Path $DataDir 'test-report.html'
try { [void](Save-ReportNow -Path $rep -NoOpen) } catch { Fail "report: $($_.Exception.Message)" }
$html = if (Test-Path $rep) { [IO.File]::ReadAllText($rep) } else { '' }
foreach ($h in 'Health', 'Junk files that can be cleaned', 'Bloatware found', 'Background services', 'Space savers', 'Browsers', 'Network', 'Programs', 'Right-click menu', 'Drivers', 'Privacy',
               'Backup', 'Scheduled tasks', 'Security', 'Stability (last 30 days)', 'Program updates available', 'Upgrade options', 'Changes made by PC Tune-Up', 'Problems inside PC Tune-Up (last 14 days)') {
    if (-not $html.Contains("<h2>$(T $h)</h2>")) { Fail "report has no '$(T $h)' section" }
}
# 4. Errors: the app's own error log, and script errors (not Windows commands answering "not found")
foreach ($l in @(Get-AppErrors 1)) { Fail "error log: $l" }
foreach ($e in @($Error | Where-Object { $_.InvocationInfo -and $_.InvocationInfo.ScriptName -eq $PSCommandPath -and "$($_.FullyQualifiedErrorId)" -notmatch ',' })) {
    Fail "script error at line $($e.InvocationInfo.ScriptLineNumber): $($e.Exception.Message) [$("$($e.InvocationInfo.Line)".Trim())]"
}
$JobTimer.Stop()
$global:PageTestFailures = $script:Failures.Count
'@
$src = $src.Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec).Replace('__FREEZE__', $MaxFreezeMs))
$tmp = Join-Path $env:TEMP "pctuneup-pagetest-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
Write-Output "PC Tune-Up page test ($Language)"
$global:PageTestFailures = -1
try { & $tmp } finally { Remove-Item $tmp, $data -Recurse -Force -ErrorAction SilentlyContinue }
if ($global:PageTestFailures -lt 0) { Write-Output 'FAIL  the test did not finish'; exit 1 }
Write-Output "$($global:PageTestFailures) failure(s)"
exit $global:PageTestFailures
