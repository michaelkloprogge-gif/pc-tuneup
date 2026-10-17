# Builds PC-TuneUp.exe: a small C# host with pc-tuneup.ps1 embedded as a resource.
# Uses the C# compiler that ships with Windows (.NET Framework 4.x) - nothing to install.
# Run again after editing pc-tuneup.ps1.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here 'pc-tuneup.ps1'
New-Item -ItemType Directory -Force (Join-Path $here 'dist') | Out-Null
$exe = Join-Path $here 'dist\PC-TuneUp.exe'
# The exe's file version comes from $AppVersion in the script, so both always agree.
if ((Get-Content $script -Raw) -notmatch "\`$AppVersion = '(\d+\.\d+\.\d+)'") { throw 'No $AppVersion found in pc-tuneup.ps1' }
$version = $Matches[1]
$work = Join-Path $env:TEMP 'PCTuneUp-build'
New-Item -ItemType Directory -Force $work | Out-Null

$csc = "$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$sma = [PSObject].Assembly.Location   # System.Management.Automation.dll of this Windows PowerShell

# --- Icon: a blue tile with a white speed gauge, stored as PNG frames in an .ico ---
function New-IconPng([int]$Size) {
    $bmp = New-Object Drawing.Bitmap($Size, $Size)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $r = [int]($Size * 0.2); $d = $r * 2; $m = $Size - 1
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90); $path.AddArc($m - $d, 0, $d, $d, 270, 90)
    $path.AddArc($m - $d, $m - $d, $d, $d, 0, 90); $path.AddArc(0, $m - $d, $d, $d, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 103, 192))), $path)
    $pen = New-Object Drawing.Pen([Drawing.Color]::White, [single]($Size * 0.09))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $pad = $Size * 0.2; $w = $Size - 2 * $pad
    $g.DrawArc($pen, [single]$pad, [single]($pad + $Size * 0.06), [single]$w, [single]$w, 160, 220)
    $cx = $Size / 2; $cy = $pad + $Size * 0.06 + $w / 2
    $g.DrawLine($pen, [single]$cx, [single]$cy, [single]($cx + $w * 0.32), [single]($cy - $w * 0.28))
    $g.FillEllipse([Drawing.Brushes]::White, [single]($cx - $Size * 0.07), [single]($cy - $Size * 0.07), [single]($Size * 0.14), [single]($Size * 0.14))
    $g.Dispose()
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , $ms.ToArray()
}
$sizes = 16, 24, 32, 48, 256
$frames = $sizes | ForEach-Object { , (New-IconPng $_) }
$ico = Join-Path $work 'app.ico'
$fs = [IO.File]::Create($ico); $bw = New-Object IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i] % 256   # 0 means 256
    $bw.Write([byte]$s); $bw.Write([byte]$s); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$frames[$i].Length); $bw.Write([uint32]$offset)
    $offset += $frames[$i].Length
}
foreach ($f in $frames) { $bw.Write($f) }
$bw.Close()

# --- Host program ---
$cs = Join-Path $work 'Program.cs'
Set-Content -Path $cs -Encoding UTF8 -Value @'
using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

[assembly: AssemblyTitle("PC Tune-Up")]
[assembly: AssemblyProduct("PC Tune-Up")]
[assembly: AssemblyDescription("Health check, cleanup, startup apps, bloatware and services")]
[assembly: AssemblyVersion("APPVERSION.0")]
[assembly: AssemblyFileVersion("APPVERSION.0")]

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string script;
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("pc-tuneup.ps1"))
        using (var r = new StreamReader(s)) script = r.ReadToEnd();

        // Run the embedded script on this (STA) thread so its WinForms window works.
        var iss = InitialSessionState.CreateDefault();
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        using (var rs = RunspaceFactory.CreateRunspace(iss))
        {
            rs.ApartmentState = System.Threading.ApartmentState.STA;
            rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
            rs.Open();
            rs.SessionStateProxy.SetVariable("AppArgs", args);   // command-line options (/fix, /report, ...)
            using (var ps = PowerShell.Create())
            {
                ps.Runspace = rs;
                ps.AddScript(script);
                try { ps.Invoke(); }
                catch (Exception e)
                {
                    MessageBox.Show("PC Tune-Up stopped:\n\n" + e.Message, "PC Tune-Up", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
            }
        }
        return 0;
    }
}
'@
(Get-Content $cs -Raw).Replace('APPVERSION', $version) | Set-Content $cs -Encoding UTF8

# --- Manifest: normal user rights, sharp on scaled screens, Windows 10/11 ---
$manifest = Join-Path $work 'app.manifest'
Set-Content -Path $manifest -Encoding UTF8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="PCTuneUp.app" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security><requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
      <requestedExecutionLevel level="asInvoker" uiAccess="false" />
    </requestedPrivileges></security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" /></application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware></windowsSettings>
  </application>
</assembly>
'@

& $csc /nologo /target:winexe /platform:x64 /optimize+ "/out:$exe" "/win32icon:$ico" "/win32manifest:$manifest" `
    "/reference:$sma" /reference:System.Windows.Forms.dll /reference:System.Core.dll `
    "/resource:$script,pc-tuneup.ps1" $cs
if ($LASTEXITCODE) { throw "Compile failed (exit $LASTEXITCODE)" }
Remove-Item $work -Recurse -Force
"Built $exe - version $version ({0:N0} KB)" -f ((Get-Item $exe).Length / 1KB)
