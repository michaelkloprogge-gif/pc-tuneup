# Runs PC Tune-Up's upgrade advice against this PC and a set of made-up PCs.
# Usage: .\tests\Test-Upgrades.ps1          prints the advice for each made-up PC (read it for anything odd)
#        .\tests\Test-Upgrades.ps1 -Check   checks the key answers and exits 1 if any is wrong (used by the GitHub build)
param([string]$App, [switch]$Check)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
$ast = [Management.Automation.Language.Parser]::ParseFile($App, [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($f.Name -in 'Get-PcIdentity', 'Get-UpgradeRows', 'Get-SupportInfo') { Invoke-Expression $f.Extent.Text }
}
foreach ($a in $ast.FindAll({ $args[0] -is [Management.Automation.Language.AssignmentStatementAst] -and $args[0].Parent -eq $ast.EndBlock }, $false)) {
    if ($a.Left.VariablePath.UserPath -eq 'UpgradeCollectWork') { Invoke-Expression $a.Extent.Text }
}
function Mod($gb, $smb, $speed, $ff, $mt = 0, $mv = 1200, $ecc = $false, $reg = $false) {
    [pscustomobject]@{ SizeGB = $gb; SmbiosType = $smb; MemoryType = $mt; Speed = $speed; FormFactor = $ff; VoltageMV = $mv; ECC = $ecc; Registered = $reg; Maker = '80CE'; Part = 'TEST'; Locator = 'X' }
}
function Disk($name, $gb, $bus, $media, $spin = 0, $sys = $true) { [pscustomobject]@{ Name = $name; SizeGB = $gb; Bus = $bus; Media = $media; Spindle = $spin; IsSystem = $sys } }
function Pc($o) {
    $d = @{ Maker = 'Contoso'; Model = 'Test'; Serial = 'ABC123'; BoardMaker = 'Contoso'; BoardProduct = 'B1'; Chassis = @(3); UsedPct = 50; Slots = 2; MaxKB = 32GB / 1KB
            Modules = @(); Disks = @(); CFreePct = 40; Usb4 = $false; Batteries = @(); Cpu = 'Test CPU'; Cores = 4; Threads = 8; Gpus = @('Intel(R) UHD Graphics'); WiFi = @() }
    foreach ($k in $o.Keys) { $d[$k] = $o[$k] }
    [pscustomobject]$d
}
$cases = [ordered]@{
    'Old office desktop: 1x4GB DDR3 + HDD' = Pc @{ Maker = 'HP'; Model = 'HP Compaq 8200 Elite SFF'; Modules = @(Mod 4 24 1333 8 0 1500); Slots = 4; MaxKB = 32GB / 1KB
        Disks = @(Disk 'ST500DM002' 466 'SATA' 'HDD' 7200); WiFi = @(); Gpus = @('Intel(R) HD Graphics 2000') }
    'Custom gaming desktop: 2x8 DDR4, 4 slots' = Pc @{ Maker = 'System manufacturer'; Model = 'System Product Name'; BoardMaker = 'ASUSTeK COMPUTER INC.'; BoardProduct = 'ROG STRIX B550-F GAMING'
        Modules = @((Mod 8 26 3200 8), (Mod 8 26 3200 8)); Slots = 4; MaxKB = 128GB / 1KB; Disks = @(Disk 'Samsung SSD 970 EVO 500GB' 466 'NVMe' 'SSD'); CFreePct = 9
        Gpus = @('NVIDIA GeForce RTX 3060'); WiFi = @('Intel(R) Wi-Fi 6 AX200 160MHz'); Serial = 'System Serial Number' }
    'Thin laptop: soldered LPDDR5 16GB' = Pc @{ Maker = 'LENOVO'; Model = '21CB'; Chassis = @(10); Modules = @((Mod 8 35 6400 0 0 500), (Mod 8 35 6400 0 0 500)); Slots = 2
        Disks = @(Disk 'SAMSUNG MZVL2512' 476 'NVMe' 'SSD'); Batteries = @([pscustomobject]@{ Wh = 57; Pct = 92; Chem = 'LiP'; Maker = 'Sunwoda'; Id = '5B10W51867' }); WiFi = @('Intel(R) Wi-Fi 6E AX211 160MHz') }
    'Budget laptop: 8GB soldered + 1 free slot' = Pc @{ Maker = 'Acer'; Model = 'Aspire A515-56'; Chassis = @(10); Modules = @(Mod 8 26 3200 13); Slots = 2; MaxKB = 0
        Disks = @(Disk 'WDC PC SN530 256GB' 238 'NVMe' 'SSD'); CFreePct = 30; WiFi = @('Intel(R) Wireless-AC 9560 160MHz')
        Batteries = @([pscustomobject]@{ Wh = 48; Pct = 71; Chem = 'Li-I'; Maker = 'SMP'; Id = 'AP18C8K' }) }
    'Laptop: single 8GB module, 2 slots' = Pc @{ Maker = 'Dell Inc.'; Model = 'Latitude 5410'; Chassis = @(10); Modules = @(Mod 8 26 2666 12); Slots = 2; MaxKB = 32GB / 1KB
        Disks = @(Disk 'KXG60ZNV256G TOSHIBA' 238 'NVMe' 'SSD'); WiFi = @('Intel(R) Wi-Fi 6 AX201 160MHz'); Serial = 'J1K2L3M' }
    'Workstation: ECC registered, firmware max wrong' = Pc @{ Maker = 'Dell Inc.'; Model = 'Precision 7920 Tower'; Modules = @((Mod 32 26 2933 8 0 1200 $true $true), (Mod 32 26 2933 8 0 1200 $true $true)); Slots = 12; MaxKB = 16GB / 1KB
        Disks = @((Disk 'PM981 NVMe 1TB' 954 'NVMe' 'SSD'), (Disk 'ST4000NM' 3726 'SAS' 'Unspecified' 7200 $false)); Gpus = @('NVIDIA Quadro P2000') }
    'Old laptop: DDR type not reported, Wi-Fi 4' = Pc @{ Maker = 'TOSHIBA'; Model = 'Satellite C55'; Chassis = @(1); Modules = @(Mod 4 0 1600 12 0 0); Slots = 2; MaxKB = 16GB / 1KB
        Disks = @(Disk 'TOSHIBA MQ01ABD100' 931 'SATA' 'Unspecified' 5400); WiFi = @('Realtek RTL8723BE 802.11 bgn Wi-Fi Adapter')
        Batteries = @([pscustomobject]@{ Wh = 45; Pct = 38; Chem = 'Li-I'; Maker = 'Panasonic'; Id = 'PA5185U' }) }
    'Virtual machine' = Pc @{ Maker = 'VMware, Inc.'; Model = 'VMware7,1'; Modules = @(Mod 8 0 0 0); Disks = @(Disk 'VMware Virtual disk' 60 'SAS' 'Unspecified') }
}
if (-not $Check) {
    foreach ($name in $cases.Keys) {
        $hw = $cases[$name]
        $si = Get-SupportInfo $hw
        "`n==================== $name ====================`nPC: $($si.Name)   support: $(if ($si.Url) { $si.Url } else { '(search)' })   serial: '$($si.Serial)'"
        foreach ($u in (Get-UpgradeRows $hw)) { "  [$($u.Part)] $($u.Option) -> $($u.Worth)`n      now: $($u.Now)`n      buy: $($u.Spec)" }
    }
    return
}

# Expected answers: case, part, which field, wildcard it must match.
$expect = @(
    ,@('Old office desktop: 1x4GB DDR3 + HDD', 'Drive', 'Option', 'Replace with an SSD')
    ,@('Old office desktop: 1x4GB DDR3 + HDD', 'Drive', 'Worth', 'Strongly recommended*')
    ,@('Old office desktop: 1x4GB DDR3 + HDD', 'Memory', 'Option', 'Add 1 x 4 GB*')
    ,@('Custom gaming desktop: 2x8 DDR4, 4 slots', 'Drive', 'Worth', 'Recommended - C: is only 9% free')
    ,@('Custom gaming desktop: 2x8 DDR4, 4 slots', 'Wi-Fi', 'Option', 'Already modern')
    ,@('Thin laptop: soldered LPDDR5 16GB', 'Memory', 'Option', 'Not upgradeable')
    ,@('Budget laptop: 8GB soldered + 1 free slot', 'Memory', 'Spec', '*same speed as the built-in memory*')
    ,@('Laptop: single 8GB module, 2 slots', 'Memory', 'Worth', 'Recommended - one module*')
    ,@('Workstation: ECC registered, firmware max wrong', 'Memory', 'Spec', '*registered ECC*')
    ,@('Old laptop: DDR type not reported, Wi-Fi 4', 'Memory', 'Spec', '*worked out from the speed*')
    ,@('Old laptop: DDR type not reported, Wi-Fi 4', 'Wi-Fi', 'Worth', 'Recommended*')
    ,@('Old laptop: DDR type not reported, Wi-Fi 4', 'Battery', 'Worth', 'Recommended*')
    ,@('Virtual machine', 'Memory / disk', 'Option', 'Change the VM settings')
)
$fail = 0
foreach ($e in $expect) {
    $rows = @(foreach ($r in (Get-UpgradeRows $cases[$e[0]])) { $r })   # the function returns its list as one object
    $row = $rows | Where-Object Part -eq $e[1] | Select-Object -First 1
    $got = if ($row) { $row.($e[2]) } else { '(no such row)' }
    if ($got -like $e[3]) { "PASS  $($e[0]) / $($e[1]).$($e[2])" } else { $fail++; "FAIL  $($e[0]) / $($e[1]).$($e[2]): expected '$($e[3])', got '$got'" }
}
$si = Get-SupportInfo $cases['Custom gaming desktop: 2x8 DDR4, 4 slots']
if ($si.Name -like '*custom-built PC*' -and -not $si.Serial) { 'PASS  custom PC identity and placeholder serial' } else { $fail++; "FAIL  custom PC identity: '$($si.Name)' serial '$($si.Serial)'" }
"$fail failure(s)"
exit [int]($fail -gt 0)
