# Clicks every button in PC Tune-Up (hidden window, own empty data folder) and fails when a button does nothing:
# no click action at all, an error, or no visible effect (no message, no dialog, no program or job started, no page
# or list change). Before the clicks, everything that could change the PC is swapped for a recorder: registry and
# service commands, scheduled tasks, files outside the test's data folder, starting programs, background jobs and
# file dialogs. Questions are answered "No". So a button can be clicked safely - it just has to show it does something.
# Usage: powershell -STA -File .\tests\Test-Buttons.ps1 [-Language en|nl|de|fr] [-TimeoutSec 360]
param([ValidateSet('en', 'nl', 'de', 'fr')][string]$Language = 'en', [int]$TimeoutSec = 360, [string]$App)
# ($PSScriptRoot is empty in parameter defaults of advanced scripts on Windows PowerShell 5.1.)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
$src = [IO.File]::ReadAllText($App)
function Patch([string]$Old, [string]$New) {
    foreach ($nl in "`r`n", "`n") { $o = $Old -replace "`r?`n", $nl; if ($script:src.Contains($o)) { $script:src = $script:src.Replace($o, ($New -replace "`r?`n", $nl)); return } }
    throw "test hook not found: $Old"
}
$data = Join-Path $env:TEMP "pctuneup-buttontest-$PID"
$env:PCTUNEUP_LANGDIR = Join-Path (Split-Path -Parent $App) 'lang'   # the copy runs from TEMP, so point it at the language files
Patch "`$DataDir = Join-Path `$env:LOCALAPPDATA 'PCTuneUp'" "`$DataDir = '$data'"
Patch '$Lang = switch ($Settings.Language)' "`$Lang = '$Language'; `$null = switch (`$Settings.Language)"
# File and folder pickers and the app's own little windows: recorded instead of shown (they would wait for a click).
$src = [regex]::Replace($src, '\$(\w+)\.ShowDialog\((\$form)?\)', { param($m) if ($m.Groups[1].Value -eq 'form' -and -not $m.Groups[2].Value) { $m.Value } else { "(Rec 'dialog' '$($m.Groups[1].Value)')" } })
$harness = @'
$script:Failures = New-Object System.Collections.ArrayList
function Fail([string]$Why) { [void]$script:Failures.Add($Why); Write-Output "FAIL  $Why" }
$script:Rec = New-Object System.Collections.ArrayList
function Rec([string]$What, [string]$Detail) { [void]$script:Rec.Add("$What $Detail".Trim()); 'Cancel' }
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    if ($Text -like 'Something went wrong*') { Fail "message box: $($Text -replace "`n", ' ')" }
    [void]$script:Rec.Add("message: $(($Text -split "`n")[0])"); if ($Buttons -eq 'OK') { 'OK' } else { 'No' }
}
$Error.Clear()
function Pump([int]$Ms = 0) { $until = (Get-Date).AddMilliseconds($Ms); do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } while ((Get-Date) -lt $until) }
# 1. Load everything as the real window does (all of this only reads).
Start-Everything
$deadline = (Get-Date).AddSeconds(__TIMEOUT__)
do { Pump } while (($script:Jobs.Count -or $script:LoadQueue.Count) -and (Get-Date) -lt $deadline)
if ($script:Jobs.Count -or $script:LoadQueue.Count) { Fail "still loading after __TIMEOUT__ s" }
foreach ($p in $script:Pages) { Show-Page $p; Pump 30 }   # every page laid out once

# 2. From here on, nothing may change the PC: swap the commands that could for recorders.
function Test-Sandboxed($Path) { $s = "$Path"; $s -and ($s.StartsWith($DataDir, 'OrdinalIgnoreCase') -or $s.StartsWith($env:TEMP, 'OrdinalIgnoreCase')) -and $s -notmatch '^(HK|Registry::)' }
foreach ($c in 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Rename-ItemProperty', 'Set-Service', 'Stop-Service', 'Start-Service', 'Restart-Service',
               'Stop-Process', 'Restart-Computer', 'Stop-Computer', 'Checkpoint-Computer', 'Enable-ScheduledTask', 'Disable-ScheduledTask', 'Register-ScheduledTask',
               'Unregister-ScheduledTask', 'Set-ScheduledTask', 'Start-ScheduledTask', 'Start-Process', 'Invoke-Item', 'Clear-RecycleBin', 'Clear-DnsClientCache',
               'Set-DnsClientServerAddress', 'Optimize-Volume', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-Bg', 'Start-WithRestorePoint', 'Set-StartupEntry', 'Set-PowerOverlay',
               'winget', 'schtasks', 'powercfg', 'cleanmgr', 'sfc', 'dism', 'DISM.exe', 'chkdsk', 'netsh', 'ipconfig', 'bcdedit', 'reg', 'reg.exe', 'sc', 'sc.exe', 'compact',
               'vssadmin', 'wevtutil', 'rundll32', 'explorer', 'explorer.exe', 'notepad', 'notepad.exe', 'control', 'msiexec', 'cmd', 'cmd.exe', 'wsreset', 'taskkill', 'shutdown',
               'defrag', 'manage-bde', 'powershell', 'powershell.exe', 'pnputil', 'msdt') {
    Set-Item "function:script:$c" ([scriptblock]::Create("[void](Rec '$c' (`"`$args`" -replace '\s+', ' '))"))
}
foreach ($c in 'Remove-Item', 'Rename-Item', 'Move-Item', 'Copy-Item', 'New-Item', 'Set-Content', 'Add-Content', 'Out-File') {
    $real = (Get-Command $c -CommandType Cmdlet).ModuleName + '\' + $c
    Set-Item "function:script:$c" ([scriptblock]::Create(@"
`$p = @(`$args | Where-Object { `$_ -is [string] -and (`$_ -match '^[A-Za-z]:\\|^HK|^Registry::') })[0]
if (-not `$p) { foreach (`$k in 'Path', 'LiteralPath', 'FilePath', 'Destination') { if (`$PSBoundParameters.ContainsKey(`$k)) { `$p = `$PSBoundParameters[`$k] } } }
if (Test-Sandboxed `$p) { if (`$MyInvocation.ExpectingInput) { `$input | & '$real' @args } else { & '$real' @args } } else { [void](Rec '$c' "`$p") }
"@))
}

# Page switches, view switches and reloads count as an effect too (in a hidden window no page ever reports itself
# as visible, so they can't be seen in the window itself). Wrap those functions so they are recorded, then run.
foreach ($fn in @(Get-ChildItem function: | Where-Object { $_.Name -in 'Show-Page', 'Set-ViewMode' -or $_.Name -like 'Update-*' -or $_.Name -like 'Start-*Scan' })) {
    $orig = $fn.ScriptBlock
    Set-Variable -Scope Script -Name "orig_$($fn.Name -replace '\W', '_')" -Value $orig
    Set-Item "function:script:$($fn.Name)" ([scriptblock]::Create("[void](Rec '$($fn.Name)' `"`$(`$args | ForEach-Object { if (`$_.Name) { `$_.Name } else { `$_ } })`"); & `$script:orig_$($fn.Name -replace '\W', '_') @args"))
}
# 3. Click every button.
$evProp = [ComponentModel.Component].GetProperty('Events', [Reflection.BindingFlags]'NonPublic, Instance')
$clickKey = [Windows.Forms.Control].GetField('EventClick', [Reflection.BindingFlags]'NonPublic, Static').GetValue($null)
$onClick = [Windows.Forms.Control].GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic, Instance')
function Get-Buttons($Parent) { foreach ($c in $Parent.Controls) { if ($c -is [Windows.Forms.Button]) { $c }; Get-Buttons $c } }
function Get-Snapshot {
    $sb = New-Object Text.StringBuilder
    function Walk($p) { foreach ($c in $p.Controls) {
        [void]$sb.Append("$($c.Text)|$($c.Visible)|$($c.Enabled);")
        if ($c -is [Windows.Forms.ListView]) { [void]$sb.Append("L$($c.Items.Count)/$($c.CheckedItems.Count)/$($c.SelectedItems.Count);") }
        if ($c -is [Windows.Forms.CheckBox]) { [void]$sb.Append("C$($c.Checked);") }
        if ($c -is [Windows.Forms.ComboBox]) { [void]$sb.Append("S$($c.SelectedIndex);") }
        Walk $c } }
    Walk $form; [void]$sb.Append("P$(@($script:Pages | Where-Object Visible | ForEach-Object Name) -join ',')V$($Settings.View)")
    $sb.ToString()
}
function Get-Where($b) { $p = $b.Parent; while ($p -and -not ($script:Pages -contains $p) -and $p -ne $simple -and $p -ne $sidebar) { $p = $p.Parent }; $p }
$skip = @('Restart as admin', (T 'Restart as admin'))   # closes the window to start again as administrator (in every language)
$skipButtons = @($actCancel)   # the activity bar's Cancel: only shown while a job runs (and jobs don't run here)
$buttons = @(Get-Buttons $form)
$n = 0; $dead = 0
foreach ($b in $buttons) {
    $where = Get-Where $b
    $label = "$(if ($where -eq $simple) { 'Simple view' } elseif ($where -eq $sidebar) { 'Sidebar' } elseif ($where) { $where.Name } else { '?' }): '$($b.Text -replace "`r?`n", ' / ')'"
    if (-not $b.Text -and $b.AccessibleName) { $label += " ($($b.AccessibleName))" }
    if ($b.Text -in $skip -or $skipButtons -contains $b) { Write-Output "      skip  $label"; continue }
    $n++
    if (-not $evProp.GetValue($b)[$clickKey]) { Fail "$label has no click action"; $dead++; continue }
    # Put the button where a person would see it: its own page, in the view it belongs to.
    if ($where -eq $simple) { if ($Settings.View -ne 'simple') { Set-ViewMode 'simple' }; if ($b -eq $sCheck) { Show-SimpleHelp } }   # (so "Check for problems" has something to switch from)
    else {
        if ($Settings.View -ne 'full') { Set-ViewMode 'full' }
        if ($script:Pages -contains $where) { Show-Page $where }
        elseif ($where -eq $sidebar -and $b.Tag -in $script:Pages) { Show-Page $(if ($b.Tag -eq $pgHealth) { $pgSet } else { $pgHealth }) }   # so going to its page is a change
    }
    Pump 20
    $before = Get-Snapshot; $script:Rec.Clear(); $errs = $Error.Count
    try { $onClick.Invoke($b, @([EventArgs]::Empty)) } catch { Fail "$label threw: $($_.Exception.InnerException.Message)" }
    Pump 60
    $after = Get-Snapshot
    $effect = if ($script:Rec.Count) { ($script:Rec | Select-Object -First 2) -join '; ' } elseif ($after -ne $before) { 'the window changed' } else { $null }
    $newErr = @($Error | Select-Object -First ($Error.Count - $errs) | Where-Object { $_.InvocationInfo -and $_.InvocationInfo.ScriptName -eq $PSCommandPath -and "$($_.FullyQualifiedErrorId)" -notmatch ',' })
    foreach ($e in $newErr) { Fail "$label - error at line $($e.InvocationInfo.ScriptLineNumber): $($e.Exception.Message)" }
    if (-not $effect -and -not $b.Enabled) { Write-Output "      off   $label (disabled at the moment - it can't be clicked now)"; continue }
    if (-not $effect) { Fail "$label does nothing when clicked$(if (-not $b.Enabled) { ' (it is disabled at the moment)' })$(if ($b.Tag) { " [tag: $($b.Tag.GetType().Name) $($b.Tag.Name)]" }) [page now: $(@($script:Pages | Where-Object Visible | ForEach-Object Name) -join ",")]"; $dead++ }
    else { Write-Output ("      ok    {0} -> {1}{2}" -f $label, $effect.Substring(0, [Math]::Min(90, $effect.Length)), $(if (-not $b.Enabled) { '  (disabled now)' })) }
}
Write-Output "      $n button(s) clicked, $dead without an effect"
foreach ($l in @(Get-AppErrors 1)) { Fail "error log: $l" }
$JobTimer.Stop()
$global:ButtonTestFailures = $script:Failures.Count
'@
$src = $src.Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec))
$tmp = Join-Path $env:TEMP "pctuneup-buttontest-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
Write-Output "PC Tune-Up button test ($Language)"
$global:ButtonTestFailures = -1
try { & $tmp } finally { Remove-Item $tmp, $data -Recurse -Force -ErrorAction SilentlyContinue }
if ($global:ButtonTestFailures -lt 0) { Write-Output 'FAIL  the test did not finish'; exit 1 }
Write-Output "$($global:ButtonTestFailures) failure(s)"
exit $global:ButtonTestFailures
