# Checks the Dutch translation: the table loads, and a sample of real on-screen texts come out right.
# Usage: .\tests\Test-Translation.ps1   (exits 1 if anything is wrong; used by the GitHub build)
param([string]$App)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
$ast = [Management.Automation.Language.Parser]::ParseFile($App, [ref]$null, [ref]$null)
$Lang = 'nl'
$Settings = @{ Language = 'nl' }
# Load just the translation pieces: the table, the code that builds the lookups, and T itself.
$table = $ast.FindAll({ $args[0] -is [Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.VariablePath.UserPath -eq 'NLTable' }, $false)[0]
Invoke-Expression $table.Extent.Text
$init = $ast.FindAll({ $args[0] -is [Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.VariablePath.UserPath -eq 'script:TExact' }, $false)[0]
$build = $ast.FindAll({ $args[0] -is [Management.Automation.Language.IfStatementAst] -and $args[0].Extent.Text -match 'TPatterns' -and $args[0].Extent.Text -match '^\s*if \(\$Lang -eq ''nl''\)' }, $false)[0]
Invoke-Expression $init.Extent.Text
$script:TCache = New-Object Collections.Hashtable([StringComparer]::Ordinal); $script:TPatterns = @()
Invoke-Expression $build.Extent.Text
$tFunc = $ast.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'T' }, $false)[0]
Invoke-Expression $tFunc.Extent.Text

$fail = 0
# Every line of the table: English and Dutch, separated by one tab, with the same {n} placeholders.
foreach ($line in $NLTable -split "`r?`n") {
    if (-not $line.Trim()) { continue }
    $parts = $line -split "`t"
    if ($parts.Count -ne 2) { $fail++; "FAIL  table line without exactly one tab: $line"; continue }
    $a = @([regex]::Matches($parts[0], '\{\d+\}') | ForEach-Object Value | Sort-Object -Unique)
    $b = @([regex]::Matches($parts[1], '\{\d+\}') | ForEach-Object Value | Sort-Object -Unique)
    if (($a -join ',') -ne ($b -join ',')) { $fail++; "FAIL  placeholders differ: $line" }
}
# Pairs (not a hashtable: "Claude" and "claude" must stay two different cases).
$cases = @(
    ,@('Fix my PC', 'Pc repareren')
    ,@('17 program(s) can be updated, 2 pre-checked.', "17 programma('s) kunnen worden bijgewerkt, 2 al aangevinkt.")
    ,@('Updates  (17)', 'Updates  (17)')
    ,@('Security  (1)', 'Beveiliging  (1)')
    ,@('Balanced plan, best performance mode, plugged in', 'schema Gebalanceerd, modus beste prestaties, aangesloten op netstroom')
    ,@('NVIDIA nView crashed M365Copilot.exe, ms-teams.exe', 'NVIDIA nView liet M365Copilot.exe, ms-teams.exe crashen')
    ,@('  - Your temp files', '  - Je tijdelijke bestanden')
    ,@("Delete the junk in:`n - App crash dumps", "De rommel verwijderen in:`r`n - Crashgegevens van apps")
    ,@('Claude', 'Claude')
    ,@('claude', 'claude')
    ,@('SupportAssistAgent', 'SupportAssistAgent')
)
foreach ($c in $cases) {
    $got = T $c[0]
    if ($got -ceq $c[1]) { "PASS  $($c[0] -replace "`n", ' / ')" } else { $fail++; "FAIL  '$($c[0] -replace "`n", ' / ')' -> '$got' (expected '$($c[1])')" }
}
"$fail failure(s)"
exit [int]($fail -gt 0)
