# Checks lang\*.tsv against the Dutch table's English texts: every line "English<TAB>translation", every English text known,
# placeholders ({0} {1} ...) and leading/trailing spaces the same, no empty translations. Lists texts that are missing.
# Usage: powershell -File .\tests\Test-Languages.ps1   (exit code = number of problems)
param([string]$App)
if (-not $App) { $App = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\pc-tuneup.ps1' }
$src = [IO.File]::ReadAllText($App)
$tbl = [regex]::Match($src, "(?s)\`$NLTable = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
$keys = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in $tbl -split "`r?`n") { if ($l -match "`t") { [void]$keys.Add(($l -split "`t", 2)[0]) } }
$bad = 0
foreach ($file in Get-ChildItem (Join-Path (Split-Path -Parent $App) 'lang') -Filter *.tsv) {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'; $n = 0
    foreach ($l in [IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8)) {
        $n++
        if (-not $l.Trim()) { continue }
        $p = $l -split "`t"
        if ($p.Count -ne 2) { Write-Output "FAIL  $($file.Name):$n has $($p.Count - 1) tabs"; $bad++; continue }
        $en, $tr = $p
        if (-not $keys.Contains($en)) { Write-Output "FAIL  $($file.Name):$n unknown English text: $en"; $bad++; continue }
        [void]$seen.Add($en)
        if (-not $tr.Trim()) { Write-Output "FAIL  $($file.Name):$n empty translation"; $bad++ }
        $pe = (([regex]::Matches($en, '\{\d+\}') | ForEach-Object Value) | Sort-Object) -join ','
        $pt = (([regex]::Matches($tr, '\{\d+\}') | ForEach-Object Value) | Sort-Object) -join ','
        if ($pe -ne $pt) { Write-Output "FAIL  $($file.Name):$n placeholders $pe -> $pt"; $bad++ }
        if (($en -match '^\s') -ne ($tr -match '^\s') -or ($en -match '\s$') -ne ($tr -match '\s$')) { Write-Output "FAIL  $($file.Name):$n leading/trailing space differs"; $bad++ }
    }
    $missing = @($keys | Where-Object { -not $seen.Contains($_) })
    Write-Output ("{0}: {1} texts, {2} missing{3}" -f $file.Name, $seen.Count, $missing.Count, $(if ($missing) { ': ' + (($missing | Select-Object -First 5) -join ' | ') + $(if ($missing.Count -gt 5) { ' ...' }) }))
    $bad += $missing.Count
}
Write-Output "$bad problem(s)"
exit $bad
