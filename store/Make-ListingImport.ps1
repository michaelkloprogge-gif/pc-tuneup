# Fills the listing .csv exported from Partner Center (app overview > Store listings > Export listing)
# with the texts from store\listing.md and the screenshots from store\screenshots, ready for
# Import listings > Import folder.
#   .\store\Make-ListingImport.ps1 -Csv "$env:USERPROFILE\Downloads\<exported>.csv"
param([Parameter(Mandatory)][string]$Csv)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$name = Split-Path $repo -Leaf
$folder = "$name-listing"
$out = Join-Path $PSScriptRoot "import\$folder"

# Screenshot order per app (the Store shows them in this order).
$order = @{
    'pc-move'    = 'start', 'pack-up', 'unpack', 'to-do'
    'pc-handoff' = 'start', 'check', 'sign-out', 'for-the-buyer', 'wipe'
}

# --- Read listing.md: one block per "## Language (xx-xx)" heading.
$lines = [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'listing.md'), [Text.Encoding]::UTF8)
$copyright = ($lines | Where-Object { $_ -match '^\| Copyright \| (.+) \|$' } | ForEach-Object { $Matches[1] }) | Select-Object -First 1
$langs = [ordered]@{}
$cur = $null; $part = $null
foreach ($l in $lines) {
    if ($l -match '^## .*\(([a-z]{2}-[a-z]{2})\)\s*$') {
        $cur = @{ Description = New-Object Collections.Generic.List[string]; Features = @(); Keywords = @() }
        $langs[$Matches[1]] = $cur; $part = $null; continue
    }
    if (-not $cur) { continue }
    if ($l -match '^## ') { $cur = $null; continue }
    if ($l -match '^\*\*[^*]+\*\*\s*:\s*(.+)$') { $cur.Keywords = @($Matches[1] -split '\s*,\s*' | Where-Object { $_ }); $part = $null; continue }
    if ($l -match '^\*\*[^*]+\*\*\s*$') { $part = if ($cur.Description.Count -eq 0) { 'desc' } else { 'feat' }; continue }
    if ($l -eq '---') { continue }
    if ($part -eq 'desc') { $cur.Description.Add($l) }
    elseif ($part -eq 'feat' -and $l -match '^- (.+)$') { $cur.Features += $Matches[1] }
}
if ($langs.Count -eq 0) { throw 'No languages found in listing.md' }

# --- Copy the screenshots next to the .csv (Partner Center wants paths that start with the folder name).
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$shots = @{}
foreach ($dir in Get-ChildItem (Join-Path $PSScriptRoot 'screenshots') -Directory) {
    $files = Get-ChildItem $dir.FullName -Filter *.png | Sort-Object Name
    if ($order[$name]) { $files = foreach ($n in $order[$name]) { $files | Where-Object BaseName -eq $n } }
    New-Item -ItemType Directory -Force (Join-Path $out "screenshots\$($dir.Name)") | Out-Null
    $shots[$dir.Name] = foreach ($f in $files) {
        Copy-Item $f.FullName (Join-Path $out "screenshots\$($dir.Name)")
        "$folder/screenshots/$($dir.Name)/$($f.Name)"
    }
}

# --- Fill the exported .csv by field name (Field, ID and Type stay as Partner Center made them).
$rows = @(Import-Csv -LiteralPath $Csv -Encoding UTF8)
if (-not $rows -or -not ($rows[0].PSObject.Properties.Name -contains 'Field')) { throw "$Csv is not a listing export from Partner Center" }
$cols = @($rows[0].PSObject.Properties.Name)
$byField = @{}; foreach ($r in $rows) { $byField[$r.Field] = $r }
function Set-Cell($field, $col, $value) {
    if ($byField.ContainsKey($field)) { $byField[$field].$col = $value }
    elseif ($value) { Write-Warning "The export has no field '$field'" }
}
$missingFields = 'Description', 'Feature1', 'SearchTerm1', 'DesktopScreenshot1' | Where-Object { -not $byField.ContainsKey($_) }
if ($missingFields) { throw "The export has no field(s): $($missingFields -join ', ')" }

if ($copyright) { Set-Cell 'CopyrightTrademarkInformation' 'default' $copyright }
foreach ($code in $langs.Keys) {
    $col = $cols | Where-Object { $_ -ieq $code } | Select-Object -First 1
    if (-not $col) {
        $col = $code; $cols += $col
        foreach ($r in $rows) { $r | Add-Member -NotePropertyName $col -NotePropertyValue '' }
    }
    $t = $langs[$code]
    Set-Cell 'Description' $col (($t.Description -join "`n").Trim())
    for ($i = 1; $i -le 20; $i++) { Set-Cell "Feature$i" $col $(if ($i -le $t.Features.Count) { $t.Features[$i - 1] } else { '' }) }
    for ($i = 1; $i -le 7; $i++) { Set-Cell "SearchTerm$i" $col $(if ($i -le $t.Keywords.Count) { $t.Keywords[$i - 1] } else { '' }) }
    $s = if ($shots[$code.Substring(0, 2)]) { $shots[$code.Substring(0, 2)] } else { $shots['en'] }
    for ($i = 1; $i -le 10; $i++) { Set-Cell "DesktopScreenshot$i" $col $(if ($i -le $s.Count) { $s[$i - 1] } else { '' }) }
}

# UTF-8 with BOM, every cell quoted - the format Partner Center exports and accepts.
$rows | Select-Object $cols | Export-Csv -LiteralPath (Join-Path $out "$folder.csv") -NoTypeInformation -Encoding UTF8
Write-Host "Ready: $out"
Write-Host "In Partner Center: Store listings > Import listings > Import folder > select '$folder'."
