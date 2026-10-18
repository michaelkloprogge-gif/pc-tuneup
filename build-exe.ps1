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

// The Windows functions the script needs. Defined here so the script doesn't have to compile them
// at every start (it checks for PcTuneUp.Native before calling Add-Type).
namespace PcTuneUp
{
    public static class Native
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
        [System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
        [System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string idList);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    }
    // Keep in step with the copy in pc-tuneup.ps1.
    public class HeaderFill : NativeWindow
    {
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, ref RECT r);
        [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
        public System.Drawing.Color Color;
        public HeaderFill(IntPtr header, System.Drawing.Color color) { Color = color; AssignHandle(header); }
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg != 0x000F) return;   // WM_PAINT
            var item = new RECT();
            int n = (int)SendMessage(Handle, 0x1200, IntPtr.Zero, ref item);   // HDM_GETITEMCOUNT
            if (n > 0) SendMessage(Handle, 0x1207, (IntPtr)(n - 1), ref item);   // HDM_GETITEMRECT
            RECT c; GetClientRect(Handle, out c);
            if (item.Right >= c.Right) return;
            using (var g = System.Drawing.Graphics.FromHwnd(Handle))
            using (var b = new System.Drawing.SolidBrush(Color))
                g.FillRectangle(b, item.Right, 0, c.Right - item.Right, c.Bottom);
        }
    }
}

static class Program
{
    static void LogError(string text)
    {
        try
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PCTuneUp");
            Directory.CreateDirectory(dir);
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            File.AppendAllText(Path.Combine(dir, "errors.log"), DateTime.Now.ToString("s") + "  v" + v.Major + "." + v.Minor + "." + v.Build + "  " +
                System.Text.RegularExpressions.Regex.Replace(text, @"\s+", " ") + Environment.NewLine);
        }
        catch { }
    }
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
                // Errors nobody handled (for example in a button's click handler) would vanish in a window app: keep them in errors.log.
                ps.Streams.Error.DataAdded += (s, e) => {
                    var rec = ps.Streams.Error[e.Index];
                    var at = rec.InvocationInfo != null && rec.InvocationInfo.ScriptLineNumber > 0 ? " [line " + rec.InvocationInfo.ScriptLineNumber + ": " + (rec.InvocationInfo.Line ?? "").Trim() + "]" : "";
                    LogError("unhandled: " + rec.Exception.Message + at);
                };
                try { ps.Invoke(); }
                catch (Exception e)
                {
                    LogError("PC Tune-Up stopped: " + e.Message);
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

# Extra languages (lang\de.tsv, lang\fr.tsv) go into the exe as resources too.
$langRes = @(Get-ChildItem (Join-Path $here 'lang') -Filter *.tsv -ErrorAction SilentlyContinue | ForEach-Object { "/resource:$($_.FullName),$($_.Name)" })
& $csc /nologo /target:winexe /platform:x64 /optimize+ "/out:$exe" "/win32icon:$ico" "/win32manifest:$manifest" `
    "/reference:$sma" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll `
    "/resource:$script,pc-tuneup.ps1" @($langRes) $cs
if ($LASTEXITCODE) { throw "Compile failed (exit $LASTEXITCODE)" }
Remove-Item $work -Recurse -Force
"Built $exe - version $version ({0:N0} KB)" -f ((Get-Item $exe).Length / 1KB)
