#Requires -Version 5.1
# PC Tune-Up: speed up and clean any Windows 10/11 PC, whatever the brand.
#   Health    - CPU / RAM / disk / uptime, biggest programs, internet speed test
#   Clean     - temp files, Windows Update cache, crash dumps, Recycle Bin
#   Startup   - turn startup apps on/off (same flags Task Manager uses)
#   Bloatware - find pre-installed junk (OEM tools, trial antivirus, promo apps) and uninstall it
#   Services  - background services from PC makers, updaters and telemetry, with one-click restore
#   Disk      - find the folders eating your drive
#   Upgrades  - memory / drive / battery upgrade options with the exact spec to buy
#   History   - every change, with undo
# Every change is logged to %LOCALAPPDATA%\PCTuneUp\changes.log. Anything listed
# in %LOCALAPPDATA%\PCTuneUp\keep.txt is never flagged or changed.
# Run PC-TuneUp.exe (this script embedded; rebuild with build-exe.ps1 after
# editing) or PC-TuneUp.cmd. The exe is a single file you can copy to any PC.
# Release a new version: bump $AppVersion, then .\publish-release.ps1 -Notes "...".

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$AppVersion = '1.2.0'                 # bump for every release; publish-release.ps1 tags it as v<version>
$UpdateRepo = 'michaelkloprogge-gif/pc-tuneup'       # GitHub repo whose latest release the app updates from

# Inside PC-TuneUp.exe the script is hosted in-process, so restart/icon use the exe.
$SelfExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$RunningAsExe = $SelfExe -notmatch '\\(powershell|pwsh)\.exe$'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$DataDir = Join-Path $env:LOCALAPPDATA 'PCTuneUp'
New-Item -ItemType Directory -Force $DataDir | Out-Null
$LogFile = Join-Path $DataDir 'changes.log'
$ServiceStateFile = Join-Path $DataDir 'services-original.json'
$KeepFile = Join-Path $DataDir 'keep.txt'
$HistoryFile = Join-Path $DataDir 'history.jsonl'   # one JSON entry per change; drives the History tab

function Write-Log([string]$Msg) {
    Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Msg) -Encoding UTF8
}
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N0} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} KB' -f ($Bytes / 1KB) }
}
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    [Windows.Forms.MessageBox]::Show($Text, 'PC Tune-Up', $Buttons, $Icon)
}

# History: every change, with what's needed to undo it (Undo = $null when it can't be).
function Add-History([string]$Kind, [string]$Item, [string]$Change, $Undo = $null) {
    $e = [ordered]@{ Id = [guid]::NewGuid().ToString('N'); Time = (Get-Date).ToString('s'); Kind = $Kind
                     Item = $Item; Change = $Change; Undo = $Undo; Undone = $false }
    Add-Content -Path $HistoryFile -Value ($e | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
    Write-Log "${Kind}: $Item - $Change"
}
function Get-History {
    if (-not (Test-Path $HistoryFile)) { return }
    Get-Content $HistoryFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
}
function Save-History($Entries) {
    Set-Content -Path $HistoryFile -Value @($Entries | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }) -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Keep rules. Things that make a PC work (security, VPN, drivers, databases)
# are never suggested for removal, on any brand.
# ---------------------------------------------------------------------------
if (-not (Test-Path $KeepFile)) {
    Set-Content -Path $KeepFile -Encoding UTF8 -Value @(
        '# PC Tune-Up never flags or changes anything whose name contains one of these lines.'
        '# Put one name per line, e.g. a work program. Lines starting with # are ignored.'
    )
}
function Get-UserKeep {
    (Get-Content $KeepFile -ErrorAction SilentlyContinue |
        Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } |
        ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|'
}
$KeepBuiltIn = @(
    'Defender', 'SecurityHealth', 'Windows Security', 'Malwarebytes', 'Bitdefender', 'Kaspersky', 'ESET', 'Sophos',
    'CrowdStrike', 'SentinelOne', 'Trend Micro', 'F-Secure',
    'VPN', 'WireGuard', 'WatchGuard', 'FortiClient', 'GlobalProtect', 'Cisco', 'Zscaler', 'Tailscale',
    'Realtek', 'RtkAud', 'Waves', 'Conexant', 'Dolby', 'Audio', 'Sound', 'SmartAmp', 'Goodix', 'Synaptics', 'ELAN', 'Precision Touch', 'Touchpad',
    'NVIDIA', 'AMD', 'Radeon', 'Intel', 'Thunderbolt', 'Bluetooth', 'Wi-?Fi', 'Wireless', 'Killer Network',
    'Fingerprint', 'Biometric', 'Camera', 'Hotkey', 'Fn ?Key', 'Function Key', 'Power Manage', 'Thermal', 'Battery',
    'Peripheral', 'Logitech', 'Logi ', 'Razer Synapse', 'Corsair', 'Printer', 'Spooler',
    'PostgreSQL', 'MySQL', 'SQL Server', 'MongoDB', 'Docker', 'VMware', 'VirtualBox', 'Hyper-V',
    'OneDrive', 'Backup', 'Acronis', 'Veeam'
) -join '|'

# ---------------------------------------------------------------------------
# Background work: long jobs (scans, speed test) run in a separate runspace so
# the window stays responsive. A timer polls them and calls the Done block.
# ---------------------------------------------------------------------------

# Shared by background scripts. Walks a folder without following junctions or
# symlinks, so cleaning can never escape into another folder.
$Helpers = @'
function Get-FilesSafe([string]$Root, [string]$Filter = '*') {
    if (-not [IO.Directory]::Exists($Root)) { return }
    $stack = New-Object System.Collections.Stack
    $stack.Push([IO.DirectoryInfo]$Root)
    while ($stack.Count) {
        $dir = $stack.Pop()
        try {
            foreach ($e in $dir.EnumerateFileSystemInfos()) {
                if ($e -is [IO.DirectoryInfo]) {
                    if (-not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($e) }
                } elseif ($e.Name -like $Filter) { $e }
            }
        } catch { }
    }
}
# Every subfolder under Root (not Root itself), again never crossing a junction.
function Get-DirsSafe([string]$Root) {
    if (-not [IO.Directory]::Exists($Root)) { return }
    $stack = New-Object System.Collections.Stack
    $stack.Push([IO.DirectoryInfo]$Root)
    while ($stack.Count) {
        $dir = $stack.Pop()
        try {
            foreach ($d in $dir.EnumerateDirectories()) {
                if (-not ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $d; $stack.Push($d) }
            }
        } catch { }
    }
}
'@

$script:Jobs = New-Object System.Collections.ArrayList
function Start-Bg([scriptblock]$Work, $Arg, [scriptblock]$Done) {
    # param() must come first in a script, so the work block runs as a nested block after the helpers.
    $code = "param(`$BgArg)`n$Helpers`n& {`n$Work`n} `$BgArg"
    $ps = [powershell]::Create().AddScript($code).AddArgument($Arg)
    [void]$script:Jobs.Add(@{ PS = $ps; Handle = $ps.BeginInvoke(); Done = $Done })
}
$JobTimer = New-Object Windows.Forms.Timer
$JobTimer.Interval = 250
$JobTimer.Add_Tick({
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        [void]$script:Jobs.Remove($j)
        try { $result = @($j.PS.EndInvoke($j.Handle)) }
        catch { $result = @(); Show-Msg "Something went wrong:`n$($_.Exception.Message)" 'OK' 'Warning' | Out-Null }
        $j.PS.Dispose()
        & $j.Done $result
    }
})
$JobTimer.Start()

# ---------------------------------------------------------------------------
# Window + layout helpers
# ---------------------------------------------------------------------------
$Font = New-Object Drawing.Font('Segoe UI', 9.5)
$form = New-Object Windows.Forms.Form
$form.Text = "PC Tune-Up $AppVersion" + $(if ($IsAdmin) { '  (Administrator)' } else { '' })
$form.ClientSize = New-Object Drawing.Size(980, 660)
$form.MinimumSize = New-Object Drawing.Size(780, 500)
$form.StartPosition = 'CenterScreen'
$form.Font = $Font
if ($RunningAsExe) { try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($SelfExe) } catch { } }

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

if (-not $IsAdmin) {
    $banner = New-Object Windows.Forms.Panel
    $banner.Dock = 'Top'; $banner.Height = 40; $banner.BackColor = [Drawing.Color]::FromArgb(255, 244, 206)
    $bl = New-Object Windows.Forms.Label
    $bl.Text = 'Some fixes (Windows temp, update cache, services, all-user startup apps, restore points) need administrator rights.'
    $bl.Dock = 'Fill'; $bl.TextAlign = 'MiddleLeft'; $bl.Padding = New-Object Windows.Forms.Padding(6, 0, 0, 0)
    $bb = New-Object Windows.Forms.Button
    $bb.Text = 'Restart as administrator'; $bb.Dock = 'Right'; $bb.Width = 190
    $bb.Add_Click({
        try {
            if ($RunningAsExe) { Start-Process $SelfExe -Verb RunAs }
            else { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
            $form.Close()
        } catch { }   # user said no to the UAC prompt
    })
    $banner.Controls.AddRange(@($bl, $bb))
    $form.Controls.Add($banner)
}

function New-Page([string]$Title, [string]$IntroText) {
    $page = New-Object Windows.Forms.TabPage $Title
    $page.Padding = New-Object Windows.Forms.Padding(8)
    [void]$tabs.TabPages.Add($page)
    $intro = New-Object Windows.Forms.Label
    $intro.Text = $IntroText; $intro.Dock = 'Top'; $intro.Height = 38; $intro.ForeColor = [Drawing.Color]::DimGray
    $page.Tag = $intro
    $page
}
# Docking is laid out last-added-first, so: Fill control, then bottom, then
# top controls from the lowest one upward.
function Set-PageLayout($Page, $Fill, [object[]]$Tops, $Bottom) {
    $Page.Controls.Add($Fill)
    if ($Bottom) { $Page.Controls.Add($Bottom) }
    [array]::Reverse($Tops)
    foreach ($t in $Tops) { $Page.Controls.Add($t) }
    $Page.Controls.Add($Page.Tag)
}
function New-ButtonBar([object[]]$Buttons) {
    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Top'; $bar.Height = 42; $bar.WrapContents = $false
    foreach ($b in $Buttons) { $bar.Controls.Add($b) }
    $bar
}
function New-Button([string]$Text) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text; $b.AutoSize = $true; $b.Height = 32; $b.Padding = New-Object Windows.Forms.Padding(6, 0, 6, 0)
    $b
}
function New-ListView([bool]$Checks, [object[]]$Columns) {
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $Checks; $lv.GridLines = $true; $lv.Dock = 'Fill'
    for ($i = 0; $i -lt $Columns.Count; $i += 2) { [void]$lv.Columns.Add($Columns[$i], $Columns[$i + 1]) }
    $lv
}
function New-Status {
    $l = New-Object Windows.Forms.Label
    $l.Dock = 'Bottom'; $l.Height = 30; $l.TextAlign = 'MiddleLeft'
    $l
}
function Add-Row($Lv, [object[]]$Cells, $Tag = $null, [bool]$Checked = $false) {
    $it = New-Object Windows.Forms.ListViewItem([string]$Cells[0])
    foreach ($c in $Cells[1..($Cells.Count - 1)]) { [void]$it.SubItems.Add([string]$c) }
    $it.Tag = $Tag; $it.Checked = $Checked
    [void]$Lv.Items.Add($it)
    $it
}

# ===========================================================================
# 1. Health
# ===========================================================================
$pgHealth = New-Page 'Health' 'A quick check of how the PC is doing right now. "Fix my PC" runs all the safe fixes in one go and shows you the list first.'
$btnFix = New-Button 'Fix my PC'
$btnFix.FlatStyle = 'Flat'; $btnFix.BackColor = [Drawing.Color]::FromArgb(0, 103, 192); $btnFix.ForeColor = [Drawing.Color]::White
$btnFix.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
$btnRefresh = New-Button 'Refresh'
$btnSpeed = New-Button 'Speed test'
$btnWU = New-Button 'Windows Update'
$btnReport = New-Button 'Save report'
$btnLog = New-Button 'Change log'
$btnKeep = New-Button 'Keep list'
$MonoFont = New-Object Drawing.Font('Consolas', 10.5)
$lblHealth = New-Object Windows.Forms.Label
$lblHealth.Dock = 'Top'; $lblHealth.Height = 200; $lblHealth.Font = $MonoFont
$lblAdvice = New-Object Windows.Forms.Label
$lblAdvice.Dock = 'Top'; $lblAdvice.Height = 0; $lblAdvice.ForeColor = [Drawing.Color]::DarkRed
$lblAdvice.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
$lblSpeed = New-Object Windows.Forms.Label
$lblSpeed.Dock = 'Top'; $lblSpeed.Height = 30; $lblSpeed.Font = $MonoFont
$lblSpeed.Text = 'Internet:  (not tested yet)'
$lvProc = New-ListView $false @('Program', 300, 'Memory (MB)', 120, 'Processes', 100)
Set-PageLayout $pgHealth $lvProc @((New-ButtonBar @($btnFix, $btnRefresh, $btnSpeed, $btnWU, $btnReport, $btnLog, $btnKeep)), $lblHealth, $lblAdvice, $lblSpeed)

$cs = Get-CimInstance Win32_ComputerSystem
$PcName = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
$script:HealthDeep = $null   # drive / battery / update results from the background check

# Slower checks (a few seconds), run in the background: drive health, battery wear, Windows Update.
$HealthDeepWork = {
    $lines = @(); $advice = @()
    foreach ($d in Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $extra = ''
        try {   # wear and temperature need administrator rights
            $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            if ($null -ne $rc.Wear) { $extra += ", $($rc.Wear)% worn" }
            if ($rc.Temperature) { $extra += ", $($rc.Temperature) C" }
        } catch { }
        $lines += 'Drive:     {0} ({1} {2}) - {3}{4}' -f "$($d.FriendlyName)".Trim(), $d.BusType, $d.MediaType, $d.HealthStatus, $extra
        if ("$($d.HealthStatus)" -ne 'Healthy') { $advice += "Drive '$($d.FriendlyName)' reports '$($d.HealthStatus)' - back up your files now and have the drive checked." }
    }
    $xml = Join-Path $env:TEMP "pctuneup-battery-$PID.xml"
    powercfg /batteryreport /xml /output $xml 2>$null | Out-Null
    if (Test-Path $xml) {
        try {
            [xml]$x = Get-Content $xml
            foreach ($b in @($x.BatteryReport.Batteries.Battery)) {
                if (-not $b -or [double]$b.DesignCapacity -le 0) { continue }
                $pct = [int](100 * [double]$b.FullChargeCapacity / [double]$b.DesignCapacity)
                $lines += 'Battery:   holds {0}% of its original charge' -f [Math]::Min($pct, 100)
                if ($pct -lt 60) { $advice += "The battery only holds $pct% of its original charge - short battery life is the battery wearing out, not the PC. A new battery fixes it." }
            }
        } catch { }
        Remove-Item $xml -ErrorAction SilentlyContinue
    }
    $upd = 'Updates:   could not read update history'
    try {
        $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $last = $s.QueryHistory(0, [Math]::Min($s.GetTotalHistoryCount(), 200)) |
            Where-Object { $_.ResultCode -eq 2 -and $_.Title -notmatch 'Security Intelligence|Defender' } |   # 2 = succeeded; skip daily antivirus definitions
            Sort-Object Date -Descending | Select-Object -First 1
        if ($last) {
            $days = [int]((Get-Date) - $last.Date.ToLocalTime()).TotalDays
            $upd = "Updates:   last Windows update $days day(s) ago"
            if ($days -gt 45) { $advice += "Windows hasn't installed an update in $days days - click Windows Update and check for updates." }
        }
    } catch { }
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')) {
        $upd += ' - restart needed to finish'
        $advice += 'Windows is waiting for a restart to finish installing updates - restart when you can.'
    }
    $lines += $upd
    [pscustomobject]@{ Lines = $lines; Advice = $advice }
}

function Update-Health([switch]$Quick) {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
    $up = (Get-Date) - $os.LastBootUpTime
    $procs = @(Get-Process | Group-Object Name | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; MB = [int](($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB); Count = $_.Count }
    } | Sort-Object MB -Descending)
    $usedPct = [int](100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
    $advice = @()
    $lines = @(
        "This PC:   $PcName ($($os.Caption -replace '^Microsoft ', ''))"
        "CPU load:  $cpu%"
        ('Memory:    {0:N1} GB free of {1:N1} GB ({2}% used)' -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB), $usedPct)
        ('Uptime:    {0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes)
    )
    if ($usedPct -ge 85) {
        $top = $procs | Where-Object { $_.Name -notin 'svchost', 'Memory Compression', 'System', 'dwm' } | Select-Object -First 1
        $advice += "Memory is $usedPct% full, which slows everything down - closing $($top.Name) ($($top.MB) MB) would help most."
    }
    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        if (-not $d.Size) { continue }
        $pct = [int](100 * $d.FreeSpace / $d.Size)
        $lines += ('Disk {0}:    {1} free of {2} ({3}% free)' -f $d.DeviceID.TrimEnd(':'), (Format-Size $d.FreeSpace), (Format-Size $d.Size), $pct)
        if ($pct -lt 15) { $advice += "Drive $($d.DeviceID) is getting full ($pct% free) - use Fix my PC, then the Clean and Disk tabs." }
    }
    # Power plan, plus the Windows 11 power-mode slider (an "overlay" on the plan).
    $plan = if ("$(powercfg /getactivescheme)" -match '\(([^)]+)\)') { $Matches[1] } else { 'unknown' }
    $ps = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction SilentlyContinue
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $onBattery = $bat -and $bat.BatteryStatus -eq 1
    $overlay = if ($onBattery) { $ps.ActiveOverlayDcPowerScheme } else { $ps.ActiveOverlayAcPowerScheme }
    $mode = switch ($overlay) {
        '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'best power efficiency' }
        '3af9b8d9-7c97-431d-ad78-34a8bfea439f' { 'better performance' }
        'ded574b5-45a0-4f42-8737-46345c09c238' { 'best performance' }
        default { '' }
    }
    $powerLine = "Power:     $plan plan" + $(if ($mode) { ", $mode mode" }) + $(if ($bat) { if ($onBattery) { ', on battery' } else { ', plugged in' } })
    $lines += $powerLine
    if (-not $onBattery -and ($plan -match 'saver' -or $mode -eq 'best power efficiency')) {
        $advice += 'The PC is plugged in but set to save energy - set Power mode to Balanced in Settings > System > Power for more speed.'
    }
    if ($up.TotalDays -gt 7) { $advice += "The PC hasn't restarted in $($up.Days) days - a restart clears out a lot of slowness." }

    if ($script:HealthDeep) { $lines += $script:HealthDeep.Lines; $advice += $script:HealthDeep.Advice }
    else { $lines += 'Checking drive, battery and updates...' }
    $lblHealth.Text = $lines -join "`r`n"
    $lblHealth.Height = $MonoFont.Height * $lines.Count + 8
    $lblAdvice.Text = ($advice | ForEach-Object { "!  $_" }) -join "`r`n"
    $lblAdvice.Height = if ($advice) { 21 * $advice.Count + 8 } else { 0 }
    $script:HealthAdvice = $advice

    $lvProc.BeginUpdate(); $lvProc.Items.Clear()
    $procs | Select-Object -First 20 | ForEach-Object { [void](Add-Row $lvProc @($_.Name, $_.MB, $_.Count)) }
    $lvProc.EndUpdate()

    if (-not $Quick) {   # refresh the slow checks too, then redraw with them
        Start-Bg $HealthDeepWork $null { param($r) if ($r) { $script:HealthDeep = $r[0] }; Update-Health -Quick }
    }
}

$SpeedWork = {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $mbps = $null; $err = $null; $ping = $null
    $f = [IO.Path]::GetTempFileName()
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        (New-Object Net.WebClient).DownloadFile('https://speed.cloudflare.com/__down?bytes=50000000', $f)
        $sw.Stop()
        $mbps = 400 / $sw.Elapsed.TotalSeconds
    } catch { $err = $_.Exception.Message }
    Remove-Item $f -ErrorAction SilentlyContinue
    $p = Test-Connection 1.1.1.1 -Count 4 -ErrorAction SilentlyContinue
    if ($p) { $ping = [int]($p | Measure-Object ResponseTime -Average).Average }
    [pscustomobject]@{ Mbps = $mbps; Ping = $ping; Error = $err }
}
$btnRefresh.Add_Click({ Update-Health })
$btnSpeed.Add_Click({
    $btnSpeed.Enabled = $false
    $lblSpeed.Text = 'Internet:  testing... (about 10 seconds)'
    Start-Bg $SpeedWork $null {
        param($r)
        $r = $r[0]
        $txt = if ($r.Error) { "Internet:  download failed - $($r.Error)" } else { 'Internet:  {0:N0} Mbps download' -f $r.Mbps }
        if ($r.Ping) { $txt += ", $($r.Ping) ms ping" }
        if (Get-Process | Where-Object Name -match 'vpn|wireguard') { $txt += '   (a VPN is running - it can lower this)' }
        $lblSpeed.Text = $txt
        $btnSpeed.Enabled = $true
    }
})
$btnWU.Add_Click({ Start-Process 'ms-settings:windowsupdate' })
$btnReport.Add_Click({ Save-Report })
$btnLog.Add_Click({
    if (-not (Test-Path $LogFile)) { Write-Log 'Log started' }
    Start-Process notepad.exe $LogFile
})
$btnKeep.Add_Click({
    Start-Process notepad.exe $KeepFile -Wait
    Update-Startup; Start-BloatScan; Update-Services
})

# ===========================================================================
# 2. Clean
# ===========================================================================
$pgClean = New-Page 'Clean' 'Deletes junk Windows and apps re-create on their own. Files changed in the last 24 hours and files in use are skipped. Browser caches are only cleaned while that browser is closed.'
# Browser caches: each profile's Cache / Code Cache / GPUCache. Passwords, history and logins live elsewhere and are never touched.
function Get-ChromiumCaches([string]$UserData) {
    if (-not (Test-Path -LiteralPath $UserData)) { return }
    foreach ($p in Get-ChildItem -LiteralPath $UserData -Directory -ErrorAction SilentlyContinue) {
        if ($p.Name -ne 'Default' -and $p.Name -notlike 'Profile *') { continue }
        foreach ($sub in 'Cache', 'Code Cache', 'GPUCache') {
            $x = Join-Path $p.FullName $sub
            if (Test-Path -LiteralPath $x) { $x }
        }
    }
}
# Firefox: the normal install, plus the Microsoft Store version (which keeps its profile inside its package folder).
function Get-FirefoxCaches {
    $roots = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles") +
             @(Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter 'Mozilla.Firefox_*' -ErrorAction SilentlyContinue |
               ForEach-Object { Join-Path $_.FullName 'LocalCache\Local\Mozilla\Firefox\Profiles' })
    foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'cache2' } | Where-Object { Test-Path -LiteralPath $_ }
    }
}
$BrowserCaches = @(
    @{ Name = 'Chrome cache';  Proc = 'chrome';  Paths = @(Get-ChromiumCaches "$env:LOCALAPPDATA\Google\Chrome\User Data") }
    @{ Name = 'Edge cache';    Proc = 'msedge';  Paths = @(Get-ChromiumCaches "$env:LOCALAPPDATA\Microsoft\Edge\User Data") }
    @{ Name = 'Brave cache';   Proc = 'brave';   Paths = @(Get-ChromiumCaches "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") }
    @{ Name = 'Firefox cache'; Proc = 'firefox'; Paths = @(Get-FirefoxCaches) }
)
# Path may be one folder or several. Fix = included in "Fix my PC". Proc = skip while this program runs.
$CleanTargets = @(
    [pscustomobject]@{ Name = 'Your temp files';               Path = $env:TEMP;                                      Filter = '*'; Admin = $false; On = $true; Fix = $true; Proc = $null }
    [pscustomobject]@{ Name = 'Windows temp files';            Path = "$env:windir\Temp";                             Filter = '*'; Admin = $true;  On = $true; Fix = $true; Proc = $null }
    [pscustomobject]@{ Name = 'Windows Update download cache'; Path = "$env:windir\SoftwareDistribution\Download";    Filter = '*'; Admin = $true;  On = $true; Fix = $true; Proc = $null }
    [pscustomobject]@{ Name = 'App crash dumps';               Path = "$env:LOCALAPPDATA\CrashDumps";                 Filter = '*'; Admin = $false; On = $true; Fix = $true; Proc = $null }
    [pscustomobject]@{ Name = 'Windows error reports';         Path = "$env:ProgramData\Microsoft\Windows\WER";       Filter = '*'; Admin = $true;  On = $true; Fix = $true; Proc = $null }
)
foreach ($b in $BrowserCaches) {
    if ($b.Paths.Count) { $CleanTargets += [pscustomobject]@{ Name = $b.Name; Path = $b.Paths; Filter = '*'; Admin = $false; On = $true; Fix = $true; Proc = $b.Proc } }
}
# Bigger system leftovers. These are cleaned by Windows' own Disk Cleanup engine (cleanmgr /sagerun),
# which knows how to remove them safely. Admin only, never part of Fix my PC.
$VolumeCaches = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$WinCleanup = @(
    @{ Name = 'Previous Windows installation (Windows.old)'; Handlers = @('Previous Installations'); SizePath = 'C:\Windows.old'; On = $false
       Note = 'removes the option to go back to your old Windows version'; Need = 'C:\Windows.old' }
    @{ Name = 'Old Windows update files';     Handlers = @('Update Cleanup');               SizePath = $null; On = $true; Note = 'Windows works out the size' }
    @{ Name = 'Old driver packages';          Handlers = @('Device Driver Packages');       SizePath = $null; On = $true; Note = 'keeps the drivers in use now' }
    @{ Name = 'Delivery Optimization cache';  Handlers = @('Delivery Optimization Files');  On = $true; Note = 'update pieces shared with other PCs'
       SizePath = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" }
    @{ Name = 'Windows upgrade leftovers';    Handlers = @('Windows Upgrade Log Files', 'Temporary Setup Files', 'Upgrade Discarded Files', 'Setup Log Files')
       SizePath = $null; On = $true; Note = 'Windows works out the size' }
)
foreach ($w in $WinCleanup) {
    $have = @($w.Handlers | Where-Object { Test-Path (Join-Path $VolumeCaches $_) })
    if (-not $have -or ($w.Need -and -not (Test-Path $w.Need))) { continue }
    $CleanTargets += [pscustomobject]@{ Name = $w.Name; Path = 'CLEANMGR'; Filter = '*'; Admin = $true; On = $w.On; Fix = $false; Proc = $null
                                        Handlers = $have; SizePath = $w.SizePath; WinNote = $w.Note }
}
$CleanTargets += @(
    [pscustomobject]@{ Name = 'Thumbnail cache'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Filter = 'thumbcache_*.db'; Admin = $false; On = $false; Fix = $false; Proc = $null }
    [pscustomobject]@{ Name = 'Recycle Bin';     Path = 'RECYCLE';                                       Filter = '*';               Admin = $false; On = $false; Fix = $false; Proc = $null }
)
function Test-Open($Target) { [bool]($Target.Proc -and (Get-Process -Name $Target.Proc -ErrorAction SilentlyContinue)) }
$btnScan = New-Button 'Scan'
$btnClean = New-Button 'Clean checked items'
$btnCleanMgr = New-Button 'Open Windows Disk Cleanup'
$lvClean = New-ListView $true @('What', 280, 'Size', 110, 'Files', 90, 'Note', 330)
$lblClean = New-Status
Set-PageLayout $pgClean $lvClean @((New-ButtonBar @($btnScan, $btnClean, $btnCleanMgr))) $lblClean

foreach ($t in $CleanTargets) {
    $note = if ($t.Admin -and -not $IsAdmin) { 'needs administrator' } elseif ($t.Path -eq 'RECYCLE') { 'permanently empties it' }
            elseif ($t.Path -eq 'CLEANMGR') { $t.WinNote } else { '' }
    [void](Add-Row $lvClean @($t.Name, '-', '-', $note) $t ($t.On -and -not ($t.Admin -and -not $IsAdmin)))
    $t | Add-Member -NotePropertyName Bytes -NotePropertyValue 0
    $t | Add-Member -NotePropertyName Note -NotePropertyValue $note
}

$ScanCleanWork = {
    param($targets)
    $cutoff = (Get-Date).AddDays(-1)
    foreach ($t in $targets) {
        $bytes = 0; $count = 0
        if (@($t.Path)[0] -eq 'RECYCLE') {
            try { foreach ($i in (New-Object -ComObject Shell.Application).NameSpace(10).Items()) { $bytes += $i.Size; $count++ } } catch { }
        } elseif (@($t.Path)[0] -eq 'CLEANMGR') {
            if ($t.SizePath) { foreach ($f in Get-FilesSafe $t.SizePath) { $bytes += $f.Length; $count++ } }
            else { $bytes = -1; $count = -1 }   # unknown until Windows calculates it
        } else {
            foreach ($root in @($t.Path)) {
                foreach ($f in Get-FilesSafe $root $t.Filter) { if ($f.LastWriteTime -lt $cutoff) { $bytes += $f.Length; $count++ } }
            }
        }
        [pscustomobject]@{ Name = $t.Name; Bytes = $bytes; Count = $count }
    }
}
$DoCleanWork = {
    param($targets)
    $cutoff = (Get-Date).AddDays(-1)
    # Windows' own cleanup tasks run together in one Disk Cleanup pass. StateFlags0777 marks which ones to run.
    $win = @($targets | Where-Object { @($_.Path)[0] -eq 'CLEANMGR' })
    if ($win) {
        $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        $want = @($win | ForEach-Object { $_.Handlers })
        foreach ($k in Get-ChildItem $base) {
            if ($want -contains $k.PSChildName) { Set-ItemProperty -LiteralPath $k.PSPath -Name StateFlags0777 -Value 2 -Type DWord }
            else { Remove-ItemProperty -LiteralPath $k.PSPath -Name StateFlags0777 -ErrorAction SilentlyContinue }
        }
        $before = (Get-PSDrive C).Free
        Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -Wait
        $freed = [Math]::Max(0, (Get-PSDrive C).Free - $before)
        foreach ($k in Get-ChildItem $base) { Remove-ItemProperty -LiteralPath $k.PSPath -Name StateFlags0777 -ErrorAction SilentlyContinue }
        [pscustomobject]@{ Name = ($win.Name -join ' + '); Freed = $freed; Skipped = 0 }
    }
    foreach ($t in $targets) {
        $freed = 0; $skipped = 0
        if (@($t.Path)[0] -eq 'CLEANMGR') { continue }
        if (@($t.Path)[0] -eq 'RECYCLE') {
            try { Clear-RecycleBin -Force -ErrorAction Stop; $freed = $t.Bytes } catch { $skipped = 1 }
        } else {
            foreach ($root in @($t.Path)) {
                foreach ($f in @(Get-FilesSafe $root $t.Filter)) {
                    if ($f.LastWriteTime -ge $cutoff) { continue }
                    try { $len = $f.Length; $f.Delete(); $freed += $len } catch { $skipped++ }
                }
                if ($t.Filter -eq '*') {
                    # Remove folders left empty, deepest first; never the root itself.
                    Get-DirsSafe $root | Where-Object { $_.LastWriteTime -lt $cutoff } |
                        Sort-Object { $_.FullName.Length } -Descending |
                        ForEach-Object { try { $_.Delete() } catch { } }   # DirectoryInfo.Delete() fails unless empty
                }
            }
        }
        [pscustomobject]@{ Name = $t.Name; Freed = $freed; Skipped = $skipped }
    }
}

# A function, not PerformClick(): PerformClick is ignored while the tab is hidden.
function Start-CleanScan {
    $btnScan.Enabled = $false; $btnClean.Enabled = $false
    $lblClean.Text = 'Scanning...'
    Start-Bg $ScanCleanWork $CleanTargets {
        param($results)
        $total = 0
        foreach ($r in $results) {
            foreach ($it in $lvClean.Items) {
                if ($it.Tag.Name -ne $r.Name) { continue }
                $it.Tag.Bytes = $r.Bytes
                $it.SubItems[1].Text = if ($r.Bytes -lt 0) { '?' } else { Format-Size $r.Bytes }
                $it.SubItems[2].Text = if ($r.Count -lt 0) { '-' } else { '{0:N0}' -f $r.Count }
                $it.SubItems[3].Text = if (Test-Open $it.Tag) { "$($it.Tag.Name -replace ' cache$', '') is open - close it to clean this" } else { $it.Tag.Note }
                if ($it.Checked -and $r.Bytes -gt 0) { $total += $r.Bytes }
            }
        }
        $lblClean.Text = 'Checked items add up to about {0}.' -f (Format-Size $total)
        $btnScan.Enabled = $true; $btnClean.Enabled = $true
    }
}
$btnScan.Add_Click({ Start-CleanScan })
$btnClean.Add_Click({
    $picked = @($lvClean.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { -not ($_.Admin -and -not $IsAdmin) })
    $open = @($picked | Where-Object { Test-Open $_ })
    $picked = @($picked | Where-Object { -not (Test-Open $_) })
    $skipNote = if ($open) { "`n`nSkipped because the browser is open: $(($open | ForEach-Object Name) -join ', ')" } else { '' }
    if (-not $picked) { Show-Msg "Nothing to clean - check at least one item (admin-only items need `"Restart as administrator`").$skipNote" | Out-Null; return }
    $names = ($picked | ForEach-Object { " - $($_.Name)" }) -join "`n"
    if ($picked | Where-Object { $_.Path -eq 'CLEANMGR' }) { $skipNote += "`n`nWindows Disk Cleanup will run for the Windows items - this can take several minutes." }
    if ((Show-Msg "Delete the junk in:`n$names`n`nThis can't be undone (it's all re-creatable).$skipNote" 'YesNo' 'Question') -ne 'Yes') { return }
    $btnScan.Enabled = $false; $btnClean.Enabled = $false
    $lblClean.Text = 'Cleaning...'
    Start-Bg $DoCleanWork $picked {
        param($results)
        $total = 0; $skip = 0
        foreach ($r in $results) { $total += $r.Freed; $skip += $r.Skipped; Add-History 'Clean' $r.Name ('freed {0}, {1} in-use files skipped' -f (Format-Size $r.Freed), $r.Skipped) }
        Update-History
        $lblClean.Text = 'Freed {0}. {1} files were in use and left alone.' -f (Format-Size $total), $skip
        $btnScan.Enabled = $true; $btnClean.Enabled = $true
        Start-CleanScan
    }
})
$btnCleanMgr.Add_Click({ Start-Process cleanmgr.exe })

# ===========================================================================
# 3. Startup apps
# ===========================================================================
$pgStartup = New-Page 'Startup' 'Checked apps start when you sign in. Uncheck to stop them auto-starting (the app itself stays installed) and click Apply. Same switch as Task Manager > Startup.'
$RunKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$ApprovedKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$StartupSources = @(
    [pscustomobject]@{ Scope = 'You';       Kind = 'Reg';    Path = "HKCU:\$RunKey";                                         Approved = "HKCU:\$ApprovedKey\Run" }
    [pscustomobject]@{ Scope = 'All users'; Kind = 'Reg';    Path = "HKLM:\$RunKey";                                         Approved = "HKLM:\$ApprovedKey\Run" }
    [pscustomobject]@{ Scope = 'All users'; Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$ApprovedKey\Run32" }
    [pscustomobject]@{ Scope = 'You';       Kind = 'Folder'; Path = [Environment]::GetFolderPath('Startup');                 Approved = "HKCU:\$ApprovedKey\StartupFolder" }
    [pscustomobject]@{ Scope = 'All users'; Kind = 'Folder'; Path = [Environment]::GetFolderPath('CommonStartup');           Approved = "HKLM:\$ApprovedKey\StartupFolder" }
)
# Apps that don't need to launch with Windows: launchers, chat, updaters, OEM helpers.
$StartupSafeOff = @(
    'Steam', 'Teams', 'Acrobat', 'Adobe', 'EdgeAutoLaunch', 'Microsoft\.Lists', 'Spotify', 'Discord', 'Epic', 'EADM',
    'Origin', 'EA Desktop', 'Battle\.net', 'Ubisoft', 'Skype', 'Zoom', 'iTunes', 'Cortana', 'Opera', 'CCleaner',
    'GoogleUpdate', 'jusched', 'Java Update', 'Evernote', 'uTorrent', 'BitTorrent', 'Wondershare', 'OneLaunch', 'Wave Browser',
    'SupportAssist', 'Dell (Digital|Update|Optimizer|Customer)', 'HP (JumpStart|Support|Notifications|Insights|Registration)', 'HPMSGSVC',
    'Lenovo (Vantage|Welcome|Now)', 'ASUS (Update|GiftBox|Live)', 'Acer (Care|Collection|Jumpstart|Portal)', 'MSI (Center|Dragon)',
    'McAfee', 'Norton', 'Avast', 'AVG', 'CyberLink', 'WildTangent'
) -join '|'

$btnStartReload = New-Button 'Reload'
$btnStartApply = New-Button 'Apply changes'
$btnStartTM = New-Button 'Open Task Manager'
$lvStart = New-ListView $true @('App', 260, 'For', 80, 'Advice', 170, 'Command', 420)
$lblStart = New-Status
Set-PageLayout $pgStartup $lvStart @((New-ButtonBar @($btnStartReload, $btnStartApply, $btnStartTM))) $lblStart

function Get-StartupFlag($ApprovedPath, $Name) {
    $k = Get-Item -LiteralPath $ApprovedPath -ErrorAction SilentlyContinue
    if (-not $k) { return $true }
    $v = $k.GetValue($Name)
    -not ($v -and ($v[0] % 2 -eq 1))   # 02/06 = enabled, 03/01 = disabled
}
function Set-StartupFlag($ApprovedPath, $Name, [bool]$Enable) {
    if (-not (Test-Path -LiteralPath $ApprovedPath)) { New-Item -Path $ApprovedPath -Force | Out-Null }
    $bytes = New-Object byte[] 12
    if ($Enable) { $bytes[0] = 2 }
    else { $bytes[0] = 3; [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()).CopyTo($bytes, 4) }
    Set-ItemProperty -LiteralPath $ApprovedPath -Name $Name -Value $bytes -Type Binary -ErrorAction Stop
}
# Turn one startup entry (a row's Tag) on/off and record how to flip it back.
function Set-StartupEntry($Tag, [bool]$Enable) {
    Set-StartupFlag $Tag.Src.Approved $Tag.Name $Enable
    Add-History 'Startup' ($Tag.Name -replace '_[0-9A-F]{32}$', '') ('{0} starting with Windows ({1})' -f $(if ($Enable) { 'allowed' } else { 'stopped' }), $Tag.Src.Scope) `
        @{ Type = 'Startup'; Approved = $Tag.Src.Approved; Name = $Tag.Name; Enable = (-not $Enable) }
}
function Update-Startup {
    $userKeep = Get-UserKeep
    $lvStart.BeginUpdate(); $lvStart.Items.Clear()
    foreach ($s in $StartupSources) {
        $entries = @()
        if ($s.Kind -eq 'Reg') {
            $k = Get-Item -LiteralPath $s.Path -ErrorAction SilentlyContinue
            if ($k) { $entries = $k.GetValueNames() | Where-Object { $_ } | ForEach-Object { @{ Name = $_; Cmd = [string]$k.GetValue($_) } } }
        } elseif ($s.Path -and (Test-Path -LiteralPath $s.Path)) {
            $entries = Get-ChildItem -LiteralPath $s.Path -File -Force | Where-Object Name -ne 'desktop.ini' | ForEach-Object { @{ Name = $_.Name; Cmd = $_.FullName } }
        }
        foreach ($e in $entries) {
            $on = Get-StartupFlag $s.Approved $e.Name
            # Judge by the entry's name first; the command line is only a fallback
            # (Microsoft.Lists lives in the OneDrive folder but isn't OneDrive).
            $advice = ''
            foreach ($text in @($e.Name, $e.Cmd)) {
                if ($userKeep -and $text -match $userKeep) { $advice = 'keep (your keep list)'; break }
                if ($text -match $KeepBuiltIn) { $advice = 'keep (security/VPN/drivers)'; break }
                if ($text -match $StartupSafeOff) { $advice = 'safe to turn off'; break }
            }
            $display = $e.Name -replace '_[0-9A-F]{32}$', ''
            $it = Add-Row $lvStart @($display, $s.Scope, $advice, $e.Cmd) @{ Src = $s; Name = $e.Name; On = $on } $on
            if ($advice -like 'keep*') { $it.ForeColor = [Drawing.Color]::DarkGreen }
        }
    }
    $lvStart.EndUpdate()
    $lblStart.Text = '{0} startup apps, {1} turned on.' -f $lvStart.Items.Count, $lvStart.CheckedItems.Count
}
$btnStartReload.Add_Click({ Update-Startup })
$btnStartTM.Add_Click({ Start-Process taskmgr.exe '/7 /startup' })
$btnStartApply.Add_Click({
    $changed = 0; $failed = @()
    foreach ($it in $lvStart.Items) {
        $t = $it.Tag
        if ($it.Checked -eq $t.On) { continue }
        try { Set-StartupEntry $t $it.Checked; $changed++ } catch { $failed += $it.Text }
    }
    Update-Startup; Update-History
    $msg = "$changed change(s) saved. They take effect next time you sign in."
    if ($failed) { $msg += "`n`nCouldn't change (needs administrator): $($failed -join ', ')" }
    Show-Msg $msg | Out-Null
})

# ===========================================================================
# 4. Bloatware
# ===========================================================================
$pgBloat = New-Page 'Bloatware' 'Pre-installed extras found on this PC. Junk is pre-checked; Optional means fine to remove if you never use it. Uninstalling is permanent (reinstall from the Store or maker''s site).'
# Matched against program display names and Store package names.
# Cat: Junk = ads/promos/trials nobody needs; Optional = works, but rarely needed; Trial AV = paid antivirus trials.
$BloatCatalog = @(
    # Cleaners, adware and fake optimisers
    @{ Match = 'CCleaner|Driver Booster|Advanced SystemCare|PC Cleaner|Driver Easy|Reimage|Restoro|Segurazo|ByteFence|SlimCleaner|Driver Updater|PC Optimizer|OneLaunch|Wave Browser|Shift Browser|WebCompanion|Ask Toolbar|Bing Bar'
       Cat = 'Junk'; Why = 'cleaner / driver-updater / adware - Windows does this itself' }
    @{ Match = 'WildTangent|Booking\.com|PricelinePartnerNetwork|Amazon (Assistant|Browser)|Hotspot Shield|DropboxOEM|Dropbox (Promotion|Offer|25 GB)|McAfee WebAdvisor|McAfee Security Scan'
       Cat = 'Junk'; Why = 'pre-installed promo / trial' }
    # Trial antivirus (Windows Security takes over once removed)
    @{ Match = '^McAfee|^Norton|^Avast|^AVG |^Avira|TotalAV|^Webroot|5A894077\.McAfeeSecurity'
       Cat = 'Trial AV'; Why = 'antivirus - remove if you did not pay for it; Windows Security takes over' }
    # Store promo apps and games
    @{ Match = '^king\.com\.|CandyCrush|BubbleWitch|FarmHeroes|MarchofEmpires|HiddenCity|Asphalt|DisneyMagicKingdoms|RoyalRevolt'
       Cat = 'Junk'; Why = 'pre-installed game / ad' }
    @{ Match = 'Flipboard|Twitter|PandoraMedia|Shazam|XING|EclipseManager|SlingTV|iHeartRadio|PhototasticCollage|PicsArt|ActiproSoftware|CyberLinkMediaSuiteEssentials|DrawboardPDF|AdobePhotoshopExpress|Duolingo'
       Cat = 'Junk'; Why = 'pre-installed promo app' }
    @{ Match = 'Facebook|Instagram|BytedancePte|TikTok|AmazonVideo\.PrimeVideo|SpotifyAB\.SpotifyMusic|Netflix|^Disney\.|ExpressVPN'
       Cat = 'Optional'; Why = 'pre-installed app - remove if you do not use it' }
    # Microsoft extras
    @{ Match = '^Microsoft\.(BingNews|BingWeather|BingSports|BingFinance|GetHelp|Getstarted|WindowsFeedbackHub|MixedReality\.Portal|3DBuilder|Microsoft3DViewer|Print3D|OneConnect|Messaging|MicrosoftSolitaireCollection|MicrosoftOfficeHub|People|WindowsMaps|SkypeApp|549981C3F5F10)$|^Clipchamp\.Clipchamp$'
       Cat = 'Optional'; Why = 'Windows extra - reinstall from the Store any time' }
    # PC makers: promos and registration
    @{ Match = 'DellInc\.PartnerPromo|Dell (Customer Connect|Product Registration)|HPJumpStarts|HP JumpStart|HPRegistration|HP Registration|HPConnectedMusic|Snapfish|HP Documentation|HP Customer Experience|Lenovo(ID| ID|Welcome| Welcome|Now| Now)|Lenovo.*Hotspot|ASUSGIFTBOX|ASUS GiftBox|Acer.*(Registration|User Experience Improvement|Jumpstart|Portal|Collection)|Intel.*Computing Improvement'
       Cat = 'Junk'; Why = 'PC maker promo / registration / telemetry' }
    # PC makers: support tools (fine to remove; download drivers from the maker's site when needed)
    @{ Match = 'SupportAssist|Dell (Digital Delivery|Optimizer|Pair|Mobile Connect|Update|TechHub)|DellInc\.(DellDigitalDelivery|MyDell|DellUpdate|DellSupportAssist)|My Dell'
       Cat = 'Optional'; Why = 'Dell utility - get drivers from dell.com/support when needed' }
    @{ Match = 'HP (Support Assistant|Connection Optimizer|Insights|Notifications|Audio Switch|Easy Clean|QuickDrop|Privacy Settings|Sure Run|Sure Recover|Wolf Security|Sure Click|Sure Sense)|AD2F1837\.(HPSupportAssistant|HPPrivacySettings|HPQuickDrop|HPEasyClean|HPInsights|myHP|HPWorkWell|HPPowerManager)'
       Cat = 'Optional'; Why = 'HP utility - get drivers from support.hp.com when needed' }
    @{ Match = 'Lenovo (Vantage|Utility|Smart Appearance)|E046963F\.LenovoCompanion'
       Cat = 'Optional'; Why = 'Lenovo utility (Vantage also sets battery charge limits - keep it if you use that)' }
    @{ Match = 'ASUS (Live Update|Splendid|Update)|Armoury Crate|MyASUS|B9ECED6F\.(ASUSPCAssistant|ArmouryCrate|ScreenPadMaster)'
       Cat = 'Optional'; Why = 'ASUS utility (Armoury Crate controls fans/RGB on gaming models)' }
    @{ Match = 'Acer (Care Center|Quick Access)|AcerIncorporated\.'
       Cat = 'Optional'; Why = 'Acer utility' }
    @{ Match = 'MSI (Center|Dragon Center)|Dragon Center|Micro-StarInternational'
       Cat = 'Optional'; Why = 'MSI utility (controls fans/RGB on gaming models)' }
    @{ Match = 'Intel.*Driver (&|and) Support Assistant|Killer (Intelligence|Control) Center'
       Cat = 'Optional'; Why = 'driver updater / network tweaker - Windows Update covers drivers' }
    @{ Match = 'CyberLink (PowerDVD|YouCam|PowerDirector|PhotoDirector|Media Suite|Power2Go|LabelPrint|Power Media)'
       Cat = 'Optional'; Why = 'pre-installed media software' }
)

$btnBloatScan = New-Button 'Rescan'
$btnBloatRemove = New-Button 'Uninstall checked'
$btnBloatRestore = New-Button 'Create restore point'
$btnBloatApps = New-Button 'Open Settings > Apps'
$lvBloat = New-ListView $true @('Name', 270, 'Type', 80, 'Category', 80, 'Why', 330, 'Size', 80, 'Publisher', 150)
$lblBloat = New-Status
Set-PageLayout $pgBloat $lvBloat @((New-ButtonBar @($btnBloatScan, $btnBloatRemove, $btnBloatRestore, $btnBloatApps))) $lblBloat
if (-not $IsAdmin) { $btnBloatRestore.Enabled = $false }

$BloatScanWork = {
    param($cfg)
    function Find-Match($text) { foreach ($c in $cfg.Catalog) { if ($text -match $c.Match) { return $c } } }
    $seen = @{}
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($k in $keys) {
        foreach ($sub in Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName -or -not $p.UninstallString -or $p.SystemComponent -eq 1 -or $p.ParentKeyName) { continue }
            if ($seen.ContainsKey($p.DisplayName)) { continue }
            $seen[$p.DisplayName] = $true
            if ($cfg.UserKeep -and "$($p.DisplayName) $($p.Publisher)" -match $cfg.UserKeep) { continue }
            $c = Find-Match $p.DisplayName
            if (-not $c) { continue }
            [pscustomobject]@{ Name = $p.DisplayName; Type = 'Program'; Cat = $c.Cat; Why = $c.Why; Bytes = [double]$p.EstimatedSize * 1KB
                               Publisher = $p.Publisher; Uninstall = $p.UninstallString; Quiet = $p.QuietUninstallString; Package = $null; Family = $null }
        }
    }
    foreach ($a in Get-AppxPackage -PackageTypeFilter Main -ErrorAction SilentlyContinue) {
        if ($a.NonRemovable -or "$($a.SignatureKind)" -eq 'System') { continue }
        if ($cfg.UserKeep -and $a.Name -match $cfg.UserKeep) { continue }
        $c = Find-Match $a.Name
        if (-not $c) { continue }
        [pscustomobject]@{ Name = $a.Name; Type = 'Store app'; Cat = $c.Cat; Why = $c.Why; Bytes = 0
                           Publisher = ($a.Publisher -replace '^CN=([^,]+).*', '$1'); Uninstall = $null; Quiet = $null
                           Package = $a.PackageFullName; Family = $a.PackageFamilyName }
    }
}
$BloatRemoveWork = {
    param($items)
    foreach ($i in $items) {
        $ok = $false; $msg = ''
        try {
            if ($i.Package) {
                Remove-AppxPackage -Package $i.Package -ErrorAction Stop
                $ok = $true; $msg = 'removed'
            } else {
                $cmd = if ($i.Quiet) { $i.Quiet } else { $i.Uninstall }
                if ($cmd -match '(?i)msiexec(\.exe)?"?\s+.*?(\{[0-9A-F-]{36}\})') {
                    # Swap /I (repair/modify) for /X (remove); /passive shows progress but asks nothing.
                    $p = Start-Process msiexec.exe -ArgumentList "/x $($Matches[2]) /passive /norestart" -Wait -PassThru
                    $ok = $p.ExitCode -in 0, 1605, 1641, 3010; $msg = "exit code $($p.ExitCode)"
                } else {
                    if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $rest = $Matches[2] }
                    elseif ($cmd -match '^\s*(.+?\.exe)\s*(.*)$') { $exe = $Matches[1]; $rest = $Matches[2] }
                    else { $exe = $cmd; $rest = '' }
                    $sp = @{ FilePath = $exe; Wait = $true; PassThru = $true }
                    if ($rest.Trim()) { $sp.ArgumentList = $rest }
                    $p = Start-Process @sp
                    $ok = $true; $msg = "uninstaller closed (exit code $($p.ExitCode))"
                }
            }
        } catch { $msg = $_.Exception.Message }
        [pscustomobject]@{ Name = $i.Name; Ok = $ok; Msg = $msg; Family = $i.Family }
    }
}
function Start-BloatScan {
    $btnBloatScan.Enabled = $false; $btnBloatRemove.Enabled = $false
    $lblBloat.Text = 'Looking for bloatware...'
    Start-Bg $BloatScanWork @{ Catalog = $BloatCatalog; UserKeep = (Get-UserKeep) } {
        param($rows)
        $lvBloat.BeginUpdate(); $lvBloat.Items.Clear()
        $order = @{ 'Junk' = 0; 'Trial AV' = 1; 'Optional' = 2 }
        foreach ($r in $rows | Sort-Object { $order[$_.Cat] }, Name) {
            $size = if ($r.Bytes) { Format-Size $r.Bytes } else { '' }
            $it = Add-Row $lvBloat @($r.Name, $r.Type, $r.Cat, $r.Why, $size, $r.Publisher) $r ($r.Cat -eq 'Junk')
            if ($r.Cat -eq 'Junk') { $it.ForeColor = [Drawing.Color]::DarkRed }
            elseif ($r.Cat -eq 'Trial AV') { $it.ForeColor = [Drawing.Color]::DarkOrange }
        }
        $lvBloat.EndUpdate()
        $lblBloat.Text = if ($rows.Count) { "Found $($rows.Count) item(s). Check what you want gone and click Uninstall." }
                         else { 'No known bloatware found - nice and clean.' }
        $btnBloatScan.Enabled = $true; $btnBloatRemove.Enabled = $true
    }
}
$btnBloatScan.Add_Click({ Start-BloatScan })
$btnBloatApps.Add_Click({ Start-Process 'ms-settings:appsfeatures' })
$btnBloatRestore.Add_Click({
    $btnBloatRestore.Enabled = $false
    $lblBloat.Text = 'Creating a restore point (can take a minute)...'
    Start-Bg { try { Checkpoint-Computer -Description 'PC Tune-Up' -RestorePointType APPLICATION_UNINSTALL -ErrorAction Stop; 'ok' } catch { $_.Exception.Message } } $null {
        param($r)
        $lblBloat.Text = if ("$($r[0])" -eq 'ok') { 'Restore point created (Windows skips it if one was made in the last 24 hours).' }
                         else { "Restore point failed: $($r[0]) - System Protection may be off for C:." }
        if ("$($r[0])" -eq 'ok') { Add-History 'Restore point' 'C:' 'created'; Update-History }
        $btnBloatRestore.Enabled = $true
    }
})
$btnBloatRemove.Add_Click({
    $picked = @($lvBloat.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $picked) { Show-Msg 'Check at least one item first.' | Out-Null; return }
    $names = ($picked | ForEach-Object { " - $($_.Name)" }) -join "`n"
    $q = "Uninstall these $($picked.Count) item(s)?`n$names`n`nSome uninstallers open their own window or ask for permission - follow along. " +
         "This can't be undone here; you'd reinstall from the Store or the maker's website."
    if ((Show-Msg $q 'YesNo' 'Warning') -ne 'Yes') { return }
    $btnBloatScan.Enabled = $false; $btnBloatRemove.Enabled = $false
    $lblBloat.Text = 'Uninstalling... (watch for uninstaller windows)'
    Start-Bg $BloatRemoveWork $picked {
        param($results)
        $bad = @()
        foreach ($r in $results) {
            # Store apps can be put back from the Store; desktop programs can't be undone from here.
            $undo = if ($r.Ok -and $r.Family) { @{ Type = 'Store'; Family = $r.Family } } else { $null }
            Add-History 'Uninstall' $r.Name $r.Msg $undo
            if (-not $r.Ok) { $bad += "$($r.Name): $($r.Msg)" }
        }
        Update-History
        $msg = "Done. $(@($results | Where-Object Ok).Count) of $($results.Count) uninstalled."
        if ($bad) { $msg += "`n`nProblems:`n" + ($bad -join "`n") }
        Show-Msg $msg | Out-Null
        Start-BloatScan
    }
})

# ===========================================================================
# 5. Services
# ===========================================================================
$pgSvc = New-Page 'Services' 'Non-Microsoft background services. Known bloat is listed first; "review" rows are other third-party services that start with Windows - only change those if you know what they are.'
# Matched against service name and display name. Checked before the keep rules,
# so e.g. NVIDIA telemetry is flagged even though NVIDIA drivers are kept.
$ServiceCatalog = @(
    @{ Match = 'SupportAssist';                                              Suggest = 'Disabled'; Why = 'Dell SupportAssist' }
    @{ Match = 'DellTechHub|Dell TechHub';                                   Suggest = 'Disabled'; Why = 'Dell TechHub' }
    @{ Match = 'DellClientManagement|Dell Client Management';                Suggest = 'Disabled'; Why = 'Dell Client Management' }
    @{ Match = 'Dell Digital Delivery';                                      Suggest = 'Disabled'; Why = 'Dell app installer' }
    @{ Match = 'DellPairService|Dell Pair';                                  Suggest = 'Disabled'; Why = 'Dell Pair' }
    @{ Match = '^DDV|Dell Data Vault';                                       Suggest = 'Disabled'; Why = 'Dell telemetry' }
    @{ Match = 'Dell ?Optimizer';                                            Suggest = 'Manual';   Why = 'Dell Optimizer' }
    @{ Match = 'HpTouchpointAnalytics|HP Insights Analytics|HP Analytics';   Suggest = 'Disabled'; Why = 'HP telemetry' }
    @{ Match = '^HP(Diags|AppHelper|Network|SysInfo)Cap$|HP (Diagnostics|App Helper|Network|System Info) HSA'; Suggest = 'Manual'; Why = 'HP support helper' }
    @{ Match = 'HPPrintScanDoctor';                                          Suggest = 'Manual';   Why = 'HP Print and Scan Doctor' }
    @{ Match = 'HP Support Solutions Framework';                             Suggest = 'Manual';   Why = 'HP Support Assistant helper' }
    @{ Match = 'HPJumpStart|HP JumpStart';                                   Suggest = 'Disabled'; Why = 'HP promo' }
    @{ Match = 'LenovoVantageService|Lenovo Vantage';                        Suggest = 'Manual';   Why = 'Lenovo Vantage (starts when opened)' }
    @{ Match = '^UDCService$|Universal Device Client';                       Suggest = 'Manual';   Why = 'Lenovo telemetry' }
    @{ Match = 'ASUSLink(Near|Remote)|ASUS Link';                            Suggest = 'Manual';   Why = 'ASUS phone link' }
    @{ Match = 'ASUSSoftwareManager|ASUS Software Manager|AsusUpdateCheck|ASUS Update'; Suggest = 'Manual'; Why = 'ASUS updater' }
    @{ Match = 'ASUSSystem(Analysis|Diagnosis)|ASUS System (Analysis|Diagnosis)'; Suggest = 'Manual'; Why = 'ASUS diagnostics' }
    @{ Match = 'AsusAppService|ASUS App Service';                            Suggest = 'Manual';   Why = 'MyASUS helper' }
    @{ Match = 'Acer.*(Collection|Jumpstart|Portal|Care Center|Registration|User Experience)|^ACCSvc$|AcerCCAgent'; Suggest = 'Manual'; Why = 'Acer utility' }
    @{ Match = 'MSI.*(Center|Companion|Dragon)|MSI_(Center|Companion)';      Suggest = 'Manual';   Why = 'MSI utility' }
    @{ Match = 'ESRV_SVC|SystemUsageReportSvc|Computing Improvement|Energy Server Service'; Suggest = 'Disabled'; Why = 'Intel telemetry' }
    @{ Match = '^DSAService$|^DSAUpdateService$|Driver & Support Assistant';  Suggest = 'Manual';   Why = 'Intel driver updater' }
    @{ Match = 'NvTelemetryContainer|NVIDIA Telemetry';                      Suggest = 'Disabled'; Why = 'NVIDIA telemetry' }
    @{ Match = 'Razer Game Scanner';                                         Suggest = 'Disabled'; Why = 'Razer game scanner' }
    @{ Match = 'AdobeARMservice|AdobeUpdateService|Adobe Acrobat Update|Adobe Update'; Suggest = 'Manual'; Why = 'Adobe updater' }
    @{ Match = 'AGSService|Adobe Genuine';                                   Suggest = 'Manual';   Why = 'Adobe licence checker' }
    @{ Match = '^gupdatem?$|GoogleUpdater|Google Update';                    Suggest = 'Manual';   Why = 'Google updater (Chrome still updates when open)' }
    @{ Match = '^edgeupdatem?$|Microsoft Edge Update';                       Suggest = 'Manual';   Why = 'Edge updater (Edge still updates when open)' }
    @{ Match = '^bravem?$|Brave Update';                                     Suggest = 'Manual';   Why = 'Brave updater' }
    @{ Match = '^dbupdatem?$|Dropbox Update';                                Suggest = 'Manual';   Why = 'Dropbox updater' }
    @{ Match = 'Origin(Web)?HelperService';                                  Suggest = 'Manual';   Why = 'EA Origin helper' }
    @{ Match = 'Wondershare';                                                Suggest = 'Manual';   Why = 'Wondershare helper' }
    @{ Match = 'McAfee WebAdvisor|McAfee Security Scan';                     Suggest = 'Disabled'; Why = 'McAfee promo' }
)
# Unknown services whose names look like this are probably safe to set to Manual.
$ServiceLikely = 'Updater|Update Service|Update Helper|Telemetry|Analytics|Usage Report|Customer Experience|Promo'

$btnSvcReload = New-Button 'Reload'
$btnSvcApply = New-Button 'Apply suggestion to checked'
$btnSvcManual = New-Button 'Set checked to Manual'
$btnSvcRestore = New-Button 'Restore checked'
$lvSvc = New-ListView $true @('Service', 220, 'What it is', 230, 'Company', 150, 'Starts', 80, 'Running', 70, 'Suggested', 80, 'Original', 80)
$lblSvc = New-Status
Set-PageLayout $pgSvc $lvSvc @((New-ButtonBar @($btnSvcReload, $btnSvcApply, $btnSvcManual, $btnSvcRestore))) $lblSvc
$SvcButtons = @($btnSvcApply, $btnSvcManual, $btnSvcRestore)
if (-not $IsAdmin) { $SvcButtons | ForEach-Object { $_.Enabled = $false } }

function Get-ServiceOriginals {
    $h = @{}
    if (Test-Path $ServiceStateFile) {
        (Get-Content $ServiceStateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
    }
    $h
}
function Save-ServiceOriginals($Orig) { $Orig | ConvertTo-Json | Set-Content -Path $ServiceStateFile -Encoding UTF8 }
$StartRank = @{ Automatic = 2; Manual = 1; Disabled = 0 }
# Change one service's startup type, remember its very first setting (for Restore) and record the undo.
function Set-ServiceStart([string]$Name, [string]$Target, [string]$From, $Orig) {
    Set-Service -Name $Name -StartupType $Target -ErrorAction Stop
    if ($Target -eq 'Automatic') { Start-Service -Name $Name -ErrorAction SilentlyContinue }
    else { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    if (-not $Orig.ContainsKey($Name)) { $Orig[$Name] = $From }
    elseif ($Orig[$Name] -eq $Target) { $Orig.Remove($Name) }   # back where it started
    Add-History 'Service' $Name "$From -> $Target" @{ Type = 'Service'; Name = $Name; StartType = $From }
}
$SvcScanWork = {
    param($cfg)
    $modes = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
    foreach ($s in Get-CimInstance Win32_Service) {
        $text = "$($s.Name) | $($s.DisplayName)"
        $exe = ''
        if ($s.PathName -match '^\s*"([^"]+)"') { $exe = $Matches[1] }
        elseif ($s.PathName -match '^\s*(.+?\.exe)') { $exe = $Matches[1] }
        $company = ''
        if ($exe -and (Test-Path -LiteralPath $exe)) { try { $company = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).CompanyName } catch { } }
        $known = $null
        foreach ($c in $cfg.Catalog) { if ($text -match $c.Match) { $known = $c; break } }
        $changed = $cfg.Changed -contains $s.Name
        # Windows' own services, and services shipped inside a driver package (DriverStore) - leave those alone.
        $isWindows = (-not $exe) -or ($company -match 'Microsoft') -or ($exe -match '\\Windows\\(System32|SysWOW64)\\svchost\.exe$') -or
                     ($exe -match '\\System32\\DriverStore\\')
        $kind = $null; $suggest = ''; $why = ''
        if ($cfg.UserKeep -and "$text $company" -match $cfg.UserKeep) { if ($changed) { $kind = 'review'; $why = 'on your keep list' } }
        elseif ($known) { $kind = 'known'; $suggest = $known.Suggest; $why = $known.Why }
        elseif ($isWindows) { if ($changed) { $kind = 'review'; $why = 'changed by PC Tune-Up' } }
        elseif ("$text $company" -match $cfg.Keep) { if ($changed) { $kind = 'review'; $why = 'looks important (security/driver/VPN)' } }
        elseif ($text -match $cfg.Likely) { $kind = 'likely'; $suggest = 'Manual'; $why = 'looks like an updater or telemetry' }
        elseif ($s.StartMode -eq 'Auto' -or $changed) { $kind = 'review'; $why = 'third-party, starts with Windows' }
        if (-not $kind) { continue }
        [pscustomobject]@{ Name = $s.Name; Display = $s.DisplayName; Company = $company; Start = $modes["$($s.StartMode)"]
                           State = $s.State; Suggest = $suggest; Why = $why; Kind = $kind }
    }
}
function Update-Services {
    $btnSvcReload.Enabled = $false
    $lblSvc.Text = 'Looking at services...'
    $orig = Get-ServiceOriginals
    $cfg = @{ Catalog = $ServiceCatalog; Keep = $KeepBuiltIn; Likely = $ServiceLikely; UserKeep = (Get-UserKeep); Changed = @($orig.Keys) }
    Start-Bg $SvcScanWork $cfg {
        param($rows)
        $orig = Get-ServiceOriginals
        $order = @{ known = 0; likely = 1; review = 2 }
        $lvSvc.BeginUpdate(); $lvSvc.Items.Clear()
        $todo = 0
        foreach ($r in $rows | Sort-Object { $order[$_.Kind] }, Name) {
            $o = if ($orig.ContainsKey($r.Name)) { $orig[$r.Name] } else { '' }
            $what = if ($r.Kind -eq 'review') { "$($r.Display)  (review: $($r.Why))" } else { "$($r.Why) - $($r.Display)" }
            $it = Add-Row $lvSvc @($r.Name, $what, $r.Company, $r.Start, $r.State, $(if ($r.Suggest) { $r.Suggest } else { '-' }), $o) $r
            if ($r.Suggest -and $r.Start -eq $r.Suggest) { $it.ForeColor = [Drawing.Color]::Gray }
            elseif ($r.Kind -eq 'review') { $it.ForeColor = [Drawing.Color]::DimGray }
            elseif ($r.Suggest) { $todo++ }
        }
        $lvSvc.EndUpdate()
        $lblSvc.Text = if (-not $IsAdmin) { "View only - restart as administrator to change services. $todo could be trimmed." }
                       elseif ($todo) { "$todo service(s) could be trimmed. Grey rows are already done." }
                       else { 'Nothing left to trim. Review rows are shown for information.' }
        $btnSvcReload.Enabled = $true
        $script:SvcLoaded = $true
    }
}
function Set-Services([string]$Mode) {
    $orig = Get-ServiceOriginals
    $done = 0; $failed = @(); $skipped = 0
    foreach ($it in $lvSvc.CheckedItems) {
        $name = $it.Text
        $target = switch ($Mode) {
            'Restore' { if ($orig.ContainsKey($name)) { $orig[$name] } else { 'Automatic' } }
            'Manual'  { 'Manual' }
            default   { $it.Tag.Suggest }
        }
        if (-not $target -or $target -eq $it.Tag.Start) { $skipped++; continue }
        try { Set-ServiceStart $name $target $it.Tag.Start $orig; $done++ }
        catch { $failed += "$name ($($_.Exception.Message))" }
    }
    Save-ServiceOriginals $orig
    Update-Services; Update-History
    $msg = "$done service(s) updated."
    if ($skipped) { $msg += " $skipped were already set that way or had no suggestion (use 'Set checked to Manual')." }
    if ($failed) { $msg += "`n`nFailed:`n" + ($failed -join "`n") }
    Show-Msg $msg | Out-Null
}
$btnSvcReload.Add_Click({ Update-Services })
$btnSvcApply.Add_Click({ Set-Services 'Suggest' })
$btnSvcManual.Add_Click({ Set-Services 'Manual' })
$btnSvcRestore.Add_Click({ Set-Services 'Restore' })

# ===========================================================================
# 6. Disk usage
# ===========================================================================
$pgDisk = New-Page 'Disk' 'Find what is filling the drive. Pick a place and Scan; double-click a row to look inside it. This only looks - it never deletes.'
$txtDisk = New-Object Windows.Forms.TextBox
$txtDisk.Width = 330; $txtDisk.Text = $env:USERPROFILE; $txtDisk.Margin = New-Object Windows.Forms.Padding(3, 7, 3, 3)
$btnDiskBrowse = New-Button 'Browse...'
$btnDiskScan = New-Button 'Scan'
$btnDiskUp = New-Button 'Up'
$btnDiskOpen = New-Button 'Open in Explorer'
$cmbDisk = New-Object Windows.Forms.ComboBox
$cmbDisk.DropDownStyle = 'DropDownList'; $cmbDisk.Width = 170; $cmbDisk.Margin = New-Object Windows.Forms.Padding(3, 7, 3, 3)
$lvDisk = New-ListView $false @('Folder', 460, 'Size', 120, 'Share', 90)
$lblDisk = New-Status
Set-PageLayout $pgDisk $lvDisk @((New-ButtonBar @($txtDisk, $btnDiskBrowse, $btnDiskScan, $btnDiskUp, $btnDiskOpen, $cmbDisk))) $lblDisk

# Quick picks: only places that exist on this PC.
$steamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
$DiskPicks = [ordered]@{
    'Quick pick...'      = $null
    'Your user folder'   = $env:USERPROFILE
    'Downloads'          = (Join-Path $env:USERPROFILE 'Downloads')
    'Steam games'        = $(if ($steamRoot) { Join-Path ($steamRoot -replace '/', '\') 'steamapps\common' } else { "${env:ProgramFiles(x86)}\Steam\steamapps\common" })
    'Epic games'         = "$env:ProgramFiles\Epic Games"
    'Program Files'      = $env:ProgramFiles
    'Program Files (x86)' = ${env:ProgramFiles(x86)}
    'Whole C: drive (slow)' = 'C:\'
}
foreach ($k in $DiskPicks.Keys) { if (-not $DiskPicks[$k] -or (Test-Path -LiteralPath $DiskPicks[$k])) { [void]$cmbDisk.Items.Add($k) } }
$cmbDisk.SelectedIndex = 0

$DiskWork = {
    param($root)
    $rows = @()
    $loose = 0
    try { foreach ($f in [IO.DirectoryInfo]::new($root).EnumerateFiles()) { $loose += $f.Length } } catch { }
    $subdirs = try { @([IO.DirectoryInfo]::new($root).EnumerateDirectories()) } catch { @() }
    foreach ($d in $subdirs) {
        if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $sum = 0
        foreach ($f in Get-FilesSafe $d.FullName) { $sum += $f.Length }
        $rows += [pscustomobject]@{ Name = $d.Name; Path = $d.FullName; Bytes = $sum }
    }
    if ($loose) { $rows += [pscustomobject]@{ Name = '(files directly in this folder)'; Path = $root; Bytes = $loose } }
    $rows
}
function Start-DiskScan([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { Show-Msg "Folder not found:`n$Path" 'OK' 'Warning' | Out-Null; return }
    $txtDisk.Text = $Path
    $btnDiskScan.Enabled = $false; $lvDisk.Items.Clear()
    $lblDisk.Text = 'Scanning... big folders like C:\ can take a few minutes.'
    Start-Bg $DiskWork $Path {
        param($rows)
        $total = ($rows | Measure-Object Bytes -Sum).Sum
        $lvDisk.BeginUpdate()
        foreach ($r in $rows | Sort-Object Bytes -Descending) {
            $share = if ($total) { '{0:N0}%' -f (100 * $r.Bytes / $total) } else { '' }
            [void](Add-Row $lvDisk @($r.Name, (Format-Size $r.Bytes), $share) $r.Path)
        }
        $lvDisk.EndUpdate()
        $hint = if ($txtDisk.Text -match 'steamapps|Epic Games|GOG|Program Files') {
            '  Uninstall games/programs from their launcher or Settings > Apps, not by deleting folders.' } else { '' }
        $lblDisk.Text = ('Total: {0}.{1}' -f (Format-Size $total), $hint)
        $btnDiskScan.Enabled = $true
    }
}
$btnDiskScan.Add_Click({ Start-DiskScan $txtDisk.Text })
$cmbDisk.Add_SelectedIndexChanged({
    $p = $DiskPicks[[string]$cmbDisk.SelectedItem]
    if ($p) { Start-DiskScan $p; $cmbDisk.SelectedIndex = 0 }   # reset so the same pick works again
})
$btnDiskUp.Add_Click({ $p = Split-Path $txtDisk.Text -Parent; if ($p) { Start-DiskScan $p } })
$btnDiskOpen.Add_Click({
    $p = if ($lvDisk.SelectedItems.Count) { $lvDisk.SelectedItems[0].Tag } else { $txtDisk.Text }
    Start-Process explorer.exe "`"$p`""
})
$btnDiskBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtDisk.Text
    if ($dlg.ShowDialog() -eq 'OK') { Start-DiskScan $dlg.SelectedPath }
})
$lvDisk.Add_DoubleClick({
    if ($lvDisk.SelectedItems.Count -and $lvDisk.SelectedItems[0].Tag -ne $txtDisk.Text) { Start-DiskScan $lvDisk.SelectedItems[0].Tag }
})

# ===========================================================================
# 7. Upgrades: what could be added or replaced, and the exact spec to buy
# ===========================================================================
$pgUpg = New-Page 'Upgrades' 'What you could add or replace in this PC, with the specification to buy. Click a row for the full details. Always confirm with the service manual before buying.'
$btnUpgReload = New-Button 'Refresh'
$btnUpgSupport = New-Button 'Open support page'
$btnUpgManual = New-Button 'Find service manual'
$btnUpgCopy = New-Button 'Copy shopping list'
$lvUpg = New-ListView $false @('Part', 110, 'You have now', 290, 'Upgrade option', 220, 'Worth it?', 260, 'What to buy', 600)
$txtUpg = New-Object Windows.Forms.TextBox
$txtUpg.Multiline = $true; $txtUpg.ReadOnly = $true; $txtUpg.Dock = 'Bottom'; $txtUpg.Height = 150; $txtUpg.ScrollBars = 'Vertical'
$txtUpg.BackColor = [Drawing.SystemColors]::Window
Set-PageLayout $pgUpg $lvUpg @((New-ButtonBar @($btnUpgReload, $btnUpgSupport, $btnUpgManual, $btnUpgCopy))) $txtUpg

$UpgradeWork = {
    $rows = New-Object System.Collections.ArrayList
    function Add-Upg($Part, $Now, $Option, $Worth, $Spec, $Why) {
        [void]$rows.Add([pscustomobject]@{ Part = $Part; Now = $Now; Option = $Option; Worth = $Worth; Spec = $Spec; Why = $Why })
    }
    $cs = Get-CimInstance Win32_ComputerSystem
    $model = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
    $serial = "$((Get-CimInstance Win32_BIOS).SerialNumber)".Trim()
    $chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
    $isLaptop = [bool]($chassis | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 })
    $os = Get-CimInstance Win32_OperatingSystem
    $usedPct = [int](100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))

    # --- Memory ---
    $memTypes = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $jedec = @{ '2C' = 'Micron'; 'CE' = 'Samsung'; 'AD' = 'SK hynix'; '9B' = 'Crucial'; '98' = 'Kingston'; 'CB' = 'ADATA'; '9E' = 'Corsair'; 'CD' = 'G.Skill' }
    $arr = Get-CimInstance Win32_PhysicalMemoryArray | Where-Object Use -eq 3 | Select-Object -First 1   # 3 = system memory
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    if ($mods) {
        $m = $mods[0]
        $type = $memTypes[[int]$m.SMBIOSMemoryType]; if (-not $type) { $type = 'DDR' }
        $speed = if ($m.ConfiguredClockSpeed) { $m.ConfiguredClockSpeed } else { $m.Speed }
        $ff = [int]$m.FormFactor   # 8 = DIMM (desktop), 12 = SO-DIMM (laptop)
        $ffName = if ($ff -eq 12) { 'SO-DIMM' } else { 'DIMM' }
        $pins = @{ 'DDR5|12' = 262; 'DDR5|8' = 288; 'DDR4|12' = 260; 'DDR4|8' = 288; 'DDR3|12' = 204; 'DDR3|8' = 240 }["$type|$ff"]
        $volt = if ($m.ConfiguredVoltage) { '{0:0.0#} V' -f ($m.ConfiguredVoltage / 1000) } else { '' }
        $ecc = $m.TotalWidth -gt $m.DataWidth
        $maker = "$($m.Manufacturer)".Trim()
        if ($maker -match '^[0-9A-F]{4,}$') { $code = $maker.Substring(2, 2); if ($jedec[$code]) { $maker = $jedec[$code] } }
        $slots = [Math]::Max([int]$arr.MemoryDevices, $mods.Count)
        $maxGB = if ($arr.MaxCapacityEx) { [int][Math]::Round($arr.MaxCapacityEx / 1MB) } elseif ($arr.MaxCapacity) { [int][Math]::Round($arr.MaxCapacity / 1MB) } else { 0 }
        $sizes = @($mods | ForEach-Object { [int]($_.Capacity / 1GB) })
        $totalGB = ($sizes | Measure-Object -Sum).Sum
        $free = $slots - $mods.Count
        $layout = (($sizes | Group-Object | ForEach-Object { "$($_.Count) x $($_.Name) GB" }) -join ' + ')
        $now = "$totalGB GB: $layout $type-$speed $ffName ($maker $("$($m.PartNumber)".Trim())), $(if ($free) { "$free of $slots slot(s) free" } else { "all $slots slots used" })"
        $soldered = $type -like 'LP*' -or $ff -notin 8, 12
        if ($soldered) {
            Add-Upg 'Memory' $now 'Not upgradeable' 'n/a' 'Nothing to buy - this memory is soldered to the motherboard.' `
                "$type memory, or a form factor other than a removable module, means it can't be swapped or added to."
        } else {
            $target = if ($totalGB -lt 16) { 16 } elseif ($totalGB -lt 32) { 32 } else { 64 }
            if ($maxGB -and $target -gt $maxGB) { $target = $maxGB }
            $base = "$type-$speed $ffName$(if ($pins) { " ($pins-pin)" })$(if ($volt) { ", $volt" }), $(if ($ecc) { 'ECC' } else { 'non-ECC' })"
            if ($target -le $totalGB) {
                Add-Upg 'Memory' $now 'Already at the maximum' 'Not needed' "Nothing to buy - $totalGB GB is the most this PC supports." "The firmware reports a maximum of $maxGB GB."
            } else {
                $each = $sizes[0]
                if ($free -gt 0 -and ($totalGB + $free * $each) -ge $target) {
                    $n = [Math]::Ceiling(($target - $totalGB) / $each)
                    $option = "Add $n x $each GB (total $($totalGB + $n * $each) GB)"
                    $spec = "$n x $each GB $base - match the module already fitted. Total afterwards: $($totalGB + $n * $each) GB."
                } else {
                    $per = [int]($target / $slots)
                    $option = "Replace with $slots x $per GB (total $target GB)"
                    $spec = "A matched kit of $slots x $per GB $base = $target GB. The current modules come out (keep or sell them)."
                }
                $spec += " Faster-rated $type modules also work and simply run at $speed MT/s." + $(if ($maxGB) { " Most supported: $maxGB GB." })
                $worth = if ($mods.Count -eq 1 -and $slots -ge 2) { 'Recommended - one module means single-channel; a matching second module roughly doubles memory speed' }
                         elseif ($totalGB -lt 8) { 'Strongly recommended' }
                         elseif ($totalGB -lt 16) { 'Recommended' }
                         elseif ($usedPct -ge 80) { "Recommended - memory is $usedPct% full right now" }
                         elseif ($totalGB -lt 32) { 'Optional - worth it for virtual machines, big spreadsheets, photo/video/CAD work or many browser tabs' }
                         else { 'Not needed' }
                Add-Upg 'Memory' $now $option $worth $spec "Memory is $usedPct% used right now. Modules must match the type ($type) and form factor ($ffName) and should match the speed; mixing sizes works but can lose dual-channel speed."
            }
        }
    }

    # --- Storage ---
    $sysDisk = try { (Get-Partition -DriveLetter C -ErrorAction Stop | Get-Disk).Number } catch { $null }
    $cDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $cPct = if ($cDrive.Size) { [int](100 * $cDrive.FreeSpace / $cDrive.Size) } else { 100 }
    foreach ($d in Get-PhysicalDisk) {
        if ("$($d.BusType)" -eq 'USB') { continue }
        $gb = [int]($d.Size / 1GB)
        $isSys = "$($d.DeviceId)" -eq "$sysDisk"
        $now = "$("$($d.FriendlyName)".Trim()): $gb GB $($d.BusType) $($d.MediaType)$(if ($isSys) { ", holds Windows (C: $cPct% free)" })"
        if ("$($d.MediaType)" -eq 'HDD') {
            Add-Upg 'Drive' $now 'Replace with an SSD' $(if ($isSys) { 'Strongly recommended - the biggest speed-up an older PC can get' } else { 'Optional' }) `
                '1 TB (or larger) SSD: 2.5-inch SATA SSD to replace this drive, or an M.2 NVMe SSD if the PC has an M.2 slot. Copy ("clone") the old drive with the SSD maker''s free tool.' `
                'Hard disks are 20-50x slower than SSDs at the small reads Windows does all the time.'
        } elseif ($isSys) {
            $worth = if ($cPct -lt 15) { "Recommended - C: is only $cPct% free" } elseif ($gb -lt 300) { 'Recommended - small drive' } else { 'Optional' }
            $form = if ("$($d.BusType)" -eq 'NVMe') { 'M.2 2280 NVMe SSD, PCIe Gen4 x4 (also works in Gen3 slots)' } else { '2.5-inch SATA SSD (or M.2 NVMe if the PC has an M.2 slot)' }
            $spec = "$form, 1 TB or 2 TB."
            $spec += if ($isLaptop) { ' If the laptop has a free M.2 slot, add it as a second drive; if not, replace this drive with the bigger one and clone it.' }
                     else { ' Desktops usually have spare M.2 slots or 2.5/3.5-inch bays - add it as a second drive.' }
            Add-Upg 'Drive' $now 'Bigger or second SSD' $worth $spec 'Check the service manual for a free M.2 slot - Windows cannot see empty slots. Gen4 drives fall back to the slot''s speed, so they are always a safe pick.'
        }
    }
    $usb4 = [bool](Get-CimInstance Win32_USBController -ErrorAction SilentlyContinue | Where-Object Name -match 'USB4|Thunderbolt')
    Add-Upg 'External drive' $(if ($usb4) { 'This PC has a USB4/Thunderbolt port' } else { 'USB ports' }) 'External SSD' 'Optional - no screwdriver needed, good for games, photos and backups' `
        $(if ($usb4) { 'External NVMe SSD (or an NVMe enclosure) for USB4/Thunderbolt, 1-2 TB: up to ~3,000 MB/s on this PC.' } else { 'USB 3.2 Gen 2 external SSD, 1-2 TB (about 1,000 MB/s).' }) `
        'Use the fastest port - on most laptops it has a lightning or USB4 symbol.'

    # --- Battery ---
    if ($isLaptop) {
        $xml = Join-Path $env:TEMP "pctuneup-upg-battery-$PID.xml"
        powercfg /batteryreport /xml /output $xml 2>$null | Out-Null
        if (Test-Path $xml) {
            try {
                [xml]$x = Get-Content $xml
                foreach ($b in @($x.BatteryReport.Batteries.Battery)) {
                    if (-not $b -or [double]$b.DesignCapacity -le 0) { continue }
                    $pct = [Math]::Min(100, [int](100 * [double]$b.FullChargeCapacity / [double]$b.DesignCapacity))
                    $wh = [Math]::Round([double]$b.DesignCapacity / 1000)
                    $worth = if ($pct -lt 60) { 'Recommended - battery life is roughly halved' } elseif ($pct -lt 80) { 'Optional' } else { 'Not needed' }
                    Add-Upg 'Battery' "$wh Wh $($b.Chemistry) battery ($($b.Manufacturer)), now holds $pct% of its original charge" 'Replacement battery' $worth `
                        "Replacement battery for the $model`: $wh Wh $($b.Chemistry). This battery reports itself as '$("$($b.Id)".Trim())' - search that, or your service tag, to find the exact part. Prefer the maker's original part." `
                        'Batteries wear with age and charge cycles. A worn battery doesn''t slow the PC down, it just runs out sooner.'
                }
            } catch { }
            Remove-Item $xml -ErrorAction SilentlyContinue
        }
    }

    # --- Processor and graphics (information) ---
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuNow = "$("$($cpu.Name)".Trim()) - $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"
    if ($isLaptop) { Add-Upg 'Processor' $cpuNow 'Not upgradeable' 'n/a' 'Nothing to buy - laptop processors are soldered to the motherboard.' 'If the processor is too slow, the upgrade path is a new laptop.' }
    else {
        $board = Get-CimInstance Win32_BaseBoard
        Add-Upg 'Processor' $cpuNow 'Depends on the motherboard' 'Rarely worth it' "Check the CPU support list of your motherboard ($($board.Manufacturer) $($board.Product)) on the maker's website." 'A new processor often needs a BIOS update first, and only fits the same socket.'
    }
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Meta' })
    $gpuNow = ($gpus | ForEach-Object { $_.Name.Trim() }) -join ' + '
    if ($isLaptop) { Add-Upg 'Graphics' $gpuNow 'Not upgradeable' 'n/a' 'Nothing to buy - laptop graphics are soldered. An external GPU box over Thunderbolt/USB4 is possible but costly.' '' }
    else { Add-Upg 'Graphics' $gpuNow 'Graphics card' 'Depends on use' 'Needs a free PCIe x16 slot, enough power-supply wattage and connectors, and room in the case - check all three first.' '' }

    $support = if ($cs.Manufacturer -match 'Dell' -and $serial) { "https://www.dell.com/support/home/en-us/product-support/servicetag/$serial/overview" } else { $null }
    [pscustomobject]@{ Rows = $rows; Model = $model; Support = $support
                       Manual = 'https://www.bing.com/search?q=' + [uri]::EscapeDataString("$model service manual memory SSD upgrade") }
}
function Update-Upgrades {
    $btnUpgReload.Enabled = $false
    $txtUpg.Text = 'Looking at this PC''s hardware...'
    Start-Bg $UpgradeWork $null {
        param($r)
        $btnUpgReload.Enabled = $true
        if (-not $r) { $txtUpg.Text = 'Could not read the hardware details.'; return }
        $script:UpgInfo = $r[0]
        $btnUpgSupport.Enabled = [bool]$script:UpgInfo.Support
        $lvUpg.BeginUpdate(); $lvUpg.Items.Clear()
        foreach ($u in $script:UpgInfo.Rows) {
            $it = Add-Row $lvUpg @($u.Part, $u.Now, $u.Option, $u.Worth, $u.Spec) $u
            if ($u.Worth -like 'Strongly*' -or $u.Worth -like 'Recommended*') { $it.ForeColor = [Drawing.Color]::DarkRed }
            elseif ($u.Worth -in 'n/a', 'Not needed') { $it.ForeColor = [Drawing.Color]::Gray }
        }
        $lvUpg.EndUpdate()
        if ($lvUpg.Items.Count) { $lvUpg.Items[0].Selected = $true } else { $txtUpg.Text = '' }
    }
}
$lvUpg.Add_SelectedIndexChanged({
    if (-not $lvUpg.SelectedItems.Count) { return }
    $u = $lvUpg.SelectedItems[0].Tag
    $txtUpg.Text = "$($u.Part): $($u.Option)`r`nWorth it? $($u.Worth)`r`n`r`nYou have now: $($u.Now)`r`n`r`nWhat to buy: $($u.Spec)" + $(if ($u.Why) { "`r`n`r`nGood to know: $($u.Why)" })
})
$btnUpgReload.Add_Click({ Update-Upgrades })
$btnUpgSupport.Add_Click({ if ($script:UpgInfo.Support) { Start-Process $script:UpgInfo.Support } })
$btnUpgManual.Add_Click({ if ($script:UpgInfo) { Start-Process $script:UpgInfo.Manual } })
$btnUpgCopy.Add_Click({
    $items = @($lvUpg.Items | ForEach-Object Tag | Where-Object { $_.Worth -notin 'n/a', 'Not needed' })
    if (-not $items) { Show-Msg 'Nothing worth upgrading was found.' | Out-Null; return }
    $text = "Upgrade shopping list for $($script:UpgInfo.Model)`r`n`r`n" + (($items | ForEach-Object { "- $($_.Part) ($($_.Worth)):`r`n  $($_.Spec)" }) -join "`r`n`r`n")
    [Windows.Forms.Clipboard]::SetText($text)
    Show-Msg 'Shopping list copied - paste it into an email, a note or a shop''s chat.' | Out-Null
})

# ===========================================================================
# 8. History
# ===========================================================================
$pgHist = New-Page 'History' 'Every change PC Tune-Up made on this PC, newest first. Check rows and click Undo to put them back. Cleaned files and uninstalled programs can''t be undone; removed Store apps can be reinstalled.'
$btnHistReload = New-Button 'Reload'
$btnHistUndo = New-Button 'Undo checked'
$btnHistLog = New-Button 'Open text log'
$btnUpdate = New-Button 'Check for updates'
$lvHist = New-ListView $true @('When', 140, 'What', 100, 'Item', 270, 'Change', 300, 'Undo', 150)
$lblHist = New-Status
Set-PageLayout $pgHist $lvHist @((New-ButtonBar @($btnHistReload, $btnHistUndo, $btnHistLog, $btnUpdate))) $lblHist

function Get-UndoStatus($E) {
    if ($E.Undone) { 'undone' } elseif ($E.Undo.Type -eq 'Store') { 'reinstall from Store' } elseif ($E.Undo) { 'can undo' } else { '-' }
}
function Update-History {
    $entries = @(Get-History)
    $lvHist.BeginUpdate(); $lvHist.Items.Clear()
    foreach ($e in $entries | Sort-Object Time -Descending) {
        $status = Get-UndoStatus $e
        $it = Add-Row $lvHist @(([datetime]$e.Time).ToString('g'), $e.Kind, $e.Item, $e.Change, $status) $e
        if ($status -eq 'undone' -or $status -eq '-') { $it.ForeColor = [Drawing.Color]::Gray }
    }
    $lvHist.EndUpdate()
    $n = @($entries | Where-Object { (Get-UndoStatus $_) -eq 'can undo' }).Count
    $lblHist.Text = if ($entries.Count) { "$($entries.Count) change(s) recorded, $n can be undone." } else { 'No changes yet. (Changes from before this version are in the text log.)' }
}
$btnHistReload.Add_Click({ Update-History })
$btnHistLog.Add_Click({ $btnLog.PerformClick() })
$btnHistUndo.Add_Click({
    $picked = @($lvHist.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { (Get-UndoStatus $_) -in 'can undo', 'reinstall from Store' })
    if (-not $picked) { Show-Msg 'Check one or more rows that say "can undo" first.' | Out-Null; return }
    if ($IsAdmin -eq $false -and ($picked | Where-Object { $_.Undo.Type -eq 'Service' })) {
        Show-Msg 'Undoing service changes needs administrator rights - use "Restart as administrator" first.' 'OK' 'Warning' | Out-Null; return
    }
    $names = ($picked | ForEach-Object { " - $($_.Item): $($_.Change)" }) -join "`n"
    if ((Show-Msg "Undo these changes?`n$names" 'YesNo' 'Question') -ne 'Yes') { return }

    $all = @(Get-History); $logs = @(); $failed = @(); $done = 0
    foreach ($e in $picked) {
        try {
            $u = $e.Undo; $markUndone = $true
            switch ($u.Type) {
                'Startup' {
                    Set-StartupFlag $u.Approved $u.Name ([bool]$u.Enable)
                    $logs += , @('Undo', $e.Item, $(if ($u.Enable) { 'allowed to start with Windows again' } else { 'stopped starting with Windows again' }))
                }
                'Service' {
                    Set-Service -Name $u.Name -StartupType $u.StartType -ErrorAction Stop
                    if ($u.StartType -eq 'Automatic') { Start-Service -Name $u.Name -ErrorAction SilentlyContinue }
                    $orig = Get-ServiceOriginals
                    if ($orig.ContainsKey($u.Name) -and $orig[$u.Name] -eq $u.StartType) { $orig.Remove($u.Name); Save-ServiceOriginals $orig }
                    $logs += , @('Undo', $e.Item, "service back to $($u.StartType)")
                }
                'Store' {
                    Start-Process "ms-windows-store://pdp/?PFN=$($u.Family)"   # opens its Store page; user clicks Get
                    $markUndone = $false
                }
            }
            if ($markUndone) { ($all | Where-Object Id -eq $e.Id) | ForEach-Object { $_.Undone = $true } }
            $done++
        } catch { $failed += "$($e.Item): $($_.Exception.Message)" }
    }
    Save-History $all                                                # mark rows first, then append the undo records
    foreach ($l in $logs) { Add-History $l[0] $l[1] $l[2] }
    Update-History; Update-Startup; Update-Services
    $msg = "$done change(s) undone."
    if ($picked | Where-Object { $_.Undo.Type -eq 'Startup' }) { $msg += ' Startup changes take effect next time you sign in.' }
    if ($failed) { $msg += "`n`nFailed:`n" + ($failed -join "`n") }
    Show-Msg $msg | Out-Null
})

# ===========================================================================
# Report: one HTML page with everything the tabs currently show, saved to Documents
# ===========================================================================
function ConvertTo-HtmlRows([object[]]$Headers, $Items, [int[]]$Cols) {
    $enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
    $h = ($Headers | ForEach-Object { "<th>$(& $enc $_)</th>" }) -join ''
    $rows = foreach ($it in $Items) {
        '<tr>' + (($Cols | ForEach-Object { "<td>$(& $enc $it.SubItems[$_].Text)</td>" }) -join '') + '</tr>'
    }
    if (-not $rows) { return '<p class="none">Nothing found.</p>' }
    "<table><tr>$h</tr>$($rows -join '')</table>"
}
function Save-Report {
    $enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
    $advice = if ($script:HealthAdvice) { '<ul class="advice">' + (($script:HealthAdvice | ForEach-Object { "<li>$(& $enc $_)</li>" }) -join '') + '</ul>' }
              else { '<p class="ok">No problems spotted.</p>' }
    $startOn = @($lvStart.Items | Where-Object Checked)
    $svcTodo = @($lvSvc.Items | Where-Object { $_.Tag.Kind -ne 'review' })
    $histRows = @($lvHist.Items | Select-Object -First 50)
    $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>PC Tune-Up report - $(& $enc $PcName)</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px auto;max-width:1000px;padding:0 16px;color:#1b1b1b;background:#fff}
h1{font-size:22px;margin:0 0 4px} h2{font-size:16px;margin:28px 0 8px;border-bottom:2px solid #0067c0;padding-bottom:4px}
.sub{color:#666;margin:0 0 16px} pre{background:#f4f6f8;padding:12px;border-radius:6px;font:13px Consolas,monospace;white-space:pre-wrap}
table{border-collapse:collapse;width:100%;font-size:13px} th,td{text-align:left;padding:5px 8px;border-bottom:1px solid #e3e3e3;vertical-align:top}
th{background:#f4f6f8} .advice li{color:#a00000;margin:4px 0} .ok{color:#0a7a2f} .none{color:#666}
</style></head><body>
<h1>PC Tune-Up report</h1>
<p class="sub">$(& $enc $PcName) - $(Get-Date -Format 'dddd d MMMM yyyy, HH:mm')</p>
<h2>Health</h2><pre>$(& $enc $lblHealth.Text)
$(& $enc $lblSpeed.Text)</pre>
<h2>Advice</h2>$advice
<h2>Junk files that can be cleaned</h2>$(ConvertTo-HtmlRows @('What', 'Size', 'Files', 'Note') $lvClean.Items @(0, 1, 2, 3))
<h2>Apps that start with Windows ($($startOn.Count) on)</h2>$(ConvertTo-HtmlRows @('App', 'For', 'Advice') $startOn @(0, 1, 2))
<h2>Bloatware found</h2>$(ConvertTo-HtmlRows @('Name', 'Type', 'Category', 'Why', 'Size') $lvBloat.Items @(0, 1, 2, 3, 4))
<h2>Background services</h2>$(ConvertTo-HtmlRows @('Service', 'What it is', 'Starts', 'Suggested') $svcTodo @(0, 1, 3, 5))
<h2>Upgrade options</h2>$(ConvertTo-HtmlRows @('Part', 'You have now', 'Upgrade option', 'Worth it?', 'What to buy') $lvUpg.Items @(0, 1, 2, 3, 4))
<h2>Changes made by PC Tune-Up</h2>$(ConvertTo-HtmlRows @('When', 'What', 'Item', 'Change', 'Undo') $histRows @(0, 1, 2, 3, 4))
</body></html>
"@
    $safeName = ($PcName -replace '[\\/:*?"<>|]', '').Trim()
    $file = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("PC Tune-Up report - $safeName - $(Get-Date -Format 'yyyy-MM-dd HHmm').html")
    Set-Content -Path $file -Value $html -Encoding UTF8
    Write-Log "Report saved: $file"
    Start-Process $file
}

# ===========================================================================
# Fix my PC: the safe subset of every tab in one click
#   - clean temp, crash dumps, error reports, Windows Update cache, closed browsers' caches
#   - stop "safe to turn off" apps starting with Windows
#   - (admin) set known bloat services to their suggestion
# Never uninstalls anything. Everything except cleaned files can be undone from History.
# ===========================================================================
$script:SvcLoaded = $false
$btnFix.Add_Click({
    if ($IsAdmin -and -not $script:SvcLoaded) { Show-Msg 'Still checking services - try again in a few seconds.' | Out-Null; return }
    $clean = @($CleanTargets | Where-Object { $_.Fix -and -not ($_.Admin -and -not $IsAdmin) -and -not (Test-Open $_) })
    $openBrowsers = @($CleanTargets | Where-Object { $_.Fix -and (Test-Open $_) } | ForEach-Object Name)
    $startup = @($lvStart.Items | Where-Object { $_.Tag.On -and $_.SubItems[2].Text -eq 'safe to turn off' })
    $svc = if ($IsAdmin) {
        @($lvSvc.Items | Where-Object { $_.Tag.Kind -eq 'known' -and $_.Tag.Suggest -and $StartRank[$_.Tag.Start] -gt $StartRank[$_.Tag.Suggest] })
    } else { @() }

    $plan = @('PC Tune-Up will:', " - Clean junk files: $(($clean | ForEach-Object Name) -join ', ')")
    if ($openBrowsers) { $plan += "     (skipping $($openBrowsers -join ', ') - close the browser first to include it)" }
    if ($startup) { $plan += " - Stop $($startup.Count) app(s) starting with Windows: $(($startup | ForEach-Object Text) -join ', ')" }
    if ($svc) { $plan += " - Set $($svc.Count) background service(s) to their suggested setting: $(($svc | ForEach-Object Text) -join ', ')" }
    if (-not $IsAdmin) { $plan += '', 'Tip: "Restart as administrator" first to also clean Windows files and trim background services.' }
    $plan += '', 'Nothing gets uninstalled. Startup and service changes can be undone from the History tab.'
    if ((Show-Msg ($plan -join "`n") 'OKCancel' 'Question') -ne 'OK') { return }

    $nStart = 0; foreach ($it in $startup) { try { Set-StartupEntry $it.Tag $false; $nStart++ } catch { } }
    $nSvc = 0
    if ($svc) {
        $orig = Get-ServiceOriginals
        foreach ($it in $svc) { try { Set-ServiceStart $it.Text $it.Tag.Suggest $it.Tag.Start $orig; $nSvc++ } catch { } }
        Save-ServiceOriginals $orig
    }
    $script:FixCounts = @{ Startup = $nStart; Services = $nSvc }
    $btnFix.Enabled = $false; $btnFix.Text = 'Fixing...'
    Start-Bg $DoCleanWork $clean {
        param($results)
        $freed = 0
        foreach ($r in $results) { $freed += $r.Freed; Add-History 'Clean' $r.Name ('freed {0} (Fix my PC)' -f (Format-Size $r.Freed)) }
        $junk = @($lvBloat.Items | Where-Object { $_.Tag.Cat -eq 'Junk' }).Count
        $lines = @('Done!', '',
            " - Freed $(Format-Size $freed) of junk files",
            " - $($script:FixCounts.Startup) app(s) no longer start with Windows")
        if ($IsAdmin) { $lines += " - $($script:FixCounts.Services) background service(s) trimmed" }
        if ($junk) { $lines += " - $junk junk app(s) found - see the Bloatware tab if you want them gone" }
        $lines += '', 'Startup changes take effect next time you sign in. Undo anything from the History tab.'
        $btnFix.Text = 'Fix my PC'; $btnFix.Enabled = $true
        Update-Health; Start-CleanScan; Update-Startup; Update-Services; Update-History
        Show-Msg ($lines -join "`n") | Out-Null
    }
})

# ===========================================================================
# Updates: compare with the latest GitHub release, download it, verify it, swap the exe.
# ===========================================================================
$UpdateCheckWork = {
    param($repo)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'PC-TuneUp' } -TimeoutSec 15
        $asset = @($r.assets | Where-Object name -eq 'PC-TuneUp.exe')[0]
        [pscustomobject]@{ Version = ($r.tag_name -replace '^v', ''); Notes = [string]$r.body; Url = $asset.browser_download_url
                           Digest = [string]$asset.digest; Page = $r.html_url; Error = $null }
    } catch { [pscustomobject]@{ Error = $_.Exception.Message } }
}
$UpdateDownloadWork = {
    param($info)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $file = Join-Path $env:TEMP "PC-TuneUp-$($info.Version).exe"
    try {
        Invoke-WebRequest $info.Url -OutFile $file -UseBasicParsing -Headers @{ 'User-Agent' = 'PC-TuneUp' } -TimeoutSec 120
        # GitHub publishes each asset's SHA-256; refuse the file if it doesn't match.
        if ($info.Digest -match '^sha256:([0-9a-f]{64})$') {
            if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $Matches[1]) { Remove-Item $file -Force; throw 'downloaded file is damaged (checksum mismatch)' }
        }
        [pscustomobject]@{ File = $file; Error = $null }
    } catch { [pscustomobject]@{ File = $null; Error = $_.Exception.Message } }
}
function Start-UpdateCheck([switch]$Silent) {
    if ($UpdateRepo -like 'OWNER/*') { if (-not $Silent) { Show-Msg 'Updates are not set up in this build.' | Out-Null }; return }
    $btnUpdate.Enabled = $false
    $script:UpdateSilent = [bool]$Silent
    Start-Bg $UpdateCheckWork $UpdateRepo {
        param($r)
        $btnUpdate.Enabled = $true
        $r = $r[0]
        if ($r.Error) { if (-not $script:UpdateSilent) { Show-Msg "Couldn't check for updates:`n$($r.Error)" 'OK' 'Warning' | Out-Null }; return }
        $newer = try { [version]$r.Version -gt [version]$AppVersion } catch { $false }
        if (-not $newer) { if (-not $script:UpdateSilent) { Show-Msg "You have the latest version ($AppVersion)." | Out-Null }; return }
        $notes = (($r.Notes -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 8) -join "`n").Trim()
        if (-not $RunningAsExe -or -not $r.Url) {
            if ((Show-Msg "PC Tune-Up $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nOpen the download page?" 'YesNo' 'Information') -eq 'Yes') { Start-Process $r.Page }
            return
        }
        if ((Show-Msg "PC Tune-Up $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nUpdate now? The app restarts by itself." 'YesNo' 'Information') -ne 'Yes') { return }
        $btnUpdate.Enabled = $false; $btnUpdate.Text = 'Downloading...'
        $script:UpdateInfo = $r
        Start-Bg $UpdateDownloadWork $r {
            param($d)
            $d = $d[0]
            $btnUpdate.Text = 'Check for updates'; $btnUpdate.Enabled = $true
            if ($d.Error) { Show-Msg "Update failed: $($d.Error)" 'OK' 'Warning' | Out-Null; return }
            # A running exe can be renamed but not overwritten: move it aside, put the new one in its place, restart.
            $old = [IO.Path]::ChangeExtension($SelfExe, '.old.exe')
            try {
                Remove-Item $old -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $SelfExe -Destination $old -ErrorAction Stop
                try { Move-Item -LiteralPath $d.File -Destination $SelfExe -ErrorAction Stop }
                catch { Move-Item -LiteralPath $old -Destination $SelfExe; throw }
            } catch {
                Show-Msg "Couldn't replace the app file ($($_.Exception.Message)). Download it yourself from:`n$($script:UpdateInfo.Page)" 'OK' 'Warning' | Out-Null
                return
            }
            Write-Log "Updated PC Tune-Up $AppVersion -> $($script:UpdateInfo.Version)"
            Start-Process $SelfExe
            $form.Close()
        }
    }
}
$btnUpdate.Add_Click({ Start-UpdateCheck })
# A self-update leaves the previous exe behind as .old.exe. It is usually still closing when the new
# version starts, so keep retrying in the background for up to a minute.
$OldExeCleanupWork = {
    param($old)
    for ($i = 0; $i -lt 30 -and (Test-Path -LiteralPath $old); $i++) {
        Start-Sleep 2
        Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
$form.Add_Shown({ Update-Health; Update-Startup; Start-CleanScan; Start-BloatScan; Update-Services; Update-Upgrades; Update-History; Start-UpdateCheck -Silent
    $oldExe = [IO.Path]::ChangeExtension($SelfExe, '.old.exe')
    if ($RunningAsExe -and (Test-Path -LiteralPath $oldExe)) { Start-Bg $OldExeCleanupWork $oldExe { } }
})
[void]$form.ShowDialog()
$JobTimer.Stop()
