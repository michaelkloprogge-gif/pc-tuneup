# Builds the .msix for the Microsoft Store from the exe in dist (run build-exe.ps1 first).
# The Store signs the package itself; -Register instead registers the unpacked layout on this PC to try it
# (needs Developer Mode, no signing).
# Identity values come from Partner Center > the app > Product identity.
param(
    [string]$Name = 'MichaelKloprogge.PCTuneUp',
    [string]$Publisher = 'CN=Michael Kloprogge',
    [string]$PublisherName = 'Michael Kloprogge',
    [switch]$Register
)
$ErrorActionPreference = 'Stop'
$App = @{ Title = 'PC Tune-Up'; Exe = 'PC-TuneUp.exe'; Script = 'pc-tuneup.ps1'; Alias = 'pc-tuneup.exe'; Id = 'PCTuneUp'
          Description = 'Check, clean and speed up your PC, and undo anything.'; Unvirtualized = $true }
Add-Type -AssemblyName System.Drawing
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here "dist\$($App.Exe)"
if (-not (Test-Path $exe)) { throw "dist\$($App.Exe) not found - run build-exe.ps1 first" }
if ((Get-Content (Join-Path $here $App.Script) -Raw) -notmatch "\`$AppVersion = '(\d+\.\d+\.\d+)'") { throw "No `$AppVersion found in $($App.Script)" }
$version = "$($Matches[1]).0"   # the Store wants the last number to be 0
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
if (-not $sdk) { throw 'makeappx.exe not found - install the Windows SDK' }

$layout = Join-Path $here 'dist\msix'
if (Test-Path $layout) {
    if ($Register) { Get-AppxPackage -Name $Name | Remove-AppxPackage }
    Remove-Item $layout -Recurse -Force
}
New-Item -ItemType Directory -Force (Join-Path $layout 'Assets') | Out-Null
Copy-Item $exe $layout

# --- Tiles: the same icon as the exe (New-IconPng from build-exe.ps1) ---
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $here 'build-exe.ps1'), [ref]$null, [ref]$null)
$fn = $ast.Find({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'New-IconPng' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
foreach ($a in @(@('StoreLogo', 50), @('Square44x44Logo', 44), @('Square150x150Logo', 150), @('Square44x44Logo.targetsize-256', 256))) {
    [IO.File]::WriteAllBytes((Join-Path $layout "Assets\$($a[0]).png"), (New-IconPng $a[1]))
}

# Full trust and may ask for administrator. With Unvirtualized, writes are not redirected into the package:
# the settings the app changes (registry, AppData of other programs, programs winget installs) must land in the real places.
$novirt = if ($App.Unvirtualized) { "`n    <desktop6:RegistryWriteVirtualization>disabled</desktop6:RegistryWriteVirtualization>`n    <desktop6:FileSystemWriteVirtualization>disabled</desktop6:FileSystemWriteVirtualization>" } else { '' }
$novirtCap = if ($App.Unvirtualized) { "`n    <rescap:Capability Name=`"unvirtualizedResources`" />" } else { '' }
Set-Content -Path (Join-Path $layout 'AppxManifest.xml') -Encoding UTF8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap3="http://schemas.microsoft.com/appx/manifest/uap/windows10/3"
  xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
  xmlns:desktop6="http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap3 desktop desktop6 rescap">
  <Identity Name="$Name" Publisher="$Publisher" Version="$version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$($App.Title)</DisplayName>
    <PublisherDisplayName>$PublisherName</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>$novirt
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" /><Resource Language="nl-nl" /><Resource Language="de-de" /><Resource Language="fr-fr" />
    <Resource Language="es-es" /><Resource Language="it-it" /><Resource Language="pl-pl" />
  </Resources>
  <Applications>
    <Application Id="$($App.Id)" Executable="$($App.Exe)" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$($App.Title)" Description="$($App.Description)"
        BackgroundColor="transparent" Square150x150Logo="Assets\Square150x150Logo.png" Square44x44Logo="Assets\Square44x44Logo.png" />
      <Extensions>
        <uap3:Extension Category="windows.appExecutionAlias">
          <uap3:AppExecutionAlias><desktop:ExecutionAlias Alias="$($App.Alias)" /></uap3:AppExecutionAlias>
        </uap3:Extension>
      </Extensions>
    </Application>
  </Applications>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
    <rescap:Capability Name="allowElevation" />$novirtCap
  </Capabilities>
</Package>
"@

if ($Register) {
    Add-AppxPackage -Register (Join-Path $layout 'AppxManifest.xml')
    "Registered $Name $version from $layout"
} else {
    $msix = Join-Path $here "dist\$([IO.Path]::ChangeExtension($App.Exe, '.msix'))"
    & $sdk.FullName pack /o /d $layout /p $msix | Out-Null
    if ($LASTEXITCODE) { throw "makeappx failed (exit $LASTEXITCODE)" }
    "Built $msix - version $version ({0:N0} KB)" -f ((Get-Item $msix).Length / 1KB)
}
