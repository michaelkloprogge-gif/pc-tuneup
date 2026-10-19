#Requires -Version 5.1
# PC Tune-Up: speed up and clean any Windows 10/11 PC, whatever the brand.
#   Health    - CPU / RAM / disk / uptime, biggest programs, internet speed test
#   Clean     - temp files, Windows Update cache, crash dumps, Recycle Bin
#   Startup   - turn startup apps on/off (same flags Task Manager uses)
#   Bloatware - find pre-installed junk (OEM tools, trial antivirus, promo apps) and uninstall it
#   Services  - background services from PC makers, updaters and telemetry, with one-click restore
#   Tasks     - scheduled tasks from other companies (updaters, telemetry), switch off/on with undo
#   Programs  - installed programs with size and last use; uninstall several, leftovers to the Recycle Bin
#   Right-click - Explorer menu entries from other programs (leftovers pre-checked), hide with undo
#   Privacy   - Windows ads, tips and tracking settings, switch off with undo
#   Drivers   - devices with problems, and the age of the drivers that matter most
#   Browsers  - extensions, search engine, home page and forced policies (adware) in Chrome/Edge/Brave/Vivaldi/Firefox
#   Network   - Wi-Fi signal, delays, DNS speed, dropped connections, network reset
#   Gaming    - which graphics card a running game uses, what else is busy, Game Mode / recording / GPU settings
#   Search    - Ctrl+F finds pages, settings and rows on every page
#   Battery   - wear, wear speed, runtime, charge-limit advice (laptops only)
#   Space savers - hibernation file, reserved storage, OneDrive copies, Compact OS, Storage Sense (with undo)
#   Disk      - find the folders eating your drive
#   Updates   - outdated programs, updated through winget
#   Security  - Windows support status, Windows 11 readiness, antivirus, firewall, encryption, Secure Boot, TPM...
#   Stability - crashes, freezes, blue screens and errors from the last 30 days, with one-click fixes
#   Backup    - are Desktop/Documents/Pictures in the cloud, File History, backup programs, restore points
#   Upgrades  - memory / drive / battery upgrade options with the exact spec to buy
#   History   - every change, with undo
# Every change is logged to %LOCALAPPDATA%\PCTuneUp\changes.log. Anything listed
# in %LOCALAPPDATA%\PCTuneUp\keep.txt is never flagged or changed.
# Run PC-TuneUp.exe (this script embedded; rebuild with build-exe.ps1 after
# editing) or PC-TuneUp.cmd. The exe is a single file you can copy to any PC.
# Release a new version: bump $AppVersion, then .\publish-release.ps1 -Notes "...".

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# Tell Windows this app scales itself, so it is drawn sharp at 125%/150% instead of being stretched (blurry).
# Must happen before the first window is created. PC-TuneUp.exe already contains these functions (no compiling
# at start-up, which costs about half a second); the plain script compiles them itself.
if (-not ('PcTuneUp.Native' -as [type])) { Add-Type -Namespace PcTuneUp -Name Native -ErrorAction SilentlyContinue -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h, int attr, ref int value, int size);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(System.IntPtr h, string app, string idList);
[DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr h, int msg, System.IntPtr w, System.IntPtr l);
'@ }
# Paints the empty end of a dark list header (Windows draws it light). The exe has it too; keep both copies in step.
function Get-HeaderFillType {
    if (-not ('PcTuneUp.HeaderFill' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Windows.Forms;
namespace PcTuneUp
{
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
'@
    }
    'PcTuneUp.HeaderFill' -as [type]
}
$script:HeaderFills = New-Object Collections.ArrayList   # keeps the hooks alive
try { [void][PcTuneUp.Native]::SetProcessDPIAware() } catch { }
[Windows.Forms.Application]::EnableVisualStyles()
$DpiScale = try { [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96 } catch { 1 }
function Px([double]$Pixels) { [int][Math]::Round($Pixels * $DpiScale) }   # for sizes WinForms doesn't scale itself

# Command line (PC-TuneUp.exe /fix /report[:file] /auto /install /uninstall /?). The exe host passes $AppArgs.
$CliArgs = if ($AppArgs) { @($AppArgs) } else { @($args) }
$Cli = @{ Fix = $false; Report = $null; Help = $false; Install = $false; Uninstall = $false; Auto = $false }
foreach ($a in $CliArgs) {
    switch -Regex ("$a") {
        '^[/-](\?|h|help)$' { $Cli.Help = $true }
        '^[/-]fix$' { $Cli.Fix = $true }
        '^[/-]auto$' { $Cli.Auto = $true }   # the scheduled maintenance run: no window, a notification at the end
        '^[/-]report(:(.+))?$' { $Cli.Report = "$($Matches[2])" }
        '^[/-]install$' { $Cli.Install = $true }
        '^[/-]uninstall$' { $Cli.Uninstall = $true }
    }
}
$CliMode = $Cli.Help -or $Cli.Fix -or $Cli.Auto -or ($null -ne $Cli.Report)

$AppVersion = '1.22.0'                 # bump for every release; publish-release.ps1 tags it as v<version>
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
$HistoryFile = Join-Path $DataDir 'history.jsonl'
$ErrorLogFile = Join-Path $DataDir 'errors.log'      # problems inside PC Tune-Up itself; "Save report" includes recent ones
$script:ErrorsThisRun = 0
function Write-AppError([string]$Where, $Err) {
    try {
        $msg = if ($Err -is [Management.Automation.ErrorRecord]) {
            $at = if ($Err.InvocationInfo -and $Err.InvocationInfo.ScriptLineNumber) { " [line $($Err.InvocationInfo.ScriptLineNumber): $("$($Err.InvocationInfo.Line)".Trim())]" } else { '' }
            "$($Err.Exception.Message)$at"
        } else { "$Err" }
        Add-Content -Path $ErrorLogFile -Value ('{0:s}  v{1}  {2}: {3}' -f (Get-Date), $AppVersion, $Where, ($msg -replace '\s+', ' ')) -Encoding UTF8
        if ((Get-Item -LiteralPath $ErrorLogFile).Length -gt 256KB) { Set-Content -Path $ErrorLogFile -Value @(Get-Content $ErrorLogFile -Tail 500) -Encoding UTF8 }
        $script:ErrorsThisRun++
    } catch { }
}
function Get-AppErrors([int]$Days = 14) {
    if (-not (Test-Path $ErrorLogFile)) { return }
    $since = (Get-Date).AddDays(-$Days).ToString('s')
    Get-Content $ErrorLogFile -Encoding UTF8 -Tail 300 | Where-Object { $_.Length -ge 19 -and $_.Substring(0, 19) -ge $since }
}   # one JSON entry per change; drives the History tab
$SettingsFile = Join-Path $DataDir 'settings.json'
$Settings = [ordered]@{ Language = 'auto'; Theme = 'system'; CheckUpdates = $true; RestorePoints = $true; AskedInstall = $false; AutoMaintenance = 'off'; LastAuto = ''; AutoNotify = 'changes'; TourShown = $false; View = '' }
if (Test-Path $SettingsFile) {
    try { (Get-Content $SettingsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { if ($Settings.Contains($_.Name)) { $Settings[$_.Name] = $_.Value } } } catch { }
}
function Save-Settings { $Settings | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8 }
# ---------------------------------------------------------------------------
# Language. Code and data stay English; T() translates text on its way to the screen.
# Table: English <TAB> Dutch, one per line; {0}, {1}... stand for values filled in at run time.
# ---------------------------------------------------------------------------
$Lang = switch ($Settings.Language) { { $_ -in 'nl', 'en', 'de', 'fr', 'es', 'it', 'pl' } { $_ } default { $w = (Get-UICulture).TwoLetterISOLanguageName; if ($w -in 'nl', 'de', 'fr', 'es', 'it', 'pl') { $w } else { 'en' } } }
$NLTable = @'
Health	Gezondheid
Clean	Opruimen
Startup	Opstarten
Bloatware	Bloatware
Services	Services
Disk	Schijf
Updates	Updates
Security	Beveiliging
Stability	Stabiliteit
Upgrades	Uitbreiden
History	Geschiedenis
Settings	Instellingen
CLEAN UP	OPRUIMEN
CHECK	CONTROLEREN
MORE	MEER
{0}  ({1})	{0}  ({1})
Version {0}	Versie {0}
Limited mode	Beperkte modus
Limited mode - some fixes need administrator rights.	Beperkte modus - sommige oplossingen hebben beheerdersrechten nodig.
Some fixes need administrator rights.	Sommige oplossingen hebben beheerdersrechten nodig.
Restart as admin	Opnieuw als beheerder
Restart as administrator	Opnieuw starten als beheerder
Cancel	Annuleren
Stopping...	Stoppen...
{0}      ({1} more waiting)	{0}      (nog {1} in de wachtrij)
{0}: {1}	{0}: {1}
How the PC is doing right now. "Fix my PC" runs all the safe fixes in one go - it shows you the list first.	Hoe het nu met de pc gaat. "Pc repareren" voert alle veilige oplossingen in één keer uit - je ziet eerst de lijst.
Fix my PC	Pc repareren
Fixing...	Bezig...
Refresh	Vernieuwen
Speed test	Snelheidstest
Windows Update	Windows Update
Save report	Rapport opslaan
Change log	Wijzigingslog
Keep list	Bewaarlijst
This PC	Deze pc
CPU load	Processorbelasting
Memory	Geheugen
Uptime	Aan sinds
Power	Energie
Drive	Schijf
Battery	Accu
Disk {0}	Schijf {0}
{0} GB free of {1} GB ({2}% used)	{0} GB vrij van {1} GB ({2}% in gebruik)
{0} free of {1} ({2}% free)	{0} vrij van {1} ({2}% vrij)
{0}d {1}h {2}m	{0}d {1}u {2}m
holds {0}% of its original charge	houdt nog {0}% van de oorspronkelijke lading vast
last Windows update {0} day(s) ago	laatste Windows-update {0} dag(en) geleden
last Windows update {0} day(s) ago - restart needed to finish	laatste Windows-update {0} dag(en) geleden - herstart nodig om af te ronden
could not read update history	updategeschiedenis kon niet worden gelezen
{0} plan	schema {0}
{0} plan, {1} mode	schema {0}, modus {1}
{0} plan, plugged in	schema {0}, aangesloten op netstroom
{0} plan, on battery	schema {0}, op de accu
{0} plan, {1} mode, plugged in	schema {0}, modus {1}, aangesloten op netstroom
{0} plan, {1} mode, on battery	schema {0}, modus {1}, op de accu
Balanced	Gebalanceerd
Power saver	Energiebesparing
High performance	Hoge prestaties
best power efficiency	beste energie-efficiëntie
better performance	betere prestaties
best performance	beste prestaties
{0} ({1} {2}) - Healthy	{0} ({1} {2}) - in orde
{0} ({1} {2}) - Healthy, {3}% worn	{0} ({1} {2}) - in orde, {3}% versleten
Checking drive, battery and updates...	Schijf, accu en updates controleren...
Internet:  not tested yet - click Speed test	Internet:  nog niet getest - klik op Snelheidstest
Internet:  testing... (about 10 seconds)	Internet:  bezig met testen... (ongeveer 10 seconden)
Internet:  {0} Mbps download	Internet:  {0} Mbps download
Internet:  {0} Mbps download, {1} ms ping	Internet:  {0} Mbps download, {1} ms ping
Internet:  {0} Mbps download, {1} ms ping   (a VPN is running - it can lower this)	Internet:  {0} Mbps download, {1} ms ping   (er draait een VPN - dat kan de snelheid verlagen)
Internet:  download failed - {0}	Internet:  download mislukt - {0}
Programs using the most memory	Programma's die het meeste geheugen gebruiken
Program	Programma
Memory (MB)	Geheugen (MB)
Processes	Processen
Drive '{0}' reports '{1}' - back up your files now and have the drive checked.	Schijf '{0}' meldt '{1}' - maak nu een back-up van je bestanden en laat de schijf nakijken.
The battery only holds {0}% of its original charge - short battery life is the battery wearing out, not the PC. A new battery fixes it.	De accu houdt nog maar {0}% van de oorspronkelijke lading vast - een korte accuduur komt door slijtage van de accu, niet door de pc. Een nieuwe accu lost het op.
Windows hasn't installed an update in {0} days - click Windows Update and check for updates.	Windows heeft al {0} dagen geen update geïnstalleerd - klik op Windows Update en zoek naar updates.
Windows is waiting for a restart to finish installing updates - restart when you can.	Windows wacht op een herstart om updates af te ronden - start opnieuw op wanneer het uitkomt.
Memory is {0}% full, which slows everything down - closing {1} ({2} MB) would help most.	Het geheugen is voor {0}% vol, en dat vertraagt alles - {1} sluiten ({2} MB) helpt het meest.
Drive {0} is getting full ({1}% free) - use Fix my PC, then the Clean and Disk tabs.	Schijf {0} raakt vol ({1}% vrij) - gebruik Pc repareren en daarna Opruimen en Schijf.
The PC is plugged in but set to save energy - set Power mode to Balanced in Settings > System > Power for more speed.	De pc zit aan de netstroom maar staat op energie besparen - zet de energiemodus op Gebalanceerd in Instellingen > Systeem > Energie voor meer snelheid.
The PC hasn't restarted in {0} days - a restart clears out a lot of slowness.	De pc is al {0} dagen niet opnieuw opgestart - een herstart verhelpt veel traagheid.
Stability: {0} ({1}x) - see the Stability tab.	Stabiliteit: {0} ({1}x) - zie Stabiliteit.
Security: {0} problem(s) - see the Security tab.	Beveiliging: {0} probleem/problemen - zie Beveiliging.
{0} program update(s) available - see the Updates tab.	{0} programma-update(s) beschikbaar - zie Updates.
Deletes junk Windows and apps re-create on their own. Files changed in the last 24 hours and files in use are skipped. Browser caches are only cleaned while that browser is closed.	Verwijdert rommel die Windows en apps zelf opnieuw aanmaken. Bestanden die de afgelopen 24 uur zijn gewijzigd of in gebruik zijn, worden overgeslagen. Browsercaches worden alleen opgeruimd als die browser dicht is.
Scan	Scannen
Clean checked items	Aangevinkte items opruimen
Open Windows Disk Cleanup	Windows Schijfopruiming openen
What	Wat
Size	Grootte
Files	Bestanden
Note	Opmerking
Your temp files	Je tijdelijke bestanden
Windows temp files	Tijdelijke Windows-bestanden
Windows Update download cache	Downloadcache van Windows Update
App crash dumps	Crashgegevens van apps
Windows error reports	Windows-foutrapporten
Chrome cache	Chrome-cache
Edge cache	Edge-cache
Brave cache	Brave-cache
Firefox cache	Firefox-cache
Previous Windows installation (Windows.old)	Vorige Windows-installatie (Windows.old)
Old Windows update files	Oude Windows-updatebestanden
Old driver packages	Oude stuurprogrammapakketten
Delivery Optimization cache	Cache voor Delivery Optimization
Windows upgrade leftovers	Restanten van Windows-upgrades
Thumbnail cache	Miniaturencache
Recycle Bin	Prullenbak
needs administrator	beheerder nodig
permanently empties it	maakt hem definitief leeg
removes the option to go back to your old Windows version	je kunt daarna niet meer terug naar je oude Windows-versie
Windows works out the size	Windows berekent de grootte
keeps the drivers in use now	houdt de stuurprogramma's die nu in gebruik zijn
update pieces shared with other PCs	updatestukjes die met andere pc's worden gedeeld
{0} is open - close it to clean this	{0} is geopend - sluit het om dit op te ruimen
Chrome is open - close it to clean this	Chrome is geopend - sluit het om dit op te ruimen
Edge is open - close it to clean this	Edge is geopend - sluit het om dit op te ruimen
Firefox is open - close it to clean this	Firefox is geopend - sluit het om dit op te ruimen
Checked items add up to about {0}.	De aangevinkte items zijn samen ongeveer {0}.
Scanning...	Bezig met scannen...
Cleaning...	Bezig met opruimen...
Skipped because the browser is open: {0}	Overgeslagen omdat de browser geopend is: {0}
Nothing to clean - check at least one item (admin-only items need "Restart as administrator").	Niets om op te ruimen - vink minstens één item aan (items voor beheerders vragen om "Opnieuw starten als beheerder").
Windows Disk Cleanup will run for the Windows items - this can take several minutes.	Voor de Windows-items draait Windows Schijfopruiming - dat kan enkele minuten duren.
Delete the junk in:	De rommel verwijderen in:
This can't be undone (it's all re-creatable).	Dit kan niet ongedaan worden gemaakt (alles wordt vanzelf opnieuw aangemaakt).
freed {0}, {1} in-use files skipped	{0} vrijgemaakt, {1} bestanden in gebruik overgeslagen
Freed {0}. {1} files were in use and left alone.	{0} vrijgemaakt. {1} bestanden waren in gebruik en zijn blijven staan.
freed {0} (Fix my PC)	{0} vrijgemaakt (Pc repareren)
Checked apps start when you sign in. Uncheck to stop them auto-starting (the app itself stays installed) and click Apply. Same switch as Task Manager > Startup.	Aangevinkte apps starten als je je aanmeldt. Vink uit om automatisch starten te stoppen (de app blijft geïnstalleerd) en klik op Wijzigingen toepassen. Dezelfde schakelaar als Taakbeheer > Opstarten.
Reload	Opnieuw laden
Apply changes	Wijzigingen toepassen
Open Task Manager	Taakbeheer openen
App	App
For	Voor
Advice	Advies
Command	Opdracht
You	Jij
All users	Alle gebruikers
keep (your keep list)	houden (je bewaarlijst)
keep (security/VPN/drivers)	houden (beveiliging/VPN/stuurprogramma's)
safe to turn off	veilig om uit te zetten
{0} startup apps, {1} turned on.	{0} opstart-apps, {1} ingeschakeld.
{0} starting with Windows ({1})	{0} met Windows starten ({1})
allowed starting with Windows ({0})	mag met Windows starten ({0})
stopped starting with Windows ({0})	start niet meer met Windows ({0})
{0} change(s) saved. They take effect next time you sign in.	{0} wijziging(en) opgeslagen. Ze gaan in als je je de volgende keer aanmeldt.
Couldn't change (needs administrator): {0}	Kon niet wijzigen (beheerder nodig): {0}
Pre-installed extras found on this PC. Junk is pre-checked; Optional means fine to remove if you never use it. Uninstalling is permanent (reinstall from the Store or maker's site).	Vooraf geïnstalleerde extra's op deze pc. Rommel is al aangevinkt; Optioneel betekent: prima om weg te halen als je het nooit gebruikt. Verwijderen is definitief (opnieuw installeren via de Store of de site van de fabrikant).
Rescan	Opnieuw scannen
Uninstall checked	Aangevinkte verwijderen
Create restore point	Herstelpunt maken
Open Settings > Apps	Instellingen > Apps openen
Name	Naam
Type	Type
Category	Categorie
Why	Waarom
Publisher	Uitgever
Store app	Store-app
Junk	Rommel
Optional	Optioneel
Trial AV	Proef-antivirus
cleaner / driver-updater / adware - Windows does this itself	opschoner / driver-updater / adware - Windows doet dit zelf
pre-installed promo / trial	vooraf geïnstalleerde reclame / proefversie
antivirus - remove if you did not pay for it; Windows Security takes over	antivirus - verwijder het als je er niet voor betaald hebt; Windows-beveiliging neemt het over
pre-installed game / ad	vooraf geïnstalleerde game / reclame
pre-installed promo app	vooraf geïnstalleerde reclame-app
pre-installed app - remove if you do not use it	vooraf geïnstalleerde app - verwijder het als je het niet gebruikt
Windows extra - reinstall from the Store any time	Windows-extraatje - altijd opnieuw te installeren via de Store
PC maker promo / registration / telemetry	reclame / registratie / telemetrie van de pc-fabrikant
Dell utility - get drivers from dell.com/support when needed	Dell-hulpprogramma - haal stuurprogramma's van dell.com/support als je ze nodig hebt
HP utility - get drivers from support.hp.com when needed	HP-hulpprogramma - haal stuurprogramma's van support.hp.com als je ze nodig hebt
Lenovo utility (Vantage also sets battery charge limits - keep it if you use that)	Lenovo-hulpprogramma (Vantage stelt ook laadlimieten voor de accu in - houd het als je dat gebruikt)
ASUS utility (Armoury Crate controls fans/RGB on gaming models)	ASUS-hulpprogramma (Armoury Crate regelt ventilatoren/RGB op gamingmodellen)
Acer utility	Acer-hulpprogramma
MSI utility (controls fans/RGB on gaming models)	MSI-hulpprogramma (regelt ventilatoren/RGB op gamingmodellen)
driver updater / network tweaker - Windows Update covers drivers	driver-updater / netwerkversneller - Windows Update regelt stuurprogramma's al
pre-installed media software	vooraf geïnstalleerde mediasoftware
removed	verwijderd
exit code {0}	afsluitcode {0}
uninstaller closed (exit code {0})	verwijderprogramma gesloten (afsluitcode {0})
Looking for bloatware...	Zoeken naar bloatware...
Found {0} item(s). Check what you want gone and click Uninstall.	{0} item(s) gevonden. Vink aan wat weg mag en klik op Aangevinkte verwijderen.
No known bloatware found - nice and clean.	Geen bekende bloatware gevonden - netjes.
Creating a restore point (can take a minute)...	Herstelpunt maken (kan een minuut duren)...
Restore point created (Windows skips it if one was made in the last 24 hours).	Herstelpunt gemaakt (Windows slaat het over als er de afgelopen 24 uur al een is gemaakt).
Restore point failed: {0} - System Protection may be off for C:.	Herstelpunt mislukt: {0} - Systeembeveiliging staat misschien uit voor C:.
Check at least one item first.	Vink eerst minstens één item aan.
Uninstall these {0} item(s)?	Deze {0} item(s) verwijderen?
Some uninstallers open their own window or ask for permission - follow along. This can't be undone here; you'd reinstall from the Store or the maker's website.	Sommige verwijderprogramma's openen een eigen venster of vragen om toestemming - volg de stappen. Dit kan hier niet ongedaan worden gemaakt; je installeert het dan opnieuw via de Store of de site van de fabrikant.
Uninstalling... (watch for uninstaller windows)	Bezig met verwijderen... (let op vensters van verwijderprogramma's)
Done. {0} of {1} uninstalled.	Klaar. {0} van {1} verwijderd.
Problems:	Problemen:
Non-Microsoft background services. Known bloat is listed first; "review" rows are other third-party services that start with Windows - only change those if you know what they are.	Achtergrondservices die niet van Microsoft zijn. Bekende bloat staat bovenaan; rijen met "controleren" zijn andere services die met Windows starten - wijzig die alleen als je weet wat ze doen.
Apply suggestion to checked	Advies toepassen op aangevinkte
Set checked to Manual	Aangevinkte op Handmatig zetten
Restore checked	Aangevinkte herstellen
Service	Service
What it is	Wat het is
Company	Bedrijf
Starts	Start
Running	Actief
Stopped	Gestopt
Suggested	Advies
Original	Oorspronkelijk
Automatic	Automatisch
Manual	Handmatig
Disabled	Uitgeschakeld
Looking at services...	Services bekijken...
{0}  (review: {1})	{0}  (controleren: {1})
third-party, starts with Windows	van een andere maker, start met Windows
on your keep list	op je bewaarlijst
changed by PC Tune-Up	gewijzigd door PC Tune-Up
looks important (security/driver/VPN)	lijkt belangrijk (beveiliging/stuurprogramma/VPN)
looks like an updater or telemetry	lijkt een updater of telemetrie
View only - restart as administrator to change services. {0} could be trimmed.	Alleen bekijken - start opnieuw als beheerder om services te wijzigen. {0} kunnen worden ingeperkt.
{0} service(s) could be trimmed. Grey rows are already done.	{0} service(s) kunnen worden ingeperkt. Grijze rijen zijn al gedaan.
Nothing left to trim. Review rows are shown for information.	Niets meer om in te perken. Rijen met "controleren" staan er ter informatie.
{0} service(s) updated.	{0} service(s) bijgewerkt.
{0} service(s) updated. {1} were already set that way or had no suggestion (use 'Set checked to Manual').	{0} service(s) bijgewerkt. {1} stonden al zo of hadden geen advies (gebruik 'Aangevinkte op Handmatig zetten').
Failed:	Mislukt:
Dell SupportAssist	Dell SupportAssist
Dell app installer	Dell-app-installatieprogramma
Dell telemetry	Dell-telemetrie
HP telemetry	HP-telemetrie
HP support helper	HP-ondersteuningshulp
HP promo	HP-reclame
Lenovo Vantage (starts when opened)	Lenovo Vantage (start als je het opent)
Lenovo telemetry	Lenovo-telemetrie
ASUS phone link	ASUS-telefoonkoppeling
ASUS updater	ASUS-updater
ASUS diagnostics	ASUS-diagnose
MyASUS helper	MyASUS-hulp
MSI utility	MSI-hulpprogramma
Intel telemetry	Intel-telemetrie
Intel driver updater	Intel-driver-updater
NVIDIA telemetry	NVIDIA-telemetrie
Razer game scanner	Razer-gamescanner
Adobe updater	Adobe-updater
Adobe licence checker	Adobe-licentiecontrole
Google updater (Chrome still updates when open)	Google-updater (Chrome werkt zichzelf nog steeds bij als het open is)
Edge updater (Edge still updates when open)	Edge-updater (Edge werkt zichzelf nog steeds bij als het open is)
Brave updater	Brave-updater
Dropbox updater	Dropbox-updater
EA Origin helper	EA Origin-hulp
Wondershare helper	Wondershare-hulp
McAfee promo	McAfee-reclame
{0} - {1}	{0} - {1}
Find what is filling the drive. Pick a place and Scan; double-click a row to look inside it. This only looks - it never deletes.	Zoek uit wat de schijf vult. Kies een plek en klik op Scannen; dubbelklik op een rij om erin te kijken. Dit kijkt alleen - er wordt nooit iets verwijderd.
Browse...	Bladeren...
Up	Omhoog
Open in Explorer	Openen in Verkenner
Folder	Map
Share	Aandeel
Quick pick...	Snel kiezen...
Your user folder	Je gebruikersmap
Downloads	Downloads
Steam games	Steam-games
Epic games	Epic-games
Program Files	Program Files
Program Files (x86)	Program Files (x86)
Whole C: drive (slow)	Hele C:-schijf (traag)
(files directly in this folder)	(bestanden direct in deze map)
Folder not found:	Map niet gevonden:
Scanning... big folders like C:\ can take a few minutes.	Bezig met scannen... grote mappen zoals C:\ kunnen enkele minuten duren.
Total: {0}.	Totaal: {0}.
Total: {0}.  Uninstall games/programs from their launcher or Settings > Apps, not by deleting folders.	Totaal: {0}.  Verwijder games/programma's via hun launcher of Instellingen > Apps, niet door mappen te wissen.
Programs with a newer version available, via winget (built into Windows). Small updates are pre-checked; big version jumps, self-updating apps, very large updates and keep-list programs are not. Close a program before updating it.	Programma's waarvoor een nieuwere versie is, via winget (ingebouwd in Windows). Kleine updates zijn al aangevinkt; grote versiesprongen, apps die zichzelf bijwerken, heel grote updates en programma's op de bewaarlijst niet. Sluit een programma voordat je het bijwerkt.
Check for updates	Zoeken naar updates
Update checked	Aangevinkte bijwerken
Store app updates	Updates voor Store-apps
Installed	Geïnstalleerd
Available	Beschikbaar
winget took too long - try again later	winget deed er te lang over - probeer het later opnieuw
stopped - you pressed Cancel	gestopt - je klikte op Annuleren
took longer than 30 minutes - stopped	duurde langer dan 30 minuten - gestopt
Asking winget which programs have updates (20-60 seconds)...	winget vragen welke programma's updates hebben (20-60 seconden)...
winget is missing on this PC - install "App Installer" from the Microsoft Store, then check again.	winget ontbreekt op deze pc - installeer "App Installer" uit de Microsoft Store en controleer opnieuw.
on the keep list - update it yourself if you want	op de bewaarlijst - werk het zelf bij als je wilt
updates itself - just restart it	werkt zichzelf bij - start het gewoon opnieuw
very large update - run it when you have time	heel grote update - doe het als je tijd hebt
name cut off by winget - update it from the program itself	naam afgekapt door winget - werk het bij vanuit het programma zelf
major new version - check it still suits you	grote nieuwe versie - controleer of die nog bij je past
small update	kleine update
{0} program(s) can be updated, {1} pre-checked.	{0} programma('s) kunnen worden bijgewerkt, {1} al aangevinkt.
Everything winget knows about is up to date.	Alles wat winget kent is bijgewerkt.
Check at least one program first.	Vink eerst minstens één programma aan.
Update these {0} program(s)?	Deze {0} programma('s) bijwerken?
Close them first. Some show a permission prompt - click Yes. This can take a few minutes.	Sluit ze eerst. Sommige vragen om toestemming - klik op Ja. Dit kan een paar minuten duren.
Updating {0} program(s)... watch for permission prompts.	{0} programma('s) bijwerken... let op vragen om toestemming.
{0} -> {1}: updated	{0} -> {1}: bijgewerkt
{0} -> {1}: failed - {2}	{0} -> {1}: mislukt - {2}
{0} of {1} program(s) updated.	{0} van {1} programma('s) bijgewerkt.
Not updated (often because the program was open - close it and try again):	Niet bijgewerkt (vaak omdat het programma open was - sluit het en probeer opnieuw):
Is this PC protected? Green is fine, orange is worth a look, red needs fixing. Double-click a row (or select it and click Open setting) to go to the right Windows setting.	Is deze pc beschermd? Groen is goed, oranje is het bekijken waard, rood moet worden opgelost. Dubbelklik op een rij (of selecteer hem en klik op Instelling openen) om naar de juiste Windows-instelling te gaan.
Check again	Opnieuw controleren
Open setting	Instelling openen
Open Windows Security	Windows-beveiliging openen
Check	Controle
Status	Status
Result	Resultaat
What to do	Wat te doen
Problem	Probleem
Warning	Waarschuwing
Info	Info
OK	OK
Windows version	Windows-versie
{0} (long-term edition)	{0} (langetermijneditie)
Long-term editions get security updates for years. Nothing to do.	Langetermijnedities krijgen jarenlang beveiligingsupdates. Niets te doen.
Not a version this check knows. Open Windows Update to see if a newer one is offered.	Deze versie kent de controle niet. Open Windows Update om te zien of er een nieuwere wordt aangeboden.
{0} - no longer supported	{0} - wordt niet meer ondersteund
This Windows 10 version gets no security updates any more. See the Windows 11 check below for your options.	Deze Windows 10-versie krijgt geen beveiligingsupdates meer. Zie de Windows 11-controle hieronder voor je mogelijkheden.
This version gets no more security updates. Open Windows Update and install the newest Windows 11 version (free).	Deze versie krijgt geen beveiligingsupdates meer. Open Windows Update en installeer de nieuwste Windows 11-versie (gratis).
Windows 10 stopped getting security updates. Upgrade to Windows 11 for free if the PC qualifies (see below), sign up for Extended Security Updates, or plan a replacement.	Windows 10 krijgt geen beveiligingsupdates meer. Upgrade gratis naar Windows 11 als de pc geschikt is (zie hieronder), meld je aan voor Extended Security Updates, of plan een vervanger.
{0} - security updates ended {1}	{0} - beveiligingsupdates gestopt op {1}
{0} - security updates end {1}	{0} - beveiligingsupdates stoppen op {1}
Install the newest Windows version from Windows Update before then (free).	Installeer voor die tijd de nieuwste Windows-versie via Windows Update (gratis).
{0} - supported until about {1}	{0} - ondersteund tot ongeveer {1}
{0} - supported until {1}	{0} - ondersteund tot {1}
Nothing to do - Windows Update keeps it patched.	Niets te doen - Windows Update houdt het bij.
Nothing to do.	Niets te doen.
Secure Boot	Beveiligd opstarten
PC starts in old "legacy BIOS" mode	Pc start in de oude "legacy BIOS"-modus
Modern UEFI mode with Secure Boot blocks malware that loads before Windows. Switching needs care (the disk must be converted with MBR2GPT) - get help if unsure.	De moderne UEFI-modus met beveiligd opstarten blokkeert malware die vóór Windows laadt. Overschakelen vraagt zorg (de schijf moet worden omgezet met MBR2GPT) - vraag hulp als je twijfelt.
On	Aan
Off	Uit
Switch Secure Boot on in the firmware (BIOS/UEFI) settings - usually F2, F10 or Del while the PC starts.	Zet beveiligd opstarten aan in de firmware-instellingen (BIOS/UEFI) - meestal F2, F10 of Del tijdens het opstarten.
TPM security chip	TPM-beveiligingschip
TPM {0} present	TPM {0} aanwezig
Old TPM {0}	Oude TPM {0}
Windows 11 needs TPM 2.0. Some PCs can switch to 2.0 with a firmware update from the maker.	Windows 11 heeft TPM 2.0 nodig. Sommige pc's kunnen naar 2.0 met een firmware-update van de fabrikant.
None found	Niet gevonden
Many PCs have one that is switched off - look for TPM, PTT (Intel) or fTPM (AMD) in the firmware settings.	Veel pc's hebben er een die uit staat - zoek naar TPM, PTT (Intel) of fTPM (AMD) in de firmware-instellingen.
Could not check	Kon niet controleren
Run "tpm.msc" to see the TPM status.	Voer "tpm.msc" uit om de TPM-status te zien.
Windows 11 ready?	Klaar voor Windows 11?
No - missing: {0}	Nee - ontbreekt: {0}
If only TPM or Secure Boot is missing, switch them on in the firmware settings and check again. Otherwise: Extended Security Updates for Windows 10, or a new or refurbished PC.	Als alleen TPM of beveiligd opstarten ontbreekt, zet ze aan in de firmware-instellingen en controleer opnieuw. Anders: Extended Security Updates voor Windows 10, of een nieuwe of refurbished pc.
Probably - processor not recognised ({0}); confirm with Microsoft's PC Health Check	Waarschijnlijk - processor niet herkend ({0}); controleer het met Pc-statuscontrole van Microsoft
Yes - this PC can run Windows 11	Ja - deze pc kan Windows 11 draaien
Upgrade for free: Settings > Windows Update > Upgrade to Windows 11. Back up your files first.	Gratis upgraden: Instellingen > Windows Update > Upgraden naar Windows 11. Maak eerst een back-up van je bestanden.
Antivirus	Antivirus
{0} - on and up to date	{0} - aan en bijgewerkt
{0} - on but out of date	{0} - aan maar verouderd
Open it and update it. If that fails, check the internet connection or whether its subscription ran out.	Open het en werk het bij. Lukt dat niet, controleer dan de internetverbinding of het abonnement verlopen is.
{0} - switched off	{0} - uitgeschakeld
Switch it on. If a paid antivirus expired, uninstall it - Microsoft Defender then takes over for free.	Zet het aan. Is een betaalde antivirus verlopen, verwijder hem dan - Microsoft Defender neemt het gratis over.
No antivirus found	Geen antivirus gevonden
Open Windows Security and switch on Microsoft Defender.	Open Windows-beveiliging en zet Microsoft Defender aan.
Firewall	Firewall
Windows Firewall is on	Windows Firewall staat aan
{0} firewall is on	Firewall van {0} staat aan
Windows Firewall is off ({0})	Windows Firewall staat uit ({0})
Switch it on in Windows Security > Firewall & network protection.	Zet hem aan in Windows-beveiliging > Firewall- en netwerkbeveiliging.
Open Windows Security > Firewall & network protection.	Open Windows-beveiliging > Firewall- en netwerkbeveiliging.
Drive encryption	Schijfversleuteling
C: is encrypted (BitLocker / Device encryption)	C: is versleuteld (BitLocker / apparaatversleuteling)
Know where the recovery key is: account.microsoft.com/devices/recoverykey - you need it if the PC ever asks for it.	Weet waar de herstelsleutel is: account.microsoft.com/devices/recoverykey - je hebt hem nodig als de pc er ooit om vraagt.
Encryption is paused	Versleuteling is gepauzeerd
It is usually paused during an update and resumes after a restart. If it stays paused, resume it in BitLocker settings.	Meestal is dat tijdens een update en gaat het na een herstart verder. Blijft het gepauzeerd, hervat het dan in de BitLocker-instellingen.
C: is not encrypted	C: is niet versleuteld
Anyone who steals the laptop can read its files. Turn on Device encryption (Settings > Privacy & security > Device encryption) or BitLocker on Pro. Know where the recovery key is: account.microsoft.com/devices/recoverykey - you need it if the PC ever asks for it.	Wie de laptop steelt, kan de bestanden lezen. Zet apparaatversleuteling aan (Instellingen > Privacy en beveiliging > Apparaatversleuteling) of BitLocker op Pro. Weet waar de herstelsleutel is: account.microsoft.com/devices/recoverykey - je hebt hem nodig als de pc er ooit om vraagt.
Less important for a desktop that stays at home; worth it for business PCs.	Minder belangrijk voor een desktop die thuis blijft; wel zinvol voor zakelijke pc's.
See Settings > Privacy & security > Device encryption.	Zie Instellingen > Privacy en beveiliging > Apparaatversleuteling.
Memory integrity	Geheugenintegriteit
Optional extra protection: Windows Security > Device security > Core isolation. Very old drivers can block it.	Optionele extra bescherming: Windows-beveiliging > Apparaatbeveiliging > Kernisolatie. Heel oude stuurprogramma's kunnen het blokkeren.
User Account Control	Gebruikersaccountbeheer
Off - every program runs with full rights	Uit - elk programma draait met volledige rechten
Search "UAC" in Start, set the slider back to the default level and restart.	Zoek "UAC" in Start, zet de schuifregelaar terug op het standaardniveau en start opnieuw op.
Old file sharing (SMB 1.0)	Oude bestandsdeling (SMB 1.0)
SMB 1.0 is what the WannaCry worm used. Remove it unless a very old NAS or printer needs it: Windows Features > untick "SMB 1.0/CIFS File Sharing Support".	SMB 1.0 is wat de WannaCry-worm gebruikte. Verwijder het tenzij een heel oude NAS of printer het nodig heeft: Windows-onderdelen > vink "Ondersteuning voor SMB 1.0/CIFS-bestandsdeling" uit.
Remote Desktop	Extern bureaublad
On - this PC accepts remote connections	Aan - deze pc accepteert externe verbindingen
Fine if you use it. Otherwise switch it off: Settings > System > Remote Desktop.	Prima als je het gebruikt. Anders uitzetten: Instellingen > Systeem > Extern bureaublad.
Out-of-support software	Software zonder ondersteuning
{0} found: {1}	{0} gevonden: {1}
These no longer get security fixes. Uninstall them in Settings > Apps; old .NET runtimes can go too - a program that still needs one will ask for it.	Deze krijgen geen beveiligingsupdates meer. Verwijder ze via Instellingen > Apps; oude .NET-runtimes mogen ook weg - een programma dat er nog een nodig heeft, vraagt er vanzelf om.
None of the usual suspects (Flash, Java 6/7, QuickTime, Silverlight, old .NET)	Geen van de bekende boosdoeners (Flash, Java 6/7, QuickTime, Silverlight, oude .NET)
Checking security settings...	Beveiligingsinstellingen controleren...
{0} of {1} checks fine.	{0} van {1} controles in orde.
{0} of {1} checks fine, {2} worth a look.	{0} van {1} controles in orde, {2} het bekijken waard.
{0} of {1} checks fine, {2} problem(s).	{0} van {1} controles in orde, {2} probleem/problemen.
{0} of {1} checks fine, {2} problem(s), {3} worth a look.	{0} van {1} controles in orde, {2} probleem/problemen, {3} het bekijken waard.
Couldn't open {0}	Kon {0} niet openen
This one is changed in the firmware (BIOS/UEFI) settings, not in Windows - see "What to do".	Dit wijzig je in de firmware-instellingen (BIOS/UEFI), niet in Windows - zie "Wat te doen".
What to do: {0}	Wat te doen: {0}
What went wrong in the last 30 days according to Windows' own logs - crashes, freezes, blue screens, errors - and what usually fixes it. Click a row for details.	Wat er de afgelopen 30 dagen misging volgens de logboeken van Windows zelf - crashes, vastlopers, blauwe schermen, fouten - en wat het meestal oplost. Klik op een rij voor details.
Open Reliability Monitor	Betrouwbaarheidsmonitor openen
Search selected online	Selectie online opzoeken
Times	Keer
Last	Laatst
App crashes	App-crashes
Freezes	Vastlopers
Blue screens	Blauwe schermen
Sudden shutdowns	Plotseling uitgevallen
Graphics resets	Grafische herstarts
Drive errors	Schijffouten
Hardware errors	Hardwarefouten
Windows Update	Windows Update
Store app updates	Updates voor Store-apps
NVIDIA nView	NVIDIA nView
{0} crashed {1}	{0} liet {1} crashen
{0} crashed	{0} is gecrasht
NVIDIA nView (an old desktop-manager add-on) loads itself into other programs and crashes them. Turn it off: NVIDIA Control Panel > Desktop Management > Disable, or uninstall "NVIDIA nView" in Settings > Apps.	NVIDIA nView (een oude invoegtoepassing voor bureaubladbeheer) laadt zichzelf in andere programma's en laat ze crashen. Zet het uit: NVIDIA-configuratiescherm > Desktop Management > Disable, of verwijder "NVIDIA nView" via Instellingen > Apps.
NVIDIA graphics driver	NVIDIA-grafisch stuurprogramma
Update the NVIDIA driver from nvidia.com or the PC maker's support page (choose a clean install).	Werk het NVIDIA-stuurprogramma bij via nvidia.com of de ondersteuningspagina van de pc-fabrikant (kies een schone installatie).
AMD graphics driver	AMD-grafisch stuurprogramma
Update the AMD graphics driver from amd.com or the PC maker's support page.	Werk het AMD-grafische stuurprogramma bij via amd.com of de ondersteuningspagina van de pc-fabrikant.
Intel graphics driver	Intel-grafisch stuurprogramma
Update the Intel graphics driver (Windows Update > Advanced > Optional updates, or the PC maker's support page).	Werk het Intel-grafische stuurprogramma bij (Windows Update > Geavanceerd > Optionele updates, of de ondersteuningspagina van de pc-fabrikant).
Visual C++ runtime	Visual C++-runtime
Repair "Microsoft Visual C++ Redistributable" in Settings > Apps (Modify > Repair), then update the crashing programs.	Herstel "Microsoft Visual C++ Redistributable" via Instellingen > Apps (Wijzigen > Herstellen) en werk daarna de crashende programma's bij.
an overlay or audio add-on	een overlay of audio-invoegtoepassing
An overlay (Steam, Discord, RivaTuner) or audio enhancer (Nahimic, Sonic Studio) loads into other programs. Update it or switch its overlay off.	Een overlay (Steam, Discord, RivaTuner) of audioverbeteraar (Nahimic, Sonic Studio) laadt zich in andere programma's. Werk hem bij of zet de overlay uit.
Update or reinstall {0}. If it keeps crashing, check the maker's support site (crash point: {1}).	Werk {0} bij of installeer het opnieuw. Blijft het crashen, kijk dan op de ondersteuningssite van de maker (crashpunt: {1}).
{0} stopped responding	{0} reageerde niet meer
If {0} freezes often, update it. Many different programs freezing points to full memory or a slow or failing drive - see the Health tab.	Als {0} vaak vastloopt, werk het dan bij. Lopen veel verschillende programma's vast, dan wijst dat op vol geheugen of een trage of falende schijf - zie Gezondheid.
{0} program(s) froze once ({1})	{0} programma('s) liepen één keer vast ({1})
A one-off freeze is normal. Many different programs freezing points to full memory or a slow or failing drive - see the Health tab.	Eén keer vastlopen is normaal. Lopen veel verschillende programma's vast, dan wijst dat op vol geheugen of een trage of falende schijf - zie Gezondheid.
Windows crashed: {0}	Windows is gecrasht: {0}
Usually caused by {0}. Install driver updates (Windows Update > Advanced options > Optional updates, or the PC maker's support page). If it keeps happening, test the memory: run mdsched.exe.	Meestal veroorzaakt door {0}. Installeer updates voor stuurprogramma's (Windows Update > Geavanceerde opties > Optionele updates, of de ondersteuningspagina van de pc-fabrikant). Blijft het gebeuren, test dan het geheugen: voer mdsched.exe uit.
a driver	een stuurprogramma
memory (RAM) or a driver	het geheugen (RAM) of een stuurprogramma
memory or a driver	het geheugen of een stuurprogramma
the drive or its connection	de schijf of de aansluiting ervan
a driver during sleep or wake-up	een stuurprogramma tijdens slaapstand of ontwaken
a driver (often network or Wi-Fi)	een stuurprogramma (vaak netwerk of wifi)
damaged Windows files or the drive	beschadigde Windows-bestanden of de schijf
the drive	de schijf
the graphics driver	het grafische stuurprogramma
hardware (processor, memory or overheating)	hardware (processor, geheugen of oververhitting)
memory (RAM)	het geheugen (RAM)
a storage or other driver	een opslag- of ander stuurprogramma
a driver or memory	een stuurprogramma of het geheugen
a driver or hardware	een stuurprogramma of hardware
The PC switched off without shutting down properly	De pc ging uit zonder netjes af te sluiten
A power cut, the battery running flat, the power button held down, or overheating. If it happens on its own, check the charger or power supply and clean the fans.	Een stroomstoring, een lege accu, de aan/uit-knop ingedrukt gehouden, of oververhitting. Gebeurt het vanzelf, controleer dan de oplader of voeding en maak de ventilatoren schoon.
The graphics driver stopped responding and recovered	Het grafische stuurprogramma reageerde niet meer en herstelde zich
Update the graphics driver. If it happens in games, check the GPU temperature and stop any overclocking.	Werk het grafische stuurprogramma bij. Gebeurt het in games, controleer dan de GPU-temperatuur en stop met overklokken.
Storage errors ({0})	Opslagfouten ({0})
Back up important files now. Then check drive health on the Health tab and run the drive maker's tool; frequent errors mean the drive or its cable is failing.	Maak nu een back-up van belangrijke bestanden. Controleer daarna de schijfgezondheid op Gezondheid en draai het hulpprogramma van de schijffabrikant; veel fouten betekenen dat de schijf of de kabel het begeeft.
The processor, memory or a PCIe device reported errors	De processor, het geheugen of een PCIe-apparaat meldde fouten
Make sure the PC isn't overheating (clean the fans). If blue screens happen too, test the memory: run mdsched.exe.	Zorg dat de pc niet oververhit raakt (maak de ventilatoren schoon). Komen er ook blauwe schermen voor, test dan het geheugen: voer mdsched.exe uit.
{0} Store app update(s) kept waiting ({1}...)	{0} Store-app-update(s) moesten wachten ({1}...)
Usually because the app was open at the time - they install by themselves later. To force it: Microsoft Store > Library > Get updates.	Meestal omdat de app op dat moment open was - ze installeren later vanzelf. Forceren: Microsoft Store > Bibliotheek > Updates ophalen.
Couldn't install: {0}	Kon niet installeren: {0}
Restart and try Windows Update again. If it keeps failing: Settings > System > Troubleshoot > Other troubleshooters > Windows Update. (Error {0})	Start opnieuw op en probeer Windows Update nog eens. Blijft het mislukken: Instellingen > Systeem > Probleemoplossing > Andere probleemoplossers > Windows Update. (Fout {0})
Reading Windows' logs...	Logboeken van Windows lezen...
Windows rates stability {0} out of 10. {1} kind(s) of trouble in the last 30 days.	Windows geeft de stabiliteit een {0} op 10. {1} soort(en) problemen in de afgelopen 30 dagen.
Windows rates stability {0} out of 10. {1} kind(s) of trouble in the last 30 days, {2} worth fixing.	Windows geeft de stabiliteit een {0} op 10. {1} soort(en) problemen in de afgelopen 30 dagen, {2} het oplossen waard.
Windows rates stability {0} out of 10. Nothing went wrong in the last 30 days.	Windows geeft de stabiliteit een {0} op 10. Er ging niets mis in de afgelopen 30 dagen.
{0} kind(s) of trouble in the last 30 days.	{0} soort(en) problemen in de afgelopen 30 dagen.
{0} kind(s) of trouble in the last 30 days, {1} worth fixing.	{0} soort(en) problemen in de afgelopen 30 dagen, {1} het oplossen waard.
Nothing went wrong in the last 30 days.	Er ging niets mis in de afgelopen 30 dagen.
No crashes, freezes or errors found.	Geen crashes, vastlopers of fouten gevonden.
{0}: {1} - {2} time(s) in 30 days, last on {3}	{0}: {1} - {2} keer in 30 dagen, laatst op {3}
What you could add or replace in this PC, with the specification to buy. Click a row for the full details. Always confirm with the service manual before buying.	Wat je in deze pc kunt toevoegen of vervangen, met de specificatie om te kopen. Klik op een rij voor alle details. Controleer het altijd in de servicehandleiding voordat je iets koopt.
Open support page	Ondersteuningspagina openen
Find service manual	Servicehandleiding zoeken
Find motherboard manual	Handleiding moederbord zoeken
Copy shopping list	Boodschappenlijst kopiëren
Part	Onderdeel
You have now	Wat je nu hebt
Upgrade option	Mogelijke uitbreiding
Worth it?	De moeite waard?
What to buy	Wat te kopen
Memory / disk	Geheugen / schijf
{0} GB memory - this is a virtual machine	{0} GB geheugen - dit is een virtuele machine
Change the VM settings	Instellingen van de VM wijzigen
Nothing to buy - give the virtual machine more memory or disk space in VMware / VirtualBox / Hyper-V settings.	Niets te kopen - geef de virtuele machine meer geheugen of schijfruimte in de instellingen van VMware / VirtualBox / Hyper-V.
Physical upgrades belong to the computer that runs the VM.	Fysieke uitbreidingen horen bij de computer waarop de VM draait.
Not upgradeable	Niet uit te breiden
Nothing to buy - this memory is soldered to the motherboard.	Niets te kopen - dit geheugen is op het moederbord gesoldeerd.
Already at the maximum	Al het maximum
Not needed	Niet nodig
Nothing to buy - {0} GB is the most this PC supports.	Niets te kopen - {0} GB is het maximum voor deze pc.
The firmware reports a maximum of {0} GB.	De firmware meldt een maximum van {0} GB.
Add {0} x {1} GB (total {2} GB)	{0} x {1} GB toevoegen (totaal {2} GB)
Replace with {0} x {1} GB (total {2} GB)	Vervangen door {0} x {1} GB (totaal {2} GB)
Recommended - one module means single-channel; a matching second module roughly doubles memory speed	Aanbevolen - één module betekent single-channel; een tweede, gelijke module verdubbelt ongeveer de geheugensnelheid
Strongly recommended	Sterk aanbevolen
Recommended	Aanbevolen
Recommended - memory is {0}% full right now	Aanbevolen - het geheugen is nu voor {0}% vol
Optional - worth it for virtual machines, big spreadsheets, photo/video/CAD work or many browser tabs	Optioneel - de moeite waard voor virtuele machines, grote spreadsheets, foto/video/CAD-werk of veel browsertabbladen
Replace with an SSD	Vervangen door een SSD
Strongly recommended - the biggest speed-up an older PC can get	Sterk aanbevolen - de grootste versnelling die een oudere pc kan krijgen
Optional - only matters for files on this disk	Optioneel - alleen van belang voor bestanden op deze schijf
Hard disks are 20-50x slower than SSDs at the small reads Windows does all the time.	Harde schijven zijn 20-50x trager dan SSD's bij de kleine leesacties die Windows steeds doet.
Recommended - C: is only {0}% free	Aanbevolen - C: is nog maar voor {0}% vrij
Recommended - small drive	Aanbevolen - kleine schijf
Bigger or second SSD	Grotere of tweede SSD
Windows cannot see empty slots, so check the manual for a free one. Gen4 drives fall back to the slot's speed, so they are always a safe pick.	Windows ziet geen lege sloten, dus controleer de handleiding op een vrij slot. Gen4-schijven passen zich aan de snelheid van het slot aan, dus die zijn altijd een veilige keuze.
External drive	Externe schijf
This PC has a USB4/Thunderbolt port	Deze pc heeft een USB4/Thunderbolt-poort
USB ports	USB-poorten
External SSD	Externe SSD
Optional - no screwdriver needed, good for games, photos and backups	Optioneel - geen schroevendraaier nodig, handig voor games, foto's en back-ups
External NVMe SSD (or an NVMe enclosure) for USB4/Thunderbolt, 1-2 TB: up to ~3,000 MB/s on this PC.	Externe NVMe-SSD (of een NVMe-behuizing) voor USB4/Thunderbolt, 1-2 TB: tot ~3.000 MB/s op deze pc.
USB 3.2 Gen 2 external SSD, 1-2 TB (about 1,000 MB/s) - use a blue or "SS 10" USB port.	Externe USB 3.2 Gen 2-SSD, 1-2 TB (ongeveer 1.000 MB/s) - gebruik een blauwe of "SS 10"-USB-poort.
Use the fastest port: USB4/Thunderbolt (lightning symbol) > USB-C 10 Gbps > blue USB-A.	Gebruik de snelste poort: USB4/Thunderbolt (bliksemsymbool) > USB-C 10 Gbps > blauwe USB-A.
Recommended - battery life is roughly halved	Aanbevolen - de accuduur is ongeveer gehalveerd
{0} Wh {1} battery ({2}), now holds {3}% of its original charge	{0} Wh {1}-accu ({2}), houdt nu nog {3}% van de oorspronkelijke lading vast
Replacement battery	Vervangende accu
Batteries wear with age and charge cycles. A worn battery doesn't slow the PC down, it just runs out sooner.	Accu's slijten door ouderdom en laadcycli. Een versleten accu maakt de pc niet trager, hij is alleen sneller leeg.
Recommended - Wi-Fi 4 is slow and crowded	Aanbevolen - wifi 4 is traag en druk
Optional - faster and steadier on a Wi-Fi 6 router	Optioneel - sneller en stabieler met een wifi 6-router
Optional - check which Wi-Fi standard this card supports	Optioneel - controleer welke wifi-standaard deze kaart ondersteunt
Nothing to buy - this Wi-Fi is already current.	Niets te kopen - deze wifi is al actueel.
Already modern	Al modern
Wi-Fi 6E card	Wifi 6E-kaart
Faster Wi-Fi only helps if your router supports it too.	Snellere wifi helpt alleen als je router het ook ondersteunt.
No Wi-Fi adapter	Geen wifi-adapter
Add Wi-Fi	Wifi toevoegen
Optional - only if you can't use a cable	Optioneel - alleen als je geen kabel kunt gebruiken
A network cable is still the fastest and steadiest connection.	Een netwerkkabel is nog steeds de snelste en stabielste verbinding.
Not read - Windows didn't answer in time (busy with a game?). Click Refresh later.	Niet gelezen - Windows antwoordde niet op tijd (bezig met een game?). Klik later op Vernieuwen.
Processor	Processor
Nothing to buy - laptop processors are soldered to the motherboard.	Niets te kopen - laptopprocessors zijn op het moederbord gesoldeerd.
If the processor is too slow, the upgrade path is a new laptop.	Is de processor te traag, dan is een nieuwe laptop de enige uitbreiding.
Graphics	Grafisch
Nothing to buy - laptop graphics are soldered.	Niets te kopen - laptopgrafische chips zijn gesoldeerd.
An external graphics box over USB4/Thunderbolt is possible but costly.	Een externe grafische kast via USB4/Thunderbolt kan, maar is duur.
Depends on the motherboard	Hangt af van het moederbord
Rarely worth it	Zelden de moeite waard
A new processor only fits the same socket and often needs a BIOS update first.	Een nieuwe processor past alleen in dezelfde socket en heeft vaak eerst een BIOS-update nodig.
Add a graphics card	Een videokaart toevoegen
Faster graphics card	Snellere videokaart
Optional - for gaming, video editing or 3D	Optioneel - voor gamen, videobewerking of 3D
Depends on use	Hangt af van het gebruik
Needs a free PCIe x16 slot, enough power-supply wattage and connectors, and room in the case - check all three first.	Heeft een vrij PCIe x16-slot nodig, genoeg vermogen en aansluitingen op de voeding, en ruimte in de kast - controleer eerst alle drie.
Office PCs from HP, Dell and Lenovo often have small power supplies; a low-profile card that needs no power cable is the safe choice there.	Kantoor-pc's van HP, Dell en Lenovo hebben vaak een kleine voeding; een low-profile kaart zonder voedingskabel is daar de veilige keuze.
Looking at this PC's hardware...	De hardware van deze pc bekijken...
Could not read the hardware details.	De hardwaregegevens konden niet worden gelezen.
Nothing worth upgrading was found.	Er is niets gevonden dat het uitbreiden waard is.
Shopping list copied - paste it into an email, a note or a shop's chat.	Boodschappenlijst gekopieerd - plak hem in een e-mail, een notitie of de chat van een winkel.
The serial number ({0}) is copied - paste it into the support page's search box to see this exact PC's parts.	Het serienummer ({0}) is gekopieerd - plak het in het zoekvak van de ondersteuningspagina om de onderdelen van precies deze pc te zien.
Worth it? {0}	De moeite waard? {0}
You have now: {0}	Wat je nu hebt: {0}
What to buy: {0}	Wat te kopen: {0}
Good to know: {0}	Goed om te weten: {0}
Every change PC Tune-Up made on this PC, newest first. Check rows and click Undo to put them back. Cleaned files and uninstalled programs can't be undone; removed Store apps can be reinstalled.	Elke wijziging die PC Tune-Up op deze pc heeft gemaakt, nieuwste eerst. Vink rijen aan en klik op Aangevinkte ongedaan maken om ze terug te zetten. Opgeruimde bestanden en verwijderde programma's kunnen niet terug; verwijderde Store-apps kun je opnieuw installeren.
Undo checked	Aangevinkte ongedaan maken
Open text log	Tekstlog openen
When	Wanneer
Item	Item
Change	Wijziging
Undo	Ongedaan maken
undone	ongedaan gemaakt
reinstall from Store	opnieuw installeren via de Store
can undo	kan ongedaan worden
Update	Update
Uninstall	Verwijderd
Restore point	Herstelpunt
created	gemaakt
created before {0}	gemaakt vóór {0}
Fix my PC	Pc repareren
{0} change(s) recorded, {1} can be undone.	{0} wijziging(en) vastgelegd, {1} kunnen ongedaan worden gemaakt.
No changes yet. (Changes from before this version are in the text log.)	Nog geen wijzigingen. (Wijzigingen van voor deze versie staan in het tekstlog.)
Check one or more rows that say "can undo" first.	Vink eerst een of meer rijen aan met "kan ongedaan worden".
Undoing service changes needs administrator rights - use "Restart as administrator" first.	Wijzigingen aan services ongedaan maken vraagt beheerdersrechten - gebruik eerst "Opnieuw starten als beheerder".
Undo these changes?	Deze wijzigingen ongedaan maken?
allowed to start with Windows again	mag weer met Windows starten
stopped starting with Windows again	start weer niet meer met Windows
service back to {0}	service terug op {0}
{0} change(s) undone.	{0} wijziging(en) ongedaan gemaakt.
{0} change(s) undone. Startup changes take effect next time you sign in.	{0} wijziging(en) ongedaan gemaakt. Wijzigingen aan opstarten gaan in als je je de volgende keer aanmeldt.
How PC Tune-Up looks and behaves, where its files are, and what it is. Changes are saved straight away.	Hoe PC Tune-Up eruitziet en werkt, waar de bestanden staan, en wat het is. Wijzigingen worden meteen opgeslagen.
Language	Taal
Takes effect when PC Tune-Up restarts.	Gaat in als PC Tune-Up opnieuw start.
Automatic (Windows language)	Automatisch (taal van Windows)
Restart now	Nu opnieuw starten
Theme	Thema
Light, dark, or the same as Windows. Takes effect when PC Tune-Up restarts.	Licht, donker, of hetzelfde als Windows. Gaat in als PC Tune-Up opnieuw start.
Same as Windows	Hetzelfde als Windows
Light	Licht
Dark	Donker
You have version {0}. New versions come from github.com/{1} and are checked against GitHub's checksum before they are installed.	Je hebt versie {0}. Nieuwe versies komen van github.com/{1} en worden gecontroleerd met de controlesom van GitHub voordat ze worden geïnstalleerd.
Check for updates when PC Tune-Up starts	Zoeken naar updates als PC Tune-Up start
Check for updates now	Nu zoeken naar updates
Safety	Veiligheid
A restore point lets Windows roll the whole PC back to before a change (Settings > System > Recovery, or search "restore point"). Windows makes at most one per day.	Met een herstelpunt zet Windows de hele pc terug naar vóór een wijziging (Instellingen > Systeem > Herstel, of zoek op "herstelpunt"). Windows maakt er maximaal één per dag.
Create a restore point before Fix my PC, uninstalling and service changes (needs administrator)	Een herstelpunt maken vóór Pc repareren, verwijderen en wijzigingen aan services (beheerder nodig)
Installation	Installatie
Installed for you in {0} - it appears in the Start menu and in Settings > Apps.	Voor jou geïnstalleerd in {0} - het staat in het menu Start en in Instellingen > Apps.
Running from {0} without installing. Install to get a Start-menu entry and uninstall it like any other app (no administrator needed).	Draait vanaf {0} zonder installatie. Installeer het voor een plek in het menu Start en om het te verwijderen zoals elke andere app (geen beheerder nodig).
Running as a PowerShell script (developer mode) - install from PC-TuneUp.exe instead.	Draait als PowerShell-script (ontwikkelaarsmodus) - installeer in plaats daarvan vanuit PC-TuneUp.exe.
Uninstall PC Tune-Up	PC Tune-Up verwijderen
Install on this PC	Op deze pc installeren
Files	Bestanden
Settings, history, the keep list and the change log are kept in {0}.	Instellingen, geschiedenis, de bewaarlijst en het wijzigingslog staan in {0}.
Open data folder	Gegevensmap openen
Command line	Opdrachtregel
For scripts and IT use (use "start /wait" so the window waits for it):	Voor scripts en IT-gebruik (gebruik "start /wait" zodat het venster erop wacht):
About	Over
PC Tune-Up {0} - free and open source (MIT licence). Privacy: everything runs on this PC. The only internet use is the update check (GitHub), the speed test (Cloudflare) and winget's program list; nothing about this PC is sent anywhere.	PC Tune-Up {0} - gratis en open source (MIT-licentie). Privacy: alles draait op deze pc. Internet wordt alleen gebruikt voor de updatecontrole (GitHub), de snelheidstest (Cloudflare) en de programmalijst van winget; er wordt niets over deze pc verstuurd.
Install from PC-TuneUp.exe, not from the script.	Installeer vanuit PC-TuneUp.exe, niet vanuit het script.
Installing failed: {0}	Installeren mislukt: {0}
PC Tune-Up is installed. It is in the Start menu and on the desktop, and you can uninstall it in Settings > Apps.	PC Tune-Up is geïnstalleerd. Het staat in het menu Start en op het bureaublad, en je kunt het verwijderen via Instellingen > Apps.
The installed copy opens now; you can delete the file you started this from.	De geïnstalleerde versie opent nu; je kunt het bestand waarmee je dit startte verwijderen.
Remove PC Tune-Up from this PC?	PC Tune-Up van deze pc verwijderen?
Also delete its settings, keep list and change history?	Ook de instellingen, bewaarlijst en wijzigingsgeschiedenis verwijderen?
PC Tune-Up has been removed.	PC Tune-Up is verwijderd.
Install PC Tune-Up on this PC?	PC Tune-Up op deze pc installeren?
It adds PC Tune-Up to the Start menu and to Settings > Apps (so it can be uninstalled like any app), and it keeps itself up to date. No administrator rights needed.	Het zet PC Tune-Up in het menu Start en in Instellingen > Apps (zodat je het kunt verwijderen zoals elke app), en het houdt zichzelf up-to-date. Geen beheerdersrechten nodig.
You can also do this later in Settings.	Je kunt dit ook later doen via Instellingen.
Still checking services - try again in a few seconds.	Services worden nog gecontroleerd - probeer het over een paar seconden opnieuw.
PC Tune-Up will:	PC Tune-Up gaat:
Clean junk files: {0}	Rommel opruimen: {0}
(skipping {0} - close the browser first to include it)	({0} overslaan - sluit eerst de browser om het mee te nemen)
Stop {0} app(s) starting with Windows: {1}	{0} app(s) niet meer met Windows laten starten: {1}
Set {0} background service(s) to their suggested setting: {1}	{0} achtergrondservice(s) op de aanbevolen instelling zetten: {1}
Create a restore point first	Eerst een herstelpunt maken
Tip: "Restart as admin" first to also clean Windows files and trim background services.	Tip: kies eerst "Opnieuw als beheerder" om ook Windows-bestanden op te ruimen en achtergrondservices in te perken.
Nothing gets uninstalled. Startup and service changes can be undone from the History page.	Er wordt niets verwijderd. Wijzigingen aan opstarten en services kun je ongedaan maken via Geschiedenis.
Done!	Klaar!
Stopped early.	Vroegtijdig gestopt.
Freed {0} of junk files	{0} aan rommel vrijgemaakt
{0} app(s) no longer start with Windows	{0} app(s) starten niet meer met Windows
{0} background service(s) trimmed	{0} achtergrondservice(s) ingeperkt
{0} junk app(s) found - see the Bloatware page if you want them gone	{0} rommel-app(s) gevonden - zie Bloatware als je ze weg wilt hebben
Startup changes take effect next time you sign in. Undo anything from the History page.	Wijzigingen aan opstarten gaan in als je je de volgende keer aanmeldt. Maak alles ongedaan via Geschiedenis.
Updates are not set up in this build.	Updates zijn in deze versie niet ingesteld.
Couldn't check for updates:	Kon niet zoeken naar updates:
You have the latest version ({0}).	Je hebt de nieuwste versie ({0}).
PC Tune-Up {0} is available (you have {1}).	PC Tune-Up {0} is beschikbaar (je hebt {1}).
Open the download page?	De downloadpagina openen?
Update now? The app restarts by itself.	Nu bijwerken? De app start vanzelf opnieuw.
Update failed: {0}	Bijwerken mislukt: {0}
Couldn't replace the app file ({0}). Download it yourself from:	Kon het app-bestand niet vervangen ({0}). Download het zelf via:
Something went wrong:	Er ging iets mis:
Checking drive, battery and updates	Schijf, accu en updates controleren
Testing internet speed	Internetsnelheid testen
Measuring junk files	Rommel meten
Cleaning	Opruimen
Looking for bloatware	Zoeken naar bloatware
Creating a restore point	Herstelpunt maken
Creating a restore point first	Eerst een herstelpunt maken
Uninstalling	Verwijderen
Reading services	Services lezen
Measuring folders	Mappen meten
Checking for program updates	Zoeken naar programma-updates
Updating programs	Programma's bijwerken
Checking security	Beveiliging controleren
Reading Windows logs	Logboeken van Windows lezen
Reading the hardware	Hardware lezen
Fix my PC: cleaning	Pc repareren: opruimen
Downloading the update	Update downloaden
PC Tune-Up report	PC Tune-Up-rapport
Junk files that can be cleaned	Rommel die kan worden opgeruimd
Apps that start with Windows ({0} on)	Apps die met Windows starten ({0} aan)
Bloatware found	Gevonden bloatware
Background services	Achtergrondservices
Stability (last 30 days)	Stabiliteit (afgelopen 30 dagen)
Program updates available	Beschikbare programma-updates
Upgrade options	Mogelijke uitbreidingen
Changes made by PC Tune-Up	Wijzigingen door PC Tune-Up
Nothing found.	Niets gevonden.
No problems spotted.	Geen problemen gevonden.
Worth a look:	Het bekijken waard:
A matched kit of {0} x {1} GB {2}. The current modules come out (keep or sell them). Faster-rated {3} modules also work and simply run at {4} MT/s. Most supported: {5} GB.	Een bij elkaar passende set van {0} x {1} GB {2}. De huidige modules gaan eruit (bewaar of verkoop ze). Sneller geclassificeerde {3}-modules werken ook en lopen dan gewoon op {4} MT/s. Maximaal ondersteund: {5} GB.
A matched kit of {0} x {1} GB {2}. The current modules come out (keep or sell them). Faster-rated {3} modules also work and simply run at {4} MT/s.	Een bij elkaar passende set van {0} x {1} GB {2}. De huidige modules gaan eruit (bewaar of verkoop ze). Sneller geclassificeerde {3}-modules werken ook en lopen dan gewoon op {4} MT/s.
{0} x {1} GB {2} - match the module already fitted. Total afterwards: {3} GB. Faster-rated {4} modules also work and simply run at {5} MT/s. Most supported: {6} GB.	{0} x {1} GB {2} - gelijk aan de module die er al in zit. Daarna in totaal: {3} GB. Sneller geclassificeerde {4}-modules werken ook en lopen dan gewoon op {5} MT/s. Maximaal ondersteund: {6} GB.
{0} x {1} GB {2} - match the module already fitted. Total afterwards: {3} GB. Faster-rated {4} modules also work and simply run at {5} MT/s.	{0} x {1} GB {2} - gelijk aan de module die er al in zit. Daarna in totaal: {3} GB. Sneller geclassificeerde {4}-modules werken ook en lopen dan gewoon op {5} MT/s.
{0} x {1} GB {2} - same speed as the built-in memory. Total afterwards: {3} GB. Faster-rated {4} modules also work and simply run at {5} MT/s. Most supported: {6} GB.	{0} x {1} GB {2} - dezelfde snelheid als het ingebouwde geheugen. Daarna in totaal: {3} GB. Sneller geclassificeerde {4}-modules werken ook en lopen dan gewoon op {5} MT/s. Maximaal ondersteund: {6} GB.
{0} x {1} GB {2} - same speed as the built-in memory. Total afterwards: {3} GB. Faster-rated {4} modules also work and simply run at {5} MT/s.	{0} x {1} GB {2} - dezelfde snelheid als het ingebouwde geheugen. Daarna in totaal: {3} GB. Sneller geclassificeerde {4}-modules werken ook en lopen dan gewoon op {5} MT/s.
{0} SO-DIMM (laptop size), {1}-pin, {2}, {3}	{0} SO-DIMM (laptopformaat), {1} pinnen, {2}, {3}
{0} DIMM (desktop size), {1}-pin, {2}, {3}	{0} DIMM (desktopformaat), {1} pinnen, {2}, {3}
non-ECC	zonder ECC
registered ECC (RDIMM)	registered ECC (RDIMM)
unbuffered ECC	unbuffered ECC
{0} GB: {1} ({2}), {3}	{0} GB: {1} ({2}), {3}
all {0} slot(s) used	alle {0} sloten bezet
{0} of {1} slot(s) free	{0} van {1} sloten vrij
{0} GB soldered, {1} of {2} slot(s) free	{0} GB gesoldeerd, {1} van {2} sloten vrij
{0} GB soldered, all {1} slot(s) used	{0} GB gesoldeerd, alle {1} sloten bezet
soldered to the motherboard	op het moederbord gesoldeerd
Memory is {0}% used right now. Modules must match the type ({1}) and size ({2}). Crucial's free System Scanner (crucial.com) or the service manual lists the exact modules this PC accepts.	Het geheugen is nu voor {0}% in gebruik. Modules moeten passen bij het type ({1}) en formaat ({2}). De gratis System Scanner van Crucial (crucial.com) of de servicehandleiding noemt precies welke modules deze pc accepteert.
SO-DIMM (laptop size)	SO-DIMM (laptopformaat)
DIMM (desktop size)	DIMM (desktopformaat)
{0}: {1} GB {2} {3}, holds Windows (C: {4}% free)	{0}: {1} GB {2} {3}, met Windows erop (C: {4}% vrij)
{0}, 1 TB or 2 TB. If the laptop has a free M.2 slot, add it as a second drive; if not, replace this drive with the bigger one and clone it.	{0}, 1 TB of 2 TB. Heeft de laptop een vrij M.2-slot, zet hem er dan bij als tweede schijf; zo niet, vervang deze schijf door de grotere en kloon hem.
{0}, 1 TB or 2 TB. Desktops usually have spare M.2 slots or 2.5/3.5-inch bays - add it as a second drive.	{0}, 1 TB of 2 TB. Desktops hebben meestal vrije M.2-sloten of 2,5/3,5-inch-ruimtes - zet hem erbij als tweede schijf.
M.2 2280 NVMe SSD, PCIe Gen4 x4 (also works in Gen3 slots)	M.2 2280 NVMe-SSD, PCIe Gen4 x4 (werkt ook in Gen3-sloten)
2.5-inch SATA SSD, or M.2 NVMe if the motherboard has an M.2 slot	2,5-inch SATA-SSD, of M.2 NVMe als het moederbord een M.2-slot heeft
2.5-inch SATA SSD, or M.2 if the laptop has an M.2 slot (check whether it takes SATA or NVMe M.2)	2,5-inch SATA-SSD, of M.2 als de laptop een M.2-slot heeft (controleer of het SATA of NVMe M.2 is)
SSD of the same type as the current one	SSD van hetzelfde type als de huidige
1 TB 2.5-inch SATA SSD (7 mm) in place of this hard disk, or an M.2 SSD if the laptop has an M.2 slot. Copy ("clone") the old drive with the SSD maker's free tool.	1 TB 2,5-inch SATA-SSD (7 mm) in plaats van deze harde schijf, of een M.2-SSD als de laptop een M.2-slot heeft. Kopieer ("kloon") de oude schijf met het gratis hulpprogramma van de SSD-fabrikant.
1 TB SSD: M.2 NVMe if the motherboard has an M.2 slot (fastest), otherwise a 2.5-inch SATA SSD. Put Windows on it and keep the hard disk for files.	1 TB SSD: M.2 NVMe als het moederbord een M.2-slot heeft (snelst), anders een 2,5-inch SATA-SSD. Zet Windows erop en houd de harde schijf voor bestanden.
Replacement battery for the {0}: {1} Wh {2}. It reports itself as '{3}' - search that, or the serial number, to find the exact part. Prefer the maker's original.	Vervangende accu voor de {0}: {1} Wh {2}. Hij meldt zich als '{3}' - zoek daarop, of op het serienummer, om het precieze onderdeel te vinden. Kies bij voorkeur het origineel van de fabrikant.
{0} - {1} cores / {2} threads	{0} - {1} kernen / {2} threads
M.2 2230 Wi-Fi 6E card with Bluetooth (e.g. Intel AX210). Most laptops let you swap it; a few have it soldered or only accept approved cards - check the manual.	M.2 2230 wifi 6E-kaart met Bluetooth (bijv. Intel AX210). Bij de meeste laptops kun je hem wisselen; bij enkele zit hij vastgesoldeerd of werken alleen goedgekeurde kaarten - controleer de handleiding.
PCIe Wi-Fi 6E card with Bluetooth (e.g. Intel AX210 based), or a USB Wi-Fi 6 adapter if you'd rather not open the case.	PCIe wifi 6E-kaart met Bluetooth (bijv. op basis van Intel AX210), of een USB wifi 6-adapter als je de kast liever niet openmaakt.
PCIe Wi-Fi 6E card with Bluetooth, or a USB Wi-Fi 6 adapter.	PCIe wifi 6E-kaart met Bluetooth, of een USB wifi 6-adapter.
Check the CPU support list of the motherboard ({0}) on its maker's website.	Bekijk de lijst met ondersteunde processors van het moederbord ({0}) op de site van de fabrikant.
1 x {0} GB {1} in place of the current module.	1 x {0} GB {1} in plaats van de huidige module.
1 x {0} GB {1} in place of the current module (the {2} GB soldered memory stays).	1 x {0} GB {1} in plaats van de huidige module (het {2} GB gesoldeerde geheugen blijft).
Upgrade shopping list for {0}	Boodschappenlijst voor uitbreidingen van {0}
Upgrade shopping list for {0} (serial {1})	Boodschappenlijst voor uitbreidingen van {0} (serienummer {1})
{0} ({1}):	{0} ({1}):
Tasks	Taken
Backup	Back-up
Scheduled tasks	Geplande taken
Scheduled tasks from other companies: updaters, telemetry and helpers that Windows runs on a timer or at sign-in - the last place bloatware hides. Known junk is listed first and pre-checked. Switching a task off can be undone from History.	Geplande taken van andere bedrijven: updaters, telemetrie en hulpprogramma's die Windows op vaste tijden of bij het aanmelden start - de laatste plek waar bloatware zich verstopt. Bekende rommel staat bovenaan en is al aangevinkt. Een taak uitzetten kun je terugdraaien via Geschiedenis.
Turn off checked	Aangevinkte uitzetten
Turn on checked	Aangevinkte aanzetten
Open Task Scheduler	Taakplanner openen
Task	Taak
Made by	Gemaakt door
Runs	Start
State	Staat
Reading scheduled tasks	Geplande taken lezen
Reading scheduled tasks...	Geplande taken lezen...
at sign-in	bij aanmelden
at start-up	bij opstarten
daily	dagelijks
weekly	wekelijks
when idle	bij inactiviteit
on unlock	bij ontgrendelen
on a Windows event	bij een Windows-gebeurtenis
when installed	na installatie
repeatedly	herhaaldelijk
once	eenmalig
on a schedule	volgens schema
only when started	alleen als iets hem start
NVIDIA nView launcher - crashes other programs	NVIDIA nView-starter - laat andere programma's crashen
NVIDIA telemetry / updater	NVIDIA-telemetrie / updater
Adobe updater (Acrobat still updates when opened)	Adobe-updater (Acrobat werkt zichzelf nog bij als je het opent)
Adobe Creative Cloud helper - only needed if you use Creative Cloud	Adobe Creative Cloud-hulp - alleen nodig als je Creative Cloud gebruikt
Google promotions helper	Google-promotiehulp
browser updater (updates when the browser is open)	browser-updater (werkt bij als de browser open is)
Firefox usage reporting	Firefox-gebruiksrapportage
Zoom updater (Zoom updates itself when opened)	Zoom-updater (Zoom werkt zichzelf bij als je het opent)
Dell support / telemetry tool	Dell-ondersteunings- / telemetrieprogramma
HP support / telemetry tool	HP-ondersteunings- / telemetrieprogramma
Lenovo helper / telemetry	Lenovo-hulp / telemetrie
Acer promo / registration	Acer-promotie / registratie
cleaner / trial / adware helper	opschoner / proefversie / adware-hulp
Windows tips and promotional notifications	Windows-tips en reclamemeldingen
looks like an updater or telemetry - usually safe to turn off	lijkt een updater of telemetrie - meestal veilig om uit te zetten
review: only turn off if you know what it is	nakijken: alleen uitzetten als je weet wat het is
{0} known junk task(s) are switched on and pre-checked. Grey rows are already off.	{0} bekende rommeltaak/-taken staan aan en zijn aangevinkt. Grijze rijen staan al uit.
No known junk tasks are running. Grey rows are already off.	Er staan geen bekende rommeltaken aan. Grijze rijen staan al uit.
Check one or more tasks that are off first.	Vink eerst een of meer taken aan die uit staan.
Check one or more tasks that are on first.	Vink eerst een of meer taken aan die aan staan.
{0} task(s) switched off. Undo from the History page.	{0} taak/taken uitgezet. Terugdraaien via Geschiedenis.
{0} task(s) switched on. Undo from the History page.	{0} taak/taken aangezet. Terugdraaien via Geschiedenis.
These need administrator rights (click "Restart as admin"): {0}	Hiervoor zijn beheerdersrechten nodig (klik op "Opnieuw als beheerder"): {0}
switched off	uitgezet
switched on	aangezet
scheduled task switched back on	geplande taak weer aangezet
scheduled task switched off again	geplande taak weer uitgezet
disabled (stops NVIDIA nView crashing other programs)	uitgezet (zodat NVIDIA nView geen andere programma's meer laat crashen)
Would your files survive a broken, lost or stolen PC? Checks your cloud folders, File History, backup programs and restore points. Double-click a row (or select it and click Open setting) to change it.	Overleven je bestanden een kapotte, verloren of gestolen pc? Controleert je cloudmappen, Bestandsgeschiedenis, back-upprogramma's en herstelpunten. Dubbelklik op een rij (of selecteer hem en klik op Instelling openen) om iets te wijzigen.
Create restore point now	Nu een herstelpunt maken
Checking backups	Back-ups controleren
Checking backups...	Back-ups controleren...
Desktop, Documents and Pictures	Bureaublad, Documenten en Afbeeldingen
Backed up to {0}	Back-up in {0}
Nothing to do - every change is copied to the cloud.	Niets te doen - elke wijziging wordt naar de cloud gekopieerd.
{0} backed up to {1}; not: {2}	{0} met back-up in {1}; niet: {2}
Add the missing folders: OneDrive settings > Sync and back up > Manage back up (or Settings > Accounts > Windows backup).	Voeg de ontbrekende mappen toe: OneDrive-instellingen > Synchroniseren en back-up maken > Back-up beheren (of Instellingen > Accounts > Windows-back-up).
Not in any cloud folder	Niet in een cloudmap
If the PC breaks or is stolen, these files are gone. Turn on folder backup: Settings > Accounts > Windows backup (OneDrive), or use File History with an external drive.	Gaat de pc kapot of wordt hij gestolen, dan zijn deze bestanden weg. Zet mapback-up aan: Instellingen > Accounts > Windows-back-up (OneDrive), of gebruik Bestandsgeschiedenis met een externe schijf.
OneDrive running	OneDrive actief
Yes - changes are uploaded	Ja - wijzigingen worden geüpload
No - changes are not being uploaded	Nee - wijzigingen worden niet geüpload
Start OneDrive (it is in the Start menu) and let it sign in; check that it starts with Windows on the Startup page.	Start OneDrive (staat in het Startmenu) en laat het aanmelden; controleer op de pagina Opstarten dat het met Windows meestart.
File History	Bestandsgeschiedenis
Keep the backup drive connected now and then.	Sluit de back-upschijf af en toe aan.
Optional extra copy (also of older versions) on an external drive: Control Panel > File History.	Optionele extra kopie (ook van oudere versies) op een externe schijf: Configuratiescherm > Bestandsgeschiedenis.
Backup program	Back-upprogramma
Found: {0}	Gevonden: {0}
Check now and then that it still runs and that you can restore a file.	Controleer af en toe of het nog werkt en of je een bestand kunt terugzetten.
Optional: a backup program (Macrium Reflect and Veeam Agent have free versions) makes a full copy of the PC, including programs and settings.	Optioneel: een back-upprogramma (Macrium Reflect en Veeam Agent hebben gratis versies) maakt een volledige kopie van de pc, inclusief programma's en instellingen.
Restore points	Herstelpunten
{0} restore point(s), the latest {1} day(s) ago	{0} herstelpunt(en), het laatste {1} dag(en) geleden
Create one now (button above) - they let you undo a bad driver or update.	Maak er nu een (knop hierboven) - daarmee draai je een slecht stuurprogramma of een slechte update terug.
None found - System Protection may be off	Geen gevonden - Systeembeveiliging staat misschien uit
Switch on System Protection for C: (System Properties > System Protection > Configure), then create one.	Zet Systeembeveiliging aan voor C: (Systeemeigenschappen > Systeembeveiliging > Configureren) en maak er dan een.
Only visible as administrator	Alleen zichtbaar als beheerder
Click "Restart as admin" to check them.	Klik op "Opnieuw als beheerder" om ze te controleren.
Nothing is backing up your files.	Niets maakt een back-up van je bestanden.
Your files are backed up to {0}.	Er staat een back-up van je bestanden in {0}.
Some backup is in place - see the rows above.	Er is een vorm van back-up - zie de rijen hierboven.
Backup: nothing backs up your files - see the Backup page.	Back-up: niets maakt een back-up van je bestanden - zie de pagina Back-up.
OneDrive was not found.	OneDrive is niet gevonden.
Restore point created.	Herstelpunt gemaakt.
No restore point made: {0}	Geen herstelpunt gemaakt: {0}
Fix selected problem	Geselecteerd probleem oplossen
One-click fix: {0} (needs administrator)	Oplossen met één klik: {0} (beheerder nodig)
One-click fix: {0}	Oplossen met één klik: {0}
Turn off NVIDIA nView	NVIDIA nView uitzetten
Uninstall NVIDIA nView completely (the graphics driver stays)	NVIDIA nView helemaal verwijderen (het grafische stuurprogramma blijft)
Repair the Visual C++ runtimes	De Visual C++-runtimes repareren
Reset Windows Update	Windows Update opnieuw instellen
Repair Windows system files	Windows-systeembestanden repareren
Check drive C: for errors	Station C: op fouten controleren
Test the memory at the next restart	Het geheugen testen bij de volgende herstart
Check the drivers on the Drivers page	Controleer de stuurprogramma's op de pagina Stuurprogramma's
Open Store app updates	Updates voor Store-apps openen
Look for an update on the Updates page	Zoek een update op de pagina Updates
{0} needs administrator rights - click "Restart as admin" first.	{0} heeft beheerdersrechten nodig - klik eerst op "Opnieuw als beheerder".
Switched off: {0}	Uitgezet: {0}
Fixed: nView's start-up task is switched off and there have been no crashes since {0}. To remove it completely, uninstall "NVIDIA RTX Desktop Manager" in Settings > Apps.	Opgelost: de opstarttaak van nView staat uit en sinds {0} is er niets meer gecrasht. Wil je het helemaal weg, verwijder dan "NVIDIA RTX Desktop Manager" via Instellingen > Apps.
Windows Memory Diagnostic checks the memory while the PC restarts (about 10-20 minutes). It asks whether to restart now or next time.	Windows Geheugendiagnose controleert het geheugen terwijl de pc opnieuw opstart (ongeveer 10-20 minuten). Het vraagt of je nu of de volgende keer wilt herstarten.
Memory test	Geheugentest
scheduled with Windows Memory Diagnostic	ingepland met Windows Geheugendiagnose
Turn off NVIDIA nView?	NVIDIA nView uitzetten?
It stops its start-up task and closes it. The graphics driver and NVIDIA Control Panel keep working. You can undo this from the History page.	De opstarttaak wordt uitgezet en nView wordt gesloten. Het grafische stuurprogramma en het NVIDIA-configuratiescherm blijven werken. Terugdraaien kan via Geschiedenis.
NVIDIA nView is switched off. If programs still crash in it, uninstall "NVIDIA RTX Desktop Manager" in Settings > Apps.	NVIDIA nView staat uit. Crashen programma's er nog steeds in, verwijder dan "NVIDIA RTX Desktop Manager" via Instellingen > Apps.
NVIDIA nView is switched off (its start-up task was already off; running parts were closed). If programs still crash in it, uninstall "NVIDIA RTX Desktop Manager" in Settings > Apps.	NVIDIA nView staat uit (de opstarttaak stond al uit; draaiende onderdelen zijn gesloten). Crashen programma's er nog steeds in, verwijder dan "NVIDIA RTX Desktop Manager" via Instellingen > Apps.
Uninstall NVIDIA RTX Desktop Manager (nView)?	NVIDIA RTX Desktop Manager (nView) verwijderen?
The graphics driver stays. NVIDIA's uninstaller may show its own window.	Het grafische stuurprogramma blijft. Het verwijderprogramma van NVIDIA kan een eigen venster tonen.
Repair the Microsoft Visual C++ runtimes (64- and 32-bit)?	De Microsoft Visual C++-runtimes (64- en 32-bits) repareren?
They are reinstalled through winget; programs that use them keep working. Takes a minute or two.	Ze worden opnieuw geïnstalleerd via winget; programma's die ze gebruiken blijven werken. Duurt een minuut of twee.
Reset Windows Update?	Windows Update opnieuw instellen?
Its services are stopped, its download caches are set aside (renamed, not deleted) and it starts fresh. Afterwards, open Windows Update and check for updates again.	De services worden gestopt, de downloadcaches apart gezet (hernoemd, niet verwijderd) en het begint opnieuw. Open daarna Windows Update en zoek opnieuw naar updates.
Repair Windows system files?	Windows-systeembestanden repareren?
Runs sfc /scannow and then DISM, which can take 15-30 minutes. You can keep using the PC (and press Cancel).	Voert sfc /scannow en daarna DISM uit; dat kan 15-30 minuten duren. Je kunt de pc gewoon blijven gebruiken (en op Annuleren drukken).
Check drive C: for errors?	Station C: op fouten controleren?
An online check (chkdsk /scan) - you can keep working. If it finds a problem that needs fixing, Windows repairs it at the next restart.	Een controle terwijl Windows draait (chkdsk /scan) - je kunt doorwerken. Vindt het een probleem dat hersteld moet worden, dan doet Windows dat bij de volgende herstart.
{0}: done - {1}	{0}: klaar - {1}
{0}: problem - {1}	{0}: probleem - {1}
{0}: stopped	{0}: gestopt
done - {0}	klaar - {0}
problem - {0}	probleem - {0}
stopped	gestopt
checking system files (sfc)	systeembestanden controleren (sfc)
repairing the Windows image (DISM)	Windows-image repareren (DISM)
winget is missing	winget ontbreekt
nView is not installed any more	nView is niet meer geïnstalleerd
Privacy	Privacy
Drivers	Stuurprogramma's
Ads, tips and tracking that Windows switches on by default. Recommended ones are pre-checked. Turning a setting off only changes your own Windows settings (nothing is uninstalled) and can be undone from History or with "Turn back on".	Advertenties, tips en tracking die Windows standaard aanzet. De aanbevolen instellingen zijn al aangevinkt. Uitzetten verandert alleen je eigen Windows-instellingen (er wordt niets verwijderd) en kan worden teruggedraaid via Geschiedenis of met "Weer aanzetten".
Turn back on checked	Aangevinkte weer aanzetten
Open privacy settings	Privacyinstellingen openen
Setting	Instelling
What it does	Wat het doet
restarts Explorer	herstart Verkenner
Advertising ID	Advertentie-id
Lets apps show ads based on what you do.	Laat apps advertenties tonen op basis van wat je doet.
Tailored experiences	Afgestemde ervaringen
Microsoft uses your diagnostic data for personal tips, ads and recommendations.	Microsoft gebruikt je diagnostische gegevens voor persoonlijke tips, advertenties en aanbevelingen.
Tips and suggestions notifications	Meldingen met tips en suggesties
Pop-ups with tips and offers while you use Windows.	Pop-ups met tips en aanbiedingen terwijl je Windows gebruikt.
Suggested content in Settings	Voorgestelde inhoud in Instellingen
Suggestions and offers inside the Settings app.	Suggesties en aanbiedingen in de app Instellingen.
"Finish setting up" and welcome screens	"Apparaat instellen voltooien" en welkomstschermen
Full-screen pages after updates that push Microsoft 365, OneDrive and Game Pass.	Schermvullende pagina's na updates die Microsoft 365, OneDrive en Game Pass aanprijzen.
Promoted apps installed without asking	Gepromote apps die zonder te vragen worden geïnstalleerd
Windows quietly installs suggested apps and games on the Start menu.	Windows installeert stilletjes voorgestelde apps en games in het Startmenu.
Recommendations and ads in Start	Aanbevelingen en advertenties in Start
Suggested apps, tips and promotions in the Start menu.	Voorgestelde apps, tips en promoties in het Startmenu.
Account notifications in Start	Accountmeldingen in Start
Microsoft account and backup reminders on your picture in the Start menu.	Herinneringen over je Microsoft-account en back-up bij je foto in het Startmenu.
Fun facts and tips on the lock screen	Weetjes en tips op het vergrendelingsscherm
Text and promotions on top of the lock-screen picture.	Tekst en promoties over de afbeelding op het vergrendelingsscherm.
Search highlights	Zoekhoogtepunten
Trending news and pictures in the search box and search window.	Populair nieuws en afbeeldingen in het zoekvak en zoekvenster.
Web results in Start search	Webresultaten in zoeken via Start
What you type in Start search is also sent to Bing. As administrator the Windows policy is set too, which newer Windows versions need.	Wat je in Start zoekt, gaat ook naar Bing. Als beheerder wordt ook het Windows-beleid ingesteld, dat nieuwere Windows-versies nodig hebben.
Feedback requests	Feedbackverzoeken
Windows asks now and then what you think of it.	Windows vraagt af en toe wat je ervan vindt.
Inking and typing personalisation	Persoonlijke inkt- en typegegevens
What you type and write by hand is collected into a personal dictionary.	Wat je typt en met de hand schrijft, wordt verzameld in een persoonlijk woordenboek.
Optional diagnostic data	Optionele diagnostische gegevens
Extra data about the websites you visit and how you use apps, sent to Microsoft. The required basic data stays on.	Extra gegevens over de websites die je bezoekt en hoe je apps gebruikt, verstuurd naar Microsoft. De vereiste basisgegevens blijven aan.
Activity history	Activiteitengeschiedenis
Windows keeps a history of the apps, files and websites you used.	Windows houdt een geschiedenis bij van de apps, bestanden en websites die je hebt gebruikt.
Recall snapshots	Recall-momentopnamen
Recall saves pictures of everything on your screen every few seconds, to search later.	Recall maakt om de paar seconden een afbeelding van alles op je scherm, om later te doorzoeken.
Location for apps	Locatie voor apps
Apps such as Maps and Weather can see where you are. Only turn off if you don't need that.	Apps zoals Kaarten en Weer kunnen zien waar je bent. Zet dit alleen uit als je dat niet nodig hebt.
Partly on	Deels aan
{0} recommended setting(s) are still on. Grey rows are already off.	{0} aanbevolen instelling(en) staan nog aan. Grijze rijen staan al uit.
All recommended settings are off.	Alle aanbevolen instellingen staan uit.
Check one or more settings first.	Vink eerst een of meer instellingen aan.
{0} setting(s) turned off. Undo from the History page.	{0} instelling(en) uitgezet. Terugdraaien via Geschiedenis.
{0} setting(s) turned back on. Undo from the History page.	{0} instelling(en) weer aangezet. Terugdraaien via Geschiedenis.
Couldn't change: {0}	Kon niet wijzigen: {0}
Restart Explorer now so the Start menu, search and taskbar pick up the change?	Verkenner nu herstarten zodat het Startmenu, zoeken en de taakbalk de wijziging overnemen?
Open File Explorer windows close; nothing else is affected.	Open Verkenner-vensters worden gesloten; verder verandert er niets.
turned off	uitgezet
turned back on	weer aangezet
setting put back as it was	instelling teruggezet zoals hij was
Devices Windows reports a problem with, and the drivers that matter most (graphics, network, audio, storage, BIOS) with their age. Old drivers are a common cause of crashes, blue screens and battery drain.	Apparaten waarmee Windows een probleem meldt, en de belangrijkste stuurprogramma's (grafisch, netwerk, audio, opslag, BIOS) met hun leeftijd. Oude stuurprogramma's zijn een veelvoorkomende oorzaak van crashes, blauwe schermen en een snel lege accu.
Get driver updates	Stuurprogramma-updates ophalen
Optional updates in Windows Update	Optionele updates in Windows Update
Open Device Manager	Apparaatbeheer openen
Device	Apparaat
Kind	Soort
Driver	Stuurprogramma
Reading drivers	Stuurprogramma's lezen
Reading devices and drivers...	Apparaten en stuurprogramma's lezen...
No devices found.	Geen apparaten gevonden.
Network	Netwerk
Storage	Opslag
Camera	Camera
Sign-in	Aanmelden
BIOS	BIOS
USB	USB
Chipset	Chipset
Input	Invoer
Touchpad/mouse	Touchpad/muis
Keyboard	Toetsenbord
Printer	Printer
Other	Overig
Driver is recent enough	Stuurprogramma is recent genoeg
Driver is {0} years old	Stuurprogramma is {0} jaar oud
No proper graphics driver installed	Geen echt grafisch stuurprogramma geïnstalleerd
Device {0} (code {1})	Apparaat {0} (code {1})
Problem code {0}	Probleemcode {0}
Switched off in Device Manager (code 22)	Uitgeschakeld in Apparaatbeheer (code 22)
is not set up correctly	is niet goed ingesteld
has a damaged driver	heeft een beschadigd stuurprogramma
cannot start	kan niet starten
lacks free resources	heeft te weinig vrije bronnen
needs a restart	heeft een herstart nodig
needs its driver reinstalled	moet zijn stuurprogramma opnieuw laten installeren
has damaged settings	heeft beschadigde instellingen
has no driver installed	heeft geen stuurprogramma
is not working properly	werkt niet goed
has its driver switched off	heeft een uitgeschakeld stuurprogramma
driver failed to load	stuurprogramma kon niet laden
driver is missing or damaged	stuurprogramma ontbreekt of is beschadigd
was stopped by Windows because it reported problems	is door Windows gestopt omdat het problemen meldde
driver is blocked	stuurprogramma is geblokkeerd
driver is not signed	stuurprogramma is niet ondertekend
Driver: {0}	Stuurprogramma: {0}
Update or reinstall the driver: Device Manager > right-click the device > Update driver. If that doesn't help: Uninstall device, then Action > Scan for hardware changes.	Werk het stuurprogramma bij of installeer het opnieuw: Apparaatbeheer > rechtsklik op het apparaat > Stuurprogramma bijwerken. Helpt dat niet: Apparaat verwijderen, dan Actie > Zoeken naar gewijzigde hardware.
Switched off on purpose? Then nothing to do. Otherwise: Device Manager > right-click > Enable device.	Bewust uitgezet? Dan hoeft er niets te gebeuren. Anders: Apparaatbeheer > rechtsklik > Apparaat inschakelen.
Install its driver: Windows Update > Advanced options > Optional updates, or the PC maker's support page (button above).	Installeer het stuurprogramma: Windows Update > Geavanceerde opties > Optionele updates, of de ondersteuningspagina van de pc-maker (knop hierboven).
Restart the PC.	Start de pc opnieuw op.
Unplug the USB device and plug it into a different port (not a hub), or try another cable. If nothing is plugged in, update the chipset and USB drivers from the PC maker.	Trek het USB-apparaat los en steek het in een andere poort (geen hub), of probeer een andere kabel. Is er niets aangesloten, werk dan de chipset- en USB-stuurprogramma's van de pc-maker bij.
Install the graphics driver from the PC maker's support page or nvidia.com / amd.com / intel.com. Until then the screen is slow and games won't run.	Installeer het grafische stuurprogramma via de ondersteuningspagina van de pc-maker of nvidia.com / amd.com / intel.com. Tot die tijd is het beeld traag en werken games niet.
Update the graphics driver - from the PC maker's support page for a laptop, otherwise from nvidia.com, amd.com or intel.com.	Werk het grafische stuurprogramma bij - via de ondersteuningspagina van de pc-maker bij een laptop, anders via nvidia.com, amd.com of intel.com.
A BIOS update may be available. Get it only from the PC maker's support page (button above), and keep the PC plugged in while it installs.	Er is misschien een BIOS-update. Haal die alleen van de ondersteuningspagina van de pc-maker (knop hierboven) en laat de pc aan de lader terwijl hij installeert.
A newer driver may be available from the PC maker's support page or in Windows Update > Optional updates. Only needed if this device gives trouble.	Er is misschien een nieuwer stuurprogramma via de ondersteuningspagina van de pc-maker of Windows Update > Optionele updates. Alleen nodig als dit apparaat problemen geeft.
Drivers: {0} device(s) have a problem - see the Drivers page.	Stuurprogramma's: {0} apparaat/apparaten hebben een probleem - zie de pagina Stuurprogramma's.
Automatic maintenance	Automatisch onderhoud
PC Tune-Up cleans junk files and checks the PC by itself on Sunday around noon (or as soon as the PC is on and not in use), then shows a notification. Startup apps, services and programs are never changed without you.	PC Tune-Up ruimt zelf rommelbestanden op en controleert de pc op zondag rond het middaguur (of zodra de pc aan staat en niet wordt gebruikt), en toont daarna een melding. Opstart-apps, services en programma's worden nooit zonder jou gewijzigd.
Every week	Elke week
Every 4 weeks	Elke 4 weken
Run now	Nu uitvoeren
Not run yet.	Nog niet uitgevoerd.
Last run: {0}	Laatst uitgevoerd: {0}
Install PC Tune-Up first (Settings > Installation): the automatic run needs it in a fixed place.	Installeer PC Tune-Up eerst (Instellingen > Installatie): het automatische onderhoud heeft het op een vaste plek nodig.
Couldn't set up automatic maintenance: {0}	Kon automatisch onderhoud niet instellen: {0}
every week	elke week
every 4 weeks	elke 4 weken
The maintenance run has started in the background. A notification appears when it is done (in a minute or two).	Het onderhoud is op de achtergrond gestart. Als het klaar is verschijnt er een melding (na een minuut of twee).
PC Tune-Up maintenance	PC Tune-Up-onderhoud
Cleaned {0}. {1} thing(s) worth a look - click to see.	{0} opgeruimd. {1} punt(en) om naar te kijken - klik om te bekijken.
Cleaned {0}. Everything looks fine.	{0} opgeruimd. Alles ziet er goed uit.
freed {0}, {1} thing(s) worth a look	{0} vrijgemaakt, {1} punt(en) om naar te kijken
freed {0} (automatic)	{0} vrijgemaakt (automatisch)
Maintenance	Onderhoud
Browsers	Browsers
Programs	Programma's
Right-click	Rechtsklik
Right-click menu	Rechtsklikmenu
How much charge the battery still holds, how fast it is wearing, and how to make it last longer. From Windows' own battery report.	Hoeveel lading de accu nog vasthoudt, hoe snel hij slijt en hoe je hem langer laat meegaan. Uit het eigen accurapport van Windows.
Battery usage per app	Accugebruik per app
Power & battery settings	Instellingen voor energie en accu
Full battery report	Volledig accurapport
Find a replacement	Vervanging zoeken
Reading	Meting
Value	Waarde
What it means	Wat het betekent
Reading the battery report	Accurapport lezen
Reading the battery report...	Accurapport lezen...
Making the battery report	Accurapport maken
Windows could not make a battery report.	Windows kon geen accurapport maken.
Could not read the battery.	Kon de accu niet uitlezen.
Battery health	Accuconditie
Good - normal for its age.	Goed - normaal voor zijn leeftijd.
Worn: you get noticeably less time on battery than when it was new.	Versleten: je kunt merkbaar korter op de accu werken dan toen hij nieuw was.
Worn out: it holds less than two thirds of its charge. A new battery brings back the original battery life - see "Replacement" below.	Op: hij houdt minder dan twee derde van zijn lading vast. Een nieuwe accu geeft de oorspronkelijke gebruiksduur terug - zie "Vervanging" hieronder.
Capacity	Capaciteit
{0} Wh now, {1} Wh when new	{0} Wh nu, {1} Wh toen hij nieuw was
Wh (watt-hours) is how much energy the battery can store.	Wh (wattuur) is hoeveel energie de accu kan opslaan.
Wear over the last year	Slijtage het afgelopen jaar
no loss	geen verlies
loses about {0}% a year	verliest ongeveer {0}% per jaar
Faster than normal (about 5-10% a year). Usually heat, or the battery being kept at 100% while plugged in all day - a charge limit helps (below).	Sneller dan normaal (ongeveer 5-10% per jaar). Meestal door warmte, of doordat de accu de hele dag op 100% aan de lader zit - een laadlimiet helpt (hieronder).
Normal.	Normaal.
Time on a full charge	Gebruiksduur op een volle accu
about {0} ({1} when new)	ongeveer {0} ({1} toen hij nieuw was)
about {0}	ongeveer {0}
Windows' estimate for the way you normally use the PC.	De schatting van Windows voor hoe je de pc normaal gebruikt.
Charge cycles	Laadcycli
One cycle = 100% used in total. Most laptop batteries are made for 300-1000 cycles.	Eén cyclus = in totaal 100% verbruikt. De meeste laptopaccu's zijn gemaakt voor 300-1000 cycli.
lithium polymer	lithium-polymeer
lithium-ion	lithium-ion
{0}, made by {1} ({2})	{0}, gemaakt door {1} ({2})
{0}, made by {1}	{0}, gemaakt door {1}
Needed when you look for a replacement.	Nodig als je een vervanger zoekt.
Charge limit	Laadlimiet
plugged in now	nu aan de lader
on battery now	nu op de accu
If the PC is plugged in most of the time, stopping charging at about 80% slows wear a lot. {0}	Zit de pc meestal aan de lader, dan vertraagt stoppen met laden bij ongeveer 80% de slijtage flink. {0}
Look in the PC maker's app or in the BIOS for "charge limit", "battery care" or "conservation mode" (usually 80%).	Zoek in de app van de pc-maker of in het BIOS naar "laadlimiet", "battery care" of "conservation mode" (meestal 80%).
Dell Optimizer or Dell Power Manager > Battery > "Primarily AC use" (or Custom, e.g. 50-80%). Also in the BIOS (F2 at start-up) > Power > Battery Charge Configuration.	Dell Optimizer of Dell Power Manager > Accu > "Voornamelijk netstroom" (of Aangepast, bijv. 50-80%). Ook in het BIOS (F2 bij het opstarten) > Power > Battery Charge Configuration.
Lenovo Vantage > Device > Power > Battery Charge Threshold, or "Conservation mode".	Lenovo Vantage > Apparaat > Energie > Laaddrempel accu, of "Conservation mode".
In the BIOS (F10 at start-up) > Advanced > Power Management Options > Battery Health Manager: "Maximize my battery health".	In het BIOS (F10 bij het opstarten) > Advanced > Power Management Options > Battery Health Manager: "Maximize my battery health".
MyASUS > Customization > Battery Health Charging: "Balanced" (80%) or "Maximum lifespan" (60%).	MyASUS > Aanpassen > Battery Health Charging: "Gebalanceerd" (80%) of "Maximale levensduur" (60%).
Acer Care Center or Acer Quick Access > Battery charge limit (80%).	Acer Care Center of Acer Quick Access > Laadlimiet accu (80%).
MSI Center > Features > Battery Master: "Best for Battery".	MSI Center > Features > Battery Master: "Best for Battery".
Samsung Settings > Battery > "Protect battery" (charges to 85%).	Samsung Settings > Batterij > "Batterij beschermen" (laadt tot 85%).
Surface app > Battery > Smart Charging, or the UEFI "Enable Battery Limit" mode.	Surface-app > Batterij > Slim opladen, of de UEFI-modus "Enable Battery Limit".
Razer Synapse > System > Battery Health Optimizer.	Razer Synapse > System > Battery Health Optimizer.
In the BIOS > Advanced > Battery Charge Limit.	In het BIOS > Advanced > Battery Charge Limit.
Replacement	Vervanging
worth it	de moeite waard
Search for "{0} battery"{1} - preferably the PC maker's own part. On many laptops it is a 10-20 minute job with a screwdriver; the Upgrades page has the service manual.	Zoek naar "{0} battery"{1} - het liefst het originele onderdeel van de pc-maker. Bij veel laptops is het een klus van 10-20 minuten met een schroevendraaier; de pagina Upgrades heeft de servicehandleiding.
 (battery {0})	 (accu {0})
see button above	zie de knop hierboven
Which apps used the most battery in the last day or week (Windows Settings).	Welke apps de afgelopen dag of week de meeste accu gebruikten (Windows-instellingen).
Battery history since {0}.	Accugeschiedenis sinds {0}.
Charge it holds (% of new)	Lading die hij vasthoudt (% van nieuw)
Extensions in Chrome, Edge, Brave, Vivaldi and Firefox, the search engine, home page and start-up pages, plus Windows' hosts file and proxy. Adware hides here: extensions that weren't installed from a store, and settings forced through "policies".	Extensies in Chrome, Edge, Brave, Vivaldi en Firefox, de zoekmachine, startpagina en opstartpagina's, plus het hosts-bestand en de proxy van Windows. Hier verstopt adware zich: extensies die niet uit een store komen, en via "beleid" afgedwongen instellingen.
Open extensions page	Extensiepagina openen
Remove checked policies	Aangevinkt beleid verwijderen
Reset browser settings	Browserinstellingen herstellen
Browser	Browser
Details	Details
Extension	Extensie
Search	Zoeken
Home page	Startpagina
Start-up	Opstarten
Policy	Beleid
Risky	Riskant
Review	Nakijken
Checking browsers	Browsers controleren
Reading browser settings...	Browserinstellingen lezen...
No supported browsers found.	Geen ondersteunde browsers gevonden.
from the store	uit de store
from the add-ons site	van de add-onssite
changes {0}	wijzigt {0}
your search engine	je zoekmachine
your home page	je startpagina
your start-up pages	je opstartpagina's
the new-tab page	de nieuwe-tabbladpagina
can read and change every website you visit	kan elke website die je bezoekt lezen en wijzigen
extra powers: {0}	extra rechten: {0}
installed by a policy	geïnstalleerd via beleid
not from a store (added by a program or by hand)	niet uit een store (toegevoegd door een programma of handmatig)
added by a program, not from the add-ons site	toegevoegd door een programma, niet van de add-onssite
Remove it unless you installed it yourself on purpose: open the extensions page (button above) > Remove. If it comes back, a program keeps adding it - look on the Programs and Bloatware pages.	Verwijder hem, tenzij je hem zelf bewust hebt geïnstalleerd: open de extensiepagina (knop hierboven) > Verwijderen. Komt hij terug, dan voegt een programma hem steeds toe - kijk op de pagina's Programma's en Bloatware.
Keep it if you know it and use it; otherwise remove it from the extensions page (button above).	Houd hem als je hem kent en gebruikt; verwijder hem anders via de extensiepagina (knop hierboven).
Switched off. Remove it if you don't need it any more.	Uitgeschakeld. Verwijder hem als je hem niet meer nodig hebt.
Search engine: {0}	Zoekmachine: {0}
a well-known search engine	een bekende zoekmachine
not a well-known search engine - adware often swaps it	geen bekende zoekmachine - adware verwisselt die vaak
Change it back in the browser: Settings > Search engine. If it changes again, use "Reset browser settings".	Zet hem terug in de browser: Instellingen > Zoekmachine. Verandert hij weer, gebruik dan "Browserinstellingen herstellen".
Home page: {0}	Startpagina: {0}
Fine if you chose it.	Prima als je die zelf hebt gekozen.
Start-up pages: {0}	Opstartpagina's: {0}
Fine if you chose them; otherwise change them in Settings > On start-up.	Prima als je ze zelf hebt gekozen; wijzig ze anders bij Instellingen > Bij opstarten.
Policy: {0}	Beleid: {0}
Forced extension: {0}	Afgedwongen extensie: {0}
Forced start-up page: {0}	Afgedwongen opstartpagina: {0}
forced through {0}	afgedwongen via {0}
Set by your organisation (this PC is managed) - leave it.	Ingesteld door je organisatie (deze pc wordt beheerd) - laat het staan.
Nobody manages this home PC, so a program forced this. Check it and click "Remove checked policies" (needs administrator).	Niemand beheert deze thuis-pc, dus een programma heeft dit afgedwongen. Vink het aan en klik op "Aangevinkt beleid verwijderen" (beheerder nodig).
Policy file: policies.json	Beleidsbestand: policies.json
forced settings in {0}	afgedwongen instellingen in {0}
Open about:policies in Firefox to see what it forces. On a home PC you can delete the file (needs administrator).	Open about:policies in Firefox om te zien wat er wordt afgedwongen. Op een thuis-pc kun je het bestand verwijderen (beheerder nodig).
Policy: settings forced in the registry	Beleid: instellingen afgedwongen in het register
Open about:policies in Firefox to see what it forces.	Open about:policies in Firefox om te zien wat er wordt afgedwongen.
Browsers: {0} thing(s) look like adware - see the Browsers page.	Browsers: {0} onderdeel/onderdelen lijken op adware - zie de pagina Browsers.
Select a row first.	Selecteer eerst een rij.
Select a row of the browser to reset first.	Selecteer eerst een rij van de browser die je wilt herstellen.
Couldn't start {0}.	Kon {0} niet starten.
Open {0}'s reset page?	De herstelpagina van {0} openen?
Resetting puts the search engine, home page, start-up pages and pinned tabs back to normal and switches extensions off. Bookmarks, history and saved passwords stay.	Herstellen zet de zoekmachine, startpagina, opstartpagina's en vastgemaakte tabbladen terug en schakelt extensies uit. Favorieten, geschiedenis en opgeslagen wachtwoorden blijven.
Check one or more policy rows first (extensions are removed in the browser itself - use "Open extensions page").	Vink eerst een of meer beleidsrijen aan (extensies verwijder je in de browser zelf - gebruik "Extensiepagina openen").
Removing browser policies needs administrator rights - click "Restart as admin" first.	Browserbeleid verwijderen vereist beheerdersrechten - klik eerst op "Opnieuw als beheerder".
Remove these forced browser settings?	Deze afgedwongen browserinstellingen verwijderen?
Restart the browser afterwards. You can undo this from the History page.	Start de browser daarna opnieuw. Terugdraaien kan via Geschiedenis.
forced setting removed	afgedwongen instelling verwijderd
{0} forced setting(s) removed. Restart the browser to see the change.	{0} afgedwongen instelling(en) verwijderd. Start de browser opnieuw om het resultaat te zien.
Every installed program with its size and when you last used it (from Windows' own record of what you start, and when the program last wrote its own files). Check the ones you don't need and uninstall them in one go; leftover folders are cleaned up afterwards. Store apps are on the Bloatware page.	Elk geïnstalleerd programma met zijn grootte en wanneer je het voor het laatst gebruikte (uit de eigen administratie van Windows van wat je start, en wanneer het programma voor het laatst zijn eigen bestanden schreef). Vink aan wat je niet nodig hebt en verwijder alles in één keer; achtergebleven mappen worden daarna opgeruimd. Store-apps staan op de pagina Bloatware.
Sort: size	Sorteren: grootte
Sort: last used	Sorteren: laatst gebruikt
Sort: name	Sorteren: naam
Open Installed apps	Geïnstalleerde apps openen
Last used	Laatst gebruikt
Reading installed programs	Geïnstalleerde programma's lezen
Reading installed programs...	Geïnstalleerde programma's lezen...
now (running)	nu (actief)
no record	niet vastgelegd
on the keep list	op de bewaarlijst
used by other programs - keep	gebruikt door andere programma's - laten staan
no sign of use for {0} days	al {0} dagen niet gebruikt
never opened from Start or the desktop (may run in the background)	nooit geopend via Start of het bureaublad (draait misschien op de achtergrond)
language pack - shares its files (and size) with the main program	taalpakket - deelt zijn bestanden (en grootte) met het hoofdprogramma
{0} programs, {1} in total. {2} with no sign of use for 6 months or more.	{0} programma's, samen {1}. {2} al 6 maanden of langer niet gebruikt.
  Use is recorded since {0}.	  Gebruik wordt bijgehouden sinds {0}.
  (Windows is set not to record program use: Settings > Privacy > General.)	  (Windows houdt programmagebruik niet bij: Instellingen > Privacy > Algemeen.)
Check one or more programs first.	Vink eerst een of meer programma's aan.
Uninstall these programs?	Deze programma's verwijderen?
Careful - other programs may need: {0}	Let op - andere programma's hebben misschien nodig: {0}
Each program's own uninstaller runs, one after another; some show a window or ask for administrator rights.	Het eigen verwijderprogramma van elk programma draait, na elkaar; sommige tonen een venster of vragen om beheerdersrechten.
Uninstalling programs	Programma's verwijderen
uninstalling {0}	{0} verwijderen
{0} program(s) uninstalled.	{0} programma('s) verwijderd.
Still installed (cancelled, or the uninstaller failed): {0}	Nog geïnstalleerd (geannuleerd, of het verwijderen mislukte): {0}
These leftover folders are still there:	Deze achtergebleven mappen staan er nog:
Move them to the Recycle Bin?	Naar de Prullenbak verplaatsen?
{0} folder(s) moved to the Recycle Bin. Couldn't move (in use, or needs administrator): {1}	{0} map(pen) naar de Prullenbak verplaatst. Kon niet verplaatsen (in gebruik, of beheerder nodig): {1}
leftover folder moved to the Recycle Bin	achtergebleven map naar de Prullenbak verplaatst
uninstalled	verwijderd
measuring {0}	{0} meten
Wi-Fi signal and speed, delays to the router and the internet, how fast names are looked up (DNS), and how often the connection dropped in the last 30 days.	Wifi-signaal en -snelheid, vertraging naar de router en het internet, hoe snel namen worden opgezocht (DNS), en hoe vaak de verbinding de afgelopen 30 dagen wegviel.
Flush DNS cache	DNS-cache leegmaken
Reset network	Netwerk opnieuw instellen
Wi-Fi settings	Wifi-instellingen
Network troubleshooter	Netwerkprobleemoplosser
Checking the network	Netwerk controleren
Checking the network (about 15 seconds)...	Netwerk controleren (ongeveer 15 seconden)...
Checking the network: {0}	Netwerk controleren: {0}
connection	verbinding
router	router
internet	internet
Connection	Verbinding
Not connected	Niet verbonden
Plug in the network cable or connect to Wi-Fi (the network icon at the bottom right).	Sluit de netwerkkabel aan of maak verbinding met wifi (het netwerkpictogram rechtsonder).
Wi-Fi	Wifi
on	aan
off	uit
Installed with winget - update or remove it with winget (winget upgrade / winget uninstall MichaelKloprogge.PCTuneUp).	Geïnstalleerd met winget - bijwerken of verwijderen gaat met winget (winget upgrade / winget uninstall MichaelKloprogge.PCTuneUp).
It was installed with winget, so winget updates it. Update now? (A window opens; start PC Tune-Up again afterwards.)	Het is geïnstalleerd met winget, dus winget werkt het bij. Nu bijwerken? (Er opent een venster; start PC Tune-Up daarna opnieuw.)
shared	gedeeld
Cable (Ethernet)	Kabel (ethernet)
VPN	VPN
On: {0}	Aan: {0}
Everything below goes through the VPN, so delays are higher than without it. That is normal.	Alles hieronder gaat via de VPN, dus de vertraging is hoger dan zonder. Dat is normaal.
Wi-Fi signal	Wifi-signaal
{0}% on "{1}"{2}	{0}% op "{1}"{2}
Weak signal: move closer to the router, put the router higher and out in the open, or add a mesh point or repeater. Walls and floors weaken Wi-Fi a lot.	Zwak signaal: ga dichter bij de router zitten, zet de router hoger en vrij, of voeg een mesh-punt of repeater toe. Muren en vloeren verzwakken wifi flink.
Wi-Fi band	Wifi-band
2.4 GHz (channel {0})	2,4 GHz (kanaal {0})
This Wi-Fi card can use 5 GHz (faster, less crowded). If the router offers a separate 5 GHz network, connect to that one - or turn on "band steering" in the router.	Deze wifikaart kan 5 GHz gebruiken (sneller, minder druk). Biedt de router een apart 5 GHz-netwerk, maak daar dan verbinding mee - of zet "band steering" aan in de router.
Router	Router
{0} ms on average, worst {1} ms	gemiddeld {0} ms, slechtst {1} ms
{0} ms on average, worst {1} ms, {2}% lost	gemiddeld {0} ms, slechtst {1} ms, {2}% verloren
does not answer pings	beantwoordt geen pings
no answer, {0}% lost	geen antwoord, {0}% verloren
Some routers never answer pings - fine if the internet line is OK.	Sommige routers beantwoorden nooit pings - prima als de regel Internet in orde is.
The problem is between this PC and the router: usually weak or crowded Wi-Fi. Move closer, use 5 GHz or a cable, and restart the router.	Het probleem zit tussen deze pc en de router: meestal zwakke of drukke wifi. Ga dichterbij zitten, gebruik 5 GHz of een kabel, en start de router opnieuw.
Internet	Internet
If the router line above is fine, the delay comes from the internet connection itself: restart the modem/router; if it keeps happening, contact your internet provider.	Is de regel Router in orde, dan komt de vertraging van de internetverbinding zelf: start het modem/de router opnieuw; blijft het gebeuren, neem dan contact op met je provider.
DNS	DNS
{0}: {1} ms per look-up ({2}: {3} ms)	{0}: {1} ms per opzoeking ({2}: {3} ms)
{0}: {1} ms per look-up	{0}: {1} ms per opzoeking
{0} doesn't answer	{0} antwoordt niet
Names can't be looked up, so websites won't open. Restart the router, or set DNS to 1.1.1.1 in Settings > Network & internet > (your connection) > DNS server assignment.	Namen kunnen niet worden opgezocht, dus websites openen niet. Start de router opnieuw, of stel DNS in op 1.1.1.1 via Instellingen > Netwerk en internet > (je verbinding) > DNS-servertoewijzing.
Your DNS server is slow - every new website waits for it. Switching to {0} helps: Settings > Network & internet > (your connection) > DNS server assignment > Edit.	Je DNS-server is traag - elke nieuwe website wacht erop. Overstappen naar {0} helpt: Instellingen > Netwerk en internet > (je verbinding) > DNS-servertoewijzing > Bewerken.
Wi-Fi drops (30 days)	Wifi-onderbrekingen (30 dagen)
{0} disconnect(s), {1} failed connection(s)	{0} keer verbroken, {1} mislukte verbinding(en)
Normal - disconnects also happen at sleep, shutdown and when you move between networks.	Normaal - de verbinding valt ook weg bij slaapstand, afsluiten en wisselen van netwerk.
More than normal. Update the Wi-Fi driver (Drivers page), turn off "Allow the computer to turn off this device to save power" for the Wi-Fi card in Device Manager, and restart the router.	Meer dan normaal. Werk het wifistuurprogramma bij (pagina Stuurprogramma's), zet in Apparaatbeheer "De computer mag dit apparaat uitschakelen om energie te besparen" uit voor de wifikaart, en start de router opnieuw.
Errors on {0}	Fouten op {0}
{0} damaged packets ({1})	{0} beschadigde pakketten ({1})
Usually a bad cable or a failing port. Try another cable or port; for Wi-Fi, update the driver.	Meestal een slechte kabel of een kapotte poort. Probeer een andere kabel of poort; bij wifi: werk het stuurprogramma bij.
Network: {0} - see the Network page.	Netwerk: {0} - zie de pagina Netwerk.
DNS cache	DNS-cache
flushed	leeggemaakt
DNS cache flushed. Websites that wouldn't open because of an old address should work now.	DNS-cache leeggemaakt. Websites die niet openden door een oud adres zouden nu moeten werken.
Resetting the network needs administrator rights - click "Restart as admin" first. (Or: Settings > Network & internet > Advanced network settings > Network reset.)	Het netwerk opnieuw instellen vereist beheerdersrechten - klik eerst op "Opnieuw als beheerder". (Of: Instellingen > Netwerk en internet > Geavanceerde netwerkinstellingen > Netwerk opnieuw instellen.)
Reset the network?	Het netwerk opnieuw instellen?
This resets Windows' network settings (Winsock and TCP/IP) to factory state and clears the DNS cache - the standard fix when nothing connects although the router works. Wi-Fi passwords and VPN apps stay, but a manually set IP address or DNS server is cleared.	Dit zet de netwerkinstellingen van Windows (Winsock en TCP/IP) terug naar de fabrieksinstellingen en maakt de DNS-cache leeg - de standaardoplossing als er niets verbindt terwijl de router werkt. Wifiwachtwoorden en VPN-apps blijven, maar een handmatig ingesteld IP-adres of DNS-server wordt gewist.
The PC needs a restart afterwards.	De pc moet daarna opnieuw opstarten.
Resetting the network	Netwerk opnieuw instellen
Winsock and TCP/IP	Winsock en TCP/IP
reset ({0})	opnieuw ingesteld ({0})
The network has been reset. Restart the PC now to finish?	Het netwerk is opnieuw ingesteld. De pc nu opnieuw opstarten om af te ronden?
Entries other programs add to Explorer's right-click menu (under "Show more options" on Windows 11). Leftovers of removed programs are pre-checked. Hiding an entry can be undone from History or with "Show checked".	Items die andere programma's toevoegen aan het rechtsklikmenu van Verkenner (onder "Meer opties weergeven" in Windows 11). Restanten van verwijderde programma's zijn al aangevinkt. Een item verbergen kun je terugdraaien via Geschiedenis of met "Aangevinkte tonen".
Hide checked	Aangevinkte verbergen
Show checked	Aangevinkte tonen
Entry	Item
Shown on	Te zien bij
Hidden	Verborgen
Shown	Zichtbaar
files	bestanden
folders	mappen
files and folders	bestanden en mappen
folder background	mapachtergrond
drives	stations
desktop	bureaublad
leftover: the program is gone{0}	restant: het programma is weg{0}
Reading the right-click menu	Rechtsklikmenu lezen
Reading the right-click menu...	Rechtsklikmenu lezen...
{0} entries from other programs; {1} leftover(s) of removed programs (pre-checked).	{0} items van andere programma's; {1} restant(en) van verwijderde programma's (aangevinkt).
Check one or more entries that are shown first.	Vink eerst een of meer zichtbare items aan.
Check one or more hidden entries first.	Vink eerst een of meer verborgen items aan.
hidden from the menu	verborgen in het menu
shown in the menu again	weer zichtbaar in het menu
{0} entr(y/ies) hidden. Undo from the History page.	{0} item(s) verborgen. Terugdraaien via Geschiedenis.
{0} entr(y/ies) shown again. Undo from the History page.	{0} item(s) weer zichtbaar. Terugdraaien via Geschiedenis.
Restart Explorer now so the menu updates?	Verkenner nu herstarten zodat het menu wordt bijgewerkt?
Large files	Grote bestanden
Duplicate files	Dubbele bestanden
Recycle checked	Aangevinkte naar Prullenbak
File	Bestand
Modified	Gewijzigd
Find what is filling the drive. Pick a place and Scan; double-click a row to look inside it. "Large files" and "Duplicate files" look for files you may not need - they only go to the Recycle Bin when you say so.	Zoek uit wat de schijf vult. Kies een plek en klik op Scannen; dubbelklik op een rij om erin te kijken. "Grote bestanden" en "Dubbele bestanden" zoeken bestanden die je misschien niet nodig hebt - ze gaan alleen naar de Prullenbak als jij dat zegt.
That is a very big or system folder - this can take a long time. Program and Windows files are never pre-checked. Continue?	Dat is een heel grote map of systeemmap - dit kan lang duren. Programma- en Windows-bestanden worden nooit vooraf aangevinkt. Doorgaan?
Looking for files of 100 MB or more in {0}...	Bestanden van 100 MB of meer zoeken in {0}...
Looking for identical files of 1 MB or more in {0} (it compares contents, so this can take a while)...	Identieke bestanden van 1 MB of meer zoeken in {0} (de inhoud wordt vergeleken, dus dit kan even duren)...
Finding large files	Grote bestanden zoeken
Finding duplicate files	Dubbele bestanden zoeken
comparing files ({0} of {1})	bestanden vergelijken ({0} van {1})
in Downloads - often safe to remove	in Downloads - vaak veilig om weg te halen
installer or archive - often not needed any more	installatiebestand of archief - vaak niet meer nodig
{0} large file(s), {1} together. Check what you don't need and click Recycle checked (they go to the Recycle Bin).	{0} groot/grote bestand(en), samen {1}. Vink aan wat je niet nodig hebt en klik op Aangevinkte naar Prullenbak.
kept (1 of {0} identical copies)	bewaard (1 van {0} identieke kopieën)
identical copy of {0}	identieke kopie van {0}
{0} set(s) of identical files; the extra copies take {1}. One copy of each is kept (grey); the others are pre-checked.	{0} groep(en) identieke bestanden; de extra kopieën nemen {1} in beslag. Van elk wordt één kopie bewaard (grijs); de andere zijn aangevinkt.
Stopped. {0}	Gestopt. {0}
Check one or more files first.	Vink eerst een of meer bestanden aan.
All copies of {0} are checked - leave at least one unchecked.	Alle kopieën van {0} zijn aangevinkt - laat er minstens één uit.
Move {0} file(s) ({1}) to the Recycle Bin?	{0} bestand(en) ({1}) naar de Prullenbak verplaatsen?
You can get them back from the Recycle Bin until you empty it.	Je kunt ze terughalen uit de Prullenbak tot je die leegmaakt.
{0} file(s)	{0} bestand(en)
moved to the Recycle Bin ({0})	naar de Prullenbak verplaatst ({0})
{0} file(s) moved to the Recycle Bin ({1}). Empty the Recycle Bin to free the space.	{0} bestand(en) naar de Prullenbak verplaatst ({1}). Maak de Prullenbak leeg om de ruimte vrij te maken.
Couldn't move: {0}	Kon niet verplaatsen: {0}
PC Tune-Up score	PC Tune-Up-score
Windows stability x10	Windows-stabiliteit x10
Score {0}/100 (was {1})	Score {0}/100 (was {1})
Score {0}/100	Score {0}/100
Health over time	Gezondheid door de tijd
The score appears once all checks have run.	De score verschijnt zodra alle controles klaar zijn.
No history yet.	Nog geen geschiedenis.
PC-TuneUp.exe /auto                 the automatic maintenance run (clean, check, notify)	PC-TuneUp.exe /auto                 het automatische onderhoud (opruimen, controleren, melden)
{0} programs, {1} in total. {2} with no sign of use for 6 months or more.  Use is recorded since {3}.	{0} programma's, samen {1}. {2} al 6 maanden of langer niet gebruikt.  Gebruik wordt bijgehouden sinds {3}.
{0} programs, {1} in total. {2} with no sign of use for 6 months or more.  (Windows is set not to record program use: Settings > Privacy > General.)	{0} programma's, samen {1}. {2} al 6 maanden of langer niet gebruikt.  (Windows houdt programmagebruik niet bij: Instellingen > Privacy > Algemeen.)
{0}; {1}	{0}; {1}
Start here	Begin hier
1.  {0}	1.  {0}
2.  {0}	2.  {0}
3.  {0}	3.  {0}
Open	Openen
Nothing urgent - this PC looks good.	Niets dringends - deze pc ziet er goed uit.
Security: {0} problem(s) to fix	Beveiliging: {0} probleem/problemen om op te lossen
Fix	Oplossen
Nothing backs up your files yet	Er maakt nog niets een back-up van je bestanden
Set up backup	Back-up instellen
{0} browser item(s) look like adware	{0} browseronderdeel/-onderdelen lijken op adware
{0} device(s) have a driver problem	{0} apparaat/apparaten hebben een probleem met het stuurprogramma
{0} kind(s) of crashes or errors keep happening	{0} soort(en) crashes of fouten blijven terugkomen
See fixes	Oplossingen bekijken
Drive C: is almost full ({0} free)	Station C: is bijna vol ({0} vrij)
Free up space	Ruimte vrijmaken
The network has a problem	Het netwerk heeft een probleem
Clean up {0} of junk files	{0} aan rommelbestanden opruimen
Free up to {0} with space savers	Tot {0} vrijmaken met ruimtebesparingen
Stop {0} app(s) starting with Windows	{0} app(s) niet meer met Windows laten starten
{0} program update(s) available	{0} programma-update(s) beschikbaar
Turn off {0} Windows ads, tips and tracking settings	{0} instellingen voor Windows-advertenties, -tips en -tracking uitzetten
Turn off	Uitzetten
Switch off {0} junk scheduled task(s)	{0} geplande rommeltaak/-taken uitzetten
The battery is worn out - see how to replace it	De accu is versleten - bekijk hoe je hem vervangt
See	Bekijken
Hide {0} leftover right-click menu entr(y/ies)	{0} achtergebleven item(s) in het rechtsklikmenu verbergen
Start-up time	Opstarttijd
Start-up time: {0} s	Opstarttijd: {0} s
Reading start-up times	Opstarttijden lezen
Seconds until the desktop is ready	Seconden tot het bureaublad klaar is
Windows only shows start-up times to administrators - click "Restart as admin" to see them.	Windows toont opstarttijden alleen aan beheerders - klik op "Opnieuw als beheerder" om ze te zien.
No start-up times recorded yet.	Nog geen opstarttijden vastgelegd.
Fast startup is on, so Shut down and then starting again is quicker than Restart (only Restart does a full start).	Snel opstarten staat aan, dus Afsluiten en dan weer aanzetten is sneller dan Opnieuw opstarten (alleen Opnieuw opstarten doet een volledige start).
Fast startup is off.	Snel opstarten staat uit.
Last full start: {0} s ({1} s for Windows, then {2} s for start-up apps); {3} s on average over 30 days.	Laatste volledige start: {0} s ({1} s voor Windows, daarna {2} s voor opstart-apps); gemiddeld {3} s over 30 dagen.
Last full start: {0} s ({1} s for Windows, then {2} s for start-up apps).	Laatste volledige start: {0} s ({1} s voor Windows, daarna {2} s voor opstart-apps).
That is slow - turning off start-up apps below helps most.	Dat is traag - opstart-apps hieronder uitzetten helpt het meest.
Fine; fewer start-up apps would make it quicker.	Prima; met minder opstart-apps gaat het sneller.
Quick.	Snel.
app	app
driver	stuurprogramma
service	service
background task	achtergrondtaak
device	apparaat
Slowing it down: {0}.	Vertragen het: {0}.
Space savers	Ruimtebesparingen
Big chunks of disk space that Windows keeps by default - each with what you give up. Nothing is checked except Storage Sense; most need administrator rights, and every change except freeing OneDrive copies can be undone from History.	Grote stukken schijfruimte die Windows standaard vasthoudt - elk met wat je ervoor inlevert. Alleen Opslaginzicht is aangevinkt; de meeste hebben beheerdersrechten nodig, en elke wijziging behalve het vrijmaken van OneDrive-kopieën kun je terugdraaien via Geschiedenis.
Apply checked	Aangevinkte toepassen
Storage settings	Opslaginstellingen
Saver	Besparing
Can free	Kan vrijmaken
Now	Nu
What it does - and what you give up	Wat het doet - en wat je inlevert
Looking for space savers	Ruimtebesparingen zoeken
Checking...	Controleren...
ongoing	doorlopend
Hibernation file	Slaapstandbestand
{0} GB (full size)	{0} GB (volledige grootte)
{0} GB (already reduced)	{0} GB (al verkleind)
Shrinks C:\hiberfil.sys to half. Fast startup keeps working; the PC can no longer hibernate (sleep still works, but if the battery runs flat while asleep, unsaved work is lost).	Verkleint C:\hiberfil.sys tot de helft. Snel opstarten blijft werken; de pc kan niet meer in sluimerstand (slaapstand werkt nog, maar raakt de accu leeg tijdens de slaapstand, dan gaat niet-opgeslagen werk verloren).
Removes C:\hiberfil.sys. A desktop rarely hibernates; Fast startup is switched off too, so starting takes a few seconds longer.	Verwijdert C:\hiberfil.sys. Een desktop gaat zelden in sluimerstand; ook Snel opstarten gaat uit, dus opstarten duurt een paar seconden langer.
Already as small as it can be while keeping Fast startup.	Al zo klein als kan met Snel opstarten aan.
Reserved storage	Gereserveerde opslag
on (about 7 GB)	aan (ongeveer 7 GB)
only visible as administrator	alleen zichtbaar als beheerder
Windows keeps about 7 GB free for updates. Switching it off gives you that space; on a nearly full drive an update may then fail until you free space.	Windows houdt ongeveer 7 GB vrij voor updates. Uitzetten geeft je die ruimte; op een bijna volle schijf kan een update dan mislukken tot je ruimte vrijmaakt.
Windows keeps about 7 GB free for updates. Click "Restart as admin" to check and change it.	Windows houdt ongeveer 7 GB vrij voor updates. Klik op "Opnieuw als beheerder" om het te bekijken en te wijzigen.
Nothing to free.	Niets vrij te maken.
Compress Windows files	Windows-bestanden comprimeren
Windows says this isn't worth it on this PC (see "Now"), so it is not counted in the total. Compresses Windows' own files (Compact OS), about 2-4 GB; on a fast PC the slowdown is barely noticeable. Takes 10-20 minutes.	Windows vindt dit op deze pc niet de moeite waard (zie "Nu"), dus het telt niet mee in het totaal. Comprimeert de eigen bestanden van Windows (Compact OS), ongeveer 2-4 GB; op een snelle pc merk je de vertraging nauwelijks. Duurt 10-20 minuten.
Compresses Windows' own files (Compact OS), about 2-4 GB; on a fast PC the slowdown is barely noticeable. Takes 10-20 minutes.	Comprimeert de eigen bestanden van Windows (Compact OS), ongeveer 2-4 GB; op een snelle pc merk je de vertraging nauwelijks. Duurt 10-20 minuten.
OneDrive copies ({0})	OneDrive-kopieën ({0})
{0} file(s) kept on this PC	{0} bestand(en) op deze pc bewaard
Removes the copies on this PC; the files stay in OneDrive with a cloud icon and download again when you open them (you need internet for that). Files set to "Always keep on this device" stay.	Verwijdert de kopieën op deze pc; de bestanden blijven in OneDrive met een wolkpictogram en worden opnieuw gedownload als je ze opent (daarvoor heb je internet nodig). Bestanden met "Altijd op dit apparaat behouden" blijven staan.
Storage Sense	Opslaginzicht
Windows already cleans temporary files and old Recycle Bin items by itself.	Windows ruimt tijdelijke bestanden en oude items in de Prullenbak al zelf op.
Turns on Windows' own automatic clean-up: every week it removes temporary files and Recycle Bin items older than 30 days. Your own files are not touched.	Zet het eigen automatische opruimen van Windows aan: elke week verwijdert het tijdelijke bestanden en items in de Prullenbak die ouder zijn dan 30 dagen. Je eigen bestanden blijven onaangeroerd.
Paging file	Wisselbestand
Windows' overflow for memory. Leave it to Windows - shrinking it can make programs crash when memory fills up. If it is large, more memory is the real fix (see the Upgrades page).	De overloop van Windows voor het geheugen. Laat dit aan Windows over - verkleinen kan programma's laten crashen als het geheugen vol raakt. Is het groot, dan is meer geheugen de echte oplossing (zie de pagina Upgrades).
Extra Windows languages	Extra Windows-talen
Each extra language with its speech and handwriting add-ons takes a few hundred MB. Remove ones you don't use in Settings > Time & language > Language & region.	Elke extra taal met spraak- en handschriftonderdelen neemt een paar honderd MB in beslag. Verwijder talen die je niet gebruikt via Instellingen > Tijd en taal > Taal en regio.
Check one or more savers first (grey rows are only information).	Vink eerst een of meer besparingen aan (grijze rijen zijn alleen informatie).
These need administrator rights - click "Restart as admin" first: {0}	Deze hebben beheerdersrechten nodig - klik eerst op "Opnieuw als beheerder": {0}
Apply these space savers?	Deze ruimtebesparingen toepassen?
See the right-hand column for what each one gives up.	Zie de rechterkolom voor wat elke besparing inlevert.
Compressing Windows files takes 10-20 minutes.	Windows-bestanden comprimeren duurt 10-20 minuten.
turned on (weekly)	aangezet (wekelijks)
Storage Sense is on.	Opslaginzicht staat aan.
Applying space savers	Ruimtebesparingen toepassen
Space savers:	Ruimtebesparingen:
 - {0}: done	 - {0}: klaar
 - {0}: failed {1}	 - {0}: mislukt {1}
OneDrive frees its copies over the next minutes. Undo the others from the History page.	OneDrive maakt zijn kopieën in de komende minuten vrij. De rest draai je terug via Geschiedenis.
Space	Ruimte
done, about {0}	klaar, ongeveer {0}
done, about {0} ({1})	klaar, ongeveer {0} ({1})
put back as it was	teruggezet zoals het was
Needs administrator rights - click 'Restart as admin'.	Beheerdersrechten nodig - klik op 'Opnieuw als beheerder'.
Error log	Foutenlogboek
No problems inside PC Tune-Up have been recorded.	Er zijn geen problemen binnen PC Tune-Up vastgelegd.
Problems inside PC Tune-Up (last 14 days)	Problemen binnen PC Tune-Up (afgelopen 14 dagen)
None recorded.	Niets vastgelegd.
Notify me when something is new (recommended)	Meld het als er iets nieuws is (aanbevolen)
Notify me after every run	Meld het na elke keer
Never notify me	Nooit melden
New since last time: {0}	Nieuw sinds de vorige keer: {0}
and {0} more	en nog {0}
New browser extension: {0} ({1})	Nieuwe browserextensie: {0} ({1})
Security: {0} - {1}	Beveiliging: {0} - {1}
Device problem: {0}	Probleem met apparaat: {0}
More often: {0} (+{1})	Vaker: {0} (+{1})
freed {0}, {1} new thing(s)	{0} vrijgemaakt, {1} nieuw(e) punt(en)
freed {0}, nothing new	{0} vrijgemaakt, niets nieuws
Gaming	Gamen
Start your game, then click Check again: which graphics card it really uses, what else is busy, and the Windows settings that cost frames. Recommended fixes are pre-checked and can be undone from History.	Start je game en klik dan op Opnieuw controleren: welke videokaart hij echt gebruikt, wat er verder bezig is, en de Windows-instellingen die frames kosten. Aanbevolen oplossingen zijn al aangevinkt en kun je terugdraaien via Geschiedenis.
Apply checked fixes	Aangevinkte oplossingen toepassen
Graphics settings	Grafische instellingen
Game Mode settings	Instellingen voor Spelmodus
Checking for gaming	Controleren voor gamen
Measuring (about 5 seconds)...	Meten (ongeveer 5 seconden)...
measuring graphics and processor use	gebruik van videokaart en processor meten
Game	Game
No game running right now	Er draait nu geen game
Start your game, switch back here (Alt+Tab) and click "Check again" to see which graphics card it uses and what else is busy. The Windows settings below are checked either way.	Start je game, schakel terug naar hier (Alt+Tab) en klik op "Opnieuw controleren" om te zien welke videokaart hij gebruikt en wat er verder bezig is. De Windows-instellingen hieronder worden hoe dan ook gecontroleerd.
Game: {0}	Game: {0}
runs, but not drawing anything at the moment	draait, maar tekent op dit moment niets
Switch to the game for a moment (so it draws), then come back and click "Check again".	Schakel even naar de game (zodat hij tekent), kom dan terug en klik op "Opnieuw controleren".
runs on {0} - the slower, built-in graphics	draait op {0} - de tragere, ingebouwde graphics
Set it to use the fast graphics card (fix below), then restart the game. Same as Settings > System > Display > Graphics > (the game) > High performance.	Laat hem de snelle videokaart gebruiken (oplossing hieronder) en start de game opnieuw. Hetzelfde als Instellingen > Systeem > Beeldscherm > Graphics > (de game) > Hoge prestaties.
runs on {0} ({1}% busy)	draait op {0} ({1}% bezig)
The graphics card is the limit (fully busy) - lower the graphics settings or the resolution in the game for more frames.	De videokaart is de beperking (volledig bezig) - verlaag de grafische instellingen of de resolutie in de game voor meer frames.
Busy: {0}	Bezig: {0}
uses {0}% of the processor	gebruikt {0}% van de processor
uses {0}% of {1}	gebruikt {0}% van {1}
a graphics card	een videokaart
Close {0} while you play, if you don't need it. (It may also be Windows doing updates or a virus scan - those finish by themselves.)	Sluit {0} tijdens het spelen als je het niet nodig hebt. (Het kan ook Windows zijn dat updates of een virusscan doet - die stoppen vanzelf.)
Close {0} (videos, animated wallpapers and browser tabs use the graphics card too) while you play.	Sluit {0} tijdens het spelen (video's, bewegende achtergronden en browsertabbladen gebruiken ook de videokaart).
on battery	op de accu
Plug in the charger: on battery, laptops slow the processor and graphics card down a lot.	Sluit de lader aan: op de accu vertragen laptops de processor en videokaart flink.
Power mode	Energiemodus
Set Power mode to "Best performance" while gaming (Settings > System > Power & battery) - the button opens it.	Zet Energiemodus op "Beste prestaties" tijdens het gamen (Instellingen > Systeem > Energie en accu) - de knop opent het.
plugged in	aan de lader
plugged in, {0}	aan de lader, {0}
only {0}% free	maar {0}% vrij
Close browsers and other big programs before playing - when memory is full, games stutter.	Sluit browsers en andere grote programma's voor het spelen - als het geheugen vol is, haperen games.
Game Mode	Spelmodus
Game Mode gives the game priority and pauses Windows Update installs while you play. Turn it on (fix below).	Spelmodus geeft de game voorrang en pauzeert installaties van Windows Update tijdens het spelen. Zet hem aan (oplossing hieronder).
Background recording	Opnemen op de achtergrond
on ("Record what happened")	aan ("Opnemen wat er is gebeurd")
Windows keeps recording the last minutes of every game, which costs frames. Turn it off (fix below); you can still record by hand with Win+Alt+R.	Windows neemt steeds de laatste minuten van elke game op, en dat kost frames. Zet het uit (oplossing hieronder); met de hand opnemen kan nog steeds met Win+Alt+R.
Optimizations for windowed games	Optimalisaties voor games in een venster
Lowers delay and allows Auto HDR / variable refresh rate for games in a window or borderless window. Turn it on (fix below).	Verlaagt de vertraging en maakt Auto HDR / variabele vernieuwingsfrequentie mogelijk voor games in een (randloos) venster. Zet het aan (oplossing hieronder).
Hardware-accelerated GPU scheduling	Hardwareversnelde GPU-planning
Windows default	Windows-standaard
Lets the graphics card schedule its own work - often a little smoother, and needed for DLSS frame generation. Needs administrator and a restart (fix below). If games stutter afterwards, undo it.	Laat de videokaart zijn eigen werk plannen - vaak iets soepeler, en nodig voor DLSS-framegeneratie. Vereist beheerdersrechten en een herstart (oplossing hieronder). Haperen games daarna, draai het dan terug.
Overlays	Overlays
Overlays draw on top of the game. Usually fine; if a game stutters or crashes, switch its overlay off first.	Overlays tekenen over de game heen. Meestal prima; hapert of crasht een game, zet dan eerst de overlay uit.
Graphics driver	Grafisch stuurprogramma
Check one or more rows that have a fix first.	Vink eerst een of meer rijen met een oplossing aan.
Hardware-accelerated GPU scheduling needs administrator rights - click "Restart as admin" first, or uncheck it.	Hardwareversnelde GPU-planning vereist beheerdersrechten - klik eerst op "Opnieuw als beheerder", of vink het uit.
Couldn't change {0}: {1}	Kon {0} niet wijzigen: {1}
Done: {0}. Restart the PC for GPU scheduling to take effect. Restart the game to feel the difference. Undo from the History page.	Klaar: {0}. Start de pc opnieuw om GPU-planning te laten werken. Start de game opnieuw om het verschil te merken. Terugdraaien via Geschiedenis.
Done: {0}. Restart the game to feel the difference. Undo from the History page.	Klaar: {0}. Start de game opnieuw om het verschil te merken. Terugdraaien via Geschiedenis.
turned on	aangezet
set to use the fast graphics card	ingesteld op de snelle videokaart
turned on (after a restart)	aangezet (na een herstart)
Search  (Ctrl+F)	Zoeken  (Ctrl+F)
Everything that matches, on every page. Double-click a result (or select it and press Enter) to go there.	Alles wat overeenkomt, op elke pagina. Dubbelklik op een resultaat (of selecteer het en druk op Enter) om erheen te gaan.
Found	Gevonden
Page	Pagina
{0} result(s) for "{1}".	{0} resultaat/resultaten voor "{1}".
Nothing found for "{0}". Pages still loading are searched once they are ready.	Niets gevonden voor "{0}". Pagina's die nog laden worden doorzocht zodra ze klaar zijn.
Deutsch	Deutsch
Français	Français
PC Tune-Up settings	PC Tune-Up-instellingen
This opens GitHub with a new problem report, filled in with:	Dit opent GitHub met een nieuwe probleemmelding, ingevuld met:
  Version: {0}	  Versie: {0}
  Windows: {0}	  Windows: {0}
  Recent errors: {0}	  Recente fouten: {0}
{0} line(s) (your name, folders and PC name are blanked out)	{0} regel(s) (je naam, mappen en pc-naam zijn weggelaten)
none	geen
You can read and change everything there before you press Submit. You need a free GitHub account.	Je kunt alles daar lezen en aanpassen voordat je op Submit drukt. Je hebt een gratis GitHub-account nodig.
Saved: {0}	Opgeslagen: {0}
It holds your settings, keep list ({0}), privacy choices ({1}), switched-off scheduled tasks ({2}), startup apps ({3}) and services ({4}). No files, passwords or personal data. On the other PC: Settings > Move to another PC > Import.	Het bevat je instellingen, bewaarlijst ({0}), privacykeuzes ({1}), uitgezette geplande taken ({2}), opstart-apps ({3}) en services ({4}). Geen bestanden, wachtwoorden of persoonlijke gegevens. Op de andere pc: Instellingen > Naar een andere pc > Importeren.
That is not a PC Tune-Up settings file.	Dat is geen instellingenbestand van PC Tune-Up.
 - Settings: language, theme, updates, restore points, notifications	 - Instellingen: taal, thema, updates, herstelpunten, meldingen
 - Keep list: add {0} program(s)	 - Bewaarlijst: {0} programma('s) toevoegen
 - Privacy: turn off {0} setting(s)	 - Privacy: {0} instelling(en) uitzetten
 - Scheduled tasks: switch off {0}	 - Geplande taken: {0} uitzetten
 - Startup: stop {0} app(s) starting with Windows	 - Opstarten: {0} app(s) niet meer met Windows laten starten
 - Services: change {0}	 - Services: {0} wijzigen
 - Services: {0} skipped (needs administrator)	 - Services: {0} overgeslagen (beheerder nodig)
Import from {0}?	Importeren uit {0}?
Only what exists on this PC is changed. Everything can be undone from the History page.	Alleen wat op deze pc bestaat wordt gewijzigd. Alles kan worden teruggedraaid via Geschiedenis.
turned off (imported)	uitgezet (geïmporteerd)
switched off (imported)	uitgezet (geïmporteerd)
Imported. Language and theme take effect when PC Tune-Up restarts.	Geïmporteerd. Taal en thema werken zodra PC Tune-Up opnieuw start.
Welcome to PC Tune-Up	Welkom bij PC Tune-Up
PC Tune-Up checks this PC and explains in plain language what slows it down. The "Start here" box on the Health page always shows the three most useful things to do right now. "Fix my PC" runs all the safe fixes in one go.	PC Tune-Up controleert deze pc en legt in gewone taal uit wat hem vertraagt. Het vak "Begin hier" op de pagina Gezondheid toont altijd de drie nuttigste dingen om nu te doen. "Pc repareren" voert alle veilige oplossingen in één keer uit.
Nothing changes without you	Niets verandert zonder jou
PC Tune-Up asks first and shows exactly what it will do. Every change is listed on the History page, and almost everything can be undone with one click. Security software, VPNs and drivers are never touched, and you can add your own programs to the keep list.	PC Tune-Up vraagt het eerst en laat precies zien wat het gaat doen. Elke wijziging staat op de pagina Geschiedenis, en bijna alles kun je met één klik terugdraaien. Beveiligingssoftware, VPN's en stuurprogramma's worden nooit aangeraakt, en je kunt je eigen programma's op de bewaarlijst zetten.
A few handy things	Een paar handige dingen
Some fixes need administrator rights - click "Restart as admin" at the bottom left. Press Ctrl+F to search everything. In Settings you can switch on weekly maintenance, which cleans junk by itself and only tells you when something new turns up.	Sommige oplossingen hebben beheerdersrechten nodig - klik linksonder op "Opnieuw als beheerder". Druk op Ctrl+F om alles te doorzoeken. In Instellingen kun je wekelijks onderhoud aanzetten: dat ruimt zelf rommel op en meldt alleen iets als er iets nieuws is.
Step {0} of {1}	Stap {0} van {1}
Next	Volgende
Back	Terug
Skip	Overslaan
Get started	Aan de slag
Move to another PC	Naar een andere pc
Saves your choices to one file: settings, keep list, privacy settings you turned off, and the scheduled tasks, startup apps and services you switched off. Import it on another PC - only what exists there is changed, with undo.	Bewaart je keuzes in één bestand: instellingen, bewaarlijst, privacy-instellingen die je hebt uitgezet, en de geplande taken, opstart-apps en services die je hebt uitgezet. Importeer het op een andere pc - alleen wat daar bestaat wordt gewijzigd, met terugdraaien.
Export settings...	Instellingen exporteren...
Import settings...	Instellingen importeren...
Help and feedback	Hulp en feedback
Something not working, or an idea? It opens a report on GitHub with the version, Windows and recent errors already filled in (your name, folders and PC name are blanked out) - you see everything before you send it.	Werkt er iets niet, of heb je een idee? Er opent een melding op GitHub met de versie, Windows en recente fouten al ingevuld (je naam, mappen en pc-naam zijn weggelaten) - je ziet alles voordat je het verstuurt.
Report a problem...	Probleem melden...
Suggest an idea...	Idee voorstellen...
Show the tour again	Rondleiding opnieuw tonen
Website	Website
Ctrl+F  search everything      F5  reload this page      Ctrl+1 ... Ctrl+9  the first nine pages      Ctrl+PageDown / Ctrl+PageUp  next / previous page      Space  check or uncheck a row      Enter  open a search result	Ctrl+F  alles doorzoeken      F5  deze pagina opnieuw laden      Ctrl+1 ... Ctrl+9  de eerste negen pagina's      Ctrl+PageDown / Ctrl+PageUp  volgende / vorige pagina      Spatie  rij aan- of uitvinken      Enter  zoekresultaat openen
Report this problem? (Opens GitHub with the details filled in - you see everything before you send it.)	Dit probleem melden? (Opent GitHub met de details ingevuld - je ziet alles voordat je het verstuurt.)
Your PC's protection has a gap ({0} problem(s)). It is worth letting someone who knows computers take a look.	De beveiliging van je pc heeft een gat ({0} probleem/problemen). Laat iemand die verstand heeft van computers er even naar kijken.
Your photos and documents are not backed up anywhere. If the PC breaks or is stolen, they are gone.	Er is nergens een back-up van je foto's en documenten. Gaat de pc kapot of wordt hij gestolen, dan zijn ze weg.
Your web browser has add-ons that look like advertising software.	Je webbrowser heeft uitbreidingen die op reclamesoftware lijken.
A part of your PC (a device) is not working properly.	Een onderdeel van je pc (een apparaat) werkt niet goed.
Programs or Windows crashed several times recently.	Programma's of Windows zijn de laatste tijd een paar keer vastgelopen of gecrasht.
Your PC is almost full - only {0} is left. That makes it slow.	Je pc is bijna vol - er is nog maar {0} over. Daardoor wordt hij traag.
Your internet connection has a problem.	Je internetverbinding heeft een probleem.
There are {0} of leftover files you don't need.	Er staat {0} aan overbodige restbestanden.
Windows keeps up to {0} for things you may not need.	Windows houdt tot {0} vast voor dingen die je misschien niet nodig hebt.
{0} app(s) start by themselves every time you turn on the PC, which makes starting slower.	{0} app(s) starten vanzelf elke keer dat je de pc aanzet, waardoor opstarten langer duurt.
{0} program(s) have a newer version with fixes.	Van {0} programma('s) is er een nieuwere versie met verbeteringen.
Windows shows you ads and tips, and shares more about you than needed ({0} settings).	Windows laat je advertenties en tips zien en deelt meer over je dan nodig is ({0} instellingen).
{0} helper program(s) from other companies run in the background by themselves.	{0} hulpprogramma('s) van andere bedrijven draaien vanzelf op de achtergrond.
Your battery is worn out and doesn't last as long any more. A new battery fixes that.	Je accu is versleten en houdt het niet meer zo lang vol. Een nieuwe accu lost dat op.
Removed programs left old entries in your right-click menu.	Verwijderde programma's hebben oude items in je rechtsklikmenu achtergelaten.
Show all tools	Alle hulpmiddelen tonen
It started right after a Windows update ({0}, installed {1}). If it keeps happening, uninstall that update: Settings > Windows Update > Update history > Uninstall updates.	Het begon direct na een Windows-update ({0}, geïnstalleerd op {1}). Blijft het gebeuren, verwijder die update dan: Instellingen > Windows Update > Updategeschiedenis > Updates verwijderen.
Open the update history (to uninstall the update)	De updategeschiedenis openen (om de update te verwijderen)
Also: {0}	Ook: {0}
Slows start-up	Vertraagt opstarten
Drive wear	Slijtage schijf
{0}: {1}% used, about {2}% a year more	{0}: {1}% versleten, ongeveer {2}% per jaar erbij
{0}: {1}% used, no change in {2} days	{0}: {1}% versleten, geen verandering in {2} dagen
Drive {0} is wearing fast - at this rate it is worn out in about {1} year(s). Keep your backups up to date and plan a replacement.	Schijf {0} slijt snel - in dit tempo is hij over ongeveer {1} jaar versleten. Houd je back-ups bij en plan een vervanging.
Drive {0} got hot ({1} C) in the last 30 days - heat shortens its life. Keep the vents free and the PC off soft surfaces.	Schijf {0} werd de afgelopen 30 dagen heet ({1} C) - warmte verkort zijn levensduur. Houd de ventilatieopeningen vrij en zet de pc niet op zachte ondergronden.
Drive {0} reported new read or write errors - back up your files now and check the drive.	Schijf {0} meldde nieuwe lees- of schrijffouten - maak nu een back-up van je bestanden en laat de schijf controleren.
Español	Español
Italiano	Italiano
Polski	Polski
Earlier	Eerder
On average	Gemiddeld
At most	Hoogstens
Among the top 5	Bij de top 5
{0}% of the time	{0}% van de tijd
Memory in use, last 7 days	Geheugen in gebruik, laatste 7 dagen
Memory in use	Geheugen in gebruik
Not enough history yet - PC Tune-Up notes memory use every 10 minutes while it is open.	Nog niet genoeg geschiedenis - PC Tune-Up noteert elke 10 minuten het geheugengebruik zolang het open is.
Over the last {0} day(s) memory was nearly full {1}% of the time (on average {2}% in use).	De afgelopen {0} dag(en) was het geheugen {1}% van de tijd bijna vol (gemiddeld {2}% in gebruik).
{0} used the most.	{0} gebruikte het meeste.
Over the last {0} day(s) memory was nearly full {1}% of the time - more memory would make a real difference.	De afgelopen {0} dag(en) was het geheugen {1}% van de tijd bijna vol - meer geheugen zou echt verschil maken.
Over the last {0} day(s) memory was rarely nearly full ({1}% of the time) - more memory would hardly be noticed.	De afgelopen {0} dag(en) was het geheugen zelden bijna vol ({1}% van de tijd) - meer geheugen zou je nauwelijks merken.
Over the last {0} day(s) memory was nearly full {1}% of the time.	De afgelopen {0} dag(en) was het geheugen {1}% van de tijd bijna vol.
Later	Later
Restart	Opnieuw opstarten
Open Windows Update	Windows Update openen
Windows has been waiting {0} day(s) for a restart to finish updates	Windows wacht al {0} dag(en) op een herstart om updates af te maken
Windows has been waiting {0} day(s) for a restart to finish installing updates. Save your work and restart.	Windows wacht al {0} dag(en) op een herstart om de updates af te maken. Sla je werk op en start opnieuw op.
The PC hasn't restarted in {0} days	De pc is al {0} dagen niet opnieuw opgestart
Your PC hasn't been restarted in {0} days. A restart clears out a lot of slowness.	Je pc is al {0} dagen niet opnieuw opgestart. Een herstart haalt veel traagheid weg.
Windows hasn't installed updates in {0} days	Windows heeft al {0} dagen geen updates geïnstalleerd
Windows hasn't updated itself in {0} days. Open Windows Update and let it check.	Windows heeft zichzelf al {0} dagen niet bijgewerkt. Open Windows Update en laat het controleren.
Last clean-up was {0} days ago ({1} of junk now)	De laatste opruimbeurt was {0} dagen geleden (nu {1} aan rommel)
It has been {0} days since the last clean-up; {1} of leftover files have piled up.	Het is {0} dagen geleden dat er is opgeruimd; er is {1} aan overbodige bestanden bijgekomen.
{0} program update(s) have been waiting for {1} days	{0} programma-update(s) wachten al {1} dagen
{0} program(s) have had a newer version waiting for {1} days - updates fix security holes.	Voor {0} programma('s) staat al {1} dagen een nieuwere versie klaar - updates dichten beveiligingslekken.
Restart the PC now?	De pc nu opnieuw opstarten?
Save your work first: open programs are closed, and programs with unsaved work will ask you first.	Sla eerst je werk op: open programma's worden gesloten, en programma's met niet-opgeslagen werk vragen het je eerst.
Remove checked	Aangevinkte verwijderen
That row is about Windows itself (every browser). Select a row of a browser first.	Die rij gaat over Windows zelf (alle browsers). Selecteer eerst een rij van een browser.
Check one or more policy, hosts file or proxy rows first (extensions are removed in the browser itself - use "Open extensions page").	Vink eerst een of meer rijen met een beleid, het hosts-bestand of een proxy aan (extensies verwijder je in de browser zelf - gebruik "Extensiepagina openen").
Removing browser policies and hosts file lines needs administrator rights - click "Restart as admin" first, or check only proxy rows.	Browserbeleid en regels in het hosts-bestand verwijderen vraagt beheerdersrechten - klik eerst op "Opnieuw als beheerder", of vink alleen proxy-rijen aan.
Remove these?	Deze verwijderen?
{0} line(s) removed	{0} regel(s) verwijderd
Windows: hosts file	Windows: hosts-bestand
Windows: {0}	Windows: {0}
Couldn't change the hosts file: {0}	Kon het hosts-bestand niet wijzigen: {0}
{0} item(s) removed. Restart the browser to see the change.	{0} item(s) verwijderd. Start de browser opnieuw om het verschil te zien.
Some of these changes need administrator rights to undo - use "Restart as administrator" first.	Voor sommige van deze wijzigingen zijn beheerdersrechten nodig om ze ongedaan te maken - gebruik eerst "Opnieuw als beheerder".
Hosts file moved	Hosts-bestand verplaatst
Hosts file	Hosts-bestand
Windows reads its hosts file from {0} instead of {1}	Windows leest zijn hosts-bestand uit {0} in plaats van {1}
Programs have no reason to move it - malware does this to hide its own hosts file. Have the PC scanned (Windows Security > Virus & threat protection > Scan options > Microsoft Defender Offline scan).	Programma's hebben geen reden om het te verplaatsen - malware doet dit om zijn eigen hosts-bestand te verbergen. Laat de pc scannen (Windows-beveiliging > Virus- en bedreigingsbeveiliging > Scanopties > Microsoft Defender Offline-scan).
Hosts file blocks {0}	Hosts-bestand blokkeert {0}
hosts file line: {0}	regel in het hosts-bestand: {0}
Malware blocks security and update sites so it can't be removed. Unless you added this yourself, remove the line (check it and click "Remove checked" - needs administrator), then have the PC scanned.	Malware blokkeert beveiligings- en updatesites zodat hij niet verwijderd kan worden. Heb je dit niet zelf toegevoegd, verwijder de regel dan (vink hem aan en klik op "Aangevinkte verwijderen" - beheerder nodig) en laat de pc daarna scannen.
Hosts file: {0} -> {1}	Hosts-bestand: {0} -> {1}
Points a name at a device in your own network (a NAS, printer or server). Fine if you set it up.	Wijst een naam naar een apparaat in je eigen netwerk (een NAS, printer of server). Prima als je dat zelf hebt ingesteld.
Sends a well-known website to a different server - the way hijackers show fake pages or ads. Unless you added this yourself, remove the line (check it and click "Remove checked" - needs administrator).	Stuurt een bekende website naar een andere server - zo tonen kapers nepsites of advertenties. Heb je dit niet zelf toegevoegd, verwijder de regel dan (vink hem aan en klik op "Aangevinkte verwijderen" - beheerder nodig).
Sends this name to a fixed address. Developers and some programs do this on purpose; if you don't know why it is there, remove the line (needs administrator).	Stuurt deze naam naar een vast adres. Ontwikkelaars en sommige programma's doen dat bewust; weet je niet waarom het er staat, verwijder de regel dan (beheerder nodig).
Hosts file blocks {0} site(s)	Hosts-bestand blokkeert {0} site(s)
in the file {0}	in het bestand {0}
Usually an ad or tracking blocker you installed. If websites or programs fail to connect, look here first.	Meestal een advertentie- of trackerblokker die je hebt geïnstalleerd. Als websites of programma's geen verbinding krijgen, kijk dan eerst hier.
no redirects or blocks	geen omleidingen of blokkades
Proxy: {0}	Proxy: {0}
every website goes through a program on this PC first	elke website gaat eerst door een programma op deze pc
every website goes through this server first	elke website gaat eerst door deze server
Fine for tools like Fiddler or some security programs. Otherwise it is often adware reading or changing your web pages: switch it off (check it and click "Remove checked").	Prima voor hulpmiddelen als Fiddler of sommige beveiligingsprogramma's. Anders is het vaak adware die je webpagina's leest of verandert: zet het uit (vink het aan en klik op "Aangevinkte verwijderen").
Fine if your school, work or VPN set it up. Otherwise someone can see and change everything you browse: switch it off (check it and click "Remove checked").	Prima als je school, werk of vpn dit heeft ingesteld. Anders kan iemand alles zien en veranderen wat je bekijkt: zet het uit (vink het aan en klik op "Aangevinkte verwijderen").
Proxy script: {0}	Proxyscript: {0}
a script decides which server each website goes through	een script bepaalt via welke server elke website gaat
Normal at work or school. On a home PC adware uses this to send your browsing through its own server: remove it (check it and click "Remove checked").	Normaal op het werk of op school. Op een thuis-pc gebruikt adware dit om je surfgedrag via zijn eigen server te sturen: verwijder het (vink het aan en klik op "Aangevinkte verwijderen").
none - the PC connects directly	geen - de pc maakt direct verbinding
Proxy	Proxy
Certificate: {0}	Certificaat: {0}
Certificate	Certificaat
a trusted root certificate known from adware (store {0})	een vertrouwd basiscertificaat dat bekend is van adware (opslag {0})
It lets adware read and change secure (https) websites. Uninstall the program that came with it (Programs page), then remove the certificate: Start > "Manage computer certificates" > Trusted Root Certification Authorities.	Hiermee kan adware beveiligde (https) websites lezen en veranderen. Verwijder het programma dat het meebracht (pagina Programma's) en daarna het certificaat: Start > "Computercertificaten beheren" > Vertrouwde basiscertificeringsinstanties.
Plugged in	Aangesloten
On battery	Op de accu
Best power efficiency	Beste energie-efficiëntie
Better performance	Betere prestaties
Best performance	Beste prestaties
Fast startup	Snel opstarten
How the PC uses power: plugged in it should be quick, on battery it should last and go to sleep by itself. Recommended fixes are pre-checked; every change can be undone from History.	Hoe de pc met energie omgaat: aangesloten moet hij snel zijn, op de accu moet hij lang meegaan en vanzelf in slaap gaan. Aanbevolen oplossingen zijn al aangevinkt; elke wijziging is ongedaan te maken via Geschiedenis.
Power settings	Energie-instellingen
Power plans	Energiebeheerschema's
custom	aangepast
Ultimate Performance	Ultieme prestaties
Power mode on battery	Energiestand op de accu
Power plan	Energiebeheerschema
Maximum processor speed	Maximale processorsnelheid
Turn off the screen after	Scherm uitzetten na
Sleep after	Slaapstand na
When I close the lid	Als ik de klep sluit
Hibernate after	Sluimerstand na
USB power saving	USB-energiebesparing
never	nooit
{0} min	{0} min
{0} h	{0} u
do nothing	niets doen
sleep	slaapstand
hibernate	sluimerstand
shut down	afsluiten
Plugged in, the PC is set to save energy, which makes it slower. Best performance makes it quick (the fan may run a little more).	Aangesloten staat de pc op energie besparen, waardoor hij trager is. Beste prestaties maakt hem snel (de ventilator draait misschien wat vaker).
Fine. For the most speed when plugged in, choose Best performance (fix below) - the fan may run a little more.	Prima. Voor de meeste snelheid als hij is aangesloten kies je Beste prestaties (oplossing hieronder) - de ventilator draait misschien wat vaker.
Best performance on battery empties it much faster. Balanced keeps the PC quick enough and lasts longer.	Beste prestaties op de accu maakt hem veel sneller leeg. Gebalanceerd houdt de pc snel genoeg en gaat langer mee.
Power saver slows the PC down all the time, also when plugged in. Balanced adjusts itself and lets you use the power mode slider.	Energiebesparing maakt de pc altijd trager, ook als hij is aangesloten. Gebalanceerd past zich aan en laat je de schuifregelaar voor de energiestand gebruiken.
Keeps the processor at full speed even on battery, which empties it faster, and switches off the power mode slider. Balanced with Best performance when plugged in is usually just as quick.	Houdt de processor ook op de accu op volle snelheid, waardoor die sneller leeg is, en schakelt de schuifregelaar voor de energiestand uit. Gebalanceerd met Beste prestaties als hij is aangesloten is meestal net zo snel.
Plugged in, the processor may only run at {0}% of its speed. Set it back to 100% (fix below).	Aangesloten mag de processor maar op {0}% van zijn snelheid draaien. Zet dit terug op 100% (oplossing hieronder).
Lower on battery - that saves battery. Fine.	Lager op de accu - dat spaart de accu. Prima.
On battery the screen is the biggest power user. Turning it off after 5 minutes without use makes the battery last longer.	Op de accu verbruikt het scherm het meest. Het na 5 minuten zonder gebruik uitzetten laat de accu langer meegaan.
The screen never turns off by itself when plugged in. That uses power and can wear the screen; 10 minutes is a good choice (fix below).	Het scherm gaat nooit vanzelf uit als de pc is aangesloten. Dat kost energie en kan het scherm slijten; 10 minuten is een goede keuze (oplossing hieronder).
On battery the PC stays awake for a long time when you leave it, which empties the battery. Going to sleep after 15 minutes saves it - your work stays open.	Op de accu blijft de pc lang wakker als je wegloopt, waardoor de accu leegloopt. Na 15 minuten in slaapstand gaan spaart hem - je werk blijft open.
The PC never sleeps by itself. Fine if it has to stay on (downloads, sharing); otherwise sleeping after 30 minutes saves power (fix below).	De pc gaat nooit vanzelf in slaapstand. Prima als hij aan moet blijven (downloads, delen); anders spaart slaapstand na 30 minuten energie (oplossing hieronder).
On battery the laptop keeps running with the lid closed - in a bag it gets hot and the battery runs flat. Sleep is safer (fix below).	Op de accu blijft de laptop draaien met de klep dicht - in een tas wordt hij heet en loopt de accu leeg. Slaapstand is veiliger (oplossing hieronder).
Plugged in it keeps running (handy with a separate screen). Nothing to do.	Aangesloten blijft hij draaien (handig met een apart scherm). Niets te doen.
Asleep on battery, the laptop slowly uses its charge. Hibernating after 3 hours of sleep keeps your work safe if you forget it for days (fix below).	In slaapstand op de accu verbruikt de laptop langzaam zijn lading. Na 3 uur slaap in sluimerstand gaan houdt je werk veilig als je hem dagen vergeet (oplossing hieronder).
Windows may switch off USB devices that seem idle. If a mouse, headset or drive disconnects by itself, switch this off for plugged in (fix below).	Windows kan USB-apparaten uitzetten die niets lijken te doen. Valt een muis, headset of schijf vanzelf weg, zet dit dan uit voor aangesloten (oplossing hieronder).
Shut down is then not a full restart - when something tells you to restart, use Restart. If the PC has problems after starting up (devices, updates), switching it off helps; starting takes a few seconds longer. Needs administrator.	Afsluiten is dan geen volledige herstart - als iets vraagt om opnieuw op te starten, gebruik dan Opnieuw opstarten. Heeft de pc problemen na het opstarten (apparaten, updates), dan helpt uitzetten; opstarten duurt dan een paar seconden langer. Beheerder nodig.
Every start is a full start. Nothing to do.	Elke start is een volledige start. Niets te doen.
Checking power settings	Energie-instellingen controleren
Plug in the charger first (or click "Restart as admin"), then try again.	Sluit eerst de oplader aan (of klik op "Opnieuw als beheerder"), en probeer het dan opnieuw.
Unplug the charger first (or click "Restart as admin"), then try again.	Koppel eerst de oplader los (of klik op "Opnieuw als beheerder"), en probeer het dan opnieuw.
Windows refused the power mode (error {0})	Windows weigerde de energiestand (fout {0})
These need administrator rights - click "Restart as admin" first, or uncheck them: {0}	Hiervoor zijn beheerdersrechten nodig - klik eerst op "Opnieuw als beheerder", of vink ze uit: {0}
Done: {0}. Undo from the History page.	Klaar: {0}. Ongedaan maken via de pagina Geschiedenis.
Not changed:	Niet gewijzigd:
{0} (plugged in)	{0} (aangesloten)
{0} (on battery)	{0} (op de accu)
set to {0}	ingesteld op {0}
set to Balanced	ingesteld op Gebalanceerd
changed	gewijzigd
Fix {0} power setting(s)	{0} energie-instelling(en) verbeteren
{0} power setting(s) make the PC slower or empty the battery faster than needed.	{0} energie-instelling(en) maken de pc trager of de accu sneller leeg dan nodig.
PC Tune-Up itself.	PC Tune-Up zelf.
Right now	Nu bezig
What is slowing the PC down at this moment: the programs using the most memory, processor and disk. Updates every few seconds while this page is open. Select a program and click End task to close it.	Wat de pc op dit moment vertraagt: de programma's die het meeste geheugen, de processor en de schijf gebruiken. Wordt elke paar seconden bijgewerkt zolang deze pagina open is. Selecteer een programma en klik op Taak beëindigen om het te sluiten.
End task	Taak beëindigen
Pause	Pauzeren
Resume	Hervatten
Task Manager	Taakbeheer
Measuring...	Meten...
{0} cores	{0} kernen
{0} of {1} in use	{0} van {1} gebruikt
{0} per second	{0} per seconde
Every open tab and extension uses memory. Close tabs you don't need; Shift+Esc in the browser shows which tab uses the most.	Elk open tabblad en elke extensie gebruikt geheugen. Sluit tabbladen die je niet nodig hebt; Shift+Esc in de browser laat zien welk tabblad het meeste gebruikt.
Windows Security checking for viruses. It finishes by itself - leave it running.	Windows-beveiliging controleert op virussen. Dat stopt vanzelf - laat het draaien.
Windows Update installing updates. Let it finish, and restart when Windows asks.	Windows Update installeert updates. Laat het afmaken en start opnieuw op als Windows erom vraagt.
Windows Search indexing your files so searching is quick. It slows down by itself while you use the PC.	Windows Zoeken indexeert je bestanden zodat zoeken snel gaat. Het remt vanzelf af terwijl je de pc gebruikt.
Syncing files with the cloud. It calms down when syncing is finished.	Synchroniseert bestanden met de cloud. Het wordt rustiger als het synchroniseren klaar is.
A chat app that keeps running in the background. Quit it from its icon next to the clock when you don't need it.	Een chat-app die op de achtergrond blijft draaien. Sluit hem af via zijn pictogram naast de klok als je hem niet nodig hebt.
A game launcher. It downloads updates in the background; quit it when you are not playing.	Een game-launcher. Hij downloadt updates op de achtergrond; sluit hem af als je niet speelt.
Windows squeezing memory to make room - a sign that memory is nearly full. Closing programs helps.	Windows perst het geheugen samen om ruimte te maken - een teken dat het geheugen bijna vol is. Programma's sluiten helpt.
Windows drawing the screen. Busier with animations, videos and extra screens.	Windows tekent het scherm. Drukker bij animaties, video's en extra schermen.
Windows answering questions about the PC (PC Tune-Up asks it too, while this page is open).	Windows beantwoordt vragen over de pc (PC Tune-Up vraagt ook dingen, zolang deze pagina open is).
Part of Windows. Leave it running; if it stays busy for a long time, a restart usually helps.	Onderdeel van Windows. Laat het draaien; blijft het lang druk, dan helpt opnieuw opstarten meestal.
A background service (part of Windows or of another program). Leave it running; the Services page shows which ones you can switch off.	Een achtergrondservice (van Windows of van een ander programma). Laat hem draaien; de pagina Services laat zien welke je kunt uitzetten.
Uses a lot of memory. Close it when you don't need it.	Gebruikt veel geheugen. Sluit het als je het niet nodig hebt.
Keeps the processor busy. If you aren't using it, close it.	Houdt de processor bezig. Gebruik je het niet, sluit het dan.
Reading or writing a lot on the disk right now.	Leest of schrijft nu veel op de schijf.
Memory is nearly full ({0}% in use) - that slows everything down. {1} uses the most ({2}).	Het geheugen is bijna vol ({0}% in gebruik) - dat maakt alles traag. {1} gebruikt het meeste ({2}).
The processor is very busy ({0}%). {1} uses the most ({2}%).	De processor is erg druk ({0}%). {1} gebruikt het meeste ({2}%).
The disk is very busy ({0}%). {1} reads and writes the most.	De schijf is erg druk ({0}%). {1} leest en schrijft het meeste.
Memory is getting full ({0}% in use). Closing programs you don't use keeps the PC quick.	Het geheugen raakt vol ({0}% in gebruik). Programma's sluiten die je niet gebruikt houdt de pc snel.
Nothing is slowing the PC down right now.	Er is nu niets dat de pc vertraagt.
{0} process(es) - memory {1}, processor {2}%, disk {3}	{0} proces(sen) - geheugen {1}, processor {2}%, schijf {3}
{0} is part of Windows or runs as a background service, so PC Tune-Up doesn't end it.	{0} is onderdeel van Windows of draait als achtergrondservice, dus PC Tune-Up beëindigt het niet.
End {0}?	{0} beëindigen?
It closes straight away ({0} process(es)). Anything not saved in it is lost - save your work first.	Het sluit meteen ({0} proces(sen)). Wat er niet in is opgeslagen gaat verloren - sla je werk eerst op.
Couldn't end {0} - it may need administrator rights, or it already closed.	Kon {0} niet beëindigen - misschien zijn beheerdersrechten nodig, of het was al gesloten.
ended	beëindigd
See what is using the processor and memory right now	Bekijk wat de processor en het geheugen nu gebruikt
Memory is {0}% full - see what is using it	Het geheugen is voor {0}% vol - bekijk wat het gebruikt
The PC's memory is almost full, which makes everything slow. Closing programs you don't use helps.	Het geheugen van de pc is bijna vol, waardoor alles traag wordt. Programma's sluiten die je niet gebruikt helpt.
Measuring the result	Het resultaat meten
Last fix	Reparatie
{0} - Fix my PC freed {1}	{0} - Pc repareren maakte {1} vrij
{0} s now, {1} s before Fix my PC	nu {0} s, {1} s vóór Pc repareren
same	gelijk
{0} fewer	{0} minder
{0} more	{0} meer
Junk files removed	Rommelbestanden verwijderd
Free space on {0}	Vrije ruimte op {0}
Apps that start with Windows	Apps die met Windows starten
Background services trimmed	Achtergrondservices beperkt
Things worth a look	Dingen om naar te kijken
after the next restart	na de volgende herstart
Fix my PC: before and after	Pc repareren: voor en na
Stopped early - this is what changed so far	Vroeg gestopt - dit is er tot nu toe veranderd
Done! This is what changed	Klaar! Dit is er veranderd
Before	Voor
After	Na
Start-up changes take effect next time you sign in. Undo anything from the History page.	Wijzigingen bij het opstarten gaan in de volgende keer dat je je aanmeldt. Alles is ongedaan te maken op de pagina Geschiedenis.
Open History	Geschiedenis openen
...and {0} more	...en nog {0}
Switch off these {0} scheduled task(s)?	Deze {0} geplande ta(a)k(en) uitzetten?
Turn off these {0} Windows setting(s)?	Deze {0} Windows-instelling(en) uitzetten?
Apply these {0} fix(es)?	Deze {0} oplossing(en) toepassen?
You can undo this on the History page.	Terugdraaien kan op de pagina Geschiedenis.
Select a row in the list first, then click the button again.	Selecteer eerst een rij in de lijst en klik dan nog een keer op de knop.
There is no setting to open for this row - see "What to do" below the list.	Voor deze rij is er geen instelling om te openen - zie "Wat te doen" onder de lijst.
Advanced view	Geavanceerde weergave
Show every page and tool. You can come back to this simple view at any time.	Toon elke pagina en elk hulpmiddel. Je kunt altijd terug naar deze eenvoudige weergave.
Most can be fixed with one click - see the list below.	De meeste los je op met één klik - zie de lijst hieronder.
Checking your PC - the list appears here in a moment.	Je pc wordt gecontroleerd - de lijst verschijnt hier zo.
Back to the simple view	Terug naar de eenvoudige weergave
Simple view shows one calm screen with three big buttons and only safe fixes - best for most people. Advanced view shows every page.	De eenvoudige weergave toont één rustig scherm met drie grote knoppen en alleen veilige oplossingen - het beste voor de meeste mensen. De geavanceerde weergave toont elke pagina.
Checking your PC...	Je pc wordt gecontroleerd...
This takes about half a minute.	Dit duurt ongeveer een halve minuut.
Make my PC faster	Maak mijn pc sneller
Removes leftover files and stops apps you don't need	Verwijdert restbestanden en stopt apps die je niet nodig hebt
Check for problems	Controleer op problemen
Shows what could be better, in plain words	Laat in gewone woorden zien wat beter kan
Get help	Hulp vragen
Send a report to someone who helps you	Stuur een rapport naar iemand die je helpt
What could be better	Wat beter kan
Nothing to do	Niets te doen
Everything looks fine. PC Tune-Up checks again next time you open it.	Alles ziet er goed uit. PC Tune-Up controleert opnieuw als je het weer opent.
Fix this	Oplossen
Show me	Laat zien
Send a report about this PC to a family member or friend who helps you - by email, with the report attached.	Stuur een rapport over deze pc naar een familielid of vriend die je helpt - per e-mail, met het rapport als bijlage.
Send by email	Per e-mail sturen
Copy a short summary to paste into WhatsApp, a text message or a chat.	Kopieer een korte samenvatting om in WhatsApp, een sms of een chat te plakken.
Copy summary	Samenvatting kopiëren
Something in PC Tune-Up itself not working? Tell the people who make it.	Werkt er iets in PC Tune-Up zelf niet? Laat het de makers weten.
Report a problem	Probleem melden
See the short introduction again.	Bekijk de korte uitleg nog eens.
Show the tour	Rondleiding tonen
Something needs attention	Er vraagt iets om aandacht
{0} thing(s) could be better	{0} punt(en) kunnen beter
Click "Check for problems" to see them - most can be fixed with one click.	Klik op "Controleer op problemen" om ze te zien - de meeste los je op met één klik.
Your PC is in good shape	Je pc is in goede staat
Nothing needs doing right now.	Er hoeft nu niets te gebeuren.
(Still checking...)	(Nog bezig met controleren...)
Stop these apps from starting by themselves?	Deze apps niet meer vanzelf laten starten?
They stay installed - you can still open them whenever you want. You can undo this on the History page.	Ze blijven geïnstalleerd - je kunt ze nog steeds openen wanneer je wilt. Terugdraaien kan op de pagina Geschiedenis.
Done. Your PC will start a little faster next time.	Klaar. Je pc start de volgende keer iets sneller.
Turn off Windows ads, tips and extra data sharing?	Advertenties, tips en extra gegevensdeling van Windows uitzetten?
Your files and programs are not touched. You can undo this on the History page.	Je bestanden en programma's worden niet aangeraakt. Terugdraaien kan op de pagina Geschiedenis.
Switch off helper programs from other companies that run in the background by themselves (updaters and data collection)?	Hulpprogramma's van andere bedrijven uitzetten die vanzelf op de achtergrond draaien (updaters en gegevensverzameling)?
The programs themselves keep working. You can undo this on the History page.	De programma's zelf blijven gewoon werken. Terugdraaien kan op de pagina Geschiedenis.
PC Tune-Up report for {0}	PC Tune-Up-rapport voor {0}
Date: {0}	Datum: {0}
Memory: {0}% used, drive C: {1} free	Geheugen: {0}% in gebruik, schijf C: {1} vrij
Could be better:	Kan beter:
Everything looks fine.	Alles ziet er goed uit.
A short summary is copied. Paste it (Ctrl+V) into WhatsApp, a text message or an email to the person who helps you.	Er is een korte samenvatting gekopieerd. Plak die (Ctrl+V) in WhatsApp, een sms of een e-mail aan degene die je helpt.
Couldn't copy: {0}	Kon niet kopiëren: {0}
This saves a report about this PC in Documents and starts an email to the person who helps you.	Dit bewaart een rapport over deze pc in Documenten en begint een e-mail aan degene die je helpt.
The report shows how the PC is doing, what it found and which programs are installed. It contains no passwords, no files and no browsing history.	Het rapport laat zien hoe het met de pc gaat, wat er is gevonden en welke programma's er zijn geïnstalleerd. Er staan geen wachtwoorden, bestanden of surfgeschiedenis in.
Couldn't save the report: {0}	Kon het rapport niet opslaan: {0}
My PC - report from PC Tune-Up	Mijn pc - rapport van PC Tune-Up
Hi, could you have a look at my PC? The report from PC Tune-Up is attached.	Hoi, wil je even naar mijn pc kijken? Het rapport van PC Tune-Up zit als bijlage bij.
(The full report is the file "{0}" in my Documents folder - I will attach it.)	(Het volledige rapport is het bestand "{0}" in mijn map Documenten - ik voeg het toe.)
An email has been started, and the report is selected in File Explorer.	Er is een e-mail begonnen, en het rapport is geselecteerd in Verkenner.
Drag the file "{0}" into the email (or use the paperclip), then send it.	Sleep het bestand "{0}" naar de e-mail (of gebruik de paperclip) en verstuur hem.
Help	Hulp
Report	Rapport
saved to Documents for sending ({0})	opgeslagen in Documenten om te versturen ({0})
Telemetry: information about how you use your PC that is sent to the maker.	Telemetrie: informatie over hoe je je pc gebruikt die naar de maker wordt gestuurd.
Scheduled task: a small job Windows starts by itself at set times, often an updater.	Geplande taak: een klein klusje dat Windows zelf op vaste tijden start, vaak een updater.
Service: a program that runs in the background without a window.	Service: een programma dat zonder venster op de achtergrond draait.
DNS: the internet's phone book - it turns website names into addresses.	DNS: het telefoonboek van internet - het zet namen van websites om in adressen.
Hibernation file: a hidden file where Windows saves everything when the PC goes into deep sleep.	Slaapstandbestand: een verborgen bestand waarin Windows alles bewaart als de pc in diepe slaap gaat.
Paging file: space on the drive that Windows uses when the memory is full.	Wisselbestand: ruimte op de schijf die Windows gebruikt als het geheugen vol is.
BIOS: the built-in software that starts the PC before Windows.	BIOS: de ingebouwde software die de pc start vóór Windows.
Driver: the small program that lets Windows talk to a part of the PC, such as the screen or Wi-Fi.	Stuurprogramma: het kleine programma waarmee Windows met een onderdeel van de pc praat, zoals het scherm of de wifi.
Restore point: a snapshot of Windows' settings you can go back to if something goes wrong.	Herstelpunt: een momentopname van de instellingen van Windows waar je naar terug kunt als er iets misgaat.
Reserved storage: disk space Windows keeps free so updates always have room.	Gereserveerde opslag: schijfruimte die Windows vrijhoudt zodat updates altijd ruimte hebben.
Storage Sense: Windows' own automatic clean-up.	Opslaginzicht: het eigen automatische opruimen van Windows.
winget: Windows' built-in tool for installing and updating programs.	winget: het ingebouwde hulpmiddel van Windows om programma's te installeren en bij te werken.
Policy: a setting that is forced on the PC, normally by a company's IT department.	Beleid: een instelling die de pc wordt opgelegd, normaal door de IT-afdeling van een bedrijf.
Extension: an add-on for a web browser.	Extensie: een uitbreiding voor een webbrowser.
Fast startup: Windows saves part of itself when you shut down, so it starts quicker.	Snel opstarten: Windows bewaart een deel van zichzelf bij het afsluiten, zodat het sneller start.
Bloatware: programs the PC maker installed that most people never use.	Bloatware: programma's die de pc-maker heeft geïnstalleerd en die de meeste mensen nooit gebruiken.
Cache: copies a program keeps to work faster. Safe to delete - they come back when needed.	Cache: kopieën die een programma bewaart om sneller te werken. Veilig om te verwijderen - ze komen terug als ze nodig zijn.
Crash dump: a record saved when a program crashed, only useful to its makers.	Crashgegevens: een verslag dat wordt bewaard als een programma crasht, alleen nuttig voor de makers.
GPU: the graphics card - the part that draws everything on the screen.	GPU: de videokaart - het onderdeel dat alles op het scherm tekent.
Adware: software that shows you advertisements or changes your browser to make money.	Adware: software die je advertenties laat zien of je browser aanpast om geld te verdienen.
Firmware: software built into a part of the PC, such as the BIOS or the drive.	Firmware: software die in een onderdeel van de pc is ingebouwd, zoals het BIOS of de schijf.
PC Tune-Up will now:	PC Tune-Up gaat nu:
 - delete leftover files that Windows and apps make again by themselves	 - restbestanden verwijderen die Windows en apps vanzelf opnieuw aanmaken
 - stop {0} app(s) from starting by themselves (they stay installed)	 - {0} app(s) niet meer vanzelf laten starten (ze blijven geïnstalleerd)
 - switch off background programs from the PC maker that are not needed	 - onnodige achtergrondprogramma's van de pc-maker uitzetten
Your documents, photos and programs are not touched. You can undo the other changes on the History page.	Je documenten, foto's en programma's worden niet aangeraakt. De andere wijzigingen kun je terugdraaien op de pagina Geschiedenis.
Done! {0} of leftover files removed.	Klaar! {0} aan restbestanden verwijderd.
Your PC will start a little faster next time.	Je pc start de volgende keer iets sneller.
Your PC is tidier now.	Je pc is nu opgeruimder.
Your documents, photos and programs are not touched.	Je documenten, foto's en programma's worden niet aangeraakt.
View	Weergave
Simple view shows one calm screen with three big buttons and only safe fixes - best for most people. All tools shows every page.	De eenvoudige weergave toont één rustig scherm met drie grote knoppen en alleen veilige oplossingen - het beste voor de meeste mensen. Alle hulpmiddelen toont elke pagina.
Simple view	Eenvoudige weergave
All tools	Alle hulpmiddelen
Send a report to someone who helps you...	Rapport sturen naar iemand die je helpt...
Copy a short summary	Korte samenvatting kopiëren
Show the programs using the most memory	Programma's tonen die het meeste geheugen gebruiken
Back to the readings	Terug naar de metingen
'@
# Case-sensitive lookups: "Claude" (a program) and "claude" (a process) are different texts.
$script:TExact = New-Object Collections.Hashtable([StringComparer]::Ordinal)
$script:TCache = New-Object Collections.Hashtable([StringComparer]::Ordinal)
$script:TPatterns = @()
# Dates and numbers in the chosen language too (3,5 / okt 2028).
$UiCulture = switch ($Lang) { 'nl' { [Globalization.CultureInfo]::GetCultureInfo('nl-NL') } 'de' { [Globalization.CultureInfo]::GetCultureInfo('de-DE') } 'fr' { [Globalization.CultureInfo]::GetCultureInfo('fr-FR') } 'es' { [Globalization.CultureInfo]::GetCultureInfo('es-ES') } 'it' { [Globalization.CultureInfo]::GetCultureInfo('it-IT') } 'pl' { [Globalization.CultureInfo]::GetCultureInfo('pl-PL') } default { [Globalization.CultureInfo]::CurrentCulture } }
[Threading.Thread]::CurrentThread.CurrentCulture = $UiCulture
# The other languages live in lang\<code>.tsv (German, French, Spanish, Italian, Polish; same format), built into the exe as resources.
function Get-LangTable([string]$Code) {
    if ($Code -eq 'nl') { return $NLTable }
    try {
        if ($RunningAsExe) {
            $st = [Reflection.Assembly]::GetEntryAssembly().GetManifestResourceStream("$Code.tsv")
            if ($st) { try { return (New-Object IO.StreamReader($st, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $st.Dispose() } }
        }
        $dir = if ($env:PCTUNEUP_LANGDIR) { $env:PCTUNEUP_LANGDIR } else { Join-Path (Split-Path -Parent $PSCommandPath) 'lang' }
        $file = Join-Path $dir "$Code.tsv"
        if (Test-Path $file) { return [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) }
    } catch { }
    ''
}
if ($Lang -ne 'en') {
    $pats = foreach ($line in (Get-LangTable $Lang) -split "`r?`n") {
        if (-not $line.Trim()) { continue }
        $en, $nl = $line -split "`t", 2
        if ($en -notmatch '\{\d+\}') { $script:TExact[$en] = $nl; continue }
        $rx = '^' + ([regex]::Escape($en) -replace '\\\{(\d+)}', '(?<p$1>.+?)') + '$'
        @{ Rx = [regex]::new($rx); Nl = $nl; N = ([regex]::Matches($en, '\{\d+\}')).Count; Lit = ($en -replace '\{\d+\}', '').Length }
    }
    $script:TPatterns = @($pats | Sort-Object { $_.Lit } -Descending)   # most specific first; "{0}: {1}" comes last
}
function T([string]$Text, [int]$Depth = 0) {
    if ($Lang -eq 'en' -or -not $Text -or $Depth -gt 3) { return $Text }
    if ($script:TCache.ContainsKey($Text)) { return $script:TCache[$Text] }
    $out = $Text
    if ($Text -match "`n") { $out = (($Text -split "`r?`n") | ForEach-Object { T $_ $Depth }) -join "`r`n" }
    elseif ($Text -match '^(\s*(?:(?:[-!]|\u2022)\s+)?)(.*?)(\s*)$' -and $Matches[2]) {
        $pre = $Matches[1]; $core = $Matches[2]; $post = $Matches[3]
        if ($script:TExact.ContainsKey($core)) { $out = $pre + $script:TExact[$core] + $post }
        else {
            foreach ($p in $script:TPatterns) {
                $m = $p.Rx.Match($core)
                if (-not $m.Success) { continue }
                $vals = @(for ($i = 0; $i -lt $p.N; $i++) { T $m.Groups["p$i"].Value ($Depth + 1) })
                $out = $pre + ($p.Nl -f $vals) + $post
                break
            }
        }
    }
    if ($script:TCache.Count -lt 20000) { $script:TCache[$Text] = $out }
    $out
}
# Translate a window's controls now, and again whenever their text changes later.
function Enable-Translation($Control) {
    if ($Lang -eq 'en') { return }
    $translatable = $Control -is [Windows.Forms.Label] -or $Control -is [Windows.Forms.ButtonBase] -or
                    ($Control -is [Windows.Forms.TextBox] -and $Control.ReadOnly)
    if ($translatable) {
        $Control.Text = T $Control.Text
        $Control.Add_TextChanged({ if (-not $script:InT) { $script:InT = $true; $t = T $this.Text; if ($t -ne $this.Text) { $this.Text = $t }; $script:InT = $false } })
    }
    if ($Control -is [Windows.Forms.ListView]) { foreach ($c in $Control.Columns) { $c.Text = T $c.Text } }
    foreach ($child in $Control.Controls) { Enable-Translation $child }
}
# Installed copy: per user, no administrator needed (like most modern apps).
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\PC Tune-Up'
$InstalledExe = Join-Path $InstallDir 'PC-TuneUp.exe'
$IsInstalled = $RunningAsExe -and ($SelfExe -eq $InstalledExe)
# Installed with winget ("winget install MichaelKloprogge.PCTuneUp"): winget owns the file, so it also does the updates.
$FromWinget = $RunningAsExe -and $SelfExe -match '\\Microsoft\\WinGet\\(Packages|Links)\\'

function Write-Log([string]$Msg) {
    Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Msg) -Encoding UTF8
}
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N0} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} KB' -f ($Bytes / 1KB) }
}
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    [Windows.Forms.MessageBox]::Show((T $Text), 'PC Tune-Up', $Buttons, $Icon)
}

# History: every change, with what's needed to undo it (Undo = $null when it can't be).
function Add-History([string]$Kind, [string]$Item, [string]$Change, $Undo = $null) {
    $e = [ordered]@{ Id = [guid]::NewGuid().ToString('N'); Time = (Get-Date).ToString('s'); Kind = $Kind
                     Item = $Item; Change = $Change; Undo = $Undo; Undone = $false }
    Add-Content -Path $HistoryFile -Value ($e | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
    Write-Log "${Kind}: $Item - $Change"
}
function Get-History {
    if (-not (Test-Path $HistoryFile)) { return }
    Get-Content $HistoryFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
}
function Save-History($Entries) {
    Set-Content -Path $HistoryFile -Value @($Entries | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 6 }) -Encoding UTF8
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
# Run a console program hidden and capture its output as UTF-8 (winget prints Unicode names).
function Invoke-Native([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 600) {
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $p.WaitForExit(500)) {   # check twice a second whether the user pressed Cancel
        if (($Job -and $Job.Cancel) -or (Get-Date) -gt $deadline) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ Out = ''; Code = -1; TimedOut = -not ($Job -and $Job.Cancel); Cancelled = [bool]($Job -and $Job.Cancel) }
        }
    }
    [pscustomobject]@{ Out = $out.Result + $err.Result; Code = $p.ExitCode; TimedOut = $false; Cancelled = $false }
}
# Report progress to the activity bar ($Job is shared with the window; it is $null in plain runs).
function Set-JobProgress([string]$Text, [int]$Value = -1, [int]$Max = 0) {
    if ($Job) { $Job.Text = $Text; $Job.Value = $Value; $Job.Max = $Max }
}
function Test-Cancelled { [bool]($Job -and $Job.Cancel) }
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
# -Label shows the job in the activity bar at the bottom of the window; -Cancellable adds a Cancel button.
# The Done block gets the results, and the job's state as a second argument ($State.Cancel says if it was stopped).
function Start-Bg([scriptblock]$Work, $Arg, [scriptblock]$Done, [string]$Label, [switch]$Cancellable) {
    # param() must come first in a script, so the work block runs as a nested block after the helpers.
    $code = "param(`$BgArg)`n$Helpers`n& {`n$Work`n} `$BgArg"
    $state = [hashtable]::Synchronized(@{ Text = ''; Value = -1; Max = 0; Cancel = $false })
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('Job', $state)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($code).AddArgument($Arg)
    [void]$script:Jobs.Add(@{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Done = $Done; Label = $Label; State = $state; Cancellable = [bool]$Cancellable })
    if ($activity) { Update-ActivityBar }
}
# Page data is loaded in the background a few jobs at a time, so the window opens instantly.
$script:LoadQueue = New-Object System.Collections.ArrayList
$JobTimer = New-Object Windows.Forms.Timer
$JobTimer.Interval = 250
$JobTimer.Add_Tick({
    $tick = [Diagnostics.Stopwatch]::StartNew()
    foreach ($j in @($script:Jobs)) {
        if ($tick.ElapsedMilliseconds -gt 100) { break }   # several finished at once: show the rest next tick, so the window keeps responding
        if (-not $j.Handle.IsCompleted) { continue }
        [void]$script:Jobs.Remove($j)
        $what = if ($j.Label) { $j.Label } else { 'a background check' }
        try { $result = @($j.PS.EndInvoke($j.Handle)) }
        catch {
            $result = @(); Write-AppError "$what (background)" $_
            if ((Show-Msg "Something went wrong:`n$($_.Exception.Message)`n`nReport this problem? (Opens GitHub with the details filled in - you see everything before you send it.)" 'YesNo' 'Warning') -eq 'Yes') { Open-ProblemReport 'bug' }
        }
        foreach ($e in @($j.PS.Streams.Error)) { Write-AppError "$what (background)" $e }   # errors the check didn't expect
        $j.PS.Dispose(); $j.RS.Dispose()
        try {
            & $j.Done $result $j.State
        } catch { Write-AppError "$what (showing the result)" $_ }
    }
    while ($script:LoadQueue.Count -and $script:Jobs.Count -lt 4) {   # four checks at a time
        $next = $script:LoadQueue[0]; $script:LoadQueue.RemoveAt(0)
        Invoke-PageLoader $next
    }
    if ($activity) { Update-ActivityBar }
    if ($script:ReportPending -and -not $script:Jobs.Count -and -not $script:LoadQueue.Count) { $script:ReportPending = $false; Save-ReportNow }
    if ($script:EverythingStarted -and -not $script:ScoreSaved -and -not $script:Jobs.Count -and -not $script:LoadQueue.Count) { $script:ScoreSaved = $true; Save-Score }
})
$JobTimer.Start()

# ---------------------------------------------------------------------------
# Window, theme and layout helpers
# ---------------------------------------------------------------------------
# Light and dark palettes. Settings > Theme picks one; the default follows Windows.
function Rgb([int]$R, [int]$G, [int]$B) { [Drawing.Color]::FromArgb($R, $G, $B) }
$WindowsDark = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 0
$Dark = switch ($Settings.Theme) { 'dark' { $true } 'light' { $false } default { $WindowsDark } }
$Theme = if (-not $Dark) {
    @{  Bg = (Rgb 255 255 255); Input = (Rgb 255 255 255); Side = (Rgb 243 244 246); Hover = (Rgb 229 231 235)
        Text = (Rgb 32 32 32); Dim = (Rgb 105 105 110); Border = (Rgb 206 209 214); Soft = (Rgb 246 247 249)
        Accent = (Rgb 0 103 192); AccentDark = (Rgb 0 84 160); AccentSoft = (Rgb 222 236 250); AccentText = (Rgb 0 95 180)
        WarnBg = (Rgb 255 245 219); WarnText = (Rgb 128 68 0)
        Bad = (Rgb 176 32 32); Warn = (Rgb 196 98 0); Good = (Rgb 20 120 50); Muted = (Rgb 130 130 135) }
} else {
    @{  Bg = (Rgb 32 32 34); Input = (Rgb 45 45 48); Side = (Rgb 43 43 46); Hover = (Rgb 58 58 62)
        Text = (Rgb 236 236 236); Dim = (Rgb 165 165 170); Border = (Rgb 82 82 88); Soft = (Rgb 44 44 48)
        Accent = (Rgb 0 110 205); AccentDark = (Rgb 0 92 175); AccentSoft = (Rgb 36 58 86); AccentText = (Rgb 110 180 255)
        WarnBg = (Rgb 64 50 22); WarnText = (Rgb 255 208 130)
        Bad = (Rgb 255 120 110); Warn = (Rgb 255 178 80); Good = (Rgb 110 205 135); Muted = (Rgb 140 140 146) }
}
# Dark title bar, scrollbars and list headers (Windows 10 1809 and later).
function Set-DarkChrome($Control, [string]$ThemeName = 'DarkMode_Explorer') {
    if (-not $Dark) { return }
    try { [void][PcTuneUp.Native]::SetWindowTheme($Control.Handle, $ThemeName, $null) } catch { }
}
$Font = New-Object Drawing.Font('Segoe UI', 9.75)
$FontBold = New-Object Drawing.Font('Segoe UI Semibold', 9.75)
$FontSmall = New-Object Drawing.Font('Segoe UI Semibold', 8.25)
$FontTitle = New-Object Drawing.Font('Segoe UI Semibold', 16)
$form = New-Object Windows.Forms.Form
$form.Text = "PC Tune-Up $AppVersion" + $(if ($IsAdmin) { '  (Administrator)' } else { '' })
# Sizes below are written for 100% scaling; Scale-ToScreen grows the whole window to the screen's scaling just before it opens.
$form.AutoScaleMode = 'None'
$form.ClientSize = New-Object Drawing.Size(1140, 740)
$form.StartPosition = 'CenterScreen'
$form.Font = $Font; $form.BackColor = $Theme.Bg; $form.ForeColor = $Theme.Text
$form.Add_HandleCreated({
    if ($Dark) { $on = 1; try { [void][PcTuneUp.Native]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) } catch { } }   # 20 = dark title bar
})
if ($RunningAsExe) { try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($SelfExe) } catch { } }

# A sidebar on the left picks which page shows in the content area (see Build-Sidebar at the end).
$content = New-Object Windows.Forms.Panel
$content.Dock = 'Fill'; $content.BackColor = $Theme.Bg
$sidebar = New-Object Windows.Forms.Panel
$sidebar.Dock = 'Left'; $sidebar.Width = 204; $sidebar.BackColor = $Theme.Side
$form.Controls.Add($content); $form.Controls.Add($sidebar)
$script:Pages = New-Object System.Collections.ArrayList

function New-Page([string]$Title, [string]$IntroText) {
    $page = New-Object Windows.Forms.Panel
    $page.Name = $Title; $page.Text = $Title; $page.Dock = 'Fill'; $page.Visible = $false
    $page.Padding = New-Object Windows.Forms.Padding(26, 16, 26, 12); $page.BackColor = $Theme.Bg
    $content.Controls.Add($page)
    [void]$script:Pages.Add($page)
    $head = New-Object Windows.Forms.Panel
    $head.Dock = 'Top'; $head.Height = 80
    $t = New-Object Windows.Forms.Label
    $t.Text = $Title; $t.Font = $FontTitle; $t.Dock = 'Top'; $t.Height = 36
    $d = New-Object Windows.Forms.Label
    $d.Text = $IntroText; $d.ForeColor = $Theme.Dim; $d.Dock = 'Fill'
    $head.Controls.Add($d); $head.Controls.Add($t)
    $page.Tag = $head
    $page
}
# Docking is laid out last-added-first, so: Fill control, then bottom, then
# top controls from the lowest one upward.
function Set-PageLayout($Page, $Fill, [object[]]$Tops, $Bottom) {
    # Tab moves through the page top to bottom: buttons, then the list, then the details.
    $n = 0; foreach ($t in $Tops) { $t.TabIndex = $n++ }; $Fill.TabIndex = $n++; if ($Bottom) { $Bottom.TabIndex = $n }
    if ($Fill -is [Windows.Forms.ListView]) { $Fill.AccessibleName = "$($Page.Name)"; $Fill.AccessibleDescription = $Page.Tag.Controls[0].Text }
    $Page.Controls.Add($Fill)
    if ($Bottom) { $Page.Controls.Add($(if ($Bottom.Wrapper) { $Bottom.Wrapper } else { $Bottom })) }
    [array]::Reverse($Tops)
    foreach ($t in $Tops) { $Page.Controls.Add($t) }
    $Page.Controls.Add($Page.Tag)
}
function New-ButtonBar([object[]]$Buttons) {
    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Top'; $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'; $bar.WrapContents = $true
    $bar.Padding = New-Object Windows.Forms.Padding(0, 2, 0, 6)
    foreach ($b in $Buttons) { $bar.Controls.Add($b) }
    $bar
}
function New-Button([string]$Text) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text; $b.AutoSize = $true; $b.MinimumSize = New-Object Drawing.Size(0, 34)
    $b.Padding = New-Object Windows.Forms.Padding(10, 0, 10, 0); $b.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 6)
    $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false; $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.BackColor = $Theme.Bg; $b.ForeColor = $Theme.Text; $b.FlatAppearance.BorderColor = $Theme.Border; $b.FlatAppearance.MouseOverBackColor = $Theme.Soft
    $b.FlatAppearance.BorderSize = 0
    # Drawn by us: rounded corners, a soft border, a hover colour, readable disabled text (Windows' fixed grey is unreadable in dark mode).
    $b.Add_Paint({ param($sender, $e) Draw-Button $sender $e.Graphics })
    $b.Add_MouseEnter({ $script:HotButton = $this; $this.Invalidate() })
    $b.Add_MouseLeave({ if ($script:HotButton -eq $this) { $script:HotButton = $null }; $this.Invalidate() })
    $b
}
# A rounded rectangle, used for buttons, the sidebar and the progress bar.
function New-RoundRect([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [single][Math]::Max([double]1, [Math]::Min([double]($R * 2), [Math]::Min([double]$W, [double]$H)))
    $p.AddArc($X, $Y, $d, $d, 180, 90); $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90); $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90); $p.CloseFigure()
    $p
}
function Draw-Button($B, $G) {
    $G.SmoothingMode = 'AntiAlias'
    $G.Clear($(if ($B.Parent) { $B.Parent.BackColor } else { $Theme.Bg }))
    $primary = $B.BackColor.ToArgb() -eq $Theme.Accent.ToArgb()
    $fill = if (-not $B.Enabled) { if ($primary) { $Theme.Soft } else { $B.BackColor } } elseif ($script:HotButton -eq $B) { $B.FlatAppearance.MouseOverBackColor } else { $B.BackColor }
    $path = New-RoundRect 0.5 0.5 ($B.Width - 1.5) ($B.Height - 1.5) (Px 6)
    $br = New-Object Drawing.SolidBrush($fill); $G.FillPath($br, $path); $br.Dispose()
    if (-not $primary -or -not $B.Enabled) { $pen = New-Object Drawing.Pen($(if ($script:HotButton -eq $B -and $B.Enabled) { $Theme.Dim } else { $Theme.Border })); $G.DrawPath($pen, $path); $pen.Dispose() }
    $path.Dispose()
    $flags = [Windows.Forms.TextFormatFlags]'VerticalCenter, EndEllipsis'
    if ($B.TextAlign -in 'MiddleLeft', 'TopLeft', 'BottomLeft') { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::Left } else { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::HorizontalCenter }
    if ($B.Text -match "`n") { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::WordBreak }
    if (-not $B.UseMnemonic) { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::NoPrefix }
    # Centred text may use the padding too: Windows sizes the button a little too narrow for long (translated) texts.
    $r = if ($flags -band [Windows.Forms.TextFormatFlags]::HorizontalCenter) { New-Object Drawing.Rectangle(2, 0, ($B.Width - 4), $B.Height) }
         else { New-Object Drawing.Rectangle($B.Padding.Left, 0, ($B.Width - $B.Padding.Horizontal), $B.Height) }
    [Windows.Forms.TextRenderer]::DrawText($G, $B.Text, $B.Font, $r, $(if ($B.Enabled) { $B.ForeColor } else { $Theme.Muted }), $flags)
    if ($B.Focused -and $B.ShowFocusCues) {
        $fp = New-RoundRect 2.5 2.5 ($B.Width - 5.5) ($B.Height - 5.5) (Px 4)
        $pen = New-Object Drawing.Pen($(if ($primary) { [Drawing.Color]::White } else { $Theme.Accent }), 1); $pen.DashStyle = 'Dot'; $G.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose()
    }
}
# The main action of a page: filled blue.
function Set-Primary($Button) {
    $Button.Font = $FontBold; $Button.FlatAppearance.MouseOverBackColor = $Theme.AccentDark
    $Button.Add_EnabledChanged({ Update-PrimaryLook $this })
    Update-PrimaryLook $Button
}
# Blue when usable; plain grey when disabled (grey text on blue is hard to read).
function Update-PrimaryLook($Button) {
    if ($Button.Enabled) { $Button.BackColor = $Theme.Accent; $Button.ForeColor = [Drawing.Color]::White; $Button.FlatAppearance.BorderSize = 0 }
    else { $Button.BackColor = $Theme.Soft; $Button.ForeColor = $Theme.Dim; $Button.FlatAppearance.BorderSize = 1 }
}
# The row under the mouse gets a light background (each list remembers its own).
$script:HotRows = @{}
function Set-HotRow($Lv, $Item) {
    $k = $Lv.GetHashCode(); $old = $script:HotRows[$k]
    if ($old -eq $Item) { return }
    foreach ($pair in @(@($old, $Theme.Bg), @($Item, $Theme.Hover))) {
        $it = $pair[0]; if (-not $it -or -not $it.ListView) { continue }
        $it.BackColor = $pair[1]; if (-not $it.UseItemStyleForSubItems) { foreach ($si in $it.SubItems) { $si.BackColor = $pair[1] } }
    }
    $script:HotRows[$k] = $Item
}
# The status column shows a coloured dot and word; the rest of the row stays easy to read. Grey (info) rows stay grey.
function Set-RowStatus($Item, [int]$Col, $Color) {
    if ($Color.ToArgb() -eq $Theme.Muted.ToArgb()) { $Item.ForeColor = $Theme.Muted; return }
    $Item.UseItemStyleForSubItems = $false
    foreach ($si in $Item.SubItems) { $si.ForeColor = $Theme.Text }
    $si = $Item.SubItems[$Col]; $si.Text = "$([char]0x25CF)  $($si.Text)"; $si.ForeColor = $Color
}
function New-ListView([bool]$Checks, [object[]]$Columns) {
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $Checks; $lv.Dock = 'Fill'; $lv.ShowItemToolTips = $true
    $lv.BorderStyle = 'None'; $lv.HeaderStyle = 'Nonclickable'; $lv.BackColor = $Theme.Bg; $lv.ForeColor = $Theme.Text
    $rows = New-Object Windows.Forms.ImageList; $rows.ImageSize = New-Object Drawing.Size(1, (Px 28))   # taller rows
    $lv.Add_MouseMove({ Set-HotRow $this ($this.GetItemAt($_.X, $_.Y)) })
    $lv.Add_MouseLeave({ Set-HotRow $this $null })
    $lv.SmallImageList = $rows
    for ($i = 0; $i -lt $Columns.Count; $i += 2) { [void]$lv.Columns.Add($Columns[$i], (Px $Columns[$i + 1])) }
    if ($Dark) {   # the native header ignores colours, so draw it; rows still draw themselves
        $lv.OwnerDraw = $true
        $lv.Add_DrawColumnHeader({
            param($sender, $e)
            $fillR = $e.Bounds
            # The last column also paints the strip to its right (above the scroll bar), which Windows would leave light grey.
            if ($e.ColumnIndex -eq $sender.Columns.Count - 1) { $fillR = New-Object Drawing.Rectangle($e.Bounds.X, $e.Bounds.Y, [Math]::Max($e.Bounds.Width, $sender.Width - $e.Bounds.X), $e.Bounds.Height) }
            $brush = New-Object Drawing.SolidBrush($Theme.Side); $e.Graphics.FillRectangle($brush, $fillR); $brush.Dispose()
            $r = $e.Bounds; $r.X += (Px 5); $r.Width -= (Px 5)
            [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $sender.Font, $r, $Theme.Dim, 'VerticalCenter, Left, EndEllipsis')
        })
        $lv.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $true })
        $lv.Add_DrawSubItem({ param($sender, $e) $e.DrawDefault = $true })
    }
    $lv.Add_HandleCreated({
        Set-DarkChrome $this
        $header = [PcTuneUp.Native]::SendMessage($this.Handle, 0x101F, [IntPtr]::Zero, [IntPtr]::Zero)   # LVM_GETHEADER
        if ($Dark -and $header -ne [IntPtr]::Zero) {
            try { [void][PcTuneUp.Native]::SetWindowTheme($header, 'DarkMode_ItemsView', $null) } catch { }
            try { $t = Get-HeaderFillType; if ($t) { [void]$script:HeaderFills.Add($t::new($header, $Theme.Side)) } } catch { Write-AppError 'Header colour' $_ }
        }
    })
    $lv.Tag = @($lv.Columns | ForEach-Object Width)   # designed widths
    $lv.Add_Resize({ Resize-LastColumn $this })
    $lv
}
# Let the last column take the remaining width, so lists never scroll sideways.
function Resize-LastColumn($Lv) {
    $n = $Lv.Columns.Count
    if ($n -lt 2) { return }
    $avail = $Lv.ClientSize.Width - [Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 2
    $design = @($Lv.Tag)
    $fixed = 0; for ($i = 0; $i -lt $n - 1; $i++) { $fixed += $design[$i] }
    $scale = [Math]::Min(1.0, [Math]::Max(0.3, ($avail - 160) / [Math]::Max(1, $fixed)))   # leave the last column at least ~160 px
    $used = 0
    for ($i = 0; $i -lt $n - 1; $i++) { $w = [int]($design[$i] * $scale); $Lv.Columns[$i].Width = $w; $used += $w }
    $Lv.Columns[$n - 1].Width = [Math]::Max(120, $avail - $used)
}
function New-Status {
    $l = New-Object Windows.Forms.Label
    $l.Dock = 'Bottom'; $l.Height = 32; $l.TextAlign = 'BottomLeft'; $l.ForeColor = $Theme.Dim
    $l
}
# Read-only details area under a list, on a light background.
function New-DetailBox([int]$Height = 110) {
    $wrap = New-Object Windows.Forms.Panel
    $wrap.Dock = 'Bottom'; $wrap.Height = $Height; $wrap.BackColor = $Theme.Soft; $wrap.Padding = New-Object Windows.Forms.Padding(12, 10, 12, 8)
    $box = New-Object Windows.Forms.TextBox
    $box.Multiline = $true; $box.ReadOnly = $true; $box.Dock = 'Fill'; $box.ScrollBars = 'Vertical'
    $box.BorderStyle = 'None'; $box.BackColor = $Theme.Soft; $box.ForeColor = $Theme.Text
    $box.Add_HandleCreated({ Set-DarkChrome $this })
    $wrap.Controls.Add($box)
    $box | Add-Member -NotePropertyName Wrapper -NotePropertyValue $wrap
    $box
}
# A small line chart (Battery wear, Health over time). Set-Chart gives it series of points with a date X and a value Y.
$FontChart = New-Object Drawing.Font('Segoe UI', 8.25)
function New-Chart([int]$Height = 150) {
    $c = New-Object Windows.Forms.PictureBox
    $c.Dock = 'Top'; $c.Height = $Height; $c.BackColor = $Theme.Bg
    $c.Tag = @{ Series = @(); Max = 100; Suffix = ''; Title = ''; Empty = 'No history yet.' }
    $c.Add_Paint({ param($s, $e) Draw-Chart $s $e.Graphics })
    $c.Add_Resize({ $this.Invalidate() })
    $c
}
function Set-Chart($Chart, [object[]]$Series, [double]$Max = 100, [string]$Suffix = '', [string]$Title = '', [string]$Empty = '') {
    $Chart.Tag.Series = $Series; $Chart.Tag.Max = $Max; $Chart.Tag.Suffix = $Suffix; $Chart.Tag.Title = $Title
    if ($Empty) { $Chart.Tag.Empty = $Empty }
    $Chart.Invalidate()
}
function Draw-Chart($C, $G) {
    $d = $C.Tag
    $G.SmoothingMode = 'AntiAlias'; $G.TextRenderingHint = 'ClearTypeGridFit'
    $L = Px 40; $R = Px 12; $Tp = Px 26; $B = Px 20
    $w = $C.ClientSize.Width - $L - $R; $h = $C.ClientSize.Height - $Tp - $B
    if ($w -lt 60 -or $h -lt 30) { return }
    $dim = New-Object Drawing.SolidBrush($Theme.Dim)
    $x = $L
    if ($d.Title) { $G.DrawString((T $d.Title), $FontBold, (New-Object Drawing.SolidBrush($Theme.Text)), [single]0, [single]0); $x = $L + $G.MeasureString((T $d.Title), $FontBold).Width + (Px 16) }
    $pts = @($d.Series | ForEach-Object { $_.Points } | Where-Object { $_ })
    if (-not $pts) { $G.DrawString((T $d.Empty), $FontChart, $dim, [single]$L, [single]($Tp + $h / 2 - 8)); $dim.Dispose(); return }
    # Legend
    foreach ($s in $d.Series) {
        if (-not @($s.Points).Count) { continue }
        $br = New-Object Drawing.SolidBrush($s.Color)
        $G.FillRectangle($br, [single]$x, [single](Px 5), [single](Px 10), [single](Px 10)); $br.Dispose()
        $G.DrawString((T $s.Name), $FontChart, $dim, [single]($x + (Px 14)), [single](Px 1))
        $x += (Px 26) + $G.MeasureString((T $s.Name), $FontChart).Width
    }
    $minX = ($pts | Measure-Object -Property X -Minimum).Minimum; $maxX = ($pts | Measure-Object -Property X -Maximum).Maximum
    if ($maxX -le $minX) { $minX = $maxX.AddDays(-1) }
    $span = ($maxX - $minX).TotalSeconds
    $grid = New-Object Drawing.Pen($Theme.Border, 1); $grid.DashStyle = 'Dot'
    foreach ($f in 0, 0.25, 0.5, 0.75, 1) {
        $y = $Tp + $h - $f * $h
        $G.DrawLine($grid, [single]$L, [single]$y, [single]($L + $w), [single]$y)
        $lbl = "$([int]($f * $d.Max))$($d.Suffix)"
        $G.DrawString($lbl, $FontChart, $dim, [single]($L - (Px 6) - $G.MeasureString($lbl, $FontChart).Width), [single]($y - (Px 7)))
    }
    $grid.Dispose()
    foreach ($pair in @(@($minX, 0), @($maxX, 1))) {
        $lbl = ([datetime]$pair[0]).ToString('d MMM yyyy', $UiCulture)
        $lw = $G.MeasureString($lbl, $FontChart).Width
        $G.DrawString($lbl, $FontChart, $dim, [single]($L + $pair[1] * ($w - $lw)), [single]($Tp + $h + (Px 3)))
    }
    foreach ($s in $d.Series) {
        $ps = @($s.Points | Sort-Object X)
        if (-not $ps) { continue }
        $pen = New-Object Drawing.Pen($s.Color, [single](Px 2))
        $xy = @(foreach ($p in $ps) { New-Object Drawing.PointF([single]($L + (([datetime]$p.X - $minX).TotalSeconds / $span) * $w), [single]($Tp + $h - [Math]::Min([double]1, [Math]::Max([double]0, [double]$p.Y / [double]$d.Max)) * $h)) })
        if ($xy.Count -ge 2) { $G.DrawLines($pen, [Drawing.PointF[]]$xy) }
        $br = New-Object Drawing.SolidBrush($s.Color); $last = $xy[-1]
        $G.FillEllipse($br, [single]($last.X - (Px 3)), [single]($last.Y - (Px 3)), [single](Px 6), [single](Px 6)); $br.Dispose(); $pen.Dispose()
    }
    $dim.Dispose()
}
function Add-Row($Lv, [object[]]$Cells, $Tag = $null, [bool]$Checked = $false) {
    $it = New-Object Windows.Forms.ListViewItem([string]$Cells[0])
    $it.Text = T ([string]$Cells[0])
    foreach ($c in $Cells[1..($Cells.Count - 1)]) { [void]$it.SubItems.Add((T ([string]$c))) }
    $it.Tag = $Tag; $it.Checked = $Checked
    if ($script:GlossaryRx) { $tip = Get-GlossaryTip $Cells; if ($tip) { $it.ToolTipText = $tip } }   # plain-words explanation on hover
    [void]$Lv.Items.Add($it)
    $it
}

# ===========================================================================
# 1. Health
# ===========================================================================
$pgHealth = New-Page 'Health' 'How the PC is doing right now. "Fix my PC" runs all the safe fixes in one go - it shows you the list first.'
$btnFix = New-Button 'Fix my PC'; Set-Primary $btnFix
$btnRefresh = New-Button 'Refresh'
$btnSpeed = New-Button 'Speed test'
$btnWU = New-Button 'Windows Update'
$btnReport = New-Button 'Save report'
$btnLog = New-Button 'Change log'
$btnKeep = New-Button 'Keep list'
# Readings as a two-column grid: grey label, value.
$gridHealth = New-Object Windows.Forms.TableLayoutPanel
$gridHealth.Dock = 'Top'; $gridHealth.AutoSize = $true; $gridHealth.AutoSizeMode = 'GrowAndShrink'; $gridHealth.ColumnCount = 2
[void]$gridHealth.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', (Px 110))))
[void]$gridHealth.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
$gridHealth.Padding = New-Object Windows.Forms.Padding(0, 0, 0, 8)
$lblAdvice = New-Object Windows.Forms.Label
$lblAdvice.Dock = 'Top'; $lblAdvice.Height = 0; $lblAdvice.BackColor = $Theme.WarnBg; $lblAdvice.ForeColor = $Theme.WarnText
$lblAdvice.Padding = New-Object Windows.Forms.Padding(12, 8, 12, 8)
# The advice box grows to fit its text at the current width (long lines wrap).
function Resize-Advice {
    if (-not $lblAdvice.Text) { $lblAdvice.Height = 0; return }
    $w = [Math]::Max((Px 300), $lblAdvice.ClientSize.Width - $lblAdvice.Padding.Horizontal)
    $sz = [Windows.Forms.TextRenderer]::MeasureText($lblAdvice.Text, $lblAdvice.Font, (New-Object Drawing.Size($w, 0)), 'WordBreak')
    $lblAdvice.Height = $sz.Height + $lblAdvice.Padding.Vertical + 2
}
$lblAdvice.Add_SizeChanged({ if (-not $script:SizingAdvice) { $script:SizingAdvice = $true; Resize-Advice; $script:SizingAdvice = $false } })
$lblSpeed = New-Object Windows.Forms.Label
$lblSpeed.Dock = 'Top'; $lblSpeed.Height = 34; $lblSpeed.TextAlign = 'MiddleLeft'; $lblSpeed.ForeColor = $Theme.Dim
$lblSpeed.Text = 'Internet:  not tested yet - click Speed test'
# The memory list doesn't fit next to everything else, so it sits behind a link: it then replaces the readings.
$lblProcCap = New-Object Windows.Forms.LinkLabel
$lblProcCap.Dock = 'Top'; $lblProcCap.Height = 30; $lblProcCap.TextAlign = 'BottomLeft'
$lblProcCap.LinkColor = $Theme.AccentText; $lblProcCap.ActiveLinkColor = $Theme.AccentText
$lblProcCap.Text = 'See what is using the processor and memory right now'
$lblProcCap.Add_LinkClicked({ Show-Page $pgNow })
$lvProc = New-ListView $false @('Program', 300, 'Memory (MB)', 120, 'Processes', 100)
# Readings on the left, "Health over time" chart on the right.
$healthTop = New-Object Windows.Forms.TableLayoutPanel
$healthTop.Dock = 'Top'; $healthTop.AutoSize = $true; $healthTop.AutoSizeMode = 'GrowAndShrink'; $healthTop.ColumnCount = 2; $healthTop.RowCount = 1
[void]$healthTop.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
[void]$healthTop.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', (Px 390))))
$chartScore = New-Chart 200
$chartScore.Dock = 'Fill'; $chartScore.Margin = New-Object Windows.Forms.Padding(12, 0, 0, 8)
$gridHealth.Dock = 'Fill'   # use the whole column, so readings don't wrap early
$healthTop.Controls.Add($gridHealth, 0, 0); $healthTop.Controls.Add($chartScore, 1, 0)
# "Start here": the three most useful next steps from all pages, each with a button that opens the right page.
$startHere = New-Object Windows.Forms.TableLayoutPanel
$startHere.Dock = 'Top'; $startHere.AutoSize = $true; $startHere.AutoSizeMode = 'GrowAndShrink'; $startHere.ColumnCount = 3; $startHere.BackColor = $Theme.AccentSoft
$startHere.Padding = New-Object Windows.Forms.Padding(14, 6, 10, 6); $startHere.Margin = New-Object Windows.Forms.Padding(0)
[void]$startHere.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
[void]$startHere.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
[void]$startHere.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$shTitle = New-Object Windows.Forms.Label
$shTitle.Text = 'Start here'; $shTitle.Font = $FontBold; $shTitle.AutoSize = $true; $shTitle.Margin = New-Object Windows.Forms.Padding(0, 2, 0, 2)
$startHere.Controls.Add($shTitle, 0, 0); $startHere.SetColumnSpan($shTitle, 3)
$script:StartRows = @(foreach ($n in 1..3) {
    $l = New-Object Windows.Forms.Label
    $l.AutoSize = $true; $l.Anchor = 'Left'; $l.Margin = New-Object Windows.Forms.Padding(0, 1, 8, 1); $l.Text = ''
    $b = New-Button 'Open'; $b.MinimumSize = New-Object Drawing.Size(110, 28); $b.Height = 28; $b.Margin = New-Object Windows.Forms.Padding(0, 1, 0, 1)
    $b.Add_Click({ $st = $this.Tag; if ($st -and $st.Remind) { Invoke-Reminder $st } elseif ($st -and $st.Page) { Show-Page $st.Page } })
    # Reminders can be put off for a few days.
    $lt = New-Button 'Later'; $lt.MinimumSize = New-Object Drawing.Size(80, 28); $lt.Height = 28; $lt.Margin = New-Object Windows.Forms.Padding(6, 1, 0, 1); $lt.Enabled = $false
    $lt.Add_Click({ if ($this.Tag -and $this.Tag.Remind) { Set-ReminderLater $this.Tag.Id $this.Tag.Later } })
    $startHere.Controls.Add($l, 0, $n); $startHere.Controls.Add($b, 1, $n); $startHere.Controls.Add($lt, 2, $n)
    $l.Visible = $false; $b.Visible = $false; $lt.Visible = $false
    @{ Label = $l; Button = $b; Later = $lt }
})
$shGap = New-Object Windows.Forms.Panel; $shGap.Dock = 'Top'; $shGap.Height = 10
Set-PageLayout $pgHealth $lvProc @((New-ButtonBar @($btnFix, $btnRefresh, $btnSpeed, $btnWU, $btnReport, $btnLog, $btnKeep)), $startHere, $shGap, $healthTop, $lblAdvice, $lblSpeed, $lblProcCap)
$lvProc.Visible = $false

# Health score: 100, minus points for each thing worth a look and for a low Windows stability rating. Saved once a day.
$ScoreFile = Join-Path $DataDir 'scores.jsonl'
function Get-Scores { if (Test-Path $ScoreFile) { Get-Content $ScoreFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } } }
function Get-HealthScore {
    $sc = 100 - [Math]::Min(48, 8 * @($script:HealthAdvice).Count)
    if ($null -ne $script:StabIndex) { $sc -= [Math]::Min(30, [int](3 * (10 - $script:StabIndex))) }
    [Math]::Max(0, [Math]::Min(100, $sc))
}
function Save-Score {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $all = @(Get-Scores | Where-Object { $_.Date -ne $today })
    $all += [pscustomobject]@{ Date = $today; Score = (Get-HealthScore); Stability = $script:StabIndex; Advice = @($script:HealthAdvice).Count }
    try { Set-Content -Path $ScoreFile -Value @($all | Select-Object -Last 400 | ForEach-Object { $_ | ConvertTo-Json -Compress }) -Encoding UTF8 } catch { }
    Update-ScoreChart
}
function Update-ScoreChart {
    $sc = @(Get-Scores)
    $series = @(@{ Name = 'PC Tune-Up score'; Color = $Theme.Accent; Points = @($sc | ForEach-Object { [pscustomobject]@{ X = [datetime]::ParseExact($_.Date, 'yyyy-MM-dd', $null); Y = [double]$_.Score } }) })
    if ($script:StabHistory) { $series += @{ Name = 'Windows stability x10'; Color = $Theme.Warn; Points = @($script:StabHistory | ForEach-Object { [pscustomobject]@{ X = $_.D; Y = 10 * [double]$_.V } }) } }
    $now = if ($sc) { [int]$sc[-1].Score } else { $null }
    $prev = @($sc | Where-Object { [datetime]::ParseExact($_.Date, 'yyyy-MM-dd', $null) -le (Get-Date).AddDays(-7) }) | Select-Object -Last 1
    $title = if ($null -ne $now) { "Score $now/100$(if ($prev) { " (was $([int]$prev.Score))" })" } else { 'Health over time' }
    Set-Chart $chartScore $series 100 '' $title 'The score appears once all checks have run.'
}

function Set-KeyValues($Grid, [string[]]$Lines) {
    $Grid.SuspendLayout()
    $Grid.Controls.Clear(); $Grid.RowStyles.Clear(); $Grid.RowCount = 0
    foreach ($l in $Lines) {
        $k, $v = if ($l -match '^([^:]+):\s+(.*)$') { $Matches[1], $Matches[2] } else { '', $l }
        $kl = New-Object Windows.Forms.Label
        $kl.Text = T $k; $kl.ForeColor = $Theme.Dim; $kl.AutoSize = $true; $kl.Margin = New-Object Windows.Forms.Padding(0, 3, 0, 3)
        $vl = New-Object Windows.Forms.Label
        $vl.Text = T $v; $vl.AutoSize = $true; $vl.Margin = New-Object Windows.Forms.Padding(0, 3, 0, 3)
        $Grid.Controls.Add($kl, 0, $Grid.RowCount); $Grid.Controls.Add($vl, 1, $Grid.RowCount); $Grid.RowCount++
    }
    $Grid.ResumeLayout()
}

# The PC's name from the registry (instant) rather than WMI (~200 ms at every start); WMI only if it's missing.
$bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue
$PcName = ('{0} {1}' -f $bios.SystemManufacturer, $bios.SystemProductName).Trim()
if (-not $PcName) { $cs = Get-CimInstance Win32_ComputerSystem; $PcName = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim() }
$script:HealthDeep = $null   # drive / battery / update results from the background check
$script:ExtraAdvice = @{}    # one-line findings from the Updates / Security / Stability tabs, keyed by tab

# Slower checks (a few seconds), run in the background: drive health, battery wear, Windows Update.
$HealthDeepWork = {
    $lines = @(); $advice = @(); $diskData = @()
    foreach ($d in Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $extra = ''
        try {   # wear and temperature need administrator rights
            $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            if ($null -ne $rc.Wear) { $extra += ", $($rc.Wear)% worn" }
            if ($rc.Temperature) { $extra += ", $($rc.Temperature) C" }
            $diskData += [pscustomobject]@{ N = "$($d.FriendlyName)".Trim(); S = "$($d.SerialNumber)".Trim(); W = $rc.Wear; T = $rc.Temperature; TMax = $rc.TemperatureMax
                                            E = [int64]$rc.ReadErrorsUncorrected + [int64]$rc.WriteErrorsUncorrected; H = $rc.PowerOnHours }
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
            $upd = "Updates:   last Windows update $days day(s) ago"; $wuDays = $days
            if ($days -gt 45) { $advice += "Windows hasn't installed an update in $days days - click Windows Update and check for updates." }
        }
    } catch { }
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')) {
        $upd += ' - restart needed to finish'
        $advice += 'Windows is waiting for a restart to finish installing updates - restart when you can.'
    }
    $lines += $upd
    [pscustomobject]@{ Lines = $lines; Advice = $advice; WuDays = $wuDays; Disks = $diskData }
}

# The everyday readings (CPU, memory, disks, power, top programs). Gathered in the background: reading
# the processor load alone takes about a second, which would freeze the window.
$HealthQuickWork = {
    $PSDefaultParameterValues = @{ 'Get-CimInstance:OperationTimeoutSec' = 15; 'Get-CimInstance:ErrorAction' = 'SilentlyContinue' }
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
    $procs = @(Get-Process | Group-Object Name | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; MB = [int](($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB); Count = $_.Count }
    } | Sort-Object MB -Descending | Select-Object -First 25)
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object Size |
               ForEach-Object { [pscustomobject]@{ Id = $_.DeviceID; Free = [double]$_.FreeSpace; Size = [double]$_.Size } })
    # Power plan, plus the Windows 11 power-mode slider (an "overlay" on the plan).
    $plan = if ("$(powercfg /getactivescheme)" -match '\(([^)]+)\)') { $Matches[1] } else { 'unknown' }
    $ps = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction SilentlyContinue
    $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
    $onBattery = [bool]($bat -and $bat.BatteryStatus -eq 1)
    $overlay = if ($onBattery) { $ps.ActiveOverlayDcPowerScheme } else { $ps.ActiveOverlayAcPowerScheme }
    $mode = switch ($overlay) {
        '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'best power efficiency' }
        '3af9b8d9-7c97-431d-ad78-34a8bfea439f' { 'better performance' }
        'ded574b5-45a0-4f42-8737-46345c09c238' { 'best performance' }
        default { '' }
    }
    [pscustomobject]@{ Stamp = [guid]::NewGuid(); Caption = "$($os.Caption)" -replace '^Microsoft ', ''; Cpu = $cpu
                       FreeKB = [double]$os.FreePhysicalMemory; TotalKB = [double]$os.TotalVisibleMemorySize; Boot = $os.LastBootUpTime
                       Procs = $procs; Disks = $disks; Plan = $plan; Mode = $mode; HasBattery = [bool]$bat; OnBattery = $onBattery }
}
$script:HealthQuick = $null

# Drive health over time: one note per drive per day (wear, temperature, uncorrected errors - administrator only), kept a year,
# so the Health page can say how fast a drive wears and warn about heat or new errors.
$DiskFile = Join-Path $DataDir 'disks.jsonl'
$script:DiskTrend = $null
function Save-DiskSample($Disks) {
    $Disks = @($Disks | Where-Object { $null -ne $_.W -or $_.T })
    if (-not $Disks) { return }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $old = @(if (Test-Path $DiskFile) { Get-Content $DiskFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } })
    $keep = @($old | Where-Object { $_.D -ne $today -and [datetime]$_.D -gt (Get-Date).AddDays(-400) })
    $new = foreach ($d in $Disks) { [pscustomobject]@{ D = $today; N = $d.N; S = $d.S; W = $d.W; T = $d.T; TMax = $d.TMax; E = $d.E; H = $d.H } }
    try { Set-Content -Path $DiskFile -Value @(@($keep) + @($new) | ForEach-Object { $_ | ConvertTo-Json -Compress }) -Encoding UTF8 } catch { }
    $script:DiskTrend = $null
}
# Lines for the readings and advice, worked out once per new note.
function Get-DiskTrend {
    if ($script:DiskTrend) { return $script:DiskTrend }
    $lines = @(); $advice = @()
    $all = @(if (Test-Path $DiskFile) { Get-Content $DiskFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } })
    foreach ($g in $all | Group-Object { if ($_.S) { $_.S } else { $_.N } }) {
        $s = @($g.Group | Sort-Object D); $first = $s[0]; $last = $s[-1]; $name = $last.N
        $days = ([datetime]$last.D - [datetime]$first.D).TotalDays
        if ($null -ne $last.W -and $null -ne $first.W -and $days -ge 30) {
            $perYear = [Math]::Round(([double]$last.W - [double]$first.W) / $days * 365, 1)
            if ($perYear -gt 0) {
                $years = [Math]::Round((100 - [double]$last.W) / $perYear)
                $lines += "Drive wear:  $((T '{0}: {1}% used, about {2}% a year more').Replace('{0}', $name).Replace('{1}', "$($last.W)").Replace('{2}', "$perYear"))"
                if ($years -lt 2) { $advice += (T 'Drive {0} is wearing fast - at this rate it is worn out in about {1} year(s). Keep your backups up to date and plan a replacement.').Replace('{0}', $name).Replace('{1}', "$([Math]::Max(0, $years))") }
            } else { $lines += "Drive wear:  $((T '{0}: {1}% used, no change in {2} days').Replace('{0}', $name).Replace('{1}', "$($last.W)").Replace('{2}', "$([int]$days)"))" }
        }
        $hot = @($s | Where-Object { [double]$_.T -ge 70 -and ([datetime]$_.D) -gt (Get-Date).AddDays(-30) })
        if ($hot) { $advice += (T 'Drive {0} got hot ({1} C) in the last 30 days - heat shortens its life. Keep the vents free and the PC off soft surfaces.').Replace('{0}', $name).Replace('{1}', "$(($hot | Measure-Object T -Maximum).Maximum)") }
        if ($s.Count -ge 2 -and [int64]$last.E -gt [int64]$s[-2].E) { $advice += (T 'Drive {0} reported new read or write errors - back up your files now and check the drive.').Replace('{0}', $name) }
    }
    $script:DiskTrend = [pscustomobject]@{ Lines = $lines; Advice = $advice }
    $script:DiskTrend
}
# Draws the Health page from the latest readings. Cheap (no Windows queries), so every page can call it.
function Render-Health {
    $q = $script:HealthQuick
    $advice = @()
    $lines = @()
    if ($q) {
        $up = (Get-Date) - $q.Boot
        $usedPct = [int](100 * (1 - $q.FreeKB / $q.TotalKB))
        $lines += "This PC:   $PcName ($($q.Caption))"
        $lines += "CPU load:  $($q.Cpu)%"
        $lines += ('Memory:    {0:N1} GB free of {1:N1} GB ({2}% used)' -f ($q.FreeKB / 1MB), ($q.TotalKB / 1MB), $usedPct)
        $lines += ('Uptime:    {0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes)
        if ($usedPct -ge 85) {
            $top = $q.Procs | Where-Object { $_.Name -notin 'svchost', 'Memory Compression', 'System', 'dwm' } | Select-Object -First 1
            $advice += "Memory is $usedPct% full, which slows everything down - closing $($top.Name) ($($top.MB) MB) would help most."
        }
        foreach ($d in $q.Disks) {
            $pct = [int](100 * $d.Free / $d.Size)
            $lines += ('Disk {0}:    {1} free of {2} ({3}% free)' -f $d.Id.TrimEnd(':'), (Format-Size $d.Free), (Format-Size $d.Size), $pct)
            if ($pct -lt 15) { $advice += "Drive $($d.Id) is getting full ($pct% free) - use Fix my PC, then the Clean and Disk tabs." }
        }
        $lines += "Power:     $($q.Plan) plan" + $(if ($q.Mode) { ", $($q.Mode) mode" }) + $(if ($q.HasBattery) { if ($q.OnBattery) { ', on battery' } else { ', plugged in' } })
        if (-not $q.OnBattery -and ($q.Plan -match 'saver' -or $q.Mode -eq 'best power efficiency')) {
            $advice += 'The PC is plugged in but set to save energy - set Power mode to Balanced in Settings > System > Power for more speed.'
        }
        if ($up.TotalDays -gt 7) { $advice += "The PC hasn't restarted in $($up.Days) days - a restart clears out a lot of slowness." }
    } else { $lines += "This PC:   $PcName"; $lines += 'Checking this PC...' }
    if ($script:HealthDeep) { $lines += $script:HealthDeep.Lines; $advice += $script:HealthDeep.Advice }
    else { $lines += 'Checking drive, battery and updates...' }
    $lines += @(Get-FixLines)
    $dt = Get-DiskTrend; $lines += @($dt.Lines); $advice += @($dt.Advice)
    foreach ($k in 'Browsers', 'Network', 'Drivers', 'Backup', 'Security', 'Stability', 'Updates') { if ($script:ExtraAdvice[$k]) { $advice += $script:ExtraAdvice[$k] } }
    $key = ($lines + $advice) -join '|'
    if ($key -ne $script:HealthDrawn) {   # only rebuild what changed
        $script:HealthDrawn = $key
        $script:HealthLines = $lines
        Set-KeyValues $gridHealth $lines
        $lblAdvice.Text = ($advice | ForEach-Object { [char]0x2022 + "  $_" }) -join "`r`n"
        Resize-Advice
    }
    $script:HealthAdvice = $advice
    if ($script:NavButtons) { Update-NavBadges }
    if ($q -and $script:ProcsDrawn -ne $q.Stamp) {
        $script:ProcsDrawn = $q.Stamp
        $lvProc.BeginUpdate(); $lvProc.Items.Clear()
        $q.Procs | Select-Object -First 20 | ForEach-Object { [void](Add-Row $lvProc @($_.Name, $_.MB, $_.Count)) }
        $lvProc.EndUpdate()
    }
}
# -Quick: just redraw. Otherwise also refresh both sets of readings in the background.
function Update-Health([switch]$Quick) {
    Render-Health
    if ($Quick) { return }
    Start-Bg -Label 'Checking this PC' $HealthQuickWork $null { param($r) if ($r) { $script:HealthQuick = $r[0] }; Render-Health }
    Start-Bg -Label 'Checking drive, battery and updates' $HealthDeepWork $null { param($r) if ($r) { $script:HealthDeep = $r[0]; Save-DiskSample $script:HealthDeep.Disks }; Render-Health }
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
    Start-Bg -Label 'Testing internet speed' $SpeedWork $null {
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
# Functions, not handlers: buttons on other pages (Settings, History) call them too. (PerformClick on a button
# whose page is hidden does nothing, which is why those buttons once did nothing.)
function Open-ChangeLog {
    if (-not (Test-Path $LogFile)) { Write-Log 'Log started' }
    Start-Process notepad.exe $LogFile
}
function Open-KeepList {
    Start-Process notepad.exe $KeepFile -Wait
    Update-Startup; Start-BloatScan; Update-Services
}
$btnLog.Add_Click({ Open-ChangeLog })
$btnKeep.Add_Click({ Open-KeepList })

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
    $n = 0; $all = @($targets).Count
    foreach ($t in $targets) {
        $n++; Set-JobProgress $t.Name $n $all
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
    $n = 0; $all = @($targets).Count
    foreach ($t in $targets) {
        $n++; if (Test-Cancelled) { break }; Set-JobProgress $t.Name $n $all
        $freed = 0; $skipped = 0
        if (@($t.Path)[0] -eq 'CLEANMGR') { continue }
        if (@($t.Path)[0] -eq 'RECYCLE') {
            try { Clear-RecycleBin -Force -ErrorAction Stop; $freed = $t.Bytes } catch { $skipped = 1 }
        } else {
            foreach ($root in @($t.Path)) {
                foreach ($f in @(Get-FilesSafe $root $t.Filter)) {
                    if (Test-Cancelled) { break }; if ($f.LastWriteTime -ge $cutoff) { continue }
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
    Start-Bg -Label 'Measuring junk files' $ScanCleanWork $CleanTargets {
        param($results)
        $total = 0
        foreach ($r in $results) {
            foreach ($it in $lvClean.Items) {
                if ($it.Tag.Name -ne $r.Name) { continue }
                $it.Tag.Bytes = $r.Bytes
                $it.SubItems[1].Text = if ($r.Bytes -lt 0) { '?' } else { Format-Size $r.Bytes }
                $it.SubItems[2].Text = if ($r.Count -lt 0) { '-' } else { '{0:N0}' -f $r.Count }
                $it.SubItems[3].Text = T $(if (Test-Open $it.Tag) { "$($it.Tag.Name -replace ' cache$', '') is open - close it to clean this" } else { $it.Tag.Note })
                if ($it.Checked -and $r.Bytes -gt 0) { $total += $r.Bytes }
            }
        }
        $lblClean.Text = 'Checked items add up to about {0}.' -f (Format-Size $total)
        $script:JunkBytes = $total; if ($script:NavButtons) { Update-NavBadges }
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
    if ((Show-Msg "Delete the junk in:`n$names`n`nThis can't be undone (it's all re-creatable).$skipNote`n`nYour documents, photos and programs are not touched." 'YesNo' 'Question') -ne 'Yes') { return }
    $btnScan.Enabled = $false; $btnClean.Enabled = $false
    $lblClean.Text = 'Cleaning...'
    Start-Bg -Label 'Cleaning' -Cancellable $DoCleanWork $picked {
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
$lvStart = New-ListView $true @('App', 260, 'For', 80, 'Advice', 170, 'Slows start-up', 110, 'Command', 320)
$lblStart = New-Status
$chartBoot = New-Chart 150
$lblBoot = New-Object Windows.Forms.Label
$lblBoot.Dock = 'Top'; $lblBoot.Height = 74; $lblBoot.ForeColor = $Theme.Dim; $lblBoot.Padding = New-Object Windows.Forms.Padding(0, 2, 0, 6)
Set-PageLayout $pgStartup $lvStart @((New-ButtonBar @($btnStartReload, $btnStartApply, $btnStartTM)), $chartBoot, $lblBoot) $lblStart

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
            $it = Add-Row $lvStart @($display, $s.Scope, $advice, '', $e.Cmd) @{ Src = $s; Name = $e.Name; On = $on; Advice = $advice; Cmd = $e.Cmd } $on
            if ($advice -like 'keep*') { $it.ForeColor = $Theme.Good }
        }
    }
    $lvStart.EndUpdate()
    Set-StartupImpact
    $lblStart.Text = '{0} startup apps, {1} turned on.' -f $lvStart.Items.Count, $lvStart.CheckedItems.Count
}
# The "Slows start-up" column: how many seconds each app added to a start in the last 90 days (Windows' own measurement,
# visible to administrators only). Empty when Windows recorded no delay for it.
function Set-StartupImpact {
    if ($null -eq $script:BootApps) { return }
    foreach ($it in $lvStart.Items) {
        $cmd = "$($it.Tag.Cmd)"
        $a = @($script:BootApps | Where-Object { $_.File -and $cmd.IndexOf($_.File, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Sort-Object Sec -Descending)[0]
        $it.SubItems[3].Text = if ($a) { '+{0:N1} s' -f $a.Sec } else { '' }
        if ($a -and $a.Sec -ge 5) { $it.UseItemStyleForSubItems = $false; $it.SubItems[3].ForeColor = $Theme.Warn }
    }
}
$btnStartReload.Add_Click({ Update-Startup })
$btnStartTM.Add_Click({ Start-Process taskmgr.exe '/7 /startup' })

# --- Start-up time: how long Windows takes to start, from its own log (readable by administrators only) ---
$BootWork = {
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $data = { param($e) $h = @{}; foreach ($d in ([xml]$e.ToXml()).Event.EventData.Data) { $h[$d.Name] = $d.'#text' }; $h }
    # Without administrator rights a filtered query just says "no events", so test access to the log first.
    try { [void](Get-WinEvent -LogName $log -MaxEvents 1 -ErrorAction Stop) } catch [UnauthorizedAccessException] { return [pscustomobject]@{ Denied = $true } } catch { if ($_.Exception.Message -match 'unauthori|access') { return [pscustomobject]@{ Denied = $true } } }
    # A switched-off or empty log makes filtered queries fail with "The parameter is incorrect": treat that as "nothing recorded".
    $ev = try { @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 100 } -MaxEvents 200 -ErrorAction Stop) } catch { @() }
    $boots = @(foreach ($e in $ev) { $h = & $data $e
        if ([double]$h.BootTime -gt 0) { [pscustomobject]@{ X = $e.TimeCreated; Y = [Math]::Round([double]$h.BootTime / 1000, 1); Main = [double]$h.MainPathBootTime / 1000; Post = [double]$h.BootPostBootTime / 1000 } } })
    # What slowed start-up down (apps, drivers, services, devices) in the last 90 days
    $kind = @{ 101 = 'app'; 102 = 'driver'; 103 = 'service'; 106 = 'background task'; 109 = 'device' }
    $slowEv = try { @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 101, 102, 103, 106, 109; StartTime = (Get-Date).AddDays(-90) } -ErrorAction Stop) } catch { @() }
    $slow = @($slowEv | ForEach-Object {
        $h = & $data $_; $name = if ($h.FriendlyName) { $h.FriendlyName } else { $h.Name }
        if ($name) { [pscustomobject]@{ Name = "$name".Trim(); Kind = $kind[$_.Id]; Sec = [double]$h.DegradationTime / 1000 } } } |
        Group-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Kind = $_.Group[0].Kind; Sec = [Math]::Round(($_.Group | Measure-Object Sec -Maximum).Maximum, 1); Times = $_.Count } } |
        Sort-Object Sec -Descending | Select-Object -First 5)
    # Per start-up app (event 101): the longest it delayed a start, matched to the Startup list by its program file.
    $apps = @($slowEv | Where-Object Id -eq 101 | ForEach-Object { $h = & $data $_; if ($h.Name) { [pscustomobject]@{ File = "$($h.Name)".Trim(); Sec = [double]$h.DegradationTime / 1000 } } } |
        Group-Object File | ForEach-Object { [pscustomobject]@{ File = $_.Name; Sec = [Math]::Round(($_.Group | Measure-Object Sec -Maximum).Maximum, 1); Times = $_.Count } })
    [pscustomobject]@{ Denied = $false; Boots = $boots; Slow = $slow; Apps = $apps }
}
function Update-Boot {
    $fast = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled -eq 1
    $script:BootFast = $fast
    Start-Bg -Label 'Reading start-up times' $BootWork $null {
        param($r)
        $r = @($r)[0]
        $fastTxt = if ($script:BootFast) { 'Fast startup is on, so Shut down and then starting again is quicker than Restart (only Restart does a full start).' } else { 'Fast startup is off.' }
        if (-not $r -or $r.Denied) {
            Set-Chart $chartBoot @() 60 ' s' 'Start-up time' 'Windows only shows start-up times to administrators - click "Restart as admin" to see them.'
            $lblBoot.Text = $fastTxt; return
        }
        $b = @($r.Boots | Sort-Object X)
        $script:BootList = $b; Update-FixBoot
        $script:BootApps = @($r.Apps); Set-StartupImpact
        if (-not $b) { Set-Chart $chartBoot @() 60 ' s' 'Start-up time' 'No start-up times recorded yet.'; $lblBoot.Text = $fastTxt; return }
        $max = [Math]::Max(30, [Math]::Ceiling((($b | Measure-Object Y -Maximum).Maximum) / 30) * 30)
        $recent = @($b | Where-Object { $_.X -gt (Get-Date).AddDays(-30) })
        $avg = if ($recent) { [Math]::Round(($recent | Measure-Object Y -Average).Average) } else { $null }
        $last = $b[-1]
        Set-Chart $chartBoot @(@{ Name = 'Seconds until the desktop is ready'; Color = $Theme.Accent; Points = $b }) $max ' s' "Start-up time: $([Math]::Round($last.Y)) s"
        $txt = "Last full start: $([Math]::Round($last.Y)) s ($([Math]::Round($last.Main)) s for Windows, then $([Math]::Round($last.Post)) s for start-up apps)$(if ($avg) { "; $avg s on average over 30 days" })."
        # One sentence per line, so each line translates on its own.
        $txt += "`r`n" + $(if ($last.Y -gt 60) { 'That is slow - turning off start-up apps below helps most.' } elseif ($last.Y -gt 30) { 'Fine; fewer start-up apps would make it quicker.' } else { 'Quick.' })
        if ($r.Slow) { $txt += "`r`nSlowing it down: $(($r.Slow | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($(T $_.Kind), +$($_.Sec) s)" }) -join ', ')." }
        $lblBoot.Text = "$txt`r`n$fastTxt"
    }
}

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
    $n = 0; $all = @($items).Count
    foreach ($i in $items) {
        $n++; if (Test-Cancelled) { break }; Set-JobProgress $i.Name $n $all
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
    Start-Bg -Label 'Looking for bloatware' $BloatScanWork @{ Catalog = $BloatCatalog; UserKeep = (Get-UserKeep) } {
        param($rows)
        $lvBloat.BeginUpdate(); $lvBloat.Items.Clear()
        $order = @{ 'Junk' = 0; 'Trial AV' = 1; 'Optional' = 2 }
        foreach ($r in $rows | Sort-Object { $order[$_.Cat] }, Name) {
            $size = if ($r.Bytes) { Format-Size $r.Bytes } else { '' }
            $it = Add-Row $lvBloat @($r.Name, $r.Type, $r.Cat, $r.Why, $size, $r.Publisher) $r ($r.Cat -eq 'Junk')
            if ($r.Cat -eq 'Junk') { $it.ForeColor = $Theme.Bad }
            elseif ($r.Cat -eq 'Trial AV') { $it.ForeColor = $Theme.Warn }
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
    Start-Bg -Label 'Creating a restore point' { try { Checkpoint-Computer -Description 'PC Tune-Up' -RestorePointType APPLICATION_UNINSTALL -ErrorAction Stop; 'ok' } catch { $_.Exception.Message } } $null {
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
    $script:BloatPicked = $picked
    Start-WithRestorePoint 'uninstalling apps' { Start-Bg -Label 'Uninstalling' -Cancellable $BloatRemoveWork $script:BloatPicked {
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
    } }
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
    Start-Bg -Label 'Reading services' $SvcScanWork $cfg {
        param($rows)
        $orig = Get-ServiceOriginals
        $order = @{ known = 0; likely = 1; review = 2 }
        $lvSvc.BeginUpdate(); $lvSvc.Items.Clear()
        $todo = 0
        foreach ($r in $rows | Sort-Object { $order[$_.Kind] }, Name) {
            $o = if ($orig.ContainsKey($r.Name)) { $orig[$r.Name] } else { '' }
            $what = if ($r.Kind -eq 'review') { "$($r.Display)  (review: $($r.Why))" } else { "$($r.Why) - $($r.Display)" }
            $it = Add-Row $lvSvc @($r.Name, $what, $r.Company, $r.Start, $r.State, $(if ($r.Suggest) { $r.Suggest } else { '-' }), $o) $r
            if ($r.Suggest -and $r.Start -eq $r.Suggest) { $it.ForeColor = $Theme.Muted }
            elseif ($r.Kind -eq 'review') { $it.ForeColor = $Theme.Muted }
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
        $name = $it.Tag.Name
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
$btnSvcApply.Add_Click({ Start-WithRestorePoint 'changing services' { Set-Services 'Suggest' } })
$btnSvcManual.Add_Click({ Start-WithRestorePoint 'changing services' { Set-Services 'Manual' } })
$btnSvcRestore.Add_Click({ Set-Services 'Restore' })

# ===========================================================================
# 6. Disk usage
# ===========================================================================
$pgDisk = New-Page 'Disk' 'Find what is filling the drive. Pick a place and Scan; double-click a row to look inside it. "Large files" and "Duplicate files" look for files you may not need - they only go to the Recycle Bin when you say so.'
$txtDisk = New-Object Windows.Forms.TextBox
$txtDisk.Width = 270; $txtDisk.Text = $env:USERPROFILE; $txtDisk.Margin = New-Object Windows.Forms.Padding(3, 7, 3, 3)
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
$script:DiskPickKeys = @(foreach ($k in $DiskPicks.Keys) { if (-not $DiskPicks[$k] -or (Test-Path -LiteralPath $DiskPicks[$k])) { $k } })
foreach ($k in $script:DiskPickKeys) { [void]$cmbDisk.Items.Add((T $k)) }
$cmbDisk.SelectedIndex = 0

$DiskWork = {
    param($root)
    $rows = @()
    $loose = 0
    try { foreach ($f in [IO.DirectoryInfo]::new($root).EnumerateFiles()) { $loose += $f.Length } } catch { }
    $subdirs = try { @([IO.DirectoryInfo]::new($root).EnumerateDirectories()) } catch { @() }
    $n = 0
    foreach ($d in $subdirs) {
        $n++; if (Test-Cancelled) { break }; Set-JobProgress $d.Name $n $subdirs.Count
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
    Show-DiskList $false
    $btnDiskScan.Enabled = $false; $lvDisk.Items.Clear()
    $lblDisk.Text = 'Scanning... big folders like C:\ can take a few minutes.'
    Start-Bg -Label 'Measuring folders' -Cancellable $DiskWork $Path {
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
    $p = $DiskPicks[$script:DiskPickKeys[$cmbDisk.SelectedIndex]]
    if ($p) { Start-DiskScan $p; $cmbDisk.SelectedIndex = 0 }   # reset so the same pick works again
})
$btnDiskUp.Add_Click({ $p = Split-Path $txtDisk.Text -Parent; if ($p) { Start-DiskScan $p } })
$btnDiskOpen.Add_Click({
    if ($lvFiles.Visible -and $lvFiles.SelectedItems.Count) { Start-Process explorer.exe "/select,`"$($lvFiles.SelectedItems[0].Tag.Path)`""; return }
    $p = if ($lvDisk.SelectedItems.Count) { $lvDisk.SelectedItems[0].Tag } else { $txtDisk.Text }
    Start-Process explorer.exe "`"$p`""
})
$btnDiskBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtDisk.Text
    if ($dlg.ShowDialog() -eq 'OK') { Start-DiskScan $dlg.SelectedPath }
})
# --- Large and duplicate files in the chosen folder (a second list on the Disk page) ---
$btnDiskLarge = New-Button 'Large files'
$btnDiskDup = New-Button 'Duplicate files'
$btnDiskRecycle = New-Button 'Recycle checked'; $btnDiskRecycle.Visible = $false
$lvFiles = New-ListView $true @('File', 280, 'Folder', 380, 'Size', 90, 'Modified', 100, 'Note', 260)
$lvFiles.Visible = $false
$pgDisk.Controls.Add($lvFiles); $lvFiles.BringToFront()
$diskBar = $btnDiskScan.Parent
foreach ($b in $btnDiskLarge, $btnDiskDup, $btnDiskRecycle) { $diskBar.Controls.Add($b) }
$diskBar.Controls.SetChildIndex($cmbDisk, $diskBar.Controls.Count - 1)
function Show-DiskList([bool]$Files) {
    $lvFiles.Visible = $Files; $lvDisk.Visible = -not $Files; $btnDiskRecycle.Visible = $Files
    if ($Files) { $lvFiles.BringToFront() } else { $lvDisk.BringToFront() }
}
# Files never touched: cloud-only OneDrive files (opening them would download them), app data, and Windows' own folders.
$FileScanWork = {
    param($a)
    $skip = '\\AppData\\|\\\.git\\|\\node_modules\\|^[A-Za-z]:\\(Windows|ProgramData|\$Recycle\.Bin|System Volume Information)\\'
    $cloud = 0x400000 -bor 0x40000 -bor 0x1000   # recall-on-access, recall-on-open, offline
    $files = foreach ($f in Get-FilesSafe $a.Root) {
        if (Test-Cancelled) { break }
        if ($f.Length -lt $a.Min -or ([int]$f.Attributes -band $cloud) -or $f.FullName -match $skip) { continue }
        $f
    }
    if ($a.Mode -eq 'large') {
        return $files | Sort-Object Length -Descending | Select-Object -First 300 | ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Name = $_.Name; Dir = $_.DirectoryName; Bytes = $_.Length; Modified = $_.LastWriteTime; Group = 0; Keep = $false } }
    }
    # Duplicates: same size, then the same first 64 KB, then the same full SHA-256.
    $head = { param($p) try { $s = [IO.File]::OpenRead($p); $buf = New-Object byte[] 65536; $n = $s.Read($buf, 0, 65536); $s.Dispose()
        [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash($buf, 0, $n)) } catch { $null } }
    $sizeGroups = @($files | Group-Object Length | Where-Object Count -gt 1)
    $g = 0; $i = 0; $out = New-Object System.Collections.ArrayList
    foreach ($sg in $sizeGroups) {
        $i++; if (Test-Cancelled) { break }
        Set-JobProgress "comparing files ($i of $($sizeGroups.Count))" $i $sizeGroups.Count
        foreach ($hg in @($sg.Group | Group-Object { & $head $_.FullName } | Where-Object { $_.Count -gt 1 -and $_.Name })) {
            foreach ($fg in @($hg.Group | Group-Object { try { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } catch { '' } } | Where-Object { $_.Count -gt 1 -and $_.Name })) {
                $g++
                # Keep the copy outside Downloads/Temp with the shortest path (usually the "real" one).
                $keep = $fg.Group | Sort-Object { $_.FullName -match '\\(Downloads|Temp|tmp)\\' }, { $_.FullName.Length }, CreationTime | Select-Object -First 1
                foreach ($f in $fg.Group) {
                    [void]$out.Add([pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Dir = $f.DirectoryName; Bytes = $f.Length; Modified = $f.LastWriteTime; Group = $g; Keep = ($f.FullName -eq $keep.FullName); Copies = $fg.Count })
                }
            }
        }
    }
    $out
}
function Start-FileScan([string]$Mode) {
    $root = $txtDisk.Text
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Show-Msg "Folder not found:`n$root" 'OK' 'Warning' | Out-Null; return }
    if ($root -match '^[A-Za-z]:\\?$|^[A-Za-z]:\\(Windows|Program Files)') { if ((Show-Msg 'That is a very big or system folder - this can take a long time. Program and Windows files are never pre-checked. Continue?' 'YesNo' 'Question') -ne 'Yes') { return } }
    Show-DiskList $true
    $lvFiles.Items.Clear(); $btnDiskLarge.Enabled = $false; $btnDiskDup.Enabled = $false
    $script:FileMode = $Mode
    $lblDisk.Text = if ($Mode -eq 'large') { "Looking for files of 100 MB or more in $root..." } else { "Looking for identical files of 1 MB or more in $root (it compares contents, so this can take a while)..." }
    Start-Bg -Label $(if ($Mode -eq 'large') { 'Finding large files' } else { 'Finding duplicate files' }) -Cancellable $FileScanWork @{ Root = $root; Mode = $Mode; Min = $(if ($Mode -eq 'large') { 100MB } else { 1MB }) } {
        param($rows, $state)
        $btnDiskLarge.Enabled = $true; $btnDiskDup.Enabled = $true
        $rows = @($rows)
        $sys = '^[A-Za-z]:\\(Windows|Program Files|Program Files \(x86\))\\'
        $lvFiles.BeginUpdate()
        if ($script:FileMode -eq 'large') {
            foreach ($r in $rows) {
                $note = if ($r.Path -match '\\Downloads\\') { 'in Downloads - often safe to remove' } elseif ($r.Path -match '\.(iso|zip|7z|rar|msi|exe)$') { 'installer or archive - often not needed any more' } else { '' }
                [void](Add-Row $lvFiles @($r.Name, $r.Dir, (Format-Size $r.Bytes), $r.Modified.ToString('d'), $note) $r)
            }
            $lblDisk.Text = "$($rows.Count) large file(s), $(Format-Size (($rows | Measure-Object Bytes -Sum).Sum)) together. Check what you don't need and click Recycle checked (they go to the Recycle Bin)."
        } else {
            $wasted = 0
            foreach ($grp in $rows | Group-Object Group | Sort-Object { [int64]$_.Group[0].Bytes * ($_.Count - 1) } -Descending) {
                foreach ($r in $grp.Group | Sort-Object { -not $_.Keep }) {
                    $note = if ($r.Keep) { "kept (1 of $($r.Copies) identical copies)" } else { "identical copy of $($grp.Group | Where-Object Keep | ForEach-Object Name)" }
                    $it = Add-Row $lvFiles @($r.Name, $r.Dir, (Format-Size $r.Bytes), $r.Modified.ToString('d'), $note) $r (-not $r.Keep -and $r.Path -notmatch $sys)
                    if ($r.Keep) { $it.ForeColor = $Theme.Muted } else { $wasted += $r.Bytes }
                }
            }
            $lblDisk.Text = "$(@($rows | Group-Object Group).Count) set(s) of identical files; the extra copies take $(Format-Size $wasted). One copy of each is kept (grey); the others are pre-checked."
        }
        $lvFiles.EndUpdate()
        if ($state.Cancel) { $lblDisk.Text = 'Stopped. ' + $lblDisk.Text }
    }
}
$btnDiskLarge.Add_Click({ Start-FileScan 'large' })
$btnDiskDup.Add_Click({ Start-FileScan 'dup' })
$btnDiskRecycle.Add_Click({
    $picked = @($lvFiles.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $picked) { Show-Msg 'Check one or more files first.' | Out-Null; return }
    if ($script:FileMode -eq 'dup') {   # never all copies of one file
        foreach ($g in $picked | Group-Object Group) {
            $all = @($lvFiles.Items | Where-Object { $_.Tag.Group -eq [int]$g.Name })
            if ($g.Count -ge $all.Count) { Show-Msg "All copies of $($g.Group[0].Name) are checked - leave at least one unchecked." 'OK' 'Warning' | Out-Null; return }
        }
    }
    $bytes = ($picked | Measure-Object Bytes -Sum).Sum
    if ((Show-Msg "Move $($picked.Count) file(s) ($(Format-Size $bytes)) to the Recycle Bin?`n`nYou can get them back from the Recycle Bin until you empty it." 'YesNo' 'Question') -ne 'Yes') { return }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $n = 0; $freed = 0; $bad = @()
    foreach ($f in $picked) {
        try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f.Path, 'OnlyErrorDialogs', 'SendToRecycleBin'); $n++; $freed += $f.Bytes } catch { $bad += $f.Name }
    }
    Add-History 'Files' "$n file(s)" "moved to the Recycle Bin ($(Format-Size $freed))"; Update-History
    foreach ($it in @($lvFiles.CheckedItems)) { if (-not (Test-Path -LiteralPath $it.Tag.Path)) { $lvFiles.Items.Remove($it) } }
    Show-Msg "$n file(s) moved to the Recycle Bin ($(Format-Size $freed)). Empty the Recycle Bin to free the space.$(if ($bad) { "`n`nCouldn't move: $($bad -join ', ')" })" | Out-Null
})
$lvFiles.Add_DoubleClick({ if ($lvFiles.SelectedItems.Count) { Start-Process explorer.exe "/select,`"$($lvFiles.SelectedItems[0].Tag.Path)`"" } })

$lvDisk.Add_DoubleClick({
    if ($lvDisk.SelectedItems.Count -and $lvDisk.SelectedItems[0].Tag -ne $txtDisk.Text) { Start-DiskScan $lvDisk.SelectedItems[0].Tag }
})

# ===========================================================================
# Updates: programs with a newer version, via winget (the package manager built into Windows)
# ===========================================================================
$pgUpd = New-Page 'Updates' 'Programs with a newer version available, via winget (built into Windows). Small updates are pre-checked; big version jumps, self-updating apps, very large updates and keep-list programs are not. Close a program before updating it.'
$btnUpdScan = New-Button 'Check for updates'
$btnUpdRun = New-Button 'Update checked'
$btnUpdStore = New-Button 'Store app updates'
$lvUpd = New-ListView $true @('Program', 340, 'Installed', 130, 'Available', 130, 'Note', 330)
$lblUpd = New-Status
Set-PageLayout $pgUpd $lvUpd @((New-ButtonBar @($btnUpdScan, $btnUpdRun, $btnUpdStore))) $lblUpd
# Apps that keep themselves current (winget often can't update them anyway) and updates that take ages.
$SelfUpdating = '^(Microsoft\.Edge|Google\.Chrome|Mozilla\.Firefox|Brave\.Brave|Opera\.|Valve\.Steam|Discord\.|Spotify\.|Microsoft\.Teams|Microsoft\.Office|Microsoft\.OneDrive|Microsoft\.Outlook|Anthropic\.Claude|SlackTechnologies\.|Zoom\.Zoom)'
$HeavyUpdates = '^(Microsoft\.VisualStudio\.20|Microsoft\.SQLServer\.20|Adobe\.CreativeCloud|EpicGames\.)'
function Get-Major($Version) { if ("$Version" -match '(\d+)') { [int]$Matches[1] } else { -1 } }

$UpdScanWork = {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $wg) { return [pscustomobject]@{ Error = 'winget missing'; Rows = @() } }
    $r = Invoke-Native $wg 'upgrade --accept-source-agreements --disable-interactivity' 300
    # Progress spinners rewrite a line with CR; keep only what's after the last one.
    $lines = @($r.Out -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1] })
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^-{20,}\s*$') { continue }
        # Header names are translated on non-English Windows, so columns are found by position: where each header word starts.
        $hdr = $lines[$i - 1]
        $starts = @(0) + @([regex]::Matches($hdr, '(?<=\s)\S') | ForEach-Object Index)
        if ($starts.Count -lt 4) { continue }
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $l = $lines[$j]
            if (-not $l.Trim()) { break }
            if ($l.Length -le $starts[3]) { continue }   # footer such as "27 upgrades available."
            $cut = { param($a, $b) if ($a -ge $l.Length) { '' } elseif ($b -and $b -lt $l.Length) { $l.Substring($a, $b - $a).Trim() } else { $l.Substring($a).Trim() } }
            $rows += [pscustomobject]@{ Name = (& $cut 0 $starts[1]); Id = (& $cut $starts[1] $starts[2]); Version = (& $cut $starts[2] $starts[3])
                                        Available = (& $cut $starts[3] $(if ($starts.Count -gt 4) { $starts[4] } else { $null })) }
        }
    }
    $err = if ($r.TimedOut) { 'winget took too long - try again later' }
           elseif (-not $rows -and $r.Code -ne 0 -and $r.Out -notmatch 'No (installed package|available upgrade|applicable)') {
               "winget: $(($r.Out -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].Trim() } | Where-Object { $_ } | Select-Object -Last 1))" }
           else { $null }
    [pscustomobject]@{ Error = $err; Rows = $rows }
}
$UpdRunWork = {
    param($items)
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    $n = 0; $all = @($items).Count
    foreach ($i in $items) {
        $n++; if (Test-Cancelled) { break }; Set-JobProgress $i.Name $n $all
        $r = Invoke-Native $wg "upgrade --id `"$($i.Id)`" --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" 1800
        $last = $r.Out -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].Trim() } |
                Where-Object { $_ -and $_ -notmatch '^[\-\\|/\s]+$' -and $_ -notmatch '\d+(\.\d+)? ?[KMG]B ?/ ?\d' } | Select-Object -Last 1
        [pscustomobject]@{ Name = $i.Name; Id = $i.Id; From = $i.Version; To = $i.Available; Ok = ($r.Code -eq 0)
                           Msg = $(if ($r.Cancelled) { 'stopped - you pressed Cancel' } elseif ($r.TimedOut) { 'took longer than 30 minutes - stopped' } else { $last }) }
    }
}
function Start-UpdScan {
    $btnUpdScan.Enabled = $false; $btnUpdRun.Enabled = $false
    $lblUpd.Text = 'Asking winget which programs have updates (20-60 seconds)...'
    Start-Bg -Label 'Checking for program updates' -Cancellable $UpdScanWork $null {
        param($r)
        $r = $r[0]
        $btnUpdScan.Enabled = $true; $btnUpdRun.Enabled = $true
        if ($r.Error -eq 'winget missing') {
            $lblUpd.Text = 'winget is missing on this PC - install "App Installer" from the Microsoft Store, then check again.'
            $script:ExtraAdvice.Remove('Updates'); return
        }
        $userKeep = Get-UserKeep
        $script:UpdScanned = [bool]$r -and -not $r.Error
        $lvUpd.BeginUpdate(); $lvUpd.Items.Clear()
        foreach ($u in $r.Rows) {
            $text = "$($u.Name) $($u.Id)"
            $on = $false
            $note = if (($userKeep -and $text -match $userKeep) -or $text -match $KeepBuiltIn) { 'on the keep list - update it yourself if you want' }
                    elseif ($u.Id -match $SelfUpdating) { 'updates itself - just restart it' }
                    elseif ($u.Id -match $HeavyUpdates) { 'very large update - run it when you have time' }
                    elseif ($u.Id -match [char]0x2026) { 'name cut off by winget - update it from the program itself' }
                    elseif ((Get-Major $u.Version) -ne (Get-Major $u.Available)) { 'major new version - check it still suits you' }
                    else { $on = $true; 'small update' }
            $it = Add-Row $lvUpd @($u.Name, $u.Version, $u.Available, $note) $u $on
            if (-not $on) { $it.ForeColor = $Theme.Muted }
        }
        $lvUpd.EndUpdate()
        $n = $r.Rows.Count
        $lblUpd.Text = if ($r.Error) { $r.Error } elseif ($n) { "$n program(s) can be updated, $($lvUpd.CheckedItems.Count) pre-checked." } else { 'Everything winget knows about is up to date.' }
        if ($n) { $script:ExtraAdvice['Updates'] = "$n program update(s) available - see the Updates tab." } else { $script:ExtraAdvice.Remove('Updates') }
        Update-Health -Quick
    }
}
$btnUpdScan.Add_Click({ Start-UpdScan })
$btnUpdStore.Add_Click({ Start-Process 'ms-windows-store://downloadsandupdates' })
$btnUpdRun.Add_Click({ Start-ProgramUpdates })
# (A function so the simple view's "Fix this" can start it too.)
function Start-ProgramUpdates {
    $picked = @($lvUpd.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $picked) { Show-Msg 'Check at least one program first.' | Out-Null; return }
    $names = ($picked | ForEach-Object { " - $($_.Name) ($($_.Version) -> $($_.Available))" }) -join "`n"
    $q = "Update these $($picked.Count) program(s)?`n$names`n`nClose them first. Some show a permission prompt - click Yes. This can take a few minutes."
    if ((Show-Msg $q 'YesNo' 'Question') -ne 'Yes') { return }
    $btnUpdScan.Enabled = $false; $btnUpdRun.Enabled = $false
    $lblUpd.Text = "Updating $($picked.Count) program(s)... watch for permission prompts."
    Start-Bg -Label 'Updating programs' -Cancellable $UpdRunWork $picked {
        param($results)
        $bad = @()
        foreach ($r in $results) {
            Add-History 'Update' $r.Name ('{0} -> {1}: {2}' -f $r.From, $r.To, $(if ($r.Ok) { 'updated' } else { "failed - $($r.Msg)" }))
            if (-not $r.Ok) { $bad += "$($r.Name): $($r.Msg)" }
        }
        $msg = "$(@($results | Where-Object Ok).Count) of $($results.Count) program(s) updated."
        if ($bad) { $msg += "`n`nNot updated (often because the program was open - close it and try again):`n" + ($bad -join "`n") }
        Show-Msg $msg | Out-Null
        Update-History; Start-UpdScan
    }
}

# ===========================================================================
# Security: is this PC protected?
# ===========================================================================
$pgSec = New-Page 'Security' 'Is this PC protected? Green is fine, orange is worth a look, red needs fixing. Double-click a row (or select it and click Open setting) to go to the right Windows setting.'
$btnSecScan = New-Button 'Check again'
$btnSecOpen = New-Button 'Open setting'
$btnSecWS = New-Button 'Open Windows Security'
$lvSec = New-ListView $false @('Check', 190, 'Status', 80, 'Result', 360, 'What to do', 600)
$txtSec = New-DetailBox 104
Set-PageLayout $pgSec $lvSec @((New-ButtonBar @($btnSecScan, $btnSecOpen, $btnSecWS))) $txtSec
$lblSec = New-Status; $pgSec.Controls.Add($lblSec)

$SecScanWork = {
    param($culture)
    if ($culture) { [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($culture) }
    $PSDefaultParameterValues = @{ 'Get-CimInstance:OperationTimeoutSec' = 15; 'Get-CimInstance:ErrorAction' = 'SilentlyContinue' }
    $rows = New-Object System.Collections.ArrayList
    function Add-Sec($Check, $Level, $Result, $Todo, $Link) { [void]$rows.Add([pscustomobject]@{ Check = $Check; Level = $Level; Result = $Result; Todo = $Todo; Link = $Link }) }
    $now = Get-Date
    $chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes | ForEach-Object { [int]$_ })
    $laptop = [bool]($chassis | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 })

    # --- Windows version and how long it gets security updates ---
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $win11 = [int]$cv.CurrentBuild -ge 22000           # ProductName still says "Windows 10" on Windows 11
    $ver = if ($cv.DisplayVersion) { "$($cv.DisplayVersion)" } else { "$($cv.ReleaseId)" }
    $edition = "$($cv.EditionID)"
    $ltsc = $edition -match 'EnterpriseS|IoTEnterpriseS|LTS'
    $osName = "Windows $(if ($win11) { '11' } else { '10' }) $($edition -replace '^Professional.*', 'Pro' -replace '^Core.*', 'Home') $ver"
    # Last day of security updates for Home/Pro; Enterprise/Education get about a year more. Dates from 2028 on are estimates.
    $ends = if ($win11) { @{ '21H2' = '2023-10-10'; '22H2' = '2024-10-08'; '23H2' = '2025-11-11'; '24H2' = '2026-10-13'; '25H2' = '2027-10-12'; '26H2' = '2028-10-10' } }
            else { @{ '22H2' = '2025-10-14' } }
    if ($win11 -and $edition -match 'Enterprise|Education') {
        $ends = @{ '21H2' = '2024-10-08'; '22H2' = '2025-10-14'; '23H2' = '2026-11-10'; '24H2' = '2027-10-12'; '25H2' = '2028-10-10'; '26H2' = '2029-10-09' }
    }
    $end = $ends[$ver]
    if ($ltsc) { Add-Sec 'Windows version' 'OK' "$osName (long-term edition)" 'Long-term editions get security updates for years. Nothing to do.' 'ms-settings:windowsupdate' }
    elseif (-not $end) {
        if ($win11) { Add-Sec 'Windows version' 'Info' $osName 'Not a version this check knows. Open Windows Update to see if a newer one is offered.' 'ms-settings:windowsupdate' }
        else { Add-Sec 'Windows version' 'Problem' "$osName - no longer supported" 'This Windows 10 version gets no security updates any more. See the Windows 11 check below for your options.' 'ms-settings:windowsupdate' }
    } else {
        $endDate = [datetime]$end
        $days = [int]($endDate - $now).TotalDays
        if ($days -lt 0) {
            $todo = if ($win11) { 'This version gets no more security updates. Open Windows Update and install the newest Windows 11 version (free).' }
                    else { 'Windows 10 stopped getting security updates. Upgrade to Windows 11 for free if the PC qualifies (see below), sign up for Extended Security Updates, or plan a replacement.' }
            Add-Sec 'Windows version' 'Problem' "$osName - security updates ended $($endDate.ToString('d MMM yyyy'))" $todo 'ms-settings:windowsupdate'
        } elseif ($days -lt 120) {
            Add-Sec 'Windows version' 'Warning' "$osName - security updates end $($endDate.ToString('d MMM yyyy'))" 'Install the newest Windows version from Windows Update before then (free).' 'ms-settings:windowsupdate'
        } else {
            Add-Sec 'Windows version' 'OK' "$osName - supported until $(if ($endDate.Year -ge 2028) { 'about ' })$($endDate.ToString('MMM yyyy'))" 'Nothing to do - Windows Update keeps it patched.' 'ms-settings:windowsupdate'
        }
    }

    # --- Firmware, Secure Boot, TPM (also what Windows 11 needs) ---
    Add-Type -Namespace PcTuneUp -Name Firmware -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool GetFirmwareType(out uint t);' -ErrorAction SilentlyContinue
    $fwType = 0; try { [void][PcTuneUp.Firmware]::GetFirmwareType([ref]$fwType) } catch { }
    $secureBoot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    $tpmOut = (& tpmtool.exe getdeviceinformation 2>$null) -join "`n"
    $tpmPresent = $tpmOut -match 'TPM Present:\s*True'
    $tpmVer = if ($tpmOut -match 'TPM Version:\s*([\d.]+)') { $Matches[1] } else { '' }
    if ($fwType -eq 1) { Add-Sec 'Secure Boot' 'Warning' 'PC starts in old "legacy BIOS" mode' 'Modern UEFI mode with Secure Boot blocks malware that loads before Windows. Switching needs care (the disk must be converted with MBR2GPT) - get help if unsure.' $null }
    elseif ($secureBoot -eq 1) { Add-Sec 'Secure Boot' 'OK' 'On' 'Nothing to do.' $null }
    else { Add-Sec 'Secure Boot' 'Warning' 'Off' 'Switch Secure Boot on in the firmware (BIOS/UEFI) settings - usually F2, F10 or Del while the PC starts.' $null }
    if ($tpmPresent -and $tpmVer -like '2*') { Add-Sec 'TPM security chip' 'OK' "TPM $tpmVer present" 'Nothing to do.' $null }
    elseif ($tpmPresent) { Add-Sec 'TPM security chip' 'Warning' "Old TPM $tpmVer" 'Windows 11 needs TPM 2.0. Some PCs can switch to 2.0 with a firmware update from the maker.' $null }
    elseif ($tpmOut) { Add-Sec 'TPM security chip' 'Warning' 'None found' 'Many PCs have one that is switched off - look for TPM, PTT (Intel) or fTPM (AMD) in the firmware settings.' $null }
    else { Add-Sec 'TPM security chip' 'Info' 'Could not check' 'Run "tpm.msc" to see the TPM status.' 'tpm.msc' }

    if (-not $win11) {
        $cpuName = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim()
        $cpuOk = if ($cpuName -match 'Core\(TM\) Ultra|Core Ultra') { $true }
                 elseif ($cpuName -match 'i[3579]-(\d{4,5})') { $n = $Matches[1]; $gen = if ($n.Length -eq 5) { [int]$n.Substring(0, 2) } else { [int]$n.Substring(0, 1) }; $gen -ge 8 }
                 elseif ($cpuName -match 'Ryzen \d (PRO )?(\d)\d{3}') { [int]$Matches[2] -ge 2 }
                 else { $null }
        $os = Get-CimInstance Win32_OperatingSystem
        $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $missing = @()
        if (-not ($tpmPresent -and $tpmVer -like '2*')) { $missing += 'TPM 2.0 (often only switched off in the firmware)' }
        if ($fwType -ne 2) { $missing += 'UEFI start-up with Secure Boot' }
        if ($cpuOk -eq $false) { $missing += "a newer processor (Intel 8th gen or AMD Ryzen 2000 and later; this is a $cpuName)" }
        if ($os.TotalVisibleMemorySize -lt 3.5MB) { $missing += '4 GB of memory' }
        if ($c.Size -and $c.Size -lt 60GB) { $missing += 'a 64 GB or larger drive' }
        if ($missing) {
            Add-Sec 'Windows 11 ready?' 'Problem' "No - missing: $($missing -join '; ')" 'If only TPM or Secure Boot is missing, switch them on in the firmware settings and check again. Otherwise: Extended Security Updates for Windows 10, or a new or refurbished PC.' $null
        } else {
            Add-Sec 'Windows 11 ready?' 'Warning' $(if ($null -eq $cpuOk) { "Probably - processor not recognised ($cpuName); confirm with Microsoft's PC Health Check" } else { 'Yes - this PC can run Windows 11' }) `
                'Upgrade for free: Settings > Windows Update > Upgrade to Windows 11. Back up your files first.' 'ms-settings:windowsupdate'
        }
    }

    # --- Antivirus and firewall (as Windows Security sees them) ---
    $avs = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct)
    $avOn = @($avs | Where-Object { (($_.productState -shr 8) -band 0x10) })          # byte 2: 0x10 = enabled
    $avCurrent = @($avOn | Where-Object { -not ($_.productState -band 0x10) })        # byte 3: 0x10 = out of date
    $nameOf = { param($list) (($list | ForEach-Object { $_.displayName } | Select-Object -Unique) -join ', ') }
    if ($avCurrent) { Add-Sec 'Antivirus' 'OK' "$(& $nameOf $avCurrent) - on and up to date" 'Nothing to do.' 'windowsdefender://threat' }
    elseif ($avOn) { Add-Sec 'Antivirus' 'Warning' "$(& $nameOf $avOn) - on but out of date" 'Open it and update it. If that fails, check the internet connection or whether its subscription ran out.' 'windowsdefender://threat' }
    elseif ($avs) { Add-Sec 'Antivirus' 'Problem' "$(& $nameOf $avs) - switched off" 'Switch it on. If a paid antivirus expired, uninstall it - Microsoft Defender then takes over for free.' 'windowsdefender://threat' }
    else { Add-Sec 'Antivirus' 'Problem' 'No antivirus found' 'Open Windows Security and switch on Microsoft Defender.' 'windowsdefender://threat' }

    $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    $fwOff = @($profiles | Where-Object { "$($_.Enabled)" -eq 'False' } | ForEach-Object Name)
    $fwOther = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName FirewallProduct | Where-Object { (($_.productState -shr 8) -band 0x10) })
    if (-not $profiles) { Add-Sec 'Firewall' 'Info' 'Could not check' 'Open Windows Security > Firewall & network protection.' 'windowsdefender://network' }
    elseif (-not $fwOff) { Add-Sec 'Firewall' 'OK' 'Windows Firewall is on' 'Nothing to do.' 'windowsdefender://network' }
    elseif ($fwOther) { Add-Sec 'Firewall' 'OK' "$(& $nameOf $fwOther) firewall is on" 'Nothing to do.' 'windowsdefender://network' }
    else { Add-Sec 'Firewall' 'Problem' "Windows Firewall is off ($($fwOff -join ', '))" 'Switch it on in Windows Security > Firewall & network protection.' 'windowsdefender://network' }

    # --- Drive encryption ---
    $bl = try { (New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection') } catch { $null }
    $keyTip = 'Know where the recovery key is: account.microsoft.com/devices/recoverykey - you need it if the PC ever asks for it.'
    switch ([int]$bl) {
        { $_ -in 1, 3, 6 } { Add-Sec 'Drive encryption' 'OK' 'C: is encrypted (BitLocker / Device encryption)' $keyTip 'ms-settings:deviceencryption' }
        5 { Add-Sec 'Drive encryption' 'Warning' 'Encryption is paused' 'It is usually paused during an update and resumes after a restart. If it stays paused, resume it in BitLocker settings.' 'ms-settings:deviceencryption' }
        2 {
            if ($laptop) { Add-Sec 'Drive encryption' 'Warning' 'C: is not encrypted' "Anyone who steals the laptop can read its files. Turn on Device encryption (Settings > Privacy & security > Device encryption) or BitLocker on Pro. $keyTip" 'ms-settings:deviceencryption' }
            else { Add-Sec 'Drive encryption' 'Info' 'C: is not encrypted' 'Less important for a desktop that stays at home; worth it for business PCs.' 'ms-settings:deviceencryption' }
        }
        default { Add-Sec 'Drive encryption' 'Info' 'Could not check' 'See Settings > Privacy & security > Device encryption.' 'ms-settings:deviceencryption' }
    }

    # --- Smaller protections ---
    $hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue).Enabled
    if ($hvci -eq 1) { Add-Sec 'Memory integrity' 'OK' 'On' 'Nothing to do.' 'windowsdefender://coreisolation' }
    else { Add-Sec 'Memory integrity' 'Info' 'Off' 'Optional extra protection: Windows Security > Device security > Core isolation. Very old drivers can block it.' 'windowsdefender://coreisolation' }
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).EnableLUA
    if ($uac -eq 0) { Add-Sec 'User Account Control' 'Problem' 'Off - every program runs with full rights' 'Search "UAC" in Start, set the slider back to the default level and restart.' $null }
    else { Add-Sec 'User Account Control' 'OK' 'On' 'Nothing to do.' $null }
    $smb1 = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' -ErrorAction SilentlyContinue
    if ($smb1 -and $smb1.Start -ne 4) { Add-Sec 'Old file sharing (SMB 1.0)' 'Warning' 'Installed' 'SMB 1.0 is what the WannaCry worm used. Remove it unless a very old NAS or printer needs it: Windows Features > untick "SMB 1.0/CIFS File Sharing Support".' 'optionalfeatures.exe' }
    else { Add-Sec 'Old file sharing (SMB 1.0)' 'OK' 'Off' 'Nothing to do.' $null }
    $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).fDenyTSConnections
    if ($rdp -eq 0) { Add-Sec 'Remote Desktop' 'Info' 'On - this PC accepts remote connections' 'Fine if you use it. Otherwise switch it off: Settings > System > Remote Desktop.' 'ms-settings:remotedesktop' }
    else { Add-Sec 'Remote Desktop' 'OK' 'Off' 'Nothing to do.' 'ms-settings:remotedesktop' }

    # --- Abandoned software that no longer gets security fixes ---
    $dead = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($sub in Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue) {
            $n = "$((Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue).DisplayName)"
            if ($n -match '^Adobe Flash|^Adobe Shockwave|^Java\(TM\) [67]|^Java [67] Update|^QuickTime|^Microsoft Silverlight|^Python 2\.|^Adobe Reader (X|9|8)\b') { $dead += $n }
            elseif ($n -match '^Microsoft (Windows Desktop Runtime|\.NET Runtime|ASP\.NET Core|\.NET Core).*?\b([1-7])\.\d+\.\d+') { $dead += $n }
        }
    }
    $dead = @($dead | Select-Object -Unique)
    if ($dead) { Add-Sec 'Out-of-support software' 'Warning' "$($dead.Count) found: $(($dead | Select-Object -First 4) -join '; ')$(if ($dead.Count -gt 4) { '...' })" `
        'These no longer get security fixes. Uninstall them in Settings > Apps; old .NET runtimes can go too - a program that still needs one will ask for it.' 'ms-settings:appsfeatures' }
    else { Add-Sec 'Out-of-support software' 'OK' 'None of the usual suspects (Flash, Java 6/7, QuickTime, Silverlight, old .NET)' 'Nothing to do.' $null }
    $rows   # emitted item by item, so the Done block receives the rows themselves
}
$SecLevels = @{ Problem = 0; Warning = 1; Info = 2; OK = 3 }
function Update-Security {
    $btnSecScan.Enabled = $false
    $lblSec.Text = 'Checking security settings...'
    Start-Bg -Label 'Checking security' $SecScanWork $UiCulture.Name {
        param($rows)
        $btnSecScan.Enabled = $true
        $lvSec.BeginUpdate(); $lvSec.Items.Clear()
        foreach ($r in $rows | Sort-Object { $SecLevels[$_.Level] }) {
            $it = Add-Row $lvSec @($r.Check, $r.Level, $r.Result, $r.Todo) $r
            Set-RowStatus $it 1 $(switch ($r.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.Muted } })
        }
        $lvSec.EndUpdate()
        $p = @($rows | Where-Object Level -eq 'Problem').Count; $w = @($rows | Where-Object Level -eq 'Warning').Count
        $lblSec.Text = "$(@($rows | Where-Object Level -eq 'OK').Count) of $($rows.Count) checks fine" + $(if ($p) { ", $p problem(s)" }) + $(if ($w) { ", $w worth a look" }) + '.'
        if ($p) { $script:ExtraAdvice['Security'] = "Security: $p problem(s) - see the Security tab." } else { $script:ExtraAdvice.Remove('Security') }
        if ($lvSec.Items.Count) { $lvSec.Items[0].Selected = $true }
        Update-Health -Quick
    }
}
# For buttons that act on "the selected row": the row's data, or a short note when no row is selected
# (otherwise clicking the button seemed to do nothing).
function Get-PickedRow($Lv) {
    if ($Lv.SelectedItems.Count) { return $Lv.SelectedItems[0].Tag }
    Show-Msg 'Select a row in the list first, then click the button again.' | Out-Null
    $null
}
function Open-SecSetting {
    $row = Get-PickedRow $lvSec; if (-not $row) { return }
    $link = $row.Link
    if ($link) { try { Start-Process $link } catch { Show-Msg "Couldn't open $link" | Out-Null } }
    else { Show-Msg 'This one is changed in the firmware (BIOS/UEFI) settings, not in Windows - see "What to do".' | Out-Null }
}
$lvSec.Add_SelectedIndexChanged({
    if (-not $lvSec.SelectedItems.Count) { return }
    $r = $lvSec.SelectedItems[0].Tag
    $txtSec.Text = "$($r.Check): $($r.Result)`r`n`r`nWhat to do: $($r.Todo)"
})
$lvSec.Add_DoubleClick({ Open-SecSetting })
$btnSecOpen.Add_Click({ Open-SecSetting })
$btnSecScan.Add_Click({ Update-Security })
$btnSecWS.Add_Click({ Start-Process 'windowsdefender:' })

# ===========================================================================
# Stability: what went wrong in the last 30 days, from Windows' own logs
# ===========================================================================
$pgStab = New-Page 'Stability' 'What went wrong in the last 30 days according to Windows'' own logs - crashes, freezes, blue screens, errors - and what usually fixes it. Click a row for details.'
$btnStabScan = New-Button 'Refresh'
$btnStabRel = New-Button 'Open Reliability Monitor'
$btnStabWeb = New-Button 'Search selected online'
$btnStabFix = New-Button 'Fix selected problem'; $btnStabFix.Enabled = $false
$lvStab = New-ListView $false @('Problem', 160, 'What', 300, 'Times', 60, 'Last', 130, 'What to do', 600)
$txtStab = New-DetailBox 114
Set-PageLayout $pgStab $lvStab @((New-ButtonBar @($btnStabFix, $btnStabScan, $btnStabRel, $btnStabWeb))) $txtStab
$lblStab = New-Status; $pgStab.Controls.Add($lblStab)

$StabScanWork = {
    $since = (Get-Date).AddDays(-30)
    function Get-Events($Log, $Ids, $Providers, $Levels) {
        $f = @{ LogName = $Log; StartTime = $since }
        if ($Ids) { $f.Id = $Ids }; if ($Providers) { $f.ProviderName = $Providers }; if ($Levels) { $f.Level = $Levels }
        try { @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop) } catch { @() }
    }
    $rows = New-Object System.Collections.ArrayList
    # $Fix names the one-click fix for the row (see $StabilityFixes); set $nextFix just before calling.
    function Add-Stab($Problem, $Level, $What, $Events, $Todo, $Search, $Fix = $nextFix) {
        $last = ($Events | Measure-Object TimeCreated -Maximum).Maximum
        $first = ($Events | Measure-Object TimeCreated -Minimum).Minimum
        [void]$rows.Add([pscustomobject]@{ Problem = $Problem; Level = $Level; What = $What; Count = @($Events).Count; Last = $last; First = $first; Todo = $Todo; Search = $Search; Fix = $Fix; OrigTodo = $null })
    }
    $nextFix = $null
    $sev = { param($n, $warnAt, $probAt) if ($n -ge $probAt) { 'Problem' } elseif ($n -ge $warnAt) { 'Warning' } else { 'Info' } }

    # --- App crashes, grouped by what actually caused them ---
    # Add-ons that load themselves into other programs and are a common hidden crash cause.
    $injectors = @(
        @{ Match = 'nview'; Fix = 'nview'; Name = 'NVIDIA nView'; Todo = 'NVIDIA nView (an old desktop-manager add-on) loads itself into other programs and crashes them. Turn it off: NVIDIA Control Panel > Desktop Management > Disable, or uninstall "NVIDIA nView" in Settings > Apps.' }
        @{ Match = '^(nvlddmkm|nvwgf2um|nvd3dum|nvoglv|nvapi|nvcuda)'; Fix = 'drivers'; Name = 'NVIDIA graphics driver'; Todo = 'Update the NVIDIA driver from nvidia.com or the PC maker''s support page (choose a clean install).' }
        @{ Match = '^(atidxx|amdxx|atiumd|amdkmdag|aticfx|amdvlk)'; Fix = 'drivers'; Name = 'AMD graphics driver'; Todo = 'Update the AMD graphics driver from amd.com or the PC maker''s support page.' }
        @{ Match = '^(igd|ig\d|igc|igxelp)'; Fix = 'drivers'; Name = 'Intel graphics driver'; Todo = 'Update the Intel graphics driver (Windows Update > Advanced > Optional updates, or the PC maker''s support page).' }
        @{ Match = '^(ucrtbase|vcruntime|msvcp|msvcr)'; Fix = 'vcredist'; Name = 'Visual C++ runtime'; Todo = 'Repair "Microsoft Visual C++ Redistributable" in Settings > Apps (Modify > Repair), then update the crashing programs.' }
        @{ Match = '^(rtsshooks|gameoverlayrenderer|discordhook|overlay|nahimic|sonic|a-volute|ss3|sbiedll)'; Name = 'an overlay or audio add-on'; Todo = 'An overlay (Steam, Discord, RivaTuner) or audio enhancer (Nahimic, Sonic Studio) loads into other programs. Update it or switch its overlay off.' }
    )
    $crashes = Get-Events 'Application' 1000 'Application Error'
    $groups = @{}
    foreach ($e in $crashes) {
        $app = "$($e.Properties[0].Value)"; $mod = "$($e.Properties[3].Value)"
        $inj = $injectors | Where-Object { $mod -match $_.Match } | Select-Object -First 1
        $key = if ($inj) { "inj|$($inj.Name)" } else { "app|$app" }
        if (-not $groups[$key]) { $groups[$key] = @{ Inj = $inj; Apps = @{}; Events = @(); Mods = @{} } }
        $groups[$key].Apps[$app] = 1; $groups[$key].Mods[$mod] = 1; $groups[$key].Events += $e
    }
    foreach ($g in $groups.Values) {
        $n = $g.Events.Count; $apps = ($g.Apps.Keys | Sort-Object) -join ', '
        if ($g.Inj) {
            $nextFix = $g.Inj.Fix
            $level = & $sev $n 2 3; $todo = $g.Inj.Todo; $what = "$($g.Inj.Name) crashed $apps"
            if ($g.Inj.Fix -eq 'nview') {
                # Already switched off? Its start-up task is disabled and nothing crashed after the task last ran.
                $tasks = @(Get-ScheduledTask -TaskName 'nWizard*' -ErrorAction SilentlyContinue)
                $lastRun = ($tasks | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue | Measure-Object LastRunTime -Maximum).Maximum
                $lastCrash = ($g.Events | Measure-Object TimeCreated -Maximum).Maximum
                $running = Get-Process -Name 'nview*', 'nwiz*' -ErrorAction SilentlyContinue
                if ($tasks -and -not ($tasks | Where-Object State -ne 'Disabled') -and -not $running -and $lastRun -and $lastCrash -le $lastRun.AddMinutes(30)) {
                    $level = 'Info'; $what = "Switched off: $($g.Inj.Name) crashed $apps"
                    $todo = "Fixed: nView's start-up task is switched off and there have been no crashes since $($lastCrash.ToString('g')). To remove it completely, uninstall ""NVIDIA RTX Desktop Manager"" in Settings > Apps."
                }
            }
            Add-Stab 'App crashes' $level $what $g.Events $todo "$($g.Inj.Name) $(@($g.Mods.Keys)[0]) crash"
        } else {
            $nextFix = 'appupdate'
            Add-Stab 'App crashes' (& $sev $n 2 5) "$apps crashed" $g.Events "Update or reinstall $apps. If it keeps crashing, check the maker's support site (crash point: $(@($g.Mods.Keys)[0]))." "$apps crash $(@($g.Mods.Keys)[0])"
        }
    }

    $nextFix = $null
    # --- Programs freezing ---
    $hangs = Get-Events 'Application' 1002 'Application Hang'
    $hangGroups = @($hangs | Group-Object { "$($_.Properties[0].Value)" })
    foreach ($g in $hangGroups | Where-Object Count -gt 1) {
        Add-Stab 'Freezes' (& $sev $g.Count 3 10) "$($g.Name) stopped responding" $g.Group "If $($g.Name) freezes often, update it. Many different programs freezing points to full memory or a slow or failing drive - see the Health tab." "$($g.Name) not responding"
    }
    $once = @($hangGroups | Where-Object Count -eq 1)   # one-off freezes: one row, not one each
    if ($once) {
        $level = if ($once.Count -ge 8) { 'Warning' } else { 'Info' }
        Add-Stab 'Freezes' $level "$($once.Count) program(s) froze once ($((($once | ForEach-Object Name) | Select-Object -First 4) -join ', ')$(if ($once.Count -gt 4) { '...' }))" ($once | ForEach-Object Group) `
            'A one-off freeze is normal. Many different programs freezing points to full memory or a slow or failing drive - see the Health tab.' $null
    }

    # --- Blue screens ---
    $bugchecks = @{
        '0000000a' = 'IRQL_NOT_LESS_OR_EQUAL|a driver'; '0000001a' = 'MEMORY_MANAGEMENT|memory (RAM) or a driver'; '0000003b' = 'SYSTEM_SERVICE_EXCEPTION|a driver'
        '00000050' = 'PAGE_FAULT_IN_NONPAGED_AREA|memory or a driver'; '0000007e' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED|a driver'; '0000007a' = 'KERNEL_DATA_INPAGE_ERROR|the drive or its connection'
        '0000009f' = 'DRIVER_POWER_STATE_FAILURE|a driver during sleep or wake-up'; '000000d1' = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL|a driver (often network or Wi-Fi)'; '000000c2' = 'BAD_POOL_CALLER|a driver'
        '000000ef' = 'CRITICAL_PROCESS_DIED|damaged Windows files or the drive'; '000000f4' = 'CRITICAL_OBJECT_TERMINATION|the drive'; '00000116' = 'VIDEO_TDR_FAILURE|the graphics driver'
        '00000124' = 'WHEA_UNCORRECTABLE_ERROR|hardware (processor, memory or overheating)'; '0000012b' = 'FAULTY_HARDWARE_CORRUPTED_PAGE|memory (RAM)'; '00000133' = 'DPC_WATCHDOG_VIOLATION|a storage or other driver'
        '00000139' = 'KERNEL_SECURITY_CHECK_FAILURE|a driver or memory'; '0000001e' = 'KMODE_EXCEPTION_NOT_HANDLED|a driver'; '000000be' = 'ATTEMPTED_WRITE_TO_READONLY_MEMORY|a driver'
    }
    $bsods = Get-Events 'System' 1001 'Microsoft-Windows-WER-SystemErrorReporting'
    foreach ($g in $bsods | Group-Object { if ($_.Message -match '0x([0-9a-fA-F]{8})') { $Matches[1].ToLower() } else { '?' } }) {
        $name, $cause = "$($bugchecks[$g.Name])" -split '\|'
        if (-not $name) { $name = "stop code 0x$($g.Name)"; $cause = 'a driver or hardware' }
        $nextFix = switch -Regex ($name) {
            'MEMORY_MANAGEMENT|PAGE_FAULT|FAULTY_HARDWARE|WHEA' { 'memtest' }
            'CRITICAL_PROCESS_DIED' { 'sfc' }
            'KERNEL_DATA_INPAGE|CRITICAL_OBJECT_TERMINATION' { 'chkdsk' }
            default { 'drivers' }
        }
        Add-Stab 'Blue screens' 'Problem' "Windows crashed: $name" $g.Group `
            "Usually caused by $cause. Install driver updates (Windows Update > Advanced options > Optional updates, or the PC maker's support page). If it keeps happening, test the memory: run mdsched.exe." "$name blue screen fix"
    }

    $nextFix = $null
    # --- Shutdowns without warning (not counting blue screens, already listed) ---
    $down = @(Get-Events 'System' 41 'Microsoft-Windows-Kernel-Power' | Where-Object { "$($_.Properties[0].Value)" -eq '0' }) + @(Get-Events 'System' 6008 'EventLog')
    if ($down.Count) {
        $real = @($down | Where-Object Id -eq 41); if (-not $real) { $real = $down }
        Add-Stab 'Sudden shutdowns' (& $sev $real.Count 2 4) 'The PC switched off without shutting down properly' $real `
            'A power cut, the battery running flat, the power button held down, or overheating. If it happens on its own, check the charger or power supply and clean the fans.' 'PC turns off unexpectedly Kernel-Power 41'
    }

    # --- Graphics driver resets ---
    $tdr = Get-Events 'System' 4101 'Display'
    $nextFix = 'drivers'
    if ($tdr.Count) { Add-Stab 'Graphics resets' (& $sev $tdr.Count 2 5) 'The graphics driver stopped responding and recovered' $tdr 'Update the graphics driver. If it happens in games, check the GPU temperature and stop any overclocking.' 'display driver stopped responding and has recovered' }

    # --- Drive and hardware errors ---
    $disk = Get-Events 'System' $null @('disk', 'Ntfs', 'stornvme', 'storahci', 'iaStorVD', 'iaStorAVC', 'iaStorA') @(1, 2, 3)
    $nextFix = 'chkdsk'
    foreach ($g in $disk | Group-Object ProviderName) {
        Add-Stab 'Drive errors' (& $sev $g.Count 1 3) "Storage errors ($($g.Name))" $g.Group 'Back up important files now. Then check drive health on the Health tab and run the drive maker''s tool; frequent errors mean the drive or its cable is failing.' "$($g.Name) event error windows"
    }
    $whea = Get-Events 'System' $null 'Microsoft-Windows-WHEA-Logger' @(1, 2, 3)
    $nextFix = 'memtest'
    if ($whea.Count) { Add-Stab 'Hardware errors' $(if ($whea | Where-Object Level -le 2) { 'Problem' } else { 'Warning' }) 'The processor, memory or a PCIe device reported errors' $whea `
        'Make sure the PC isn''t overheating (clean the fans). If blue screens happen too, test the memory: run mdsched.exe.' 'WHEA-Logger error' }

    # --- Updates that keep failing ---
    $wu = Get-Events 'System' 20 'Microsoft-Windows-WindowsUpdateClient'
    $store = @($wu | Where-Object { "$($_.Properties[1].Value)" -match '^9[A-Z0-9]{11}-' })   # Store app packages
    # Defender's definition updates (KB2267602) and platform updates (KB4052623) retry on their own within hours - not worth showing.
    $win = @($wu | Where-Object { "$($_.Properties[1].Value)" -notmatch '^9[A-Z0-9]{11}-|KB2267602|KB4052623' })
    $nextFix = 'store'
    if ($store.Count) {
        $apps = @($store | ForEach-Object { ("$($_.Properties[1].Value)" -replace '^9[A-Z0-9]{11}-', '' -split '\.')[-1] } | Select-Object -Unique)
        Add-Stab 'Store app updates' 'Info' "$($apps.Count) Store app update(s) kept waiting ($(($apps | Select-Object -First 4) -join ', ')...)" $store `
            'Usually because the app was open at the time - they install by themselves later. To force it: Microsoft Store > Library > Get updates.' $null
    }
    $nextFix = 'wureset'
    foreach ($g in $win | Group-Object { "$($_.Properties[1].Value)" }) {
        $code = '0x{0:X8}' -f ([int64]$g.Group[0].Properties[0].Value -band 4294967295L)   # stored signed; show as the usual 0x8... code
        Add-Stab 'Windows Update' (& $sev $g.Count 2 4) "Couldn't install: $($g.Name)" $g.Group `
            "Restart and try Windows Update again. If it keeps failing: Settings > System > Troubleshoot > Other troubleshooters > Windows Update. (Error $code)" "$code windows update"
    }

    # --- Did it start right after an update? Windows Update's own log says what was installed when (readable without administrator).
    # A crash kind that began within 3 days of an update, after at least 10 quiet days, probably came with it. Rows whose cause is already known (an add-on, nView) are left alone.
    $updates = @(Get-Events 'System' 19 'Microsoft-Windows-WindowsUpdateClient' | ForEach-Object { [pscustomobject]@{ Time = $_.TimeCreated; Title = "$($_.Properties[0].Value)" } } |
                 Where-Object { $_.Title -notmatch 'KB2267602|KB4052623|KB890830|KB5007651|Security Intelligence|Defender Antivirus|^9[A-Z0-9]{11}-' })   # (virus definitions, the malware removal tool and Store apps don't break things)
    foreach ($row in $rows) {
        if ($row.Problem -notin 'App crashes', 'Blue screens', 'Graphics resets', 'Freezes', 'Hardware errors' -or $row.Count -lt 2 -or -not $row.First -or $row.What -match 'froze once' -or $row.Level -eq 'Info' -or $row.Fix -in 'nview', 'vcredist') { continue }
        $u = $updates | Where-Object { $_.Time -le $row.First -and ($row.First - $_.Time).TotalDays -le 3 -and ($_.Time - $since).TotalDays -ge 10 } | Sort-Object Time -Descending | Select-Object -First 1
        if (-not $u) { continue }
        $name = if ($u.Title -match '(KB\d{6,8})') { $Matches[1] } else { $t = $u.Title -replace '\s*\(.*$', ''; if ($t.Length -gt 50) { $t.Substring(0, 47) + '...' } else { $t } }
        $row.OrigTodo = $row.Todo
        $row.Todo = "It started right after a Windows update ($name, installed $($u.Time.ToString('d'))). If it keeps happening, uninstall that update: Settings > Windows Update > Update history > Uninstall updates."
        $row.Fix = 'wuhistory'
    }

    $index = $null
    $hist = @()
    try {
        $m = @(Get-CimInstance Win32_ReliabilityStabilityMetrics -OperationTimeoutSec 15 -ErrorAction Stop | Sort-Object TimeGenerated)
        $index = ($m | Select-Object -Last 1).SystemStabilityIndex
        $hist = @($m | Where-Object { $_.TimeGenerated -gt (Get-Date).AddDays(-90) } | Group-Object { $_.TimeGenerated.ToString('yyyy-MM-dd') } |
                  ForEach-Object { [pscustomobject]@{ D = [datetime]::ParseExact($_.Name, 'yyyy-MM-dd', $null); V = ($_.Group | Select-Object -Last 1).SystemStabilityIndex } })
    } catch { }
    [pscustomobject]@{ Rows = $rows; Index = $index; History = $hist }
}
$StabLevels = @{ Problem = 0; Warning = 1; Info = 2 }
function Update-Stability {
    $btnStabScan.Enabled = $false
    $lblStab.Text = 'Reading Windows'' logs...'
    Start-Bg -Label 'Reading Windows logs' $StabScanWork $null {
        param($r)
        $btnStabScan.Enabled = $true
        $r = $r[0]
        $lvStab.BeginUpdate(); $lvStab.Items.Clear()
        foreach ($s in $r.Rows | Sort-Object { $StabLevels[$_.Level] }, { - $_.Count }) {
            $it = Add-Row $lvStab @($s.Problem, $s.What, $s.Count, $(if ($s.Last) { $s.Last.ToString('g') } else { '' }), $s.Todo) $s
            $it.ForeColor = switch ($s.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } default { $Theme.Muted } }
        }
        $lvStab.EndUpdate()
        $script:StabIndex = $r.Index; $script:StabHistory = @($r.History); if ($chartScore) { Update-ScoreChart }
        $score = if ($null -ne $r.Index) { 'Windows rates stability {0:0.0} out of 10. ' -f $r.Index } else { '' }
        $p = @($r.Rows | Where-Object Level -eq 'Problem')
        $lblStab.Text = $score + $(if ($r.Rows.Count) { "$($r.Rows.Count) kind(s) of trouble in the last 30 days$(if ($p) { ", $($p.Count) worth fixing" })." } else { 'Nothing went wrong in the last 30 days.' })
        if ($p) { $script:ExtraAdvice['Stability'] = "Stability: $($p[0].What) ($($p[0].Count)x) - see the Stability tab." } else { $script:ExtraAdvice.Remove('Stability') }
        if ($lvStab.Items.Count) { $lvStab.Items[0].Selected = $true } else { $txtStab.Text = 'No crashes, freezes or errors found.' }
        Update-Health -Quick
    }
}
$lvStab.Add_SelectedIndexChanged({
    if (-not $lvStab.SelectedItems.Count) { $btnStabFix.Enabled = $false; return }
    $s = $lvStab.SelectedItems[0].Tag
    $fix = Get-StabilityFix $s
    $txtStab.Text = "$($s.Problem): $($s.What) - $($s.Count) time(s) in 30 days, last on $(if ($s.Last) { $s.Last.ToString('g') })`r`n`r`nWhat to do: $($s.Todo)" +
                    $(if ($s.OrigTodo) { "`r`n`r`nAlso: $($s.OrigTodo)" }) +
                    $(if ($fix) { "`r`n`r`nOne-click fix: $($fix.Label)$(if ($fix.Admin -and -not $IsAdmin) { ' (needs administrator)' })" })
    $btnStabFix.Enabled = [bool]$fix
})
$btnStabScan.Add_Click({ Update-Stability })
$btnStabFix.Add_Click({ Invoke-StabilityFix })

# ---------------------------------------------------------------------------
# One-click fixes for what the Stability page finds. Each asks first, and is recorded in History.
# ---------------------------------------------------------------------------
$StabilityFixes = @{
    nview     = @{ Label = 'Turn off NVIDIA nView'; Admin = $true }
    nviewgone = @{ Label = 'Uninstall NVIDIA nView completely (the graphics driver stays)'; Admin = $true }
    vcredist  = @{ Label = 'Repair the Visual C++ runtimes'; Admin = $false }
    wureset   = @{ Label = 'Reset Windows Update'; Admin = $true }
    sfc       = @{ Label = 'Repair Windows system files'; Admin = $true }
    chkdsk    = @{ Label = 'Check drive C: for errors'; Admin = $true }
    memtest   = @{ Label = 'Test the memory at the next restart'; Admin = $false }
    drivers   = @{ Label = 'Check the drivers on the Drivers page'; Admin = $false }
    store     = @{ Label = 'Open Store app updates'; Admin = $false }
    appupdate = @{ Label = 'Look for an update on the Updates page'; Admin = $false }
    wuhistory = @{ Label = 'Open the update history (to uninstall the update)'; Admin = $false }
}
function Get-StabilityFix($Row) {
    if (-not $Row.Fix) { return $null }
    $id = if ($Row.Fix -eq 'nview' -and $Row.Level -eq 'Info') { 'nviewgone' } else { $Row.Fix }   # already off: offer the uninstall
    $f = $StabilityFixes[$id]; if (-not $f) { return $null }
    [pscustomobject]@{ Id = $id; Label = $f.Label; Admin = $f.Admin }
}
# Long repairs run in the background; output from sfc/chkdsk/DISM is UTF-16, so stray NULs are removed.
$RepairWork = {
    param($what)
    $lastLines = { param($text) (($text -replace "`0", '') -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\d+(\.\d+)?\s*%|^\[=*\s*\d' } | Select-Object -Last 3) -join ' / ' }
    switch ($what) {
        'sfc' {
            Set-JobProgress 'checking system files (sfc)'
            $a = Invoke-Native "$env:windir\System32\sfc.exe" '/scannow' 3600
            if ($a.Cancelled) { return [pscustomobject]@{ Ok = $false; Msg = 'stopped' } }
            Set-JobProgress 'repairing the Windows image (DISM)'
            $b = Invoke-Native "$env:windir\System32\Dism.exe" '/Online /Cleanup-Image /RestoreHealth' 3600
            [pscustomobject]@{ Ok = ($a.Code -eq 0 -and $b.Code -eq 0); Msg = "sfc: $(& $lastLines $a.Out)`r`nDISM: $(& $lastLines $b.Out)" }
        }
        'chkdsk' {
            $r = Invoke-Native "$env:windir\System32\chkdsk.exe" 'C: /scan' 3600
            [pscustomobject]@{ Ok = ($r.Code -eq 0); Msg = (& $lastLines $r.Out) }
        }
        'wureset' {
            # The standard Windows Update reset: stop its services, set its caches aside (renamed, not deleted), start again.
            $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc'
            $log = @()
            foreach ($s in $svcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
            foreach ($d in "$env:windir\SoftwareDistribution", "$env:windir\System32\catroot2") {
                if (-not (Test-Path $d)) { continue }
                try { Rename-Item -LiteralPath $d -NewName "$(Split-Path $d -Leaf).bak-$stamp" -ErrorAction Stop; $log += "$(Split-Path $d -Leaf) set aside" }
                catch { $log += "$(Split-Path $d -Leaf) in use - left as it was" }
            }
            foreach ($s in $svcs) { Start-Service -Name $s -ErrorAction SilentlyContinue }
            [pscustomobject]@{ Ok = $true; Msg = ($log -join '; ') }
        }
        'vcredist' {
            $wg = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
            if (-not $wg) { return [pscustomobject]@{ Ok = $false; Msg = 'winget is missing' } }
            $out = foreach ($id in 'Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86') {
                Set-JobProgress $id
                $r = Invoke-Native $wg "install --id $id --exact --force --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" 900
                "$id`: $(if ($r.Code -eq 0) { 'repaired' } else { "exit code $($r.Code)" })"
            }
            [pscustomobject]@{ Ok = -not ($out -match 'exit code'); Msg = ($out -join '; ') }
        }
        'nviewgone' {
            $entry = foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
                Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -match 'RTX Desktop Manager|nView' } }
            $entry = @($entry)[0]
            if (-not $entry) { return [pscustomobject]@{ Ok = $false; Msg = 'nView is not installed any more' } }
            $p = Start-Process cmd.exe -ArgumentList "/c `"$($entry.UninstallString)`"" -Wait -PassThru -WindowStyle Hidden
            [pscustomobject]@{ Ok = ($p.ExitCode -eq 0); Msg = "$($entry.DisplayName): exit code $($p.ExitCode)" }
        }
    }
}
function Invoke-StabilityFix {
    if (-not $lvStab.SelectedItems.Count) { return }
    $row = $lvStab.SelectedItems[0].Tag
    $fix = Get-StabilityFix $row
    if (-not $fix) { return }
    if ($fix.Admin -and -not $IsAdmin) { Show-Msg "$($fix.Label) needs administrator rights - click ""Restart as admin"" first." 'OK' 'Warning' | Out-Null; return }
    switch ($fix.Id) {
        'drivers'   { Show-Page $pgDrv; return }
        'store'     { Start-Process 'ms-windows-store://downloadsandupdates'; return }
        'appupdate' { Show-Page $pgUpd; return }
        'wuhistory' { Start-Process 'ms-settings:windowsupdate-history'; return }
        'memtest'   {
            if ((Show-Msg 'Windows Memory Diagnostic checks the memory while the PC restarts (about 10-20 minutes). It asks whether to restart now or next time.' 'OKCancel' 'Information') -eq 'OK') {
                Start-Process mdsched.exe; Add-History 'Repair' 'Memory test' 'scheduled with Windows Memory Diagnostic'; Update-History
            }
            return
        }
        'nview' {
            if ((Show-Msg "Turn off NVIDIA nView?`n`nIt stops its start-up task and closes it. The graphics driver and NVIDIA Control Panel keep working. You can undo this from the History page." 'YesNo' 'Question') -ne 'Yes') { return }
            $done = 0
            foreach ($t in @(Get-ScheduledTask -TaskName 'nWizard*' -ErrorAction SilentlyContinue | Where-Object State -ne 'Disabled')) {
                try { [void](Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop); $done++
                      Add-History 'Task' $t.TaskName 'disabled (stops NVIDIA nView crashing other programs)' @{ Type = 'Task'; Path = $t.TaskPath; Name = $t.TaskName; Enable = $true } } catch { }
            }
            Get-Process -Name 'nview*', 'nwiz*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Show-Msg "NVIDIA nView is switched off$(if (-not $done) { ' (its start-up task was already off; running parts were closed)' }). If programs still crash in it, uninstall ""NVIDIA RTX Desktop Manager"" in Settings > Apps." | Out-Null
            Update-History; Update-Stability; return
        }
    }
    # The rest are longer repairs that run in the background.
    $ask = @{
        nviewgone = "Uninstall NVIDIA RTX Desktop Manager (nView)?`n`nThe graphics driver stays. NVIDIA's uninstaller may show its own window."
        vcredist  = "Repair the Microsoft Visual C++ runtimes (64- and 32-bit)?`n`nThey are reinstalled through winget; programs that use them keep working. Takes a minute or two."
        wureset   = "Reset Windows Update?`n`nIts services are stopped, its download caches are set aside (renamed, not deleted) and it starts fresh. Afterwards, open Windows Update and check for updates again."
        sfc       = "Repair Windows system files?`n`nRuns sfc /scannow and then DISM, which can take 15-30 minutes. You can keep using the PC (and press Cancel)."
        chkdsk    = "Check drive C: for errors?`n`nAn online check (chkdsk /scan) - you can keep working. If it finds a problem that needs fixing, Windows repairs it at the next restart."
    }
    if ((Show-Msg $ask[$fix.Id] 'YesNo' 'Question') -ne 'Yes') { return }
    $script:RepairFix = $fix
    $run = { Start-Bg -Label $script:RepairFix.Label -Cancellable $RepairWork $script:RepairFix.Id {
        param($r, $state)
        $r = $r[0]
        $msg = if ($state.Cancel) { 'stopped' } elseif ($r.Ok) { "done - $($r.Msg)" } else { "problem - $($r.Msg)" }
        Add-History 'Repair' $script:RepairFix.Label $msg
        Update-History
        Show-Msg "$($script:RepairFix.Label): $msg" | Out-Null
        if ($script:RepairFix.Id -eq 'wureset') { Start-Process 'ms-settings:windowsupdate' }
        Update-Stability
    } }
    if ($fix.Id -in 'wureset', 'sfc') { Start-WithRestorePoint $fix.Label $run } else { & $run }
}
$btnStabRel.Add_Click({ Start-Process perfmon.exe '/rel' })
$btnStabWeb.Add_Click({
    $row = Get-PickedRow $lvStab; if (-not $row) { return }
    $q = if ($row.Search) { $row.Search } else { "Windows $($row.Problem) $($row.What)" }
    Start-Process ('https://www.bing.com/search?q=' + [uri]::EscapeDataString($q))
})

# ===========================================================================
# Tasks: scheduled tasks from other companies - updaters, telemetry and helpers on a timer
# ===========================================================================
$pgTasks = New-Page 'Tasks' 'Scheduled tasks from other companies: updaters, telemetry and helpers that Windows runs on a timer or at sign-in - the last place bloatware hides. Known junk is listed first and pre-checked. Switching a task off can be undone from History.'
$btnTaskOff = New-Button 'Turn off checked'
$btnTaskOn = New-Button 'Turn on checked'
$btnTaskScan = New-Button 'Reload'
$btnTaskOpen = New-Button 'Open Task Scheduler'
$lvTasks = New-ListView $true @('Task', 270, 'Made by', 170, 'Runs', 150, 'State', 80, 'Advice', 420)
$lblTasks = New-Status
Set-PageLayout $pgTasks $lvTasks @((New-ButtonBar @($btnTaskOff, $btnTaskOn, $btnTaskScan, $btnTaskOpen))) $lblTasks
# Matched against task name, folder and author. Checked before the keep rules (like services).
$TaskCatalog = @(
    @{ Match = 'nWizard|nView';                                                           Why = 'NVIDIA nView launcher - crashes other programs' }
    @{ Match = 'NvTmRep|NvProfileUpdater|NvNodeLauncher|NvDriverUpdateCheck|GeForce Experience SelfUpdate'; Why = 'NVIDIA telemetry / updater' }
    @{ Match = 'AdobeGCInvoker|Adobe-Genuine-Software-Integrity|AdobeGenuine';              Why = 'Adobe licence checker' }
    @{ Match = 'Adobe Acrobat Update Task|AdobeAAMUpdater';                                Why = 'Adobe updater (Acrobat still updates when opened)' }
    @{ Match = 'Launch Adobe CCXProcess';                                                  Why = 'Adobe Creative Cloud helper - only needed if you use Creative Cloud' }
    @{ Match = 'GoogleUpdateTask|GoogleUpdater';                                           Why = 'Google updater (Chrome still updates when open)' }
    @{ Match = 'PlatformExperienceHelper|GoogleUserPEH';                                   Why = 'Google promotions helper' }
    @{ Match = 'MicrosoftEdgeUpdateTask';                                                  Why = 'Edge updater (Edge still updates when open)' }
    @{ Match = 'BraveSoftwareUpdate|Opera scheduled Autoupdate|Opera GX scheduled';        Why = 'browser updater (updates when the browser is open)' }
    @{ Match = 'Firefox Default Browser Agent';                                            Why = 'Firefox usage reporting' }
    @{ Match = 'ZoomUpdateTask';                                                           Why = 'Zoom updater (Zoom updates itself when opened)' }
    @{ Match = 'SupportAssist|DellTechHub|Dell(?!.*Peripheral).*(Update|Optimizer|Digital|Customer)'; Why = 'Dell support / telemetry tool' }
    @{ Match = 'HP (Customer Participation|Support Assistant|JumpStart|Touchpoint|Notifications)|HPCEE|HPAudioSwitch'; Why = 'HP support / telemetry tool' }
    @{ Match = 'Lenovo.*(UDC|Vantage|Now|Welcome)';                                        Why = 'Lenovo helper / telemetry' }
    @{ Match = 'ASUS.*(Update|LiveUpdate|GiftBox)|AsusUpdateCheck';                        Why = 'ASUS updater' }
    @{ Match = 'Acer.*(Jumpstart|Collection|Portal|Registration)';                         Why = 'Acer promo / registration' }
    @{ Match = 'Intel.*(Telemetry|SUR|ESRV)|USER_ESRV_SVC';                                Why = 'Intel telemetry' }
    @{ Match = 'CCleaner|Avast|AVG|McAfee|Norton|WildTangent|Driver Booster|OneLaunch|Wave Browser'; Why = 'cleaner / trial / adware helper' }
    @{ Match = 'SoftLanding';                                                              Why = 'Windows tips and promotional notifications' }
)
$TaskLikely = 'Update|Updater|Telemetry|Metrics|Report|Analytics|Promo|Notif|Survey'
$TaskScanWork = {
    param($cfg)
    $when = @{ MSFT_TaskLogonTrigger = 'at sign-in'; MSFT_TaskBootTrigger = 'at start-up'; MSFT_TaskDailyTrigger = 'daily'; MSFT_TaskWeeklyTrigger = 'weekly'
               MSFT_TaskIdleTrigger = 'when idle'; MSFT_TaskSessionStateChangeTrigger = 'on unlock'; MSFT_TaskEventTrigger = 'on a Windows event'; MSFT_TaskRegistrationTrigger = 'when installed' }
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $soft = $t.TaskName -like 'SoftLanding*' -or $t.TaskPath -like '\SoftLanding\*'
        if ($t.TaskPath -like '\Microsoft\*' -and -not $soft) { continue }   # Windows' own
        if ($t.TaskName -like 'PC Tune-Up*') { continue }                   # our own automatic maintenance
        $text = "$($t.TaskPath)$($t.TaskName) | $($t.Author)"
        $exe = [Environment]::ExpandEnvironmentVariables("$(@($t.Actions)[0].Execute)".Trim('"'))
        $company = if ($exe -and (Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue)) { try { [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).CompanyName } catch { '' } } else { '' }
        $maker = if ($t.Author -and $t.Author -notmatch '\\') { "$($t.Author)" } elseif ($company) { $company } elseif ($soft) { 'Microsoft (Windows)' } else { '' }
        $known = $cfg.Catalog | Where-Object { $text -match $_.Match } | Select-Object -First 1
        if (-not $known -and $cfg.UserKeep -and "$text $company" -match $cfg.UserKeep) { continue }
        if (-not $known -and "$text $company" -match $cfg.Keep) { continue }
        $kind = if ($known) { 'known' } elseif ($t.TaskName -match $cfg.Likely) { 'likely' } else { 'review' }
        $why = if ($known) { $known.Why } elseif ($kind -eq 'likely') { 'looks like an updater or telemetry - usually safe to turn off' } else { 'review: only turn off if you know what it is' }
        $runs = (@($t.Triggers | Where-Object { $_ } | ForEach-Object { $c = "$($_.CimClass.CimClassName)"; if ($c -eq 'MSFT_TaskTimeTrigger') { if ($_.Repetition.Interval) { 'repeatedly' } else { 'once' } } elseif ($c -and $when[$c]) { $when[$c] } else { 'on a schedule' } } | Select-Object -Unique))
        [pscustomobject]@{ Name = $t.TaskName; Path = $t.TaskPath; Maker = $maker; Runs = $(if ($runs) { $runs } else { , @('only when started') })
                           State = "$($t.State)"; Kind = $kind; Why = $why }
    }
}
$TaskOrder = @{ known = 0; likely = 1; review = 2 }
function Update-Tasks {
    $btnTaskScan.Enabled = $false
    $lblTasks.Text = 'Reading scheduled tasks...'
    Start-Bg -Label 'Reading scheduled tasks' $TaskScanWork @{ Catalog = $TaskCatalog; Likely = $TaskLikely; Keep = $KeepBuiltIn; UserKeep = (Get-UserKeep) } {
        param($rows)
        $btnTaskScan.Enabled = $true
        $lvTasks.BeginUpdate(); $lvTasks.Items.Clear()
        foreach ($r in $rows | Sort-Object { $TaskOrder[$_.Kind] }, { $_.State -eq 'Disabled' }, Name) {
            $it = Add-Row $lvTasks @($r.Name, $r.Maker, ((@($r.Runs) | ForEach-Object { T $_ }) -join ', '), $(if ($r.State -eq 'Disabled') { 'Off' } else { 'On' }), $r.Why) $r ($r.Kind -eq 'known' -and $r.State -ne 'Disabled')
            $it.ForeColor = if ($r.State -eq 'Disabled') { $Theme.Muted } elseif ($r.Kind -eq 'known') { $Theme.Bad } elseif ($r.Kind -eq 'review') { $Theme.Muted } else { $Theme.Text }
        }
        $lvTasks.EndUpdate()
        $active = @($rows | Where-Object { $_.Kind -eq 'known' -and $_.State -ne 'Disabled' }).Count
        $lblTasks.Text = if ($active) { "$active known junk task(s) are switched on and pre-checked. Grey rows are already off." } else { 'No known junk tasks are running. Grey rows are already off.' }
        $script:TasksActive = $active
        if ($script:NavButtons) { Update-NavBadges }
    }
}
# "Do this to these N things?" with the names listed (at most 12), for buttons that act on the checked rows.
function Confirm-Checked([string]$Question, [string[]]$Names, [string]$After) {
    $list = @($Names | Select-Object -First 12 | ForEach-Object { " - $_" })
    if ($Names.Count -gt 12) { $list += (T '...and {0} more').Replace('{0}', "$($Names.Count - 12)") }
    $q = (T $Question).Replace('{0}', "$($Names.Count)")
    (Show-Msg ("$q`n`n" + ($list -join "`n") + "`n`n" + (T $After)) 'YesNo' 'Question') -eq 'Yes'
}
# -Ask: the button asks first (the simple view asks its own, plainer question before calling this).
function Set-Tasks([bool]$Enable, [switch]$Ask) {
    $picked = @($lvTasks.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { ($_.State -eq 'Disabled') -eq $Enable })
    if (-not $picked) { Show-Msg $(if ($Enable) { 'Check one or more tasks that are off first.' } else { 'Check one or more tasks that are on first.' }) | Out-Null; return }
    if ($Ask -and -not (Confirm-Checked 'Switch off these {0} scheduled task(s)?' @($picked | ForEach-Object { $_.Name }) 'The programs themselves keep working. You can undo this on the History page.')) { return }
    $done = 0; $denied = @()
    foreach ($t in $picked) {
        try {
            if ($Enable) { [void](Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop) }
            else { [void](Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop) }
            Add-History 'Task' $t.Name $(if ($Enable) { 'switched on' } else { 'switched off' }) @{ Type = 'Task'; Path = $t.Path; Name = $t.Name; Enable = (-not $Enable) }
            $done++
        } catch { $denied += $t.Name }
    }
    Update-History; Update-Tasks
    $msg = "$done task(s) switched $(if ($Enable) { 'on' } else { 'off' }). Undo from the History page."
    if ($denied) { $msg += "`n`nThese need administrator rights (click ""Restart as admin""): $($denied -join ', ')" }
    Show-Msg $msg | Out-Null
}
$btnTaskOff.Add_Click({ Set-Tasks $false -Ask })
$btnTaskOn.Add_Click({ Set-Tasks $true })
$btnTaskScan.Add_Click({ Update-Tasks })
$btnTaskOpen.Add_Click({ Start-Process taskschd.msc })

# ===========================================================================
# Backup: would the files survive a broken, lost or stolen PC?
# ===========================================================================
$pgBackup = New-Page 'Backup' 'Would your files survive a broken, lost or stolen PC? Checks your cloud folders, File History, backup programs and restore points. Double-click a row (or select it and click Open setting) to change it.'
$btnBkOpen = New-Button 'Open setting'
$btnBkScan = New-Button 'Check again'
$btnBkRp = New-Button 'Create restore point now'
if (-not $IsAdmin) { $btnBkRp.Enabled = $false }
$lvBackup = New-ListView $false @('Check', 220, 'Status', 80, 'Result', 380, 'What to do', 560)
$txtBackup = New-DetailBox 104
Set-PageLayout $pgBackup $lvBackup @((New-ButtonBar @($btnBkOpen, $btnBkScan, $btnBkRp))) $txtBackup
$lblBackup = New-Status; $pgBackup.Controls.Add($lblBackup)
$BackupWork = {
    param($admin)
    $rows = New-Object System.Collections.ArrayList
    function Add-Bk($Check, $Level, $Result, $Todo, $Link) { [void]$rows.Add([pscustomobject]@{ Check = $Check; Level = $Level; Result = $Result; Todo = $Todo; Link = $Link }) }
    # Cloud folders that keep a copy of what's inside them
    $roots = @()
    foreach ($a in Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $a.PSPath -ErrorAction SilentlyContinue
        if ($p.UserFolder) { $roots += [pscustomobject]@{ Name = $(if ($a.PSChildName -eq 'Personal') { 'OneDrive' } else { Split-Path $p.UserFolder -Leaf }); Path = $p.UserFolder } }
    }
    $dbx = Join-Path $env:LOCALAPPDATA 'Dropbox\info.json'
    if (Test-Path $dbx) { try { (Get-Content $dbx -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { if ($_.Value.path) { $roots += [pscustomobject]@{ Name = 'Dropbox'; Path = $_.Value.path } } } } catch { } }
    $icloud = Join-Path $env:USERPROFILE 'iCloudDrive'
    if (Test-Path $icloud) { $roots += [pscustomobject]@{ Name = 'iCloud Drive'; Path = $icloud } }
    $usf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    $folders = [ordered]@{ Desktop = $usf.Desktop; Documents = $usf.Personal; Pictures = $usf.'My Pictures' }
    $covered = @(); $missing = @(); $where = @()
    foreach ($k in $folders.Keys) {
        $path = [Environment]::ExpandEnvironmentVariables("$($folders[$k])")
        $root = $roots | Where-Object { $path -and $path.StartsWith($_.Path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if ($root) { $covered += $k; $where += $root.Name } else { $missing += $k }
    }
    $cloud = ($where | Select-Object -Unique) -join ', '
    if (-not $missing) { Add-Bk 'Desktop, Documents and Pictures' 'OK' "Backed up to $cloud" 'Nothing to do - every change is copied to the cloud.' 'ms-settings:backup' }
    elseif ($covered) { Add-Bk 'Desktop, Documents and Pictures' 'Warning' "$($covered -join ', ') backed up to $cloud; not: $($missing -join ', ')" 'Add the missing folders: OneDrive settings > Sync and back up > Manage back up (or Settings > Accounts > Windows backup).' 'ms-settings:backup' }
    else { Add-Bk 'Desktop, Documents and Pictures' 'Problem' 'Not in any cloud folder' 'If the PC breaks or is stolen, these files are gone. Turn on folder backup: Settings > Accounts > Windows backup (OneDrive), or use File History with an external drive.' 'ms-settings:backup' }
    if ($roots | Where-Object Name -like 'OneDrive*') {
        if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { Add-Bk 'OneDrive running' 'OK' 'Yes - changes are uploaded' 'Nothing to do.' $null }
        else { Add-Bk 'OneDrive running' 'Warning' 'No - changes are not being uploaded' 'Start OneDrive (it is in the Start menu) and let it sign in; check that it starts with Windows on the Startup page.' 'start-onedrive' }
    }
    # File History: a second copy on an external drive or network share
    if (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FileHistory\Configuration\Config1.xml')) { Add-Bk 'File History' 'OK' 'On' 'Keep the backup drive connected now and then.' 'control.exe /name Microsoft.FileHistory' }
    else { Add-Bk 'File History' 'Info' 'Off' 'Optional extra copy (also of older versions) on an external drive: Control Panel > File History.' 'control.exe /name Microsoft.FileHistory' }
    # Backup programs
    $progs = foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall') {
        Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { "$((Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName)" } |
            Where-Object { $_ -match 'Acronis|Macrium|Veeam|Backblaze|IDrive|Carbonite|CrashPlan|EaseUS Todo Backup|AOMEI Backupper|Duplicati|Cobian|Synology (Active Backup|Drive)|Google Drive|Paragon Backup|Arq' } }
    $progs = @($progs | Select-Object -Unique)
    if ($progs) { Add-Bk 'Backup program' 'OK' "Found: $(($progs | Select-Object -First 3) -join ', ')" 'Check now and then that it still runs and that you can restore a file.' $null }
    else { Add-Bk 'Backup program' 'Info' 'None found' 'Optional: a backup program (Macrium Reflect and Veeam Agent have free versions) makes a full copy of the PC, including programs and settings.' $null }
    # Restore points (Windows only shows them to administrators)
    if ($admin) {
        $rp = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        if ($rp) {
            $last = ($rp | ForEach-Object { $_.ConvertToDateTime($_.CreationTime) } | Measure-Object -Maximum).Maximum
            $days = [int]((Get-Date) - $last).TotalDays
            Add-Bk 'Restore points' $(if ($days -le 30) { 'OK' } else { 'Warning' }) "$($rp.Count) restore point(s), the latest $days day(s) ago" `
                $(if ($days -le 30) { 'Nothing to do.' } else { 'Create one now (button above) - they let you undo a bad driver or update.' }) 'SystemPropertiesProtection.exe'
        } else { Add-Bk 'Restore points' 'Warning' 'None found - System Protection may be off' 'Switch on System Protection for C: (System Properties > System Protection > Configure), then create one.' 'SystemPropertiesProtection.exe' }
    } else { Add-Bk 'Restore points' 'Info' 'Only visible as administrator' 'Click "Restart as admin" to check them.' 'SystemPropertiesProtection.exe' }
    $none = -not $covered -and -not (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FileHistory\Configuration\Config1.xml')) -and -not $progs
    [pscustomobject]@{ Rows = $rows; NoBackup = $none; Cloud = $cloud }
}
function Update-Backup {
    $btnBkScan.Enabled = $false
    $lblBackup.Text = 'Checking backups...'
    Start-Bg -Label 'Checking backups' $BackupWork $IsAdmin {
        param($r)
        $btnBkScan.Enabled = $true
        $r = $r[0]
        $lvBackup.BeginUpdate(); $lvBackup.Items.Clear()
        foreach ($b in $r.Rows | Sort-Object { $SecLevels[$_.Level] }) {
            $it = Add-Row $lvBackup @($b.Check, $b.Level, $b.Result, $b.Todo) $b
            Set-RowStatus $it 1 $(switch ($b.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.Muted } })
        }
        $lvBackup.EndUpdate()
        $lblBackup.Text = if ($r.NoBackup) { 'Nothing is backing up your files.' } elseif ($r.Cloud) { "Your files are backed up to $($r.Cloud)." } else { 'Some backup is in place - see the rows above.' }
        if ($r.NoBackup) { $script:ExtraAdvice['Backup'] = 'Backup: nothing backs up your files - see the Backup page.' } else { $script:ExtraAdvice.Remove('Backup') }
        $script:BackupProblems = @($r.Rows | Where-Object { $_.Level -in 'Problem', 'Warning' }).Count
        if ($lvBackup.Items.Count) { $lvBackup.Items[0].Selected = $true }
        Update-Health -Quick
    }
}
function Open-BackupSetting {
    $row = Get-PickedRow $lvBackup; if (-not $row) { return }
    $link = $row.Link
    if (-not $link) { Show-Msg 'There is no setting to open for this row - see "What to do" below the list.' | Out-Null; return }
    try {
        if ($link -eq 'start-onedrive') {
            $od = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($od) { Start-Process $od } else { Show-Msg 'OneDrive was not found.' | Out-Null }
        } elseif ($link -match '^control\.exe (.*)$') { Start-Process control.exe $Matches[1] }
        else { Start-Process $link }
    } catch { Show-Msg "Couldn't open $link" | Out-Null }
}
$lvBackup.Add_SelectedIndexChanged({
    if (-not $lvBackup.SelectedItems.Count) { return }
    $b = $lvBackup.SelectedItems[0].Tag
    $txtBackup.Text = "$($b.Check): $($b.Result)`r`n`r`nWhat to do: $($b.Todo)"
    $btnBkOpen.Enabled = [bool]$b.Link
})
$lvBackup.Add_DoubleClick({ Open-BackupSetting })
$btnBkOpen.Add_Click({ Open-BackupSetting })
$btnBkScan.Add_Click({ Update-Backup })
$btnBkRp.Add_Click({
    $btnBkRp.Enabled = $false
    Start-Bg -Label 'Creating a restore point' { try { Checkpoint-Computer -Description 'PC Tune-Up' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable w -WarningAction SilentlyContinue; if ($w) { "skipped: $($w[0])" } else { 'ok' } } catch { $_.Exception.Message } } $null {
        param($r)
        $btnBkRp.Enabled = $true
        if ("$($r[0])" -eq 'ok') { Add-History 'Restore point' 'C:' 'created'; Update-History; Show-Msg 'Restore point created.' | Out-Null }
        else { Show-Msg "No restore point made: $($r[0])" 'OK' 'Warning' | Out-Null }
        Update-Backup
    }
})

# ===========================================================================
# Privacy: Windows' ads, tips and tracking settings, switched off with undo
# ===========================================================================
$pgPriv = New-Page 'Privacy' 'Ads, tips and tracking that Windows switches on by default. Recommended ones are pre-checked. Turning a setting off only changes your own Windows settings (nothing is uninstalled) and can be undone from History or with "Turn back on".'
$btnPrivOff = New-Button 'Turn off checked'
$btnPrivOn = New-Button 'Turn back on checked'
$btnPrivReload = New-Button 'Reload'
$btnPrivOpen = New-Button 'Open privacy settings'
$lvPriv = New-ListView $true @('Setting', 300, 'State', 90, 'What it does', 560, 'Note', 170)
$lblPriv = New-Status
Set-PageLayout $pgPriv $lvPriv @((New-ButtonBar @($btnPrivOff, $btnPrivOn, $btnPrivReload, $btnPrivOpen))) $lblPriv
# Each setting is one or more registry values. Off = the private value; On = Windows' own value (absent: remove ours).
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$PrivacyCatalog = @(
    @{ Name = 'Advertising ID'; Rec = $true; Why = 'Lets apps show ads based on what you do.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; N = 'Enabled'; Off = 0 }) }
    @{ Name = 'Tailored experiences'; Rec = $true; Why = 'Microsoft uses your diagnostic data for personal tips, ads and recommendations.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; N = 'TailoredExperiencesWithDiagnosticDataEnabled'; Off = 0 }) }
    @{ Name = 'Tips and suggestions notifications'; Rec = $true; Why = 'Pop-ups with tips and offers while you use Windows.'
       V = @(@{ P = $cdm; N = 'SubscribedContent-338389Enabled'; Off = 0 }) }
    @{ Name = 'Suggested content in Settings'; Rec = $true; Why = 'Suggestions and offers inside the Settings app.'
       V = @(@{ P = $cdm; N = 'SubscribedContent-338393Enabled'; Off = 0 }, @{ P = $cdm; N = 'SubscribedContent-353694Enabled'; Off = 0 }, @{ P = $cdm; N = 'SubscribedContent-353696Enabled'; Off = 0 }) }
    @{ Name = '"Finish setting up" and welcome screens'; Rec = $true; Why = 'Full-screen pages after updates that push Microsoft 365, OneDrive and Game Pass.'
       V = @(@{ P = $cdm; N = 'SubscribedContent-310093Enabled'; Off = 0 }, @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; N = 'ScoobeSystemSettingEnabled'; Off = 0 }) }
    @{ Name = 'Promoted apps installed without asking'; Rec = $true; Why = 'Windows quietly installs suggested apps and games on the Start menu.'
       V = @(@{ P = $cdm; N = 'SilentInstalledAppsEnabled'; Off = 0 }, @{ P = $cdm; N = 'PreInstalledAppsEnabled'; Off = 0 }, @{ P = $cdm; N = 'OemPreInstalledAppsEnabled'; Off = 0 }) }
    @{ Name = 'Recommendations and ads in Start'; Rec = $true; Explorer = $true; Why = 'Suggested apps, tips and promotions in the Start menu.'
       V = @(@{ P = $cdm; N = 'SystemPaneSuggestionsEnabled'; Off = 0 }, @{ P = $cdm; N = 'SubscribedContent-338388Enabled'; Off = 0 }, @{ P = $adv; N = 'Start_IrisRecommendations'; Off = 0 }) }
    @{ Name = 'Account notifications in Start'; Rec = $true; Explorer = $true; Why = 'Microsoft account and backup reminders on your picture in the Start menu.'
       V = @(@{ P = $adv; N = 'Start_AccountNotifications'; Off = 0 }) }
    @{ Name = 'Fun facts and tips on the lock screen'; Rec = $true; Why = 'Text and promotions on top of the lock-screen picture.'
       V = @(@{ P = $cdm; N = 'RotatingLockScreenOverlayEnabled'; Off = 0 }, @{ P = $cdm; N = 'SubscribedContent-338387Enabled'; Off = 0 }) }
    @{ Name = 'Search highlights'; Rec = $true; Explorer = $true; Why = 'Trending news and pictures in the search box and search window.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; N = 'IsDynamicSearchBoxEnabled'; Off = 0 }) }
    @{ Name = 'Web results in Start search'; Rec = $true; Explorer = $true; Why = 'What you type in Start search is also sent to Bing. As administrator the Windows policy is set too, which newer Windows versions need.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'BingSearchEnabled'; Off = 0 })
       AdminV = @(@{ P = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; N = 'DisableSearchBoxSuggestions'; Off = 1 }) }
    @{ Name = 'Feedback requests'; Rec = $true; Why = 'Windows asks now and then what you think of it.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\Siuf\Rules'; N = 'NumberOfSIUFInPeriod'; Off = 0 }) }
    @{ Name = 'Inking and typing personalisation'; Rec = $true; Why = 'What you type and write by hand is collected into a personal dictionary.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\InputPersonalization'; N = 'RestrictImplicitInkCollection'; Off = 1 }, @{ P = 'HKCU:\Software\Microsoft\InputPersonalization'; N = 'RestrictImplicitTextCollection'; Off = 1 },
             @{ P = 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; N = 'HarvestContacts'; Off = 0 }) }
    @{ Name = 'Optional diagnostic data'; Rec = $true; Admin = $true; Why = 'Extra data about the websites you visit and how you use apps, sent to Microsoft. The required basic data stays on.'
       V = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; N = 'AllowTelemetry'; Off = 1 }) }
    @{ Name = 'Activity history'; Rec = $true; Admin = $true; Why = 'Windows keeps a history of the apps, files and websites you used.'
       V = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; N = 'PublishUserActivities'; Off = 0 }, @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; N = 'UploadUserActivities'; Off = 0 }) }
    @{ Name = 'Recall snapshots'; Rec = $true; Admin = $true; Only = 'Recall'; Why = 'Recall saves pictures of everything on your screen every few seconds, to search later.'
       V = @(@{ P = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; N = 'DisableAIDataAnalysis'; Off = 1 }) }
    @{ Name = 'Location for apps'; Rec = $false; Why = 'Apps such as Maps and Weather can see where you are. Only turn off if you don''t need that.'
       V = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; N = 'Value'; Off = 'Deny'; On = 'Allow'; T = 'String' }) }
)
$HasRecall = Test-Path "$env:windir\SystemApps\MicrosoftWindows.Client.AIX_cw5n1h2txyewy"
function Get-RegValue([string]$Path, [string]$Name) {
    $k = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($k -and $Name -in $k.GetValueNames()) { $k.GetValue($Name) } else { $null }
}
function Set-RegValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if ($null -eq $Value) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue; return }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}
function Get-PrivacyState($Item) {
    $off = @($Item.V | Where-Object { "$(Get-RegValue $_.P $_.N)" -eq "$($_.Off)" }).Count
    if ($off -eq @($Item.V).Count) { 'Off' } elseif ($off) { 'Partly on' } else { 'On' }
}
function Update-Privacy {
    $lvPriv.BeginUpdate(); $lvPriv.Items.Clear()
    $on = 0
    foreach ($p in $PrivacyCatalog) {
        if ($p.Only -eq 'Recall' -and -not $HasRecall) { continue }
        $state = Get-PrivacyState $p
        $locked = $p.Admin -and -not $IsAdmin
        $note = @($(if ($locked) { 'needs administrator' }), $(if ($p.Explorer) { 'restarts Explorer' }) | Where-Object { $_ }) -join ', '
        $it = Add-Row $lvPriv @($p.Name, $state, $p.Why, $note) $p ($p.Rec -and $state -ne 'Off' -and -not $locked)
        $it.ForeColor = if ($state -eq 'Off' -or $locked) { $Theme.Muted } else { $Theme.Text }
        if ($p.Rec -and $state -ne 'Off') { $on++ }
    }
    $lvPriv.EndUpdate()
    $script:PrivacyOn = $on
    $lblPriv.Text = if ($on) { "$on recommended setting(s) are still on. Grey rows are already off." } else { 'All recommended settings are off.' }
    if ($script:NavButtons) { Update-NavBadges }
}
function Set-Privacy([bool]$Off, [switch]$Ask) {
    $picked = @($lvPriv.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $picked) { Show-Msg 'Check one or more settings first.' | Out-Null; return }
    if ($Ask -and -not (Confirm-Checked 'Turn off these {0} Windows setting(s)?' @($picked | ForEach-Object { T $_.Name }) 'Your files and programs are not touched. You can undo this on the History page.')) { return }
    $locked = @($picked | Where-Object { $_.Admin -and -not $IsAdmin })
    $picked = @($picked | Where-Object { -not ($_.Admin -and -not $IsAdmin) })
    $done = 0; $failed = @(); $explorer = $false
    foreach ($p in $picked) {
        $vals = @($p.V) + $(if ($IsAdmin -and $p.AdminV) { @($p.AdminV) } else { @() })
        $undo = @()
        try {
            foreach ($v in $vals) {
                $type = if ($v.T) { $v.T } else { 'DWord' }
                $undo += @{ P = $v.P; N = $v.N; Old = (Get-RegValue $v.P $v.N); T = $type }
                Set-RegValue $v.P $v.N $(if ($Off) { $v.Off } else { $v.On }) $type
            }
            Add-History 'Privacy' $p.Name $(if ($Off) { 'turned off' } else { 'turned back on' }) @{ Type = 'Reg'; Values = $undo }
            $done++; if ($p.Explorer) { $explorer = $true }
        } catch {
            foreach ($u in $undo) { try { Set-RegValue $u.P $u.N $u.Old $u.T } catch { } }   # leave nothing half-done
            $failed += "$($p.Name): $($_.Exception.Message)"
        }
    }
    Update-History; Update-Privacy
    $msg = "$done setting(s) turned $(if ($Off) { 'off' } else { 'back on' }). Undo from the History page."
    if ($locked) { $msg += "`n`nThese need administrator rights (click ""Restart as admin""): $(($locked | ForEach-Object Name) -join ', ')" }
    if ($failed) { $msg += "`n`nCouldn't change: $($failed -join '; ')" }
    Show-Msg $msg | Out-Null
    if ($explorer -and -not $script:SimpleRun -and (Show-Msg "Restart Explorer now so the Start menu, search and taskbar pick up the change?`n`nOpen File Explorer windows close; nothing else is affected." 'YesNo' 'Question') -eq 'Yes') {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue   # Windows starts it again by itself
    }
}
$btnPrivOff.Add_Click({ Set-Privacy $true -Ask })
$btnPrivOn.Add_Click({ Set-Privacy $false })
$btnPrivReload.Add_Click({ Update-Privacy })
$btnPrivOpen.Add_Click({ Start-Process 'ms-settings:privacy' })

# ===========================================================================
# Drivers: devices with problems, and the drivers that matter most and how old they are
# ===========================================================================
$pgDrv = New-Page 'Drivers' 'Devices Windows reports a problem with, and the drivers that matter most (graphics, network, audio, storage, BIOS) with their age. Old drivers are a common cause of crashes, blue screens and battery drain.'
$btnDrvGet = New-Button 'Get driver updates'
$btnDrvWU = New-Button 'Optional updates in Windows Update'
$btnDrvDm = New-Button 'Open Device Manager'
$btnDrvWeb = New-Button 'Search selected online'
$btnDrvReload = New-Button 'Reload'
$lvDrv = New-ListView $false @('Device', 300, 'Kind', 110, 'Status', 80, 'Driver', 230, 'What to do', 520)
$txtDrv = New-DetailBox 104
Set-PageLayout $pgDrv $lvDrv @((New-ButtonBar @($btnDrvGet, $btnDrvWU, $btnDrvDm, $btnDrvWeb, $btnDrvReload))) $txtDrv
$DriverWork = {
    $rows = New-Object System.Collections.ArrayList
    $kinds = @{ DISPLAY = 'Graphics'; NET = 'Network'; MEDIA = 'Audio'; BLUETOOTH = 'Bluetooth'; HDC = 'Storage'; SCSIADAPTER = 'Storage'; CAMERA = 'Camera'
                IMAGE = 'Camera'; BIOMETRIC = 'Sign-in'; FIRMWARE = 'BIOS'; USB = 'USB'; SYSTEM = 'Chipset'; HIDCLASS = 'Input'; MOUSE = 'Touchpad/mouse'
                KEYBOARD = 'Keyboard'; PRINTER = 'Printer'; AUDIOENDPOINT = 'Audio'; SOFTWAREDEVICE = 'Software'; EXTENSION = 'Extension' }
    $kindOf = { param($c) $k = $kinds["$c".ToUpper()]; if ($k) { $k } elseif ($c) { "$c" } else { 'Other' } }
    $why = @{ 1 = 'is not set up correctly'; 3 = 'has a damaged driver'; 10 = 'cannot start'; 12 = 'lacks free resources'; 14 = 'needs a restart'
              18 = 'needs its driver reinstalled'; 19 = 'has damaged settings'; 28 = 'has no driver installed'; 31 = 'is not working properly'
              32 = 'has its driver switched off'; 37 = 'driver failed to load'; 39 = 'driver is missing or damaged'; 43 = 'was stopped by Windows because it reported problems'
              48 = 'driver is blocked'; 52 = 'driver is not signed' }
    $fixDefault = 'Update or reinstall the driver: Device Manager > right-click the device > Update driver. If that doesn''t help: Uninstall device, then Action > Scan for hardware changes.'
    $seen = @{}
    # 1. Devices with a problem (code 45 = not plugged in, normal; 22 = switched off on purpose)
    foreach ($d in Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 45' -OperationTimeoutSec 30 -ErrorAction SilentlyContinue) {
        $code = [int]$d.ConfigManagerErrorCode
        $name = if ($d.Name) { "$($d.Name)" } else { "$($d.DeviceID)" }
        $kind = & $kindOf $d.PNPClass
        $level = if ($code -in 22, 24, 47) { 'Info' } else { 'Problem' }
        $status = if ($why[$code]) { "Device $($why[$code]) (code $code)" } elseif ($code -eq 22) { 'Switched off in Device Manager (code 22)' } else { "Problem code $code" }
        $todo = switch ($code) {
            22 { 'Switched off on purpose? Then nothing to do. Otherwise: Device Manager > right-click > Enable device.' }
            28 { 'Install its driver: Windows Update > Advanced options > Optional updates, or the PC maker''s support page (button above).' }
            14 { 'Restart the PC.' }
            43 { if ($kind -eq 'USB' -or $name -match 'USB') { 'Unplug the USB device and plug it into a different port (not a hub), or try another cable. If nothing is plugged in, update the chipset and USB drivers from the PC maker.' } else { $fixDefault } }
            default { $fixDefault }
        }
        $seen[$name] = 1
        [void]$rows.Add([pscustomobject]@{ Device = $name; Kind = $kind; Level = $level; Driver = ''; Todo = $todo; Search = "$name code $code"; Detail = $status })
    }
    # 2. The drivers that matter most, with their age
    $virtual = 'TAP-|WireGuard|VPN|Virtual|Hyper-V|VMware|VirtualBox|Loopback|Tunnel|WAN Miniport|Npcap|Kernel Debug|Teredo|ISATAP|Bluetooth Device \(Personal'
    $wanted = 'DISPLAY|NET|MEDIA|BLUETOOTH|HDC|SCSIADAPTER|CAMERA|BIOMETRIC|FIRMWARE'
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver -OperationTimeoutSec 60 -ErrorAction SilentlyContinue | Where-Object { $_.DeviceName -and "$($_.DeviceClass)" -match "^($wanted)$" }) {
        $name = "$($d.DeviceName)"; $class = "$($d.DeviceClass)".ToUpper()
        if ($seen[$name] -or $name -match $virtual) { continue }
        if ($class -eq 'BLUETOOTH' -and $name -notmatch 'Wireless|Adapter|Radio|Intel|Realtek|Qualcomm|MediaTek|Broadcom') { continue }   # paired gadgets, not the adapter
        $maker = "$($d.DriverProviderName)"
        if ($class -ne 'DISPLAY' -and $maker -match '^Microsoft') { continue }   # Windows' own generic drivers
        $seen[$name] = 1
        $date = $d.DriverDate
        $years = if ($date -and $date.Year -ge 2000) { [Math]::Round(((Get-Date) - $date).TotalDays / 365.25, 1) } else { $null }   # Intel's chipset INFs are dated 1968 on purpose
        $kind = & $kindOf $class
        $driver = "$($d.DriverVersion)$(if ($years -ne $null) { ' (' + $date.ToString('d') + ')' })$(if ($maker) { ', ' + $maker })"
        $level = 'OK'; $todo = 'Nothing to do.'; $detail = 'Driver is recent enough'
        if ($class -eq 'DISPLAY' -and $name -match 'Microsoft Basic Display') {
            $level = 'Problem'; $detail = 'No proper graphics driver installed'
            $todo = 'Install the graphics driver from the PC maker''s support page or nvidia.com / amd.com / intel.com. Until then the screen is slow and games won''t run.'
        } elseif ($years -ne $null) {
            $limit = @{ DISPLAY = 1.5; FIRMWARE = 2.5; NET = 3 }[$class]; if (-not $limit) { $limit = 4 }
            if ($years -ge $limit) {
                $level = if ($class -eq 'DISPLAY') { 'Warning' } else { 'Info' }
                $detail = "Driver is $years years old"
                $todo = switch ($class) {
                    'DISPLAY'  { 'Update the graphics driver - from the PC maker''s support page for a laptop, otherwise from nvidia.com, amd.com or intel.com.' }
                    'FIRMWARE' { 'A BIOS update may be available. Get it only from the PC maker''s support page (button above), and keep the PC plugged in while it installs.' }
                    default    { 'A newer driver may be available from the PC maker''s support page or in Windows Update > Optional updates. Only needed if this device gives trouble.' }
                }
            }
        }
        [void]$rows.Add([pscustomobject]@{ Device = $name; Kind = $kind; Level = $level; Driver = $driver; Todo = $todo; Search = "$name driver"; Detail = $detail })
    }
    , $rows
}
$DrvLevels = @{ Problem = 0; Warning = 1; Info = 2; OK = 3 }
function Update-Drivers {
    $btnDrvReload.Enabled = $false
    $txtDrv.Text = 'Reading devices and drivers...'
    Start-Bg -Label 'Reading drivers' $DriverWork $null {
        param($r)
        $btnDrvReload.Enabled = $true
        $rows = @(foreach ($x in $r) { $x })
        $lvDrv.BeginUpdate(); $lvDrv.Items.Clear()
        foreach ($d in $rows | Sort-Object { $DrvLevels[$_.Level] }, Kind, Device) {
            $it = Add-Row $lvDrv @($d.Device, $d.Kind, $d.Level, $d.Driver, $d.Todo) $d
            Set-RowStatus $it 2 $(switch ($d.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Text } default { $Theme.Muted } })
        }
        $lvDrv.EndUpdate()
        $bad = @($rows | Where-Object Level -eq 'Problem').Count
        $script:DriverIssues = @($rows | Where-Object { $_.Level -in 'Problem', 'Warning' }).Count
        if ($bad) { $script:ExtraAdvice['Drivers'] = "Drivers: $bad device(s) have a problem - see the Drivers page." } else { $script:ExtraAdvice.Remove('Drivers') }
        if ($lvDrv.Items.Count) { $lvDrv.Items[0].Selected = $true } else { $txtDrv.Text = 'No devices found.' }
        Update-Health -Quick
    }
}
$lvDrv.Add_SelectedIndexChanged({
    if (-not $lvDrv.SelectedItems.Count) { return }
    $d = $lvDrv.SelectedItems[0].Tag
    $txtDrv.Text = "$($d.Device) ($($d.Kind)): $($d.Detail)$(if ($d.Driver) { ""`r`nDriver: $($d.Driver)"" })`r`n`r`nWhat to do: $($d.Todo)"
})
$btnDrvGet.Add_Click({
    # The PC maker's driver page knows this exact model; Windows Update is the fallback.
    if (-not $script:UpgInfo) { Invoke-PageLoader 'Upgrades' }
    $url = if ($script:UpgInfo) { $script:UpgInfo.Url }
    if ($url) { Start-Process ($url -replace '/overview$', '/drivers') } else { Start-Process 'ms-settings:windowsupdate-optionalupdates' }
})
$btnDrvWU.Add_Click({ Start-Process 'ms-settings:windowsupdate-optionalupdates' })
$btnDrvDm.Add_Click({ Start-Process devmgmt.msc })
$btnDrvWeb.Add_Click({
    $row = Get-PickedRow $lvDrv; if (-not $row) { return }
    Start-Process ('https://www.bing.com/search?q=' + [uri]::EscapeDataString("$($row.Search) $(if ($script:UpgInfo) { $script:UpgInfo.Name })"))
})
$btnDrvReload.Add_Click({ Update-Drivers })

# ===========================================================================
# Battery: how worn it is, how fast it wears, and how to make it last
# ===========================================================================
$PowerNow = [Windows.Forms.SystemInformation]::PowerStatus
$HasBattery = -not (([int]$PowerNow.BatteryChargeStatus -band 128) -or [int]$PowerNow.BatteryChargeStatus -eq 255)   # 128 = no battery
$pgBatt = New-Page 'Battery' 'How much charge the battery still holds, how fast it is wearing, and how to make it last longer. From Windows'' own battery report.'
$btnBattUsage = New-Button 'Battery usage per app'
$btnBattSet = New-Button 'Power & battery settings'; $btnBattSet.UseMnemonic = $false
$btnBattReport = New-Button 'Full battery report'
$btnBattBuy = New-Button 'Find a replacement'
$btnBattReload = New-Button 'Reload'
$chartBatt = New-Chart 170
$lvBatt = New-ListView $false @('Reading', 200, 'Value', 300, 'What it means', 560)
$lblBatt = New-Status
Set-PageLayout $pgBatt $lvBatt @((New-ButtonBar @($btnBattUsage, $btnBattSet, $btnBattReport, $btnBattBuy, $btnBattReload)), $chartBatt) $lblBatt
$BatteryWork = {
    $x = Join-Path $env:TEMP "pctuneup-battery-$([guid]::NewGuid().ToString('N')).xml"
    [void](Invoke-Native "$env:windir\System32\powercfg.exe" "/batteryreport /xml /output `"$x`"" 60)
    if (-not (Test-Path $x)) { return [pscustomobject]@{ Error = 'Windows could not make a battery report.' } }
    try { [xml]$b = [IO.File]::ReadAllText($x) } finally { Remove-Item $x -ErrorAction SilentlyContinue }
    $bats = @($b.BatteryReport.Batteries.Battery)
    $design = ($bats | ForEach-Object { [double]$_.DesignCapacity } | Measure-Object -Sum).Sum
    $full = ($bats | ForEach-Object { [double]$_.FullChargeCapacity } | Measure-Object -Sum).Sum
    $hist = @(foreach ($h in $b.BatteryReport.History.HistoryEntry) {
        $d = [double]$h.DesignCapacity; $f = [double]$h.FullChargeCapacity
        if ($d -gt 0 -and $f -gt 0) { [pscustomobject]@{ X = ([datetime]$h.StartDate).Date; Y = [Math]::Round(100 * $f / $d, 1) } }
    })
    # Wear speed: change over the last 12 months of history
    $year = @($hist | Where-Object { $_.X -ge (Get-Date).AddDays(-365) })
    $perYear = $null
    if ($year.Count -ge 4) {
        $days = ($year[-1].X - $year[0].X).TotalDays
        if ($days -ge 90) { $perYear = [Math]::Round(($year[0].Y - $year[-1].Y) / $days * 365, 1) }
    }
    $rt = { param($s) try { if ($s) { [Xml.XmlConvert]::ToTimeSpan("$s") } } catch { $null } }
    [pscustomobject]@{
        Error = $null; Design = $design; Full = $full; Pct = $(if ($design) { [Math]::Round(100 * $full / $design) } else { $null })
        Cycles = [int]($bats | ForEach-Object { [int]$_.CycleCount } | Measure-Object -Maximum).Maximum
        Chem = "$($bats[0].Chemistry)"; Maker = "$($bats[0].Manufacturer)".Trim(); Id = "$($bats[0].Id)".Trim()
        Runtime = (& $rt $b.BatteryReport.RuntimeEstimates.FullChargeCapacity.ActiveRuntime)
        RuntimeNew = (& $rt $b.BatteryReport.RuntimeEstimates.DesignCapacity.ActiveRuntime)
        History = $hist; PerYear = $perYear; Since = $(if ($hist) { $hist[0].X })
    }
}
# Where each PC maker hides the "stop charging at 80%" setting.
$ChargeLimitTips = [ordered]@{
    'Dell'                = 'Dell Optimizer or Dell Power Manager > Battery > "Primarily AC use" (or Custom, e.g. 50-80%). Also in the BIOS (F2 at start-up) > Power > Battery Charge Configuration.'
    'Lenovo'              = 'Lenovo Vantage > Device > Power > Battery Charge Threshold, or "Conservation mode".'
    'HP|Hewlett'          = 'In the BIOS (F10 at start-up) > Advanced > Power Management Options > Battery Health Manager: "Maximize my battery health".'
    'ASUS'                = 'MyASUS > Customization > Battery Health Charging: "Balanced" (80%) or "Maximum lifespan" (60%).'
    'Acer'                = 'Acer Care Center or Acer Quick Access > Battery charge limit (80%).'
    'Micro-Star|MSI'      = 'MSI Center > Features > Battery Master: "Best for Battery".'
    'Samsung'             = 'Samsung Settings > Battery > "Protect battery" (charges to 85%).'
    'Microsoft'           = 'Surface app > Battery > Smart Charging, or the UEFI "Enable Battery Limit" mode.'
    'Razer'               = 'Razer Synapse > System > Battery Health Optimizer.'
    'Framework'           = 'In the BIOS > Advanced > Battery Charge Limit.'
}
function Update-Battery {
    if (-not $HasBattery) { return }
    $btnBattReload.Enabled = $false
    $lblBatt.Text = 'Reading the battery report...'
    Start-Bg -Label 'Reading the battery report' $BatteryWork $null {
        param($r)
        $btnBattReload.Enabled = $true
        $r = @($r)[0]
        $lvBatt.BeginUpdate(); $lvBatt.Items.Clear()
        if (-not $r -or $r.Error) { $lvBatt.EndUpdate(); $lblBatt.Text = if ($r) { $r.Error } else { 'Could not read the battery.' }; return }
        $script:Battery = $r
        $add = { param($what, $value, $means, $color) $it = Add-Row $lvBatt @($what, $value, $means) $null; if ($color) { $it.ForeColor = $color } }
        $pct = $r.Pct
        $healthMeans = if ($pct -ge 80) { 'Good - normal for its age.' } elseif ($pct -ge 60) { 'Worn: you get noticeably less time on battery than when it was new.' } else { 'Worn out: it holds less than two thirds of its charge. A new battery brings back the original battery life - see "Replacement" below.' }
        & $add 'Battery health' "holds $pct% of its original charge" $healthMeans $(if ($pct -lt 60) { $Theme.Bad } elseif ($pct -lt 80) { $Theme.Warn } else { $Theme.Good })
        & $add 'Capacity' ('{0:N1} Wh now, {1:N1} Wh when new' -f ($r.Full / 1000), ($r.Design / 1000)) 'Wh (watt-hours) is how much energy the battery can store.' $null
        if ($null -ne $r.PerYear) {
            $fast = $r.PerYear -gt 12
            & $add 'Wear over the last year' $(if ($r.PerYear -le 0) { 'no loss' } else { "loses about $($r.PerYear)% a year" }) `
                $(if ($fast) { 'Faster than normal (about 5-10% a year). Usually heat, or the battery being kept at 100% while plugged in all day - a charge limit helps (below).' } else { 'Normal.' }) $(if ($fast) { $Theme.Warn } else { $null })
        }
        if ($r.Runtime) {
            $fmt = { param($t) '{0} h {1:00} min' -f [int][Math]::Floor($t.TotalHours), $t.Minutes }
            & $add 'Time on a full charge' "about $(& $fmt $r.Runtime)$(if ($r.RuntimeNew) { " ($(& $fmt $r.RuntimeNew) when new)" })" 'Windows'' estimate for the way you normally use the PC.' $null
        }
        if ($r.Cycles -gt 0) { & $add 'Charge cycles' "$($r.Cycles)" 'One cycle = 100% used in total. Most laptop batteries are made for 300-1000 cycles.' $(if ($r.Cycles -ge 800) { $Theme.Warn } else { $null }) }
        $chem = switch -Regex ($r.Chem) { '^LiP' { 'lithium polymer'; break } '^Li' { 'lithium-ion'; break } default { $r.Chem } }
        & $add 'Type' "$chem$(if ($r.Maker) { ", made by $($r.Maker)" })$(if ($r.Id) { " ($($r.Id))" })" 'Needed when you look for a replacement.' $null
        $tip = 'Look in the PC maker''s app or in the BIOS for "charge limit", "battery care" or "conservation mode" (usually 80%).'
        foreach ($k in $ChargeLimitTips.Keys) { if ($PcName -match $k) { $tip = $ChargeLimitTips[$k]; break } }
        & $add 'Charge limit' $(if ([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Online') { 'plugged in now' } else { 'on battery now' }) `
            "If the PC is plugged in most of the time, stopping charging at about 80% slows wear a lot. $tip" $null
        if ($pct -lt 70) { & $add 'Replacement' 'worth it' "Search for ""$PcName battery""$(if ($r.Id) { " (battery $($r.Id))" }) - preferably the PC maker's own part. On many laptops it is a 10-20 minute job with a screwdriver; the Upgrades page has the service manual." $Theme.Bad }
        & $add 'Battery usage per app' 'see button above' 'Which apps used the most battery in the last day or week (Windows Settings).' $null
        $lvBatt.EndUpdate()
        Set-Chart $chartBatt @(@{ Name = 'Charge it holds (% of new)'; Color = $Theme.Accent; Points = @($r.History) }) 100 '%'
        $lblBatt.Text = if ($r.Since) { "Battery history since $($r.Since.ToString('d'))." } else { '' }
        $script:BatteryWorn = [int]($pct -lt 60)
        if ($script:NavButtons) { Update-NavBadges }
    }
}
$btnBattUsage.Add_Click({ Start-Process 'ms-settings:batterysaver-usagedetails' })
$btnBattSet.Add_Click({ Start-Process 'ms-settings:batterysaver' })
$btnBattReport.Add_Click({
    $file = Join-Path $DataDir 'battery-report.html'
    $btnBattReport.Enabled = $false
    Start-Bg -Label 'Making the battery report' { param($f) [void](Invoke-Native "$env:windir\System32\powercfg.exe" "/batteryreport /output `"$f`"" 60); Test-Path $f } $file {
        param($ok) $btnBattReport.Enabled = $true
        if (@($ok)[0]) { Start-Process (Join-Path $DataDir 'battery-report.html') } else { Show-Msg 'Windows could not make a battery report.' 'OK' 'Warning' | Out-Null }
    }
})
$btnBattBuy.Add_Click({ Start-Process ('https://www.bing.com/search?q=' + [uri]::EscapeDataString("$PcName battery $(if ($script:Battery) { $script:Battery.Id })")) })
$btnBattReload.Add_Click({ Update-Battery })

# ===========================================================================
# Power: the power mode, plan and timers - fast when plugged in, sparing on battery. Every change can be undone from History.
# ===========================================================================
$pgPower = New-Page 'Power' 'How the PC uses power: plugged in it should be quick, on battery it should last and go to sleep by itself. Recommended fixes are pre-checked; every change can be undone from History.'
$btnPowerFix = New-Button 'Apply checked fixes'
$btnPowerReload = New-Button 'Check again'
$btnPowerSet = New-Button 'Power settings'
$btnPowerPlans = New-Button 'Power plans'
$lvPower = New-ListView $true @('Setting', 230, 'Plugged in', 170, 'On battery', 170, 'What to do', 520)
$txtPower = New-DetailBox 104
Set-PageLayout $pgPower $lvPower @((New-ButtonBar @($btnPowerFix, $btnPowerReload, $btnPowerSet, $btnPowerPlans))) $txtPower
$PowerModeKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$PowerModes = [ordered]@{ '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Best power efficiency'; '00000000-0000-0000-0000-000000000000' = 'Balanced'
                          '3af9b8d9-7c97-431d-ad78-34a8bfea439f' = 'Better performance'; 'ded574b5-45a0-4f42-8737-46345c09c238' = 'Best performance' }
$PowerWork = {
    param($cfg)
    $pc = "$env:windir\System32\powercfg.exe"
    $rows = New-Object System.Collections.ArrayList
    function Add-P($Name, $Ac, $Dc, $Level, $Todo, $Fix = $null, $Rec = $false, $Admin = $false) {
        [void]$rows.Add([pscustomobject]@{ Name = $Name; Ac = $Ac; Dc = $Dc; Level = $Level; Todo = $Todo; Fix = $Fix; Rec = $Rec; Admin = $Admin }) }
    # A setting's plugged-in and battery values: the last two hex numbers powercfg prints (the same in every Windows language).
    function Get-Idx($Sub, $Set) {
        $o = (& $pc /qh SCHEME_CURRENT $Sub $Set 2>$null) -join "`n"
        $m = [regex]::Matches($o, '0x[0-9a-fA-F]{8}')
        if ($m.Count -ge 2) { @([Convert]::ToInt64($m[$m.Count - 2].Value, 16), [Convert]::ToInt64($m[$m.Count - 1].Value, 16)) }
    }
    function Format-Secs([int64]$S) { if ($S -le 0 -or $S -ge 0x7FFFFFFF) { 'never' } elseif ($S -lt 3600) { "$([int]($S / 60)) min" } else { "$([Math]::Round($S / 3600, 1)) h" } }
    $bat = $cfg.Battery
    $scheme = if ("$(& $pc /getactivescheme 2>$null)" -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $Matches[1] } else { '' }
    # Power mode (the Windows 11 slider), separately for plugged in and on battery
    $ps = Get-ItemProperty $cfg.ModeKey -ErrorAction SilentlyContinue
    $acM = "$($ps.ActiveOverlayAcPowerScheme)"; if (-not $acM) { $acM = '00000000-0000-0000-0000-000000000000' }
    $dcM = "$($ps.ActiveOverlayDcPowerScheme)"; if (-not $dcM) { $dcM = '00000000-0000-0000-0000-000000000000' }
    $name = { param($g) if ($cfg.Modes.Contains($g)) { $cfg.Modes[$g] } else { 'custom' } }
    $plans = @{ '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Balanced'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'High performance'; 'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Power saver'; 'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Ultimate Performance' }
    $planName = if ($plans.ContainsKey($scheme)) { $plans[$scheme] } elseif ("$(& $pc /getactivescheme 2>$null)" -match '\(([^)]+)\)') { $Matches[1] } else { 'unknown' }
    if ($scheme -eq '381b4222-f694-41f0-9685-ff5bb260df2e') {   # the slider only works on the Balanced plan
        if ($acM -eq '961cc777-2547-4f9d-8174-7d86181b8a7a') {
            Add-P 'Power mode' (& $name $acM) $(if ($bat) { & $name $dcM } else { '' }) 'Warning' 'Plugged in, the PC is set to save energy, which makes it slower. Best performance makes it quick (the fan may run a little more).' 'mode|ac|ded574b5-45a0-4f42-8737-46345c09c238' $true
        } elseif ($acM -ne 'ded574b5-45a0-4f42-8737-46345c09c238') {
            Add-P 'Power mode' (& $name $acM) $(if ($bat) { & $name $dcM } else { '' }) 'Info' 'Fine. For the most speed when plugged in, choose Best performance (fix below) - the fan may run a little more.' 'mode|ac|ded574b5-45a0-4f42-8737-46345c09c238'
        }
        if ($bat -and $dcM -eq 'ded574b5-45a0-4f42-8737-46345c09c238') {
            Add-P 'Power mode on battery' (& $name $acM) (& $name $dcM) 'Warning' 'Best performance on battery empties it much faster. Balanced keeps the PC quick enough and lasts longer.' 'mode|dc|00000000-0000-0000-0000-000000000000' $true
        }
        if (-not @($rows | Where-Object { $_.Name -like 'Power mode*' })) { Add-P 'Power mode' (& $name $acM) $(if ($bat) { & $name $dcM } else { '' }) 'OK' 'Nothing to do.' }
    }
    # Power plan
    if ($scheme -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') { Add-P 'Power plan' $planName $planName 'Warning' 'Power saver slows the PC down all the time, also when plugged in. Balanced adjusts itself and lets you use the power mode slider.' 'plan|381b4222-f694-41f0-9685-ff5bb260df2e' $true }
    elseif ($scheme -in '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'e9a42b02-d5df-448d-aa00-03f14749eb61' -and $bat) { Add-P 'Power plan' $planName $planName 'Info' 'Keeps the processor at full speed even on battery, which empties it faster, and switches off the power mode slider. Balanced with Best performance when plugged in is usually just as quick.' 'plan|381b4222-f694-41f0-9685-ff5bb260df2e' }
    else { Add-P 'Power plan' $planName $planName 'OK' 'Nothing to do.' }
    # Highest processor speed allowed
    $v = Get-Idx 'SUB_PROCESSOR' 'PROCTHROTTLEMAX'
    if ($v) {
        if ($v[0] -lt 100) { Add-P 'Maximum processor speed' "$($v[0])%" $(if ($bat) { "$($v[1])%" } else { '' }) 'Problem' "Plugged in, the processor may only run at $($v[0])% of its speed. Set it back to 100% (fix below)." "idx|ac|SUB_PROCESSOR|PROCTHROTTLEMAX|100|$($v[0])|$scheme|100%" $true }
        else { Add-P 'Maximum processor speed' "$($v[0])%" $(if ($bat) { "$($v[1])%" } else { '' }) $(if ($bat -and $v[1] -lt 100) { 'Info' } else { 'OK' }) $(if ($bat -and $v[1] -lt 100) { 'Lower on battery - that saves battery. Fine.' } else { 'Nothing to do.' }) }
    }
    # Screen off and sleep
    $v = Get-Idx 'SUB_VIDEO' 'VIDEOIDLE'
    if ($v) {
        if ($bat -and ($v[1] -le 0 -or $v[1] -gt 900)) { Add-P 'Turn off the screen after' (Format-Secs $v[0]) (Format-Secs $v[1]) 'Warning' 'On battery the screen is the biggest power user. Turning it off after 5 minutes without use makes the battery last longer.' "idx|dc|SUB_VIDEO|VIDEOIDLE|300|$($v[1])|$scheme|5 min" $true }
        elseif ($v[0] -le 0) { Add-P 'Turn off the screen after' (Format-Secs $v[0]) $(if ($bat) { Format-Secs $v[1] } else { '' }) 'Info' 'The screen never turns off by itself when plugged in. That uses power and can wear the screen; 10 minutes is a good choice (fix below).' "idx|ac|SUB_VIDEO|VIDEOIDLE|600|$($v[0])|$scheme|10 min" }
        else { Add-P 'Turn off the screen after' (Format-Secs $v[0]) $(if ($bat) { Format-Secs $v[1] } else { '' }) 'OK' 'Nothing to do.' }
    }
    $v = Get-Idx 'SUB_SLEEP' 'STANDBYIDLE'
    if ($v) {
        if ($bat -and ($v[1] -le 0 -or $v[1] -gt 3600)) { Add-P 'Sleep after' (Format-Secs $v[0]) (Format-Secs $v[1]) 'Warning' 'On battery the PC stays awake for a long time when you leave it, which empties the battery. Going to sleep after 15 minutes saves it - your work stays open.' "idx|dc|SUB_SLEEP|STANDBYIDLE|900|$($v[1])|$scheme|15 min" $true }
        elseif (-not $bat -and $v[0] -le 0) { Add-P 'Sleep after' (Format-Secs $v[0]) '' 'Info' 'The PC never sleeps by itself. Fine if it has to stay on (downloads, sharing); otherwise sleeping after 30 minutes saves power (fix below).' "idx|ac|SUB_SLEEP|STANDBYIDLE|1800|$($v[0])|$scheme|30 min" }
        else { Add-P 'Sleep after' (Format-Secs $v[0]) $(if ($bat) { Format-Secs $v[1] } else { '' }) 'OK' 'Nothing to do.' }
    }
    # Closing the lid (laptops)
    if ($bat) {
        $v = Get-Idx 'SUB_BUTTONS' 'LIDACTION'
        $lid = @{ 0 = 'do nothing'; 1 = 'sleep'; 2 = 'hibernate'; 3 = 'shut down' }
        if ($v) {
            if ($v[1] -eq 0) { Add-P 'When I close the lid' $lid[[int]$v[0]] $lid[[int]$v[1]] 'Warning' 'On battery the laptop keeps running with the lid closed - in a bag it gets hot and the battery runs flat. Sleep is safer (fix below).' "idx|dc|SUB_BUTTONS|LIDACTION|1|$($v[1])|$scheme|sleep" $true }
            else { Add-P 'When I close the lid' $lid[[int]$v[0]] $lid[[int]$v[1]] 'OK' $(if ($v[0] -eq 0) { 'Plugged in it keeps running (handy with a separate screen). Nothing to do.' } else { 'Nothing to do.' }) }
        }
        # Hibernate after a long sleep, so the battery can't run flat with unsaved work
        if ($cfg.Hiber) {
            $v = Get-Idx 'SUB_SLEEP' 'HIBERNATEIDLE'
            if ($v -and ($v[1] -le 0 -or $v[1] -ge 86400)) { Add-P 'Hibernate after' (Format-Secs $v[0]) (Format-Secs $v[1]) 'Info' 'Asleep on battery, the laptop slowly uses its charge. Hibernating after 3 hours of sleep keeps your work safe if you forget it for days (fix below).' "idx|dc|SUB_SLEEP|HIBERNATEIDLE|10800|$($v[1])|$scheme|3 h" }
        }
    }
    # USB devices being switched off to save power
    $v = Get-Idx '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    if ($v) {
        $on = @{ 0 = 'off'; 1 = 'on' }
        if ($v[0] -eq 1) { Add-P 'USB power saving' $on[[int]$v[0]] $(if ($bat) { $on[[int]$v[1]] } else { '' }) 'Info' 'Windows may switch off USB devices that seem idle. If a mouse, headset or drive disconnects by itself, switch this off for plugged in (fix below).' "idx|ac|2a737441-1930-4402-8d77-b2bebba308a3|48e6b7a6-50f5-4782-a5d4-53bb8f07e226|0|$($v[0])|$scheme|off" }
        else { Add-P 'USB power saving' $on[[int]$v[0]] $(if ($bat) { $on[[int]$v[1]] } else { '' }) 'OK' 'Nothing to do.' }
    }
    # Fast startup
    $fast = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($fast -eq 1) { Add-P 'Fast startup' 'on' 'on' 'Info' 'Shut down is then not a full restart - when something tells you to restart, use Restart. If the PC has problems after starting up (devices, updates), switching it off helps; starting takes a few seconds longer. Needs administrator.' 'faststart' $false $true }
    elseif ($null -ne $fast) { Add-P 'Fast startup' 'off' 'off' 'OK' 'Every start is a full start. Nothing to do.' }
    [pscustomobject]@{ Rows = $rows; Scheme = $scheme }
}
function Update-Power {
    $btnPowerReload.Enabled = $false
    $txtPower.Text = 'Checking...'
    Start-Bg -Label 'Checking power settings' $PowerWork @{ Battery = $HasBattery; ModeKey = $PowerModeKey; Modes = $PowerModes; Hiber = [IO.File]::Exists("$env:SystemDrive\hiberfil.sys") } {
        param($r)
        $btnPowerReload.Enabled = $true
        $r = @($r)[0]
        $lvPower.BeginUpdate(); $lvPower.Items.Clear()
        foreach ($p in @($r.Rows) | Sort-Object { $SecLevels[$_.Level] }) {
            $it = Add-Row $lvPower @($p.Name, $p.Ac, $(if ($HasBattery) { $p.Dc } else { '-' }), $p.Todo) $p ($p.Rec -and $p.Fix)
            Set-RowStatus $it 0 $(switch ($p.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.AccentText } })
            if ($p.Admin -and -not $IsAdmin) { $it.ForeColor = $Theme.Muted }
        }
        $lvPower.EndUpdate()
        $script:PowerIssues = @($r.Rows | Where-Object { $_.Level -in 'Problem', 'Warning' }).Count
        if ($lvPower.Items.Count) { $lvPower.Items[0].Selected = $true }
        if ($script:NavButtons) { Update-NavBadges }
    }
}
$lvPower.Add_SelectedIndexChanged({
    if (-not $lvPower.SelectedItems.Count) { return }
    $p = $lvPower.SelectedItems[0].Tag
    $txtPower.Text = "$(T $p.Name):  $(T $p.Ac)$(if ($HasBattery -and $p.Dc) { ' / ' + (T $p.Dc) })`r`n`r`n$((T 'What to do: {0}').Replace('{0}', (T $p.Todo)))$(if ($p.Admin -and -not $IsAdmin) { "`r`n`r`n" + (T 'Needs administrator rights - click ''Restart as admin''.') })"
})
# The power mode for the power source the PC is on now goes through Windows (no administrator needed); the other one is a
# setting in the registry that only administrators can change.
function Set-PowerOverlay([string]$Guid) {
    if (-not ('PcTuneUpPower.Overlay' -as [type])) { Add-Type -Namespace PcTuneUpPower -Name Overlay -MemberDefinition '[DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(System.Guid g);' }
    $r = [PcTuneUpPower.Overlay]::PowerSetActiveOverlayScheme([guid]$Guid)
    if ($r) { throw "Windows refused the power mode (error $r)" }
}
function Set-PowerMode([bool]$Ac, [string]$Guid) {
    $onAc = [Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -ne 'Offline'
    if ($onAc -eq $Ac) { Set-PowerOverlay $Guid; return }
    if (-not $IsAdmin) { throw (T $(if ($Ac) { 'Plug in the charger first (or click "Restart as admin"), then try again.' } else { 'Unplug the charger first (or click "Restart as admin"), then try again.' })) }
    Set-RegValue $PowerModeKey $(if ($Ac) { 'ActiveOverlayAcPowerScheme' } else { 'ActiveOverlayDcPowerScheme' }) $Guid 'String'
}
function Invoke-PowerCfg([string]$Arguments) {
    $pr = Start-Process "$env:windir\System32\powercfg.exe" -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($pr.ExitCode) { throw "powercfg $Arguments`: exit code $($pr.ExitCode)" }
}
$btnPowerFix.Add_Click({
    $picked = @($lvPower.CheckedItems | ForEach-Object { $_.Tag } | Where-Object Fix)
    if (-not $picked) { Show-Msg 'Check one or more rows that have a fix first.' | Out-Null; return }
    $locked = @($picked | Where-Object { $_.Admin -and -not $IsAdmin })
    if ($locked) { Show-Msg "These need administrator rights - click ""Restart as admin"" first, or uncheck them: $(($locked | ForEach-Object { T $_.Name }) -join ', ')" 'OK' 'Warning' | Out-Null; return }
    if (-not (Confirm-Checked 'Apply these {0} fix(es)?' @($picked | ForEach-Object { T $_.Name }) 'You can undo this on the History page.')) { return }
    $done = @(); $failed = @()
    foreach ($p in $picked) {
        try {
            $f = $p.Fix -split '\|'
            switch ($f[0]) {
                'mode' {
                    $ac = $f[1] -eq 'ac'
                    $old = "$(Get-RegValue $PowerModeKey $(if ($ac) { 'ActiveOverlayAcPowerScheme' } else { 'ActiveOverlayDcPowerScheme' }))"
                    if (-not $old) { $old = '00000000-0000-0000-0000-000000000000' }
                    Set-PowerMode $ac $f[2]
                    Add-History 'Power' "$($p.Name) ($(if ($ac) { 'plugged in' } else { 'on battery' }))" "set to $($PowerModes[$f[2]])" @{ Type = 'PowerMode'; Ac = $ac; Old = $old }
                }
                'plan' {
                    $old = if ("$(powercfg /getactivescheme)" -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $Matches[1] }
                    Invoke-PowerCfg "/setactive $($f[1])"
                    Add-History 'Power' 'Power plan' 'set to Balanced' $(if ($old) { @{ Type = 'Power'; Cmds = @("/setactive $old") } })
                }
                'idx' {
                    # idx|ac or dc|subgroup|setting|new value|old value|plan|new value as shown
                    $which = if ($f[1] -eq 'ac') { '/setacvalueindex' } else { '/setdcvalueindex' }
                    Invoke-PowerCfg "$which $($f[6]) $($f[2]) $($f[3]) $($f[4])"
                    Invoke-PowerCfg "/setactive $($f[6])"
                    Add-History 'Power' "$($p.Name) ($(if ($f[1] -eq 'ac') { 'plugged in' } else { 'on battery' }))" "set to $($f[7])" @{ Type = 'Power'; Cmds = @("$which $($f[6]) $($f[2]) $($f[3]) $($f[5])", "/setactive $($f[6])") }
                }
                'faststart' {
                    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; $old = Get-RegValue $k 'HiberbootEnabled'; Set-RegValue $k 'HiberbootEnabled' 0
                    Add-History 'Power' 'Fast startup' 'turned off' @{ Type = 'Reg'; Values = @(@{ P = $k; N = 'HiberbootEnabled'; Old = $old; T = 'DWord' }) }
                }
            }
            $done += T $p.Name
        } catch { $failed += "$(T $p.Name): $($_.Exception.Message)" }
    }
    Update-History; Update-Power
    $msg = if ($done) { "Done: $($done -join ', '). Undo from the History page." } else { '' }
    if ($failed) { $msg += "`n`nNot changed:`n$($failed -join "`n")" }
    Show-Msg $msg.Trim() $(if ($failed) { 'OK' } else { 'OK' }) $(if ($failed) { 'Warning' } else { 'Information' }) | Out-Null
})
$btnPowerReload.Add_Click({ Update-Power })
$btnPowerSet.Add_Click({ Start-Process 'ms-settings:powersleep' })
$btnPowerPlans.Add_Click({ Start-Process control.exe '/name Microsoft.PowerOptions' })

# ===========================================================================
# Browsers: extensions, search engine, home page, and settings forced by "policies"
# ===========================================================================
$pgBrw = New-Page 'Browsers' 'Extensions in Chrome, Edge, Brave, Vivaldi and Firefox, the search engine, home page and start-up pages, plus Windows'' hosts file and proxy. Adware hides here: extensions that weren''t installed from a store, and settings forced through "policies".'
$btnBrwExt = New-Button 'Open extensions page'
$btnBrwPol = New-Button 'Remove checked'
$btnBrwReset = New-Button 'Reset browser settings'
$btnBrwReload = New-Button 'Reload'
$lvBrw = New-ListView $true @('Item', 290, 'Browser', 130, 'Kind', 110, 'Status', 80, 'Details', 560)
$txtBrw = New-DetailBox 104
Set-PageLayout $pgBrw $lvBrw @((New-ButtonBar @($btnBrwExt, $btnBrwPol, $btnBrwReset, $btnBrwReload))) $txtBrw
$BrowserWork = {
    param($cfg)
    Add-Type -AssemblyName System.Web.Extensions
    $json = New-Object Web.Script.Serialization.JavaScriptSerializer; $json.MaxJsonLength = [int]::MaxValue
    $read = { param($p) try { if (Test-Path -LiteralPath $p) { $json.DeserializeObject([IO.File]::ReadAllText($p)) } } catch { $null } }
    $get = { param($o, [string[]]$path) foreach ($k in $path) { if ($o -is [Collections.IDictionary] -and $o.ContainsKey($k)) { $o = $o[$k] } else { return $null } }; $o }
    $rows = New-Object System.Collections.ArrayList
    function Add-B($Item, $Browser, $Kind, $Level, $Detail, $Todo, $Extra) {
        [void]$rows.Add([pscustomobject]@{ Item = $Item; Browser = $Browser; Kind = $Kind; Level = $Level; Detail = $Detail; Todo = $Todo; Extra = $Extra })
    }
    $knownSearch = 'google\.|bing\.com|duckduckgo\.|ecosia\.|startpage\.|yahoo\.|qwant\.|search\.brave\.com|yandex\.|baidu\.|naver\.|seznam\.|you\.com|perplexity\.ai|kagi\.com|msn\.com'
    $hostOf = { param($u) try { ([uri]"$u").Host -replace '^www\.', '' } catch { "$u" } }
    $allSites = '^(<all_urls>|\*://\*/\*|https?://\*/\*|\*://\*\.?[^/]*/\*)$'
    $todoRisky = 'Remove it unless you installed it yourself on purpose: open the extensions page (button above) > Remove. If it comes back, a program keeps adding it - look on the Programs and Bloatware pages.'
    $todoReview = 'Keep it if you know it and use it; otherwise remove it from the extensions page (button above).'
    $todoOk = 'Nothing to do.'
    $browsers = @(
        @{ Name = 'Chrome'; Root = "$env:LOCALAPPDATA\Google\Chrome\User Data"; Pol = 'Google\Chrome'; Stores = 'clients2\.google\.com/service/update2/crx' }
        @{ Name = 'Edge'; Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; Pol = 'Microsoft\Edge'; Stores = 'edge\.microsoft\.com/extensionwebstorebase|clients2\.google\.com/service/update2/crx' }
        @{ Name = 'Brave'; Root = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Pol = 'BraveSoftware\Brave'; Stores = 'clients2\.google\.com/service/update2/crx' }
        @{ Name = 'Vivaldi'; Root = "$env:LOCALAPPDATA\Vivaldi\User Data"; Pol = $null; Stores = 'clients2\.google\.com/service/update2/crx' }
    )
    foreach ($b in $browsers) {
        if (-not (Test-Path $b.Root)) { continue }
        $names = & $get (& $read (Join-Path $b.Root 'Local State')) @('profile', 'info_cache')
        $profiles = @(Get-ChildItem -LiteralPath $b.Root -Directory -ErrorAction SilentlyContinue | Where-Object { ($_.Name -eq 'Default' -or $_.Name -like 'Profile *') -and (Test-Path (Join-Path $_.FullName 'Preferences')) })
        foreach ($p in $profiles) {
            Set-JobProgress "$($b.Name): $($p.Name)"
            $label = $b.Name; $pn = & $get $names @($p.Name, 'name')
            if ($profiles.Count -gt 1) { $label = "$($b.Name) ($(if ($pn) { $pn } else { $p.Name }))" }
            $prefs = & $read (Join-Path $p.FullName 'Preferences')
            $sec = & $read (Join-Path $p.FullName 'Secure Preferences')
            $exts = @{}
            foreach ($src in (& $get $sec @('extensions', 'settings')), (& $get $prefs @('extensions', 'settings'))) {
                if ($src -is [Collections.IDictionary]) { foreach ($k in $src.Keys) { if (-not $exts[$k] -or $src[$k].ContainsKey('location')) { $exts[$k] = $src[$k] } } }
            }
            foreach ($id in $exts.Keys) {
                $s = $exts[$id]; $loc = $s['location']
                if ($null -eq $loc -or [int]$loc -in 5, 10) { continue }   # built into the browser
                $man = $s['manifest']
                $dir = Join-Path $p.FullName "Extensions\$id"
                if (-not $man -and (Test-Path $dir)) {
                    $v = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($v) { $man = & $read (Join-Path $v.FullName 'manifest.json'); $dir = $v.FullName }
                } elseif ($man -and (Test-Path $dir)) { $v = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1; if ($v) { $dir = $v.FullName } }
                if (-not $man) { continue }
                $name = "$($man['name'])"
                if ($name -match '^__MSG_(.+)__$') {   # translated name: look it up in the extension's own language files
                    $key = $Matches[1]; $lang = if ($man['default_locale']) { $man['default_locale'] } else { 'en' }
                    $msgs = & $read (Join-Path $dir "_locales\$lang\messages.json")
                    if ($msgs) { foreach ($mk in $msgs.Keys) { if ($mk -ieq $key) { $name = "$($msgs[$mk]['message'])"; break } } }
                }
                if (-not $name -or $name -match '^__MSG_') { $name = $id }
                $dr = $s['disable_reasons']
                $on = -not ($dr -and ((($dr -is [array]) -and $dr.Count) -or ($dr -isnot [array] -and [int]$dr -ne 0))) -and "$($s['state'])" -ne '0'
                $store = $s['from_webstore'] -eq $true -or "$($man['update_url'])" -match $b.Stores
                $perms = @($man['permissions']) + @($man['host_permissions']) + @(foreach ($cs in @($man['content_scripts'])) { if ($cs) { @($cs['matches']) } }) | Where-Object { $_ -is [string] }
                $readsAll = [bool]($perms | Where-Object { $_ -match $allSites })
                $strong = @($perms | Where-Object { $_ -in 'proxy', 'debugger', 'management', 'nativeMessaging', 'privacy', 'declarativeNetRequestWithHostAccess' })
                $ov = $man['chrome_settings_overrides']; $nt = & $get $man @('chrome_url_overrides', 'newtab')
                $changes = @($(if ($ov -and $ov['search_provider']) { 'your search engine' }), $(if ($ov -and $ov['homepage']) { 'your home page' }),
                             $(if ($ov -and $ov['startup_pages']) { 'your start-up pages' }), $(if ($nt) { 'the new-tab page' }) | Where-Object { $_ })
                $policy = [int]$loc -in 7, 9
                $notes = @()
                if ($changes) { $notes += "changes $($changes -join ', ')" }
                if ($readsAll) { $notes += 'can read and change every website you visit' }
                if ($strong) { $notes += "extra powers: $($strong -join ', ')" }
                if ($policy) { $notes += 'installed by a policy' } elseif (-not $store) { $notes += 'not from a store (added by a program or by hand)' }
                if (-not $on) { $notes += 'switched off' }
                $level = if ((-not $store -and -not $policy -and ($changes -or $readsAll)) -or ($policy -and -not $cfg.Managed -and -not $store)) { 'Risky' }
                         elseif ($changes -or (-not $store) -or $strong) { 'Review' } else { 'OK' }
                if (-not $on -and $level -eq 'Review') { $level = 'Info' }
                $todo = switch ($level) { 'Risky' { $todoRisky } 'Review' { $todoReview } 'Info' { 'Switched off. Remove it if you don''t need it any more.' } default { $todoOk } }
                Add-B $name $label 'Extension' $level $(if ($notes) { ($notes -join '; ') } else { 'from the store' }) $todo @{ Browser = $b.Name; Id = $id }
            }
            # Search engine, home page and start-up pages
            $se = & $get $prefs @('default_search_provider_data', 'template_url_data', 'url')
            if ($se) { $h = & $hostOf ($se -replace '\{[^}]+\}', 'x'); $ok = $h -match $knownSearch
                Add-B "Search engine: $h" $label 'Search' $(if ($ok) { 'OK' } else { 'Review' }) $(if ($ok) { 'a well-known search engine' } else { 'not a well-known search engine - adware often swaps it' }) `
                    $(if ($ok) { $todoOk } else { 'Change it back in the browser: Settings > Search engine. If it changes again, use "Reset browser settings".' }) $null }
            $homeUrl = & $get $prefs @('homepage')   # not $home: that is PowerShell's own (read-only) variable
            if ($homeUrl -and (& $get $prefs @('homepage_is_newtabpage')) -ne $true -and (& $get $prefs @('browser', 'show_home_button')) -eq $true) {
                Add-B "Home page: $(& $hostOf $homeUrl)" $label 'Home page' 'Info' "$homeUrl" 'Fine if you chose it.' $null
            }
            if ((& $get $prefs @('session', 'restore_on_startup')) -eq 4) {
                $urls = @(& $get $prefs @('session', 'startup_urls'))
                $odd = @($urls | Where-Object { (& $hostOf $_) -notmatch $knownSearch -and $_ -notmatch '^(chrome|edge|brave|vivaldi)://' })
                if ($urls) { Add-B "Start-up pages: $(($urls | ForEach-Object { & $hostOf $_ }) -join ', ')" $label 'Start-up' $(if ($odd) { 'Review' } else { 'OK' }) ($urls -join '  ') $(if ($odd) { 'Fine if you chose them; otherwise change them in Settings > On start-up.' } else { $todoOk }) $null }
            }
        }
        # Policies: on a home PC, settings forced here are a classic adware trick (the browser says "managed by your organisation")
        if ($b.Pol) {
            foreach ($hive in 'HKLM', 'HKCU') {
                $key = "${hive}:\SOFTWARE\Policies\$($b.Pol)"
                if (-not (Test-Path $key)) { continue }
                $k = Get-Item $key
                foreach ($vn in $k.GetValueNames() | Where-Object { $_ -match '^(DefaultSearchProvider(SearchURL|Name|Enabled)|HomepageLocation|NewTabPageLocation|HomepageIsNewTabPage|RestoreOnStartup)$' }) {
                    $val = "$($k.GetValue($vn))"
                    Add-B "Policy: $vn = $val" $b.Name 'Policy' $(if ($cfg.Managed) { 'Info' } else { 'Risky' }) "forced through $key" `
                        $(if ($cfg.Managed) { 'Set by your organisation (this PC is managed) - leave it.' } else { 'Nobody manages this home PC, so a program forced this. Check it and click "Remove checked policies" (needs administrator).' }) @{ Path = $key; Name = $vn }
                }
                foreach ($sub in 'ExtensionInstallForcelist', 'RestoreOnStartupURLs') {
                    $sk = Get-Item "$key\$sub" -ErrorAction SilentlyContinue
                    if (-not $sk) { continue }
                    foreach ($vn in $sk.GetValueNames()) {
                        $val = "$($sk.GetValue($vn))"
                        $what = if ($sub -eq 'ExtensionInstallForcelist') { "Forced extension: $(($val -split ';')[0])" } else { "Forced start-up page: $val" }
                        Add-B "Policy: $what" $b.Name 'Policy' $(if ($cfg.Managed) { 'Info' } else { 'Risky' }) "forced through $key\$sub" `
                            $(if ($cfg.Managed) { 'Set by your organisation (this PC is managed) - leave it.' } else { 'Nobody manages this home PC, so a program forced this. Check it and click "Remove checked policies" (needs administrator).' }) @{ Path = "$key\$sub"; Name = $vn }
                    }
                }
            }
        }
    }
    # Firefox
    $ff = "$env:APPDATA\Mozilla\Firefox\Profiles"
    foreach ($p in @(Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'extensions.json') })) {
        $j = & $read (Join-Path $p.FullName 'extensions.json')
        foreach ($a in @($j['addons'])) {
            if (-not $a -or $a['type'] -ne 'extension' -or "$($a['location'])" -match '^app-(builtin|system-defaults|system-addons|temporary)$') { continue }
            $name = & $get $a @('defaultLocale', 'name'); if (-not $name) { $name = $a['id'] }
            $perms = @(& $get $a @('userPermissions', 'origins')) + @(& $get $a @('userPermissions', 'permissions')) | Where-Object { $_ -is [string] }
            $readsAll = [bool]($perms | Where-Object { $_ -match $allSites })
            $byProgram = "$($a['location'])" -ne 'app-profile'
            $on = $a['active'] -eq $true
            $notes = @($(if ($readsAll) { 'can read and change every website you visit' }), $(if ($byProgram) { 'added by a program, not from the add-ons site' }), $(if (-not $on) { 'switched off' }) | Where-Object { $_ })
            $level = if ($byProgram -and $readsAll) { 'Risky' } elseif ($byProgram) { 'Review' } else { 'OK' }
            Add-B $name "Firefox$(if (@($j['addons']).Count -and $p.Name -notmatch 'default') { " ($($p.Name -replace '^[^.]+\.', ''))" })" 'Extension' $level $(if ($notes) { $notes -join '; ' } else { 'from the add-ons site' }) `
                $(switch ($level) { 'Risky' { $todoRisky } 'Review' { $todoReview } default { $todoOk } }) @{ Browser = 'Firefox'; Id = $a['id'] }
        }
    }
    $ffPol = "$env:ProgramFiles\Mozilla Firefox\distribution\policies.json"
    if (Test-Path $ffPol) { Add-B 'Policy file: policies.json' 'Firefox' 'Policy' $(if ($cfg.Managed) { 'Info' } else { 'Review' }) "forced settings in $ffPol" 'Open about:policies in Firefox to see what it forces. On a home PC you can delete the file (needs administrator).' $null }
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox') { Add-B 'Policy: settings forced in the registry' 'Firefox' 'Policy' $(if ($cfg.Managed) { 'Info' } else { 'Review' }) 'HKLM\SOFTWARE\Policies\Mozilla\Firefox' 'Open about:policies in Firefox to see what it forces.' $null }
    # Windows itself, for every browser: the hosts file, the proxy, and fake root certificates (classic hijacker tricks)
    Set-JobProgress 'hosts file and proxy'
    $etc = "$env:windir\System32\drivers\etc"
    $db = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction SilentlyContinue).DataBasePath)".TrimEnd('\')
    if ($db -and $db -ne $etc) {
        Add-B 'Hosts file moved' 'Windows' 'Hosts file' 'Risky' "Windows reads its hosts file from $db instead of $etc" 'Programs have no reason to move it - malware does this to hide its own hosts file. Have the PC scanned (Windows Security > Virus & threat protection > Scan options > Microsoft Defender Offline scan).' $null
        $etc = $db
    }
    $hostsFile = Join-Path $etc 'hosts'
    $lines = @(try { [IO.File]::ReadAllLines($hostsFile) } catch { })
    $popular = '(^|\.)(google|bing|microsoft|live|office|outlook|windowsupdate|apple|icloud|facebook|instagram|whatsapp|paypal|amazon|ebay|netflix|youtube|twitter|linkedin|yahoo|wikipedia|steampowered|steamcommunity|epicgames|discord|dropbox)\.[a-z.]+$|(^|\.)x\.com$|bank'
    $security = '(^|\.)(windowsupdate\.(com|microsoft\.com)|update\.microsoft\.com|definitionupdates\.microsoft\.com|avast\.com|avg\.com|kaspersky\.[a-z]+|eset\.com|norton\.com|mcafee\.com|malwarebytes\.com|bitdefender\.[a-z]+|sophos\.com|trendmicro\.com|f-secure\.com|avira\.com|virustotal\.com|emsisoft\.com)$'
    $blocked = 0
    foreach ($line in $lines) {
        $l = ($line -replace '#.*$', '').Trim()
        if (-not $l) { continue }
        $parts = @($l -split '\s+'); if ($parts.Count -lt 2) { continue }
        $ip = $parts[0]; $names = @($parts[1..($parts.Count - 1)] | Where-Object { $_ -notmatch '^(localhost|localhost\.localdomain|local|broadcasthost|ip6-.*)$' -and $_ -notmatch '\.(docker|local|lan|home|internal|test|localhost)$' })
        if (-not $names) { continue }
        $block = $ip -in '0.0.0.0', '127.0.0.1', '::1', '::', '0:0:0:0:0:0:0:0', '0:0:0:0:0:0:0:1'
        $private = $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|fe80:|fd)'
        if ($block) {
            $sec = @($names | Where-Object { $_ -match $security })
            if ($sec) { Add-B "Hosts file blocks $($sec[0])" 'Windows' 'Hosts file' 'Risky' "hosts file line: $line" 'Malware blocks security and update sites so it can''t be removed. Unless you added this yourself, remove the line (check it and click "Remove checked" - needs administrator), then have the PC scanned.' @{ Line = $line } }
            else { $blocked++ }
        } elseif ($private) {
            Add-B "Hosts file: $($names[0]) -> $ip" 'Windows' 'Hosts file' 'Info' "hosts file line: $line" 'Points a name at a device in your own network (a NAS, printer or server). Fine if you set it up.' @{ Line = $line }
        } else {
            $pop = @($names | Where-Object { $_ -match $popular })
            Add-B "Hosts file: $(if ($pop) { $pop[0] } else { $names[0] }) -> $ip" 'Windows' 'Hosts file' $(if ($pop) { 'Risky' } else { 'Review' }) "hosts file line: $line" `
                $(if ($pop) { 'Sends a well-known website to a different server - the way hijackers show fake pages or ads. Unless you added this yourself, remove the line (check it and click "Remove checked" - needs administrator).' } else { 'Sends this name to a fixed address. Developers and some programs do this on purpose; if you don''t know why it is there, remove the line (needs administrator).' }) @{ Line = $line }
        }
    }
    if ($blocked) { Add-B "Hosts file blocks $blocked site(s)" 'Windows' 'Hosts file' 'Info' "in the file $hostsFile" 'Usually an ad or tracking blocker you installed. If websites or programs fail to connect, look here first.' $null }
    elseif (-not @($rows | Where-Object Kind -eq 'Hosts file')) { Add-B 'Hosts file' 'Windows' 'Hosts file' 'OK' 'no redirects or blocks' $todoOk $null }
    # Proxy: everything you browse goes through it
    $isk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $is = Get-ItemProperty $isk -ErrorAction SilentlyContinue
    $proxyTodo = if ($cfg.Managed) { 'Set by your organisation (this PC is managed) - leave it.' }
    if ($is.ProxyEnable -eq 1 -and $is.ProxyServer) {
        $local = "$($is.ProxyServer)" -match '(^|=)(127\.|localhost|\[?::1)'
        Add-B "Proxy: $($is.ProxyServer)" 'Windows' 'Proxy' $(if ($cfg.Managed) { 'Info' } else { 'Review' }) $(if ($local) { 'every website goes through a program on this PC first' } else { 'every website goes through this server first' }) `
            $(if ($proxyTodo) { $proxyTodo } elseif ($local) { 'Fine for tools like Fiddler or some security programs. Otherwise it is often adware reading or changing your web pages: switch it off (check it and click "Remove checked").' } else { 'Fine if your school, work or VPN set it up. Otherwise someone can see and change everything you browse: switch it off (check it and click "Remove checked").' }) `
            @{ Path = $isk; Name = 'ProxyEnable'; Proxy = $true }
    }
    if ($is.AutoConfigURL) {
        Add-B "Proxy script: $($is.AutoConfigURL)" 'Windows' 'Proxy' $(if ($cfg.Managed) { 'Info' } else { 'Review' }) 'a script decides which server each website goes through' `
            $(if ($proxyTodo) { $proxyTodo } else { 'Normal at work or school. On a home PC adware uses this to send your browsing through its own server: remove it (check it and click "Remove checked").' }) @{ Path = $isk; Name = 'AutoConfigURL'; Proxy = $true }
    }
    if (-not ($is.ProxyEnable -eq 1 -and $is.ProxyServer) -and -not $is.AutoConfigURL) { Add-B 'Proxy' 'Windows' 'Proxy' 'OK' 'none - the PC connects directly' $todoOk $null }
    # Root certificates that adware installed to read encrypted (https) pages
    $badCa = 'Superfish|eDellRoot|DSDTestProvider|PrivDog|Komodia|Sendori|WebSafety|NetFilter|Lavasoft Ad-Aware Web Companion|Wajam|Bazooka'
    foreach ($c in @(Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -ErrorAction SilentlyContinue | Where-Object { "$($_.Subject)" -match $badCa })) {
        Add-B "Certificate: $(($c.Subject -split ',')[0] -replace '^CN=', '')" 'Windows' 'Certificate' 'Risky' "a trusted root certificate known from adware (store $($c.PSParentPath -replace '^.*::', ''))" 'It lets adware read and change secure (https) websites. Uninstall the program that came with it (Programs page), then remove the certificate: Start > "Manage computer certificates" > Trusted Root Certification Authorities.' $null
    }
    $rows

}
$BrwLevels = @{ Risky = 0; Review = 1; Info = 2; OK = 3 }
function Update-Browsers {
    $btnBrwReload.Enabled = $false
    $txtBrw.Text = 'Reading browser settings...'
    $managed = [bool]$env:USERDNSDOMAIN -or [bool](Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object { $_.GetValue('UPN') })
    Start-Bg -Label 'Checking browsers' $BrowserWork @{ Managed = $managed } {
        param($rows)
        $btnBrwReload.Enabled = $true
        $lvBrw.BeginUpdate(); $lvBrw.Items.Clear()
        foreach ($r in $rows | Sort-Object { $BrwLevels[$_.Level] }, Browser, Item) {
            $it = Add-Row $lvBrw @($r.Item, $r.Browser, $r.Kind, $r.Level, $r.Detail) $r ($r.Kind -in 'Policy', 'Hosts file' -and $r.Level -eq 'Risky' -and $r.Extra)
            Set-RowStatus $it 3 $(switch ($r.Level) { 'Risky' { $Theme.Bad } 'Review' { $Theme.Warn } 'OK' { $Theme.Text } default { $Theme.Muted } })
        }
        $lvBrw.EndUpdate()
        $script:BrowserRisky = @($rows | Where-Object Level -eq 'Risky').Count
        if ($script:BrowserRisky) { $script:ExtraAdvice['Browsers'] = "Browsers: $($script:BrowserRisky) thing(s) look like adware - see the Browsers page." } else { $script:ExtraAdvice.Remove('Browsers') }
        if ($lvBrw.Items.Count) { $lvBrw.Items[0].Selected = $true } else { $txtBrw.Text = 'No supported browsers found.' }
        Update-Health -Quick
    }
}
$lvBrw.Add_SelectedIndexChanged({
    if (-not $lvBrw.SelectedItems.Count) { return }
    $r = $lvBrw.SelectedItems[0].Tag
    $txtBrw.Text = "$($r.Item) ($($r.Browser)): $($r.Detail)`r`n`r`nWhat to do: $($r.Todo)"
})
$BrowserExe = @{ Chrome = 'chrome.exe'; Edge = 'msedge.exe'; Brave = 'brave.exe'; Vivaldi = 'vivaldi.exe'; Firefox = 'firefox.exe' }
function Open-Browser([string]$Browser, [string]$Url) {
    $exe = $BrowserExe[$Browser]
    $path = foreach ($h in 'HKCU', 'HKLM') { (Get-ItemProperty "${h}:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue).'(default)' }
    $path = @($path | Where-Object { $_ })[0]
    try { Start-Process $(if ($path) { $path.Trim('"') } else { $exe }) $Url } catch { Show-Msg "Couldn't start $Browser." 'OK' 'Warning' | Out-Null }
}
function Get-SelectedBrowser {
    $r = if ($lvBrw.SelectedItems.Count) { $lvBrw.SelectedItems[0].Tag }
    if ($r -and $r.Browser -eq 'Windows') { Show-Msg 'That row is about Windows itself (every browser). Select a row of a browser first.' | Out-Null; return $null }
    if ($r) { ($r.Browser -split ' ')[0] } else { $null }
}
$btnBrwExt.Add_Click({
    if ($lvBrw.SelectedItems.Count -and $lvBrw.SelectedItems[0].Tag.Browser -eq 'Windows') { [void](Get-SelectedBrowser); return }
    $b = Get-SelectedBrowser; if (-not $b) { Show-Msg 'Select a row first.' | Out-Null; return }
    Open-Browser $b $(switch ($b) { 'Firefox' { 'about:addons' } default { "$($b.ToLower() -replace 'edge', 'edge')://extensions" } })
})
$btnBrwReset.Add_Click({
    if ($lvBrw.SelectedItems.Count -and $lvBrw.SelectedItems[0].Tag.Browser -eq 'Windows') { [void](Get-SelectedBrowser); return }
    $b = Get-SelectedBrowser; if (-not $b) { Show-Msg 'Select a row of the browser to reset first.' | Out-Null; return }
    if ((Show-Msg "Open $b's reset page?`n`nResetting puts the search engine, home page, start-up pages and pinned tabs back to normal and switches extensions off. Bookmarks, history and saved passwords stay." 'YesNo' 'Question') -ne 'Yes') { return }
    Open-Browser $b $(switch ($b) { 'Edge' { 'edge://settings/resetProfileSettings' } 'Firefox' { 'about:support' } default { "$($b.ToLower())://settings/reset" } })
})
$btnBrwPol.Add_Click({
    $picked = @($lvBrw.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { $_.Kind -in 'Policy', 'Hosts file', 'Proxy' -and $_.Extra })
    if (-not $picked) { Show-Msg 'Check one or more policy, hosts file or proxy rows first (extensions are removed in the browser itself - use "Open extensions page").' | Out-Null; return }
    if (-not $IsAdmin -and ($picked | Where-Object Kind -in 'Policy', 'Hosts file')) { Show-Msg 'Removing browser policies and hosts file lines needs administrator rights - click "Restart as admin" first, or check only proxy rows.' 'OK' 'Warning' | Out-Null; return }
    if ((Show-Msg "Remove these?`n`n$(($picked | ForEach-Object { " - $($_.Browser): $($_.Item -replace '^Policy: ', '')" }) -join "`n")`n`nRestart the browser afterwards. You can undo this from the History page." 'YesNo' 'Question') -ne 'Yes') { return }
    $done = 0
    foreach ($p in @($picked | Where-Object Kind -eq 'Policy')) {
        try {
            $k = Get-Item -LiteralPath $p.Extra.Path
            $old = $k.GetValue($p.Extra.Name); $kind = "$($k.GetValueKind($p.Extra.Name))"
            Remove-ItemProperty -LiteralPath $p.Extra.Path -Name $p.Extra.Name -ErrorAction Stop
            Add-History 'Browser' "$($p.Browser): $($p.Item -replace '^Policy: ', '')" 'forced setting removed' @{ Type = 'Reg'; Values = @(@{ P = $p.Extra.Path; N = $p.Extra.Name; Old = $old; T = $kind }) }
            $done++
        } catch { }
    }
    foreach ($p in @($picked | Where-Object Kind -eq 'Proxy')) {
        try {
            $old = Get-RegValue $p.Extra.Path $p.Extra.Name
            if ($p.Extra.Name -eq 'ProxyEnable') { Set-RegValue $p.Extra.Path 'ProxyEnable' 0 } else { Remove-ItemProperty -LiteralPath $p.Extra.Path -Name $p.Extra.Name -ErrorAction Stop }
            Add-History 'Browser' "Windows: $($p.Item)" 'switched off' @{ Type = 'Reg'; Values = @(@{ P = $p.Extra.Path; N = $p.Extra.Name; Old = $old; T = $(if ($p.Extra.Name -eq 'ProxyEnable') { 'DWord' } else { 'String' }) }) }
            $done++
        } catch { }
    }
    $hostLines = @($picked | Where-Object Kind -eq 'Hosts file' | ForEach-Object { $_.Extra.Line })
    if ($hostLines) {
        try { Remove-HostsLines $hostLines; Add-History 'Browser' 'Windows: hosts file' "$($hostLines.Count) line(s) removed" @{ Type = 'Hosts'; Lines = $hostLines }; $done += $hostLines.Count }
        catch { Show-Msg "Couldn't change the hosts file: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null }
    }
    Update-History; Update-Browsers
    Show-Msg "$done item(s) removed. Restart the browser to see the change." | Out-Null
})
# The hosts file: lines are taken out (or put back) exactly as they were, and Windows forgets the old answers.
function Get-HostsPath {
    $db = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction SilentlyContinue).DataBasePath)".TrimEnd('\')
    Join-Path $(if ($db) { $db } else { "$env:windir\System32\drivers\etc" }) 'hosts'
}
function Remove-HostsLines([string[]]$Lines) {
    $f = Get-HostsPath
    $keep = New-Object System.Collections.ArrayList
    $left = New-Object System.Collections.ArrayList(, @($Lines))
    foreach ($l in [IO.File]::ReadAllLines($f)) { if ($left.Contains($l)) { $left.Remove($l) } else { [void]$keep.Add($l) } }
    Set-Content -LiteralPath $f -Value @($keep) -Encoding Default -ErrorAction Stop
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}
function Add-HostsLines([string[]]$Lines) {
    Add-Content -LiteralPath (Get-HostsPath) -Value $Lines -Encoding Default -ErrorAction Stop
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}
$btnBrwReload.Add_Click({ Update-Browsers })

# ===========================================================================
# Programs: everything installed, its size, and when it was last used
# ===========================================================================
$pgProg = New-Page 'Programs' 'Every installed program with its size and when you last used it (from Windows'' own record of what you start, and when the program last wrote its own files). Check the ones you don''t need and uninstall them in one go; leftover folders are cleaned up afterwards. Store apps are on the Bloatware page.'
$btnProgUn = New-Button 'Uninstall checked'
$btnProgSort = New-Button 'Sort: size'
$btnProgSet = New-Button 'Open Installed apps'
$btnProgReload = New-Button 'Reload'
$lvProg = New-ListView $true @('Program', 300, 'Publisher', 170, 'Size', 85, 'Installed', 95, 'Last used', 130, 'Note', 330)
$lblProg = New-Status
Set-PageLayout $pgProg $lvProg @((New-ButtonBar @($btnProgUn, $btnProgSort, $btnProgSet, $btnProgReload))) $lblProg
$ProgramsWork = {
    param($cfg)
    # Windows' record of programs started from Start, the taskbar, the desktop or Explorer (UserAssist, names in ROT13).
    $rot = { param($s) $c = $s.ToCharArray(); for ($i = 0; $i -lt $c.Length; $i++) { $n = [int]$c[$i]
        if ($n -ge 65 -and $n -le 90) { $c[$i] = [char](65 + ($n - 52) % 26) } elseif ($n -ge 97 -and $n -le 122) { $c[$i] = [char](97 + ($n - 84) % 26) } }; -join $c }
    $folders = @{
        '{6D809377-6AF0-444B-8957-A3773F02200E}' = $env:ProgramFiles; '{905E63B6-C1BF-494E-B29C-65B732D3D21A}' = $env:ProgramFiles
        '{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}' = ${env:ProgramFiles(x86)}; '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' = $env:windir
        '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' = "$env:windir\System32"; '{D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27}' = "$env:windir\SysWOW64"
        '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}' = $env:LOCALAPPDATA; '{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}' = $env:APPDATA
        '{62AB5D82-FDC1-4DC3-A9DD-070D1D495D97}' = $env:ProgramData; '{5E6C858F-0E22-4760-9AFE-EA3317B67173}' = $env:USERPROFILE
        '{374DE290-123F-4565-9164-39C4925E467B}' = "$env:USERPROFILE\Downloads"; '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' = [Environment]::GetFolderPath('Desktop')
    }
    $exeRuns = @(); $lnkRuns = @(); $since = $null
    foreach ($k in Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' -ErrorAction SilentlyContinue) {
        $c = Get-Item "$($k.PSPath)\Count" -ErrorAction SilentlyContinue; if (-not $c) { continue }
        foreach ($n in $c.GetValueNames()) {
            $d = $c.GetValue($n); if ($d -isnot [byte[]] -or $d.Length -lt 68) { continue }
            $ft = [BitConverter]::ToInt64($d, 60); if ($ft -le 0) { continue }
            $when = [DateTime]::FromFileTime($ft); if ($when.Year -lt 2005) { continue }
            if (-not $since -or $when -lt $since) { $since = $when }
            $name = & $rot $n
            if ($name -match '^(\{[0-9A-Fa-f-]{36}\})\\(.*)$' -and $folders[$Matches[1].ToUpper()]) { $name = Join-Path $folders[$Matches[1].ToUpper()] $Matches[2] }
            if ($name -match '\.lnk$') { $lnkRuns += [pscustomobject]@{ Key = (([IO.Path]::GetFileNameWithoutExtension($name)).ToLower() -replace '\(.*?\)', '' -replace '[^a-z0-9]', ''); When = $when } }
            elseif ($name -match '\.exe$') { $exeRuns += [pscustomobject]@{ Path = $name.ToLower(); When = $when } }
        }
    }
    $running = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { try { "$($_.Path)".ToLower() } catch { } } | Where-Object { $_ })
    $support = 'Redistributable|Runtime|\.NET|Driver|SDK|Framework|Visual C\+\+|WebView2|Java\b|Update Health|Add-in|Plug-?in|Codec|Bonjour|Help Viewer|Language Pack|Microsoft (Edge|OneDrive|Teams Meeting)'
    $seen = @{}; $rows = New-Object System.Collections.ArrayList
    $keys = @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'all users' }, @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'all users' },
              @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'you' })
    foreach ($kk in $keys) {
        foreach ($e in Get-ChildItem $kk.P -ErrorAction SilentlyContinue) {
            $v = Get-ItemProperty $e.PSPath -ErrorAction SilentlyContinue
            $name = "$($v.DisplayName)".Trim()
            if (-not $name -or $v.SystemComponent -eq 1 -or $v.ParentKeyName -or "$($v.ReleaseType)" -match 'Update|Hotfix' -or $name -match '^(Update for|Security Update|Hotfix)' -or -not ($v.UninstallString -or $v.QuietUninstallString)) { continue }
            if ($seen[$name]) { continue }; $seen[$name] = 1
            $loc = "$($v.InstallLocation)".Trim().Trim('"').TrimEnd('\')
            if (-not $loc -and $v.DisplayIcon) { $ic = ("$($v.DisplayIcon)" -replace ',\s*-?\d+$', '').Trim('"'); if ($ic -match '\.exe$' -and $ic -notmatch '\\(System32|SysWOW64|Installer)\\') { $loc = Split-Path $ic -Parent } }
            if ($loc -and ($loc.Length -le 3 -or $loc -match '^[A-Za-z]:\\(Windows|Program Files( \(x86\))?|ProgramData|Users)$')) { $loc = '' }   # never a whole system folder
            $bytes = if ($v.EstimatedSize) { [int64]$v.EstimatedSize * 1KB } else { $null }
            $installed = $null; if ("$($v.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$') { try { $installed = Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3] -Hour 0 -Minute 0 -Second 0 } catch { } }
            $last = $null; $now = $false
            if ($loc) {
                $pre = $loc.ToLower() + '\'
                foreach ($x in $exeRuns) { if ($x.Path.StartsWith($pre) -and (-not $last -or $x.When -gt $last)) { $last = $x.When } }
                if ($running | Where-Object { $_.StartsWith($pre) }) { $now = $true }
            }
            $key = $name.ToLower() -replace '\(.*?\)', '' -replace '[^a-z0-9]', ''
            foreach ($l in $lnkRuns) { if ($l.Key.Length -ge 4 -and ($key.StartsWith($l.Key) -or $l.Key.StartsWith($key)) -and (-not $last -or $l.When -gt $last)) { $last = $l.When } }
            [void]$rows.Add([pscustomobject]@{ Name = $name; Publisher = "$($v.Publisher)".Trim(); Version = "$($v.DisplayVersion)"; Bytes = $bytes; Installed = $installed; Last = $last; Now = $now
                Location = $loc; Uninstall = "$($v.UninstallString)"; Quiet = "$($v.QuietUninstallString)"; Key = $e.PSPath; Scope = $kk.Scope
                Support = ($name -match $support); Keep = (("$name $($v.Publisher)" -match $cfg.Keep) -or ($cfg.UserKeep -and "$name $($v.Publisher)" -match $cfg.UserKeep)) })
        }
    }
    # Programs started through a launcher (games via Steam or their own launcher) never show up in UserAssist, but they write
    # logs and settings into their own folder when they run - so a recent change there also counts as use.
    $busy = [Diagnostics.Stopwatch]::StartNew()
    foreach ($r in $rows | Where-Object { $_.Location -and -not $_.Now }) {
        if ($busy.Elapsed.TotalSeconds -gt 15) { break }
        try {
            $root = [IO.DirectoryInfo]::new($r.Location); if (-not $root.Exists) { continue }
            $newest = $null
            foreach ($d in @($root) + @($root.EnumerateDirectories() | Select-Object -First 40)) {
                foreach ($fi in $d.EnumerateFiles()) { if (-not $newest -or $fi.LastWriteTime -gt $newest) { $newest = $fi.LastWriteTime } }
            }
            if ($newest -and $newest -le (Get-Date) -and (-not $r.Last -or $newest -gt $r.Last)) { $r.Last = $newest }
        } catch { }
    }
    # Folder size for programs that don't report one (capped, so a huge folder can't stall the list)
    $budget = [Diagnostics.Stopwatch]::StartNew()
    foreach ($r in $rows | Where-Object { -not $_.Bytes -and $_.Location }) {
        if ($budget.Elapsed.TotalSeconds -gt 25 -or (Test-Cancelled)) { break }
        Set-JobProgress "measuring $($r.Name)"
        $sum = 0; $sw = [Diagnostics.Stopwatch]::StartNew()
        foreach ($f in Get-FilesSafe $r.Location) { $sum += $f.Length; if ($sw.Elapsed.TotalSeconds -gt 2) { break } }
        if ($sum) { $r.Bytes = $sum }
    }
    [pscustomobject]@{ Rows = $rows; Since = $since; Tracking = ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction SilentlyContinue).Start_TrackProgs -ne 0) }
}
$script:ProgSort = 'size'
function Show-Programs {
    $p = $script:ProgData; if (-not $p) { return }
    $old = (Get-Date).AddDays(-180)
    $perLoc = @{}; foreach ($x in $p.Rows) { if ($x.Location) { $perLoc[$x.Location] = 1 + [int]$perLoc[$x.Location] } }
    $isPack = { param($r) $r.Location -and $perLoc[$r.Location] -gt 1 -and $r.Name -match ' - [a-z]{2}-[a-z]{2}$' }
    $sorted = switch ($script:ProgSort) {
        'size' { $p.Rows | Sort-Object { if ($_.Bytes -and -not (& $isPack $_)) { $_.Bytes } else { 0 } } -Descending }
        'used' { $p.Rows | Sort-Object { if ($_.Now) { [datetime]::MaxValue } elseif ($_.Last) { $_.Last } else { [datetime]::MinValue } }, Name }
        default { $p.Rows | Sort-Object Name }
    }
    $lvProg.BeginUpdate(); $lvProg.Items.Clear()
    $unused = 0
    foreach ($r in $sorted) {
        $usedTxt = if ($r.Now) { 'now (running)' } elseif ($r.Last) { $r.Last.ToString('d') } else { 'no record' }
        $pack = & $isPack $r
        $note = if ($r.Keep) { 'on the keep list' } elseif ($pack) { 'language pack - shares its files (and size) with the main program' } elseif ($r.Support) { 'used by other programs - keep' }
                elseif ($r.Last -and $r.Last -lt $old -and -not $r.Now) { $unused++; "no sign of use for $([int]((Get-Date) - $r.Last).TotalDays) days" }
                elseif (-not $r.Last -and -not $r.Now -and $r.Installed -and $r.Installed -lt $old -and $p.Since -and $p.Since -lt $old) { 'never opened from Start or the desktop (may run in the background)' }
                else { '' }
        $it = Add-Row $lvProg @($r.Name, $r.Publisher, $(if ($pack) { 'shared' } elseif ($r.Bytes) { Format-Size $r.Bytes } else { '' }), $(if ($r.Installed) { $r.Installed.ToString('d') } else { '' }), $usedTxt, $note) $r
        $it.ForeColor = if ($note -like 'no sign of use*') { $Theme.Warn } elseif ($r.Keep -or $r.Support -or $pack) { $Theme.Muted } else { $Theme.Text }
    }
    $lvProg.EndUpdate()
    # Count each folder once: language packs share one folder, and games sit inside their launcher's folder (Steam).
    $sized = @($p.Rows | Where-Object Bytes | Group-Object { "$($_.Location)|$($_.Bytes)" } | ForEach-Object { $_.Group[0] })
    $locs = @($sized | Where-Object Location | ForEach-Object { $_.Location.ToLower() + '\' })
    $total = (@($sized | Where-Object { $l = "$($_.Location)".ToLower(); -not $l -or -not ($locs | Where-Object { $l.StartsWith($_) -and $l + '\' -ne $_ }) }) | Measure-Object Bytes -Sum).Sum
    $lblProg.Text = "$(@($p.Rows).Count) programs, $(Format-Size $total) in total. $unused with no sign of use for 6 months or more." +
        $(if (-not $p.Tracking) { '  (Windows is set not to record program use: Settings > Privacy > General.)' } elseif ($p.Since) { "  Use is recorded since $($p.Since.ToString('d'))." })
}
function Update-Programs {
    $btnProgReload.Enabled = $false
    $lblProg.Text = 'Reading installed programs...'
    Start-Bg -Label 'Reading installed programs' -Cancellable $ProgramsWork @{ Keep = $KeepBuiltIn; UserKeep = (Get-UserKeep) } {
        param($r)
        $btnProgReload.Enabled = $true
        $script:ProgData = @($r)[0]
        Show-Programs
    }
}
$btnProgSort.Add_Click({
    $script:ProgSort = switch ($script:ProgSort) { 'size' { 'used' } 'used' { 'name' } default { 'size' } }
    $btnProgSort.Text = switch ($script:ProgSort) { 'size' { 'Sort: size' } 'used' { 'Sort: last used' } default { 'Sort: name' } }
    Show-Programs
})
$btnProgSet.Add_Click({ Start-Process 'ms-settings:appsfeatures' })
$btnProgReload.Add_Click({ Update-Programs })
# Uninstallers run one after another (each may show its own window); then leftovers go to the Recycle Bin.
$UninstallWork = {
    param($list)
    $i = 0
    foreach ($p in $list) {
        $i++; if (Test-Cancelled) { break }
        Set-JobProgress "uninstalling $($p.Name)" $i $list.Count
        $cmd = if ($p.Quiet) { $p.Quiet } else { $p.Uninstall }
        if ($cmd -match '(?i)msiexec(\.exe)?\s+/[IX]\s*(\{[0-9A-F-]{36}\})') { $cmd = "MsiExec.exe /X$($Matches[2])" }   # /I would "repair" instead
        $code = $null
        try { $code = (Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -Wait -PassThru -WindowStyle Hidden).ExitCode } catch { }
        $gone = -not (Test-Path -LiteralPath $p.Key)
        $left = @()
        if ($gone) {
            Start-Sleep -Seconds 2
            $cands = @($p.Location) + @(foreach ($base in $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData) {
                Join-Path $base $p.Name; if ($p.Publisher) { Join-Path (Join-Path $base $p.Publisher) $p.Name } })
            $left = @($cands | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique)
        }
        [pscustomobject]@{ Name = $p.Name; Gone = $gone; Code = $code; Left = $left }
    }
}
$btnProgUn.Add_Click({
    $picked = @($lvProg.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $picked) { Show-Msg 'Check one or more programs first.' | Out-Null; return }
    $warn = @($picked | Where-Object { $_.Keep -or $_.Support })
    $msg = "Uninstall these programs?`n`n$(($picked | ForEach-Object { " - $($_.Name)" }) -join "`n")"
    if ($warn) { $msg += "`n`nCareful - other programs may need: $(($warn | ForEach-Object Name) -join ', ')" }
    $msg += "`n`nEach program's own uninstaller runs, one after another; some show a window or ask for administrator rights."
    if ((Show-Msg $msg 'YesNo' 'Question') -ne 'Yes') { return }
    $btnProgUn.Enabled = $false
    $script:ProgPicked = $picked
    Start-WithRestorePoint 'uninstalling programs' { Start-Bg -Label 'Uninstalling programs' -Cancellable $UninstallWork $script:ProgPicked {
        param($res)
        $btnProgUn.Enabled = $true
        $ok = @($res | Where-Object Gone); $failed = @($res | Where-Object { -not $_.Gone })
        foreach ($r in $ok) { Add-History 'Uninstall' $r.Name 'uninstalled' }
        $left = @($ok | ForEach-Object { $_.Left } | Where-Object { $_ })
        $msg = "$($ok.Count) program(s) uninstalled."
        if ($failed) { $msg += "`n`nStill installed (cancelled, or the uninstaller failed): $(($failed | ForEach-Object Name) -join ', ')" }
        Show-Msg $msg | Out-Null
        if ($left -and (Show-Msg "These leftover folders are still there:`n`n$($left -join "`n")`n`nMove them to the Recycle Bin?" 'YesNo' 'Question') -eq 'Yes') {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $n = 0; $bad = @()
            foreach ($d in $left) {
                try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($d, 'OnlyErrorDialogs', 'SendToRecycleBin'); $n++; Add-History 'Clean' $d 'leftover folder moved to the Recycle Bin' } catch { $bad += $d }
            }
            if ($bad) { Show-Msg "$n folder(s) moved to the Recycle Bin. Couldn't move (in use, or needs administrator): $($bad -join ', ')" | Out-Null }
        }
        Update-History; Update-Programs
        if ($script:Loaded['Bloatware']) { Start-BloatScan }
    } }
})

# ===========================================================================
# Network: Wi-Fi signal, delays, DNS speed, dropped connections, and a reset
# ===========================================================================
$pgNet = New-Page 'Network' 'Wi-Fi signal and speed, delays to the router and the internet, how fast names are looked up (DNS), and how often the connection dropped in the last 30 days.'
$btnNetScan = New-Button 'Check again'
$btnNetDns = New-Button 'Flush DNS cache'
$btnNetReset = New-Button 'Reset network'
$btnNetWifi = New-Button 'Wi-Fi settings'
$btnNetTrouble = New-Button 'Network troubleshooter'
$lvNet = New-ListView $false @('Check', 200, 'Status', 80, 'Result', 380, 'What to do', 520)
$txtNet = New-DetailBox 104
Set-PageLayout $pgNet $lvNet @((New-ButtonBar @($btnNetScan, $btnNetDns, $btnNetReset, $btnNetWifi, $btnNetTrouble))) $txtNet
$NetworkWork = {
    $rows = New-Object System.Collections.ArrayList
    function Add-N($Check, $Level, $Result, $Todo) { [void]$rows.Add([pscustomobject]@{ Check = $Check; Level = $Level; Result = $Result; Todo = $Todo }) }
    # Pings without the one-second pause of Test-Connection
    $ping = { param($ip, $n, $gapMs = 0)
        $p = New-Object Net.NetworkInformation.Ping; $ok = @()
        for ($i = 0; $i -lt $n; $i++) { try { $r = $p.Send($ip, 1000); if ($r.Status -eq 'Success') { $ok += [int]$r.RoundtripTime } } catch { }; if ($gapMs) { Start-Sleep -Milliseconds $gapMs } }
        $p.Dispose()
        [pscustomobject]@{ Loss = [int](100 * ($n - $ok.Count) / $n); Avg = $(if ($ok) { [int]($ok | Measure-Object -Average).Average }); Max = $(if ($ok) { ($ok | Measure-Object -Maximum).Maximum }) }
    }
    Set-JobProgress 'connection'
    $up = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    $vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and "$($_.InterfaceDescription) $($_.Name)" -match 'VPN|WireGuard|TAP-|OpenVPN|NordLynx|Tunnel|Fortinet|Cisco AnyConnect|GlobalProtect|Zscaler|Tailscale' })
    if (-not $up) { Add-N 'Connection' 'Problem' 'Not connected' 'Plug in the network cable or connect to Wi-Fi (the network icon at the bottom right).' }
    foreach ($a in $up) {
        $wifi = $a.MediaType -match '802\.11|Wireless' -or $a.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN'
        Add-N 'Connection' 'OK' "$(if ($wifi) { 'Wi-Fi' } else { 'Cable (Ethernet)' }): $($a.InterfaceDescription), $($a.LinkSpeed)" 'Nothing to do.'
    }
    if ($vpn) { Add-N 'VPN' 'Info' "On: $(($vpn | ForEach-Object InterfaceDescription) -join ', ')" 'Everything below goes through the VPN, so delays are higher than without it. That is normal.' }
    # Wi-Fi details (netsh prints English or Dutch labels)
    $w = @{}
    foreach ($l in (& "$env:windir\System32\netsh.exe" wlan show interfaces 2>$null)) {
        if ($l -match '^\s+(.+?)\s+:\s(.*)$') {
            $k = $Matches[1].Trim(); $v = $Matches[2].Trim()
            switch -Regex ($k) {
                '^SSID$' { $w.Ssid = $v } '^(Signal|Signaal)$' { $w.Signal = [int]($v -replace '\D', '') } '^(Band|Bande)$' { $w.Band = $v }
                '^(Channel|Kanaal|Kanal|Canal)$' { $w.Channel = $v } '^(Receive rate|Ontvangstsnelheid|Empfangsrate|D.bit de r.ception|R.ception)' { $w.Rx = $v } '^(Radio type|Radiotype|Funktyp|Type de radio)$' { $w.Radio = $v }
                '^(Description|Beschrijving)$' { $w.Card = $v }
            }
        }
    }
    if ($w.Ssid -and $null -ne $w.Signal) {
        $lvl = if ($w.Signal -ge 60) { 'OK' } elseif ($w.Signal -ge 40) { 'Warning' } else { 'Problem' }
        Add-N 'Wi-Fi signal' $lvl "$($w.Signal)% on ""$($w.Ssid)""$(if ($w.Rx) { ", $($w.Rx) Mbps" })$(if ($w.Radio) { ", $($w.Radio)" })" `
            $(if ($lvl -eq 'OK') { 'Nothing to do.' } else { 'Weak signal: move closer to the router, put the router higher and out in the open, or add a mesh point or repeater. Walls and floors weaken Wi-Fi a lot.' })
        if ($w.Band -match '^2\.4' -and "$($w.Card)" -match 'AX|AC|6E|Wi-?Fi 6|Wi-?Fi 7|BE\d|Dual') {
            Add-N 'Wi-Fi band' 'Info' "2.4 GHz (channel $($w.Channel))" 'This Wi-Fi card can use 5 GHz (faster, less crowded). If the router offers a separate 5 GHz network, connect to that one - or turn on "band steering" in the router.'
        }
    }
    # Delays: router, then the internet
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1).NextHop
    $g = $null
    if ($gw -and $gw -ne '0.0.0.0') { Set-JobProgress 'router'; $g = & $ping $gw 20 150 }
    Set-JobProgress 'internet'
    $i = & $ping '1.1.1.1' 20 150
    if ($g) {
        # Many routers answer only some pings on purpose; lost router pings only matter if the internet loses packets too.
        $loss = if ($i.Loss -eq 0) { 0 } else { $g.Loss }
        $lvl = if ($null -eq $g.Avg) { 'Info' } elseif ($loss -ge 10 -or $g.Avg -gt 30) { 'Problem' } elseif ($loss -gt 0 -or $g.Max -gt 100) { 'Warning' } else { 'OK' }
        Add-N 'Router' $lvl "$(if ($null -ne $g.Avg) { "$($g.Avg) ms on average, worst $($g.Max) ms" } else { 'does not answer pings' })$(if ($loss) { ", $loss% lost" })" `
            $(switch ($lvl) { 'OK' { 'Nothing to do.' } 'Info' { 'Some routers never answer pings - fine if the internet line is OK.' } default { 'The problem is between this PC and the router: usually weak or crowded Wi-Fi. Move closer, use 5 GHz or a cable, and restart the router.' } })
    }
    $lvl = if ($i.Loss -ge 10 -or $null -eq $i.Avg) { 'Problem' } elseif ($i.Loss -gt 0 -or $i.Avg -gt 80) { 'Warning' } else { 'OK' }
    Add-N 'Internet' $lvl "$(if ($null -ne $i.Avg) { "$($i.Avg) ms on average, worst $($i.Max) ms" } else { 'no answer' }), $($i.Loss)% lost" `
        $(switch ($lvl) { 'OK' { 'Nothing to do.' } default { 'If the router line above is fine, the delay comes from the internet connection itself: restart the modem/router; if it keeps happening, contact your internet provider.' } })
    # DNS: how fast names are looked up by the current server, compared with two public ones
    Set-JobProgress 'DNS'
    $names = 'wikipedia.org', 'github.com', 'microsoft.com', 'cloudflare.com', 'apple.com'
    $dnsTime = { param($server) $t = @()
        foreach ($n in $names) { $sw = [Diagnostics.Stopwatch]::StartNew(); try { [void](Resolve-DnsName $n -Server $server -DnsOnly -QuickTimeout -ErrorAction Stop); $t += $sw.ElapsedMilliseconds } catch { } }
        if ($t) { [int]($t | Sort-Object | Select-Object -First ([Math]::Max(1, $t.Count - 1)) | Measure-Object -Average).Average } }   # drop the slowest
    $idx = @($up | ForEach-Object ifIndex)
    $mine = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceIndex -in $idx } | ForEach-Object ServerAddresses | Select-Object -Unique)
    if ($mine) {
        $cur = & $dnsTime $mine[0]; $cf = & $dnsTime '1.1.1.1'; $gg = & $dnsTime '8.8.8.8'
        $best = @(@{ N = 'Cloudflare (1.1.1.1)'; T = $cf }, @{ N = 'Google (8.8.8.8)'; T = $gg } | Where-Object { $_.T } | Sort-Object { $_.T })[0]
        if ($null -eq $cur) { Add-N 'DNS' 'Problem' "$($mine[0]) doesn't answer" 'Names can''t be looked up, so websites won''t open. Restart the router, or set DNS to 1.1.1.1 in Settings > Network & internet > (your connection) > DNS server assignment.' }
        else {
            $slow = $best -and $cur -gt 60 -and $cur -gt 2 * $best.T
            Add-N 'DNS' $(if ($slow) { 'Warning' } else { 'OK' }) "$($mine[0]): $cur ms per look-up$(if ($best) { " ($($best.N): $($best.T) ms)" })" `
                $(if ($slow) { "Your DNS server is slow - every new website waits for it. Switching to $($best.N) helps: Settings > Network & internet > (your connection) > DNS server assignment > Edit." } else { 'Nothing to do.' })
        }
    }
    # Dropped Wi-Fi connections in the last 30 days
    $ev = try { @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8003, 8002; StartTime = (Get-Date).AddDays(-30) } -ErrorAction Stop) } catch { @() }
    $drops = @($ev | Where-Object Id -eq 8003).Count; $fails = @($ev | Where-Object Id -eq 8002).Count
    if ($w.Ssid -or $ev) {
        $lvl = if ($drops -ge 30 -or $fails -ge 10) { 'Warning' } else { 'OK' }
        Add-N 'Wi-Fi drops (30 days)' $lvl "$drops disconnect(s), $fails failed connection(s)" `
            $(if ($lvl -eq 'OK') { 'Normal - disconnects also happen at sleep, shutdown and when you move between networks.' } else { 'More than normal. Update the Wi-Fi driver (Drivers page), turn off "Allow the computer to turn off this device to save power" for the Wi-Fi card in Device Manager, and restart the router.' })
    }
    # Errors on the network card itself
    foreach ($s in Get-NetAdapterStatistics -ErrorAction SilentlyContinue | Where-Object { $_.Name -in ($up | ForEach-Object Name) }) {
        $pk = [double]$s.ReceivedUnicastPackets + $s.SentUnicastPackets; $er = [double]$s.ReceivedPacketErrors + $s.OutboundPacketErrors
        if ($pk -gt 10000 -and $er / $pk -gt 0.001) { Add-N "Errors on $($s.Name)" 'Warning' ('{0:N0} damaged packets ({1:P2})' -f $er, ($er / $pk)) 'Usually a bad cable or a failing port. Try another cable or port; for Wi-Fi, update the driver.' }
    }
    $rows
}
function Update-Network {
    $btnNetScan.Enabled = $false
    $txtNet.Text = 'Checking the network (about 15 seconds)...'
    Start-Bg -Label 'Checking the network' $NetworkWork $null {
        param($rows)
        $btnNetScan.Enabled = $true
        $lvNet.BeginUpdate(); $lvNet.Items.Clear()
        foreach ($r in $rows | Sort-Object { $SecLevels[$_.Level] }) {
            $it = Add-Row $lvNet @($r.Check, $r.Level, $r.Result, $r.Todo) $r
            Set-RowStatus $it 1 $(switch ($r.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.Muted } })
        }
        $lvNet.EndUpdate()
        $script:NetProblems = @($rows | Where-Object Level -eq 'Problem').Count
        $bad = @($rows | Where-Object { $_.Level -in 'Problem', 'Warning' })
        if ($bad) { $script:ExtraAdvice['Network'] = "Network: $(($bad | ForEach-Object Check) -join ', ') - see the Network page." } else { $script:ExtraAdvice.Remove('Network') }
        if ($lvNet.Items.Count) { $lvNet.Items[0].Selected = $true }
        Update-Health -Quick
    }
}
$lvNet.Add_SelectedIndexChanged({
    if (-not $lvNet.SelectedItems.Count) { return }
    $r = $lvNet.SelectedItems[0].Tag
    $txtNet.Text = "$($r.Check): $($r.Result)`r`n`r`nWhat to do: $($r.Todo)"
})
$btnNetScan.Add_Click({ Update-Network })
$btnNetDns.Add_Click({
    try { Clear-DnsClientCache -ErrorAction Stop } catch { [void](& "$env:windir\System32\ipconfig.exe" /flushdns) }
    Add-History 'Network' 'DNS cache' 'flushed'; Update-History
    Show-Msg 'DNS cache flushed. Websites that wouldn''t open because of an old address should work now.' | Out-Null
})
$btnNetReset.Add_Click({
    if (-not $IsAdmin) { Show-Msg 'Resetting the network needs administrator rights - click "Restart as admin" first. (Or: Settings > Network & internet > Advanced network settings > Network reset.)' 'OK' 'Warning' | Out-Null; return }
    if ((Show-Msg "Reset the network?`n`nThis resets Windows' network settings (Winsock and TCP/IP) to factory state and clears the DNS cache - the standard fix when nothing connects although the router works. Wi-Fi passwords and VPN apps stay, but a manually set IP address or DNS server is cleared.`n`nThe PC needs a restart afterwards." 'YesNo' 'Question') -ne 'Yes') { return }
    Start-WithRestorePoint 'resetting the network' {
        Start-Bg -Label 'Resetting the network' {
            $out = @()
            foreach ($a in 'winsock reset', 'int ip reset', 'int ipv6 reset') { $r = Invoke-Native "$env:windir\System32\netsh.exe" $a 120; $out += "netsh $a`: exit $($r.Code)" }
            [void](Invoke-Native "$env:windir\System32\ipconfig.exe" '/flushdns' 60)
            $out -join '; '
        } $null {
            param($r)
            Add-History 'Network' 'Winsock and TCP/IP' "reset ($(@($r)[0]))"; Update-History
            if ((Show-Msg 'The network has been reset. Restart the PC now to finish?' 'YesNo' 'Question') -eq 'Yes') { Restart-Computer -Force }
        }
    }
})
$btnNetWifi.Add_Click({ Start-Process 'ms-settings:network-wifi' })
$btnNetTrouble.Add_Click({ Start-Process 'ms-settings:troubleshoot' })

# ===========================================================================
# Right-click: entries that programs add to Explorer's right-click menu
# ===========================================================================
$pgCtx = New-Page 'Right-click' 'Entries other programs add to Explorer''s right-click menu (under "Show more options" on Windows 11). Leftovers of removed programs are pre-checked. Hiding an entry can be undone from History or with "Show checked".'
$btnCtxHide = New-Button 'Hide checked'
$btnCtxShow = New-Button 'Show checked'
$btnCtxReload = New-Button 'Reload'
$lvCtx = New-ListView $true @('Entry', 260, 'Shown on', 170, 'Made by', 170, 'State', 80, 'Details', 460)
$lblCtx = New-Status
Set-PageLayout $pgCtx $lvCtx @((New-ButtonBar @($btnCtxHide, $btnCtxShow, $btnCtxReload))) $lblCtx
$ContextWork = {
    $where = [ordered]@{ '*' = 'files'; 'AllFilesystemObjects' = 'files and folders'; 'Directory' = 'folders'; 'Directory\Background' = 'folder background'
                         'Folder' = 'folders'; 'Drive' = 'drives'; 'DesktopBackground' = 'desktop' }
    $builtin = '^(open|opennewwindow|opennewtab|opennewprocess|find|explore|print|printto|runas|runasuser|edit|properties|openas|pintohome|cmd|powershell|wsl|Windows\.\w+|UpdateEncryptionSettings\w*|AnyCode|Play|Enqueue|Shuffle)$'
    $blocked = @{}
    foreach ($h in 'HKLM', 'HKCU') { $k = Get-Item "${h}:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -ErrorAction SilentlyContinue; if ($k) { foreach ($n in $k.GetValueNames()) { $blocked[$n.ToUpper()] = $h } } }
    $fileOf = { param($cmd) $c = [Environment]::ExpandEnvironmentVariables("$cmd").Trim()
        if ($c -match '^"([^"]+)"') { $Matches[1] } elseif ($c -match '^(.+?\.(exe|dll|cmd|bat))\b') { $Matches[1] } else { ($c -split '\s')[0] } }
    $maker = { param($f) if ($f -and (Test-Path -LiteralPath $f -ErrorAction SilentlyContinue)) { try { "$([Diagnostics.FileVersionInfo]::GetVersionInfo($f).CompanyName)".Trim() } catch { '' } } }
    $dllOf = { param($clsid) foreach ($h in 'HKCU:\Software\Classes', 'HKLM:\SOFTWARE\Classes') { $d = (Get-ItemProperty "$h\CLSID\$clsid\InprocServer32" -ErrorAction SilentlyContinue).'(default)'; if ($d) { return [Environment]::ExpandEnvironmentVariables($d) } } }
    $nameOf = { param($clsid) foreach ($h in 'HKCU:\Software\Classes', 'HKLM:\SOFTWARE\Classes') { $n = (Get-ItemProperty "$h\CLSID\$clsid" -ErrorAction SilentlyContinue).'(default)'; if ($n) { return $n } } }
    $rows = @{}
    foreach ($root in 'HKCU:\Software\Classes', 'HKLM:\SOFTWARE\Classes') {
        $hive = if ($root -like 'HKCU*') { 'HKCU' } else { 'HKLM' }
        foreach ($loc in $where.Keys) {
            # Plain menu entries (verbs): hidden with a LegacyDisable value, which works per user too.
            foreach ($v in Get-ChildItem -LiteralPath "$root\$loc\shell" -ErrorAction SilentlyContinue) {
                $verb = $v.PSChildName
                if ($verb -match $builtin) { continue }
                $cmd = (Get-ItemProperty -LiteralPath "$($v.PSPath)\command" -ErrorAction SilentlyContinue).'(default)'
                $file = if ($cmd) { & $fileOf $cmd } else { $clsid = (Get-ItemProperty -LiteralPath $v.PSPath -ErrorAction SilentlyContinue).ExplorerCommandHandler; if ($clsid) { & $dllOf $clsid } }
                if (-not $file) { continue }
                $co = & $maker $file
                if ($co -match '^Microsoft' -and $file -match '\\Windows\\') { continue }
                $label = "$((Get-ItemProperty -LiteralPath $v.PSPath -ErrorAction SilentlyContinue).MUIVerb)"; if (-not $label -or $label -match '^@') { $label = "$((Get-ItemProperty -LiteralPath $v.PSPath -ErrorAction SilentlyContinue).'(default)')" }
                if (-not $label -or $label -match '^@') { $label = $verb }
                $id = "verb|$loc|$verb"
                $missing = -not (Test-Path -LiteralPath $file -ErrorAction SilentlyContinue)
                $hidden = $null -ne (Get-ItemProperty -LiteralPath $v.PSPath -ErrorAction SilentlyContinue).LegacyDisable -or (Get-ItemProperty -LiteralPath "HKCU:\Software\Classes\$loc\shell\$verb" -ErrorAction SilentlyContinue).LegacyDisable -ne $null
                if (-not $rows[$id]) {
                    $rows[$id] = [pscustomobject]@{ Name = ($label -replace '&', ''); Where = @($where[$loc]); Maker = $co; Missing = $missing; Hidden = $hidden; File = $file
                                                    Kind = 'verb'; Loc = $loc; Verb = $verb; Clsid = $null; Hive = $hive }
                }
            }
            # Shell extensions (DLLs): hidden by putting their ID on Windows' "Blocked" list for this user.
            foreach ($h in Get-ChildItem -LiteralPath "$root\$loc\shellex\ContextMenuHandlers" -ErrorAction SilentlyContinue) {
                $clsid = "$((Get-ItemProperty -LiteralPath $h.PSPath -ErrorAction SilentlyContinue).'(default)')"
                if ($clsid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { $clsid = $h.PSChildName }
                if ($clsid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { continue }
                $id = "ext|$($clsid.ToUpper())"
                if ($rows[$id]) { if ($rows[$id].Where -notcontains $where[$loc]) { $rows[$id].Where += $where[$loc] }; continue }
                $dll = & $dllOf $clsid
                $co = & $maker $dll
                if ($dll -and $co -match '^Microsoft' -and $dll -match '\\Windows\\') { continue }
                $name = $h.PSChildName -replace '^\s+', ''
                if ($name -match '^\{') { $n2 = & $nameOf $clsid; if ($n2) { $name = $n2 } }
                if ($name -match '^\{' -and $dll -and (Test-Path -LiteralPath $dll)) { $n3 = try { [Diagnostics.FileVersionInfo]::GetVersionInfo($dll).FileDescription } catch { }; if ($n3) { $name = $n3 } elseif ($co) { $name = $co } }
                $rows[$id] = [pscustomobject]@{ Name = $name; Where = @($where[$loc]); Maker = $co; Missing = (-not $dll -or -not (Test-Path -LiteralPath $dll -ErrorAction SilentlyContinue))
                                                Hidden = [bool]$blocked[$clsid.ToUpper()]; File = $dll; Kind = 'ext'; Loc = $loc; Verb = $null; Clsid = $clsid.ToUpper(); Hive = $hive }
            }
        }
    }
    $rows.Values
}
function Update-Context {
    $btnCtxReload.Enabled = $false
    $lblCtx.Text = 'Reading the right-click menu...'
    Start-Bg -Label 'Reading the right-click menu' $ContextWork $null {
        param($rows)
        $btnCtxReload.Enabled = $true
        $lvCtx.BeginUpdate(); $lvCtx.Items.Clear()
        foreach ($r in $rows | Sort-Object { -not $_.Missing }, { $_.Hidden }, Name) {
            $state = if ($r.Hidden) { 'Hidden' } else { 'Shown' }
            $detail = if ($r.Missing) { "leftover: the program is gone$(if ($r.File) { " ($($r.File))" })" } else { "$($r.File)" }
            $it = Add-Row $lvCtx @($r.Name, (($r.Where | Select-Object -Unique | ForEach-Object { T $_ }) -join ', '), $(if ($r.Maker) { $r.Maker } else { '?' }), $state, $detail) $r ($r.Missing -and -not $r.Hidden)
            $it.ForeColor = if ($r.Hidden) { $Theme.Muted } elseif ($r.Missing) { $Theme.Bad } else { $Theme.Text }
        }
        $lvCtx.EndUpdate()
        $script:CtxLeftovers = @($rows | Where-Object { $_.Missing -and -not $_.Hidden }).Count
        $lblCtx.Text = "$(@($rows).Count) entries from other programs; $($script:CtxLeftovers) leftover(s) of removed programs (pre-checked)."
        if ($script:NavButtons) { Update-NavBadges }
    }
}
function Set-ContextEntries([bool]$Hide) {
    $picked = @($lvCtx.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { $_.Hidden -ne $Hide })
    if (-not $picked) { Show-Msg $(if ($Hide) { 'Check one or more entries that are shown first.' } else { 'Check one or more hidden entries first.' }) | Out-Null; return }
    $done = 0; $failed = @()
    foreach ($r in $picked) {
        try {
            if ($r.Kind -eq 'verb') {
                # A LegacyDisable value in the user's own copy of the key hides the entry, even when it is installed for all users.
                $key = "HKCU:\Software\Classes\$($r.Loc)\shell\$($r.Verb)"
                $created = -not (Test-Path -LiteralPath $key)
                if ($Hide) { Set-RegValue $key 'LegacyDisable' '' 'String' } else {
                    Remove-ItemProperty -LiteralPath $key -Name LegacyDisable -ErrorAction SilentlyContinue
                    if ($r.Hive -eq 'HKLM') { Remove-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\$($r.Loc)\shell\$($r.Verb)" -Name LegacyDisable -ErrorAction SilentlyContinue }
                }
                Add-History 'Right-click' $r.Name $(if ($Hide) { 'hidden from the menu' } else { 'shown in the menu again' }) @{ Type = 'Reg'; Values = @(@{ P = $key; N = 'LegacyDisable'; Old = $(if ($Hide) { $null } else { '' }); T = 'String'; Created = ($Hide -and $created) }) }
            } else {
                $key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
                if ($Hide) { Set-RegValue $key $r.Clsid $r.Name 'String' } else {
                    Remove-ItemProperty -LiteralPath $key -Name $r.Clsid -ErrorAction SilentlyContinue
                    if ($IsAdmin) { Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name $r.Clsid -ErrorAction SilentlyContinue }
                }
                Add-History 'Right-click' $r.Name $(if ($Hide) { 'hidden from the menu' } else { 'shown in the menu again' }) @{ Type = 'Reg'; Values = @(@{ P = $key; N = $r.Clsid; Old = $(if ($Hide) { $null } else { $r.Name }); T = 'String' }) }
            }
            $done++
        } catch { $failed += "$($r.Name): $($_.Exception.Message)" }
    }
    Update-History; Update-Context
    $msg = "$done entr(y/ies) $(if ($Hide) { 'hidden' } else { 'shown again' }). Undo from the History page."
    if ($failed) { $msg += "`n`nCouldn't change: $($failed -join '; ')" }
    Show-Msg $msg | Out-Null
    if (-not $script:SimpleRun -and (Show-Msg "Restart Explorer now so the menu updates?`n`nOpen File Explorer windows close; nothing else is affected." 'YesNo' 'Question') -eq 'Yes') {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}
$btnCtxHide.Add_Click({ Set-ContextEntries $true })
$btnCtxShow.Add_Click({ Set-ContextEntries $false })
$btnCtxReload.Add_Click({ Update-Context })

# ===========================================================================
# Space savers: big chunks of disk space Windows sets aside by default
# ===========================================================================
$pgSpace = New-Page 'Space savers' 'Big chunks of disk space that Windows keeps by default - each with what you give up. Nothing is checked except Storage Sense; most need administrator rights, and every change except freeing OneDrive copies can be undone from History.'
$btnSpaceApply = New-Button 'Apply checked'
$btnSpaceSense = New-Button 'Storage settings'
$btnSpaceReload = New-Button 'Reload'
$lvSpace = New-ListView $true @('Saver', 260, 'Can free', 100, 'Now', 230, 'What it does - and what you give up', 560)
$txtSpace = New-DetailBox 104
Set-PageLayout $pgSpace $lvSpace @((New-ButtonBar @($btnSpaceApply, $btnSpaceSense, $btnSpaceReload))) $txtSpace
$SenseKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
$SpaceWork = {
    param($cfg)
    $rows = New-Object System.Collections.ArrayList
    function Add-S($Name, $Free, $Now, $What, $Action, $Admin, $Level = 'Info') {
        [void]$rows.Add([pscustomobject]@{ Name = $Name; Free = $Free; Now = $Now; What = $What; Action = $Action; Admin = $Admin; Level = $Level })
    }
    $ram = 0; try { $ram = [double](Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 10).TotalPhysicalMemory } catch { }
    # Hibernation file: about 40% of the memory when "full", 20% when "reduced" (enough for Fast startup).
    $hib = try { [IO.FileInfo]::new('C:\hiberfil.sys') } catch { $null }
    if ($hib -and $hib.Exists -and $hib.Length -gt 0) {
        $full = -not $ram -or $hib.Length -gt 0.3 * $ram
        if ($cfg.Battery -and $full) {
            Add-S 'Hibernation file' ([int64]($hib.Length / 2)) "$([Math]::Round($hib.Length / 1GB, 1)) GB (full size)" `
                'Shrinks C:\hiberfil.sys to half. Fast startup keeps working; the PC can no longer hibernate (sleep still works, but if the battery runs flat while asleep, unsaved work is lost).' 'hibshrink' $true
        } elseif (-not $cfg.Battery) {
            Add-S 'Hibernation file' ([int64]$hib.Length) "$([Math]::Round($hib.Length / 1GB, 1)) GB" `
                'Removes C:\hiberfil.sys. A desktop rarely hibernates; Fast startup is switched off too, so starting takes a few seconds longer.' 'hiboff' $true
        } else { Add-S 'Hibernation file' 0 "$([Math]::Round($hib.Length / 1GB, 1)) GB (already reduced)" 'Already as small as it can be while keeping Fast startup.' $null $false 'OK' }
    }
    # Reserved storage: space Windows keeps free for updates (about 7 GB)
    if ($cfg.Admin) {
        $st = try { "$((Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState)" } catch { '' }
        if ($st -eq 'Enabled') { Add-S 'Reserved storage' ([int64]7GB) 'on (about 7 GB)' 'Windows keeps about 7 GB free for updates. Switching it off gives you that space; on a nearly full drive an update may then fail until you free space.' 'reserved' $true }
        elseif ($st) { Add-S 'Reserved storage' 0 "$($st.ToLower())" 'Nothing to free.' $null $true 'OK' }
    } else { Add-S 'Reserved storage' ([int64]7GB) 'only visible as administrator' 'Windows keeps about 7 GB free for updates. Click "Restart as admin" to check and change it.' 'reserved' $true }
    # Compressing Windows' own files (Compact OS)
    $q = (& "$env:windir\System32\compact.exe" /compactos:query 2>&1 | Out-String).Trim() -replace '\s+', ' '
    if ($q -and $q -notmatch '(?i)\bis in the compact state|bevindt zich in de compacte') {
        $cw = $(if ($q -match '(?i)not beneficial|niet .*(nuttig|voordelig|zinvol)') { 'Windows says this isn''t worth it on this PC (see "Now"), so it is not counted in the total. ' }) + 'Compresses Windows'' own files (Compact OS), about 2-4 GB; on a fast PC the slowdown is barely noticeable. Takes 10-20 minutes.'
        Add-S 'Compress Windows files' ([int64]2.5GB) $(if ($q.Length -gt 90) { $q.Substring(0, 90) + '...' } else { $q }) $cw 'compact' $true $(if ($q -match '(?i)not beneficial|niet .*(nuttig|voordelig|zinvol)') { 'NotAdvised' } else { 'Info' })
    }
    # OneDrive: copies of cloud files kept on this PC
    foreach ($a in Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue) {
        $root = (Get-ItemProperty $a.PSPath -ErrorAction SilentlyContinue).UserFolder
        if (-not $root -or -not (Test-Path $root)) { continue }
        $bytes = 0; $n = 0; $sw = [Diagnostics.Stopwatch]::StartNew()
        foreach ($path in [IO.Directory]::EnumerateFiles($root, '*', 'AllDirectories')) {   # OneDrive's own folders are cloud placeholders, not junctions, so walking them is safe
            $f = [IO.FileInfo]$path
            if ($sw.Elapsed.TotalSeconds -gt 20) { break }
            $at = [int]$f.Attributes
            if (($at -band 0x400000) -or ($at -band 0x1000) -or ($at -band 0x80000)) { continue }   # already online-only, or "always keep on this device"
            $bytes += $f.Length; $n++
        }
        if ($bytes -gt 100MB) {
            Add-S "OneDrive copies ($(Split-Path $root -Leaf))" ([int64]$bytes) "$n file(s) kept on this PC" `
                'Removes the copies on this PC; the files stay in OneDrive with a cloud icon and download again when you open them (you need internet for that). Files set to "Always keep on this device" stay.' "onedrive|$root" $false
        }
    }
    # Storage Sense: Windows' own automatic clean-up
    $sense = (Get-ItemProperty $cfg.SenseKey -ErrorAction SilentlyContinue).'01'
    if ($sense -eq 1) { Add-S 'Storage Sense' 0 'on' 'Windows already cleans temporary files and old Recycle Bin items by itself.' $null $false 'OK' }
    else { Add-S 'Storage Sense' 0 'off' 'Turns on Windows'' own automatic clean-up: every week it removes temporary files and Recycle Bin items older than 30 days. Your own files are not touched.' 'sense' $false 'Recommended' }
    # Explained, but best left alone
    $pf = try { [IO.FileInfo]::new('C:\pagefile.sys') } catch { $null }
    if ($pf -and $pf.Exists) {
        Add-S 'Paging file' 0 "$([Math]::Round($pf.Length / 1GB, 1)) GB" "Windows' overflow for memory. Leave it to Windows - shrinking it can make programs crash when memory fills up. If it is large, more memory is the real fix (see the Upgrades page)." $null $false 'OK'
    }
    $langs = @(try { (Get-WinUserLanguageList).LanguageTag } catch { })
    if ($langs.Count -gt 1) { Add-S 'Extra Windows languages' 0 ($langs -join ', ') 'Each extra language with its speech and handwriting add-ons takes a few hundred MB. Remove ones you don''t use in Settings > Time & language > Language & region.' $null $false 'OK' }
    $rows
}
function Update-Space {
    $btnSpaceReload.Enabled = $false
    $txtSpace.Text = 'Checking...'
    Start-Bg -Label 'Looking for space savers' $SpaceWork @{ Admin = $IsAdmin; Battery = $HasBattery; SenseKey = $SenseKey } {
        param($rows)
        $btnSpaceReload.Enabled = $true
        $lvSpace.BeginUpdate(); $lvSpace.Items.Clear()
        foreach ($r in $rows | Sort-Object { -not $_.Action }, { - $_.Free }) {
            $free = if ($r.Free -gt 0) { Format-Size $r.Free } elseif ($r.Action -eq 'sense') { 'ongoing' } else { '' }
            $it = Add-Row $lvSpace @($r.Name, $free, $r.Now, $r.What) $r ($r.Action -eq 'sense')
            $it.ForeColor = if (-not $r.Action) { $Theme.Muted } elseif ($r.Admin -and -not $IsAdmin) { $Theme.Muted } else { $Theme.Text }
        }
        $lvSpace.EndUpdate()
        $script:SpaceFree = (@($rows | Where-Object { $_.Action -and $_.Free -gt 0 -and $_.Level -ne 'NotAdvised' -and -not ($_.Admin -and -not $IsAdmin -and $_.Action -eq 'reserved') }) | Measure-Object Free -Sum).Sum
        if ($lvSpace.Items.Count) { $lvSpace.Items[0].Selected = $true }
        if ($script:NavButtons) { Update-NavBadges }
    }
}
$lvSpace.Add_SelectedIndexChanged({
    if (-not $lvSpace.SelectedItems.Count) { return }
    $r = $lvSpace.SelectedItems[0].Tag
    $txtSpace.Text = "$($r.Name): $($r.Now)`r`n`r`n$($r.What)$(if ($r.Action -and $r.Admin -and -not $IsAdmin) { ""`r`n`r`nNeeds administrator rights - click 'Restart as admin'."" })"
})
# Longer jobs run in the background; Storage Sense is just a setting.
$SpaceApplyWork = {
    param($list)
    foreach ($a in $list) {
        Set-JobProgress $a.Name
        $ok = $true; $msg = ''
        try {
            switch -Regex ($a.Action) {
                '^hibshrink$' { $r = Invoke-Native "$env:windir\System32\powercfg.exe" '/hibernate /type reduced' 60; $ok = $r.Code -eq 0; $msg = $r.Out.Trim() }
                '^hiboff$' { $r = Invoke-Native "$env:windir\System32\powercfg.exe" '/hibernate off' 60; $ok = $r.Code -eq 0; $msg = $r.Out.Trim() }
                '^reserved$' { Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop | Out-Null }
                '^compact$' { $r = Invoke-Native "$env:windir\System32\compact.exe" '/compactos:always' 3600; $ok = $r.Code -eq 0 }
                '^onedrive\|(.+)$' {
                    $root = $Matches[1]; $n = 0
                    foreach ($path in [IO.Directory]::EnumerateFiles($root, '*', 'AllDirectories')) {
                        $f = [IO.FileInfo]$path; $at = [int]$f.Attributes
                        if (($at -band 0x400000) -or ($at -band 0x1000) -or ($at -band 0x80000)) { continue }
                        try { $f.Attributes = [Enum]::ToObject([IO.FileAttributes], ($at -bor 0x100000)); $n++ } catch { }   # "unpinned": OneDrive frees the local copy
                    }
                    $msg = "$n file(s)"
                }
            }
        } catch { $ok = $false; $msg = $_.Exception.Message }
        [pscustomobject]@{ Action = $a.Action; Name = $a.Name; Ok = $ok; Msg = $msg; Free = $a.Free }
    }
}
$btnSpaceApply.Add_Click({
    $picked = @($lvSpace.CheckedItems | ForEach-Object { $_.Tag } | Where-Object Action)
    if (-not $picked) { Show-Msg 'Check one or more savers first (grey rows are only information).' | Out-Null; return }
    $locked = @($picked | Where-Object { $_.Admin -and -not $IsAdmin })
    if ($locked) { Show-Msg "These need administrator rights - click ""Restart as admin"" first: $(($locked | ForEach-Object Name) -join ', ')" 'OK' 'Warning' | Out-Null; return }
    if ((Show-Msg "Apply these space savers?`n`n$(($picked | ForEach-Object { " - $($_.Name)" }) -join "`n")`n`nSee the right-hand column for what each one gives up.$(if ($picked | Where-Object Action -eq 'compact') { "`n`nCompressing Windows files takes 10-20 minutes." })" 'YesNo' 'Question') -ne 'Yes') { return }
    foreach ($p in @($picked | Where-Object Action -eq 'sense')) {
        $undo = @(foreach ($n in '01', '04', '08', '256', '2048') { @{ P = $SenseKey; N = $n; Old = (Get-RegValue $SenseKey $n); T = 'DWord' } })
        Set-RegValue $SenseKey '01' 1; Set-RegValue $SenseKey '04' 1; Set-RegValue $SenseKey '08' 1; Set-RegValue $SenseKey '256' 30; Set-RegValue $SenseKey '2048' 7
        Add-History 'Space' 'Storage Sense' 'turned on (weekly)' @{ Type = 'Reg'; Values = $undo }
    }
    $jobs = @($picked | Where-Object Action -ne 'sense')
    if (-not $jobs) { Update-History; Update-Space; Show-Msg 'Storage Sense is on.' | Out-Null; return }
    $btnSpaceApply.Enabled = $false
    $script:SpaceJobs = $jobs
    Start-WithRestorePoint 'space savers' { Start-Bg -Label 'Applying space savers' $SpaceApplyWork $script:SpaceJobs {
        param($res)
        $btnSpaceApply.Enabled = $true
        $undoCmd = @{ hibshrink = @('powercfg.exe', '/hibernate /type full'); hiboff = @('powercfg.exe', '/hibernate on'); compact = @('compact.exe', '/compactos:never')
                      reserved = @('DISM.exe', '/Online /Set-ReservedStorageState /State:Enabled') }
        $lines = foreach ($r in $res) {
            $key = ($r.Action -split '\|')[0]
            if ($r.Ok) {
                $u = $undoCmd[$key]
                Add-History 'Space' $r.Name "done$(if ($r.Free) { ', about ' + (Format-Size $r.Free) })$(if ($r.Msg) { " ($($r.Msg))" })" $(if ($u) { @{ Type = 'Cmd'; Exe = $u[0]; Args = $u[1]; Admin = $true } })
                " - $($r.Name): done"
            } else { " - $($r.Name): failed $($r.Msg)" }
        }
        Update-History; Update-Space; Update-Health
        Show-Msg "Space savers:`n$($lines -join "`n")`n`nOneDrive frees its copies over the next minutes. Undo the others from the History page." | Out-Null
    } }
})
$btnSpaceSense.Add_Click({ Start-Process 'ms-settings:storagesense' })
$btnSpaceReload.Add_Click({ Update-Space })

# ===========================================================================
# Gaming: what slows a game down on this PC - best checked while the game is running
# ===========================================================================
$pgGame = New-Page 'Gaming' 'Start your game, then click Check again: which graphics card it really uses, what else is busy, and the Windows settings that cost frames. Recommended fixes are pre-checked and can be undone from History.'
$btnGameScan = New-Button 'Check again'
$btnGameFix = New-Button 'Apply checked fixes'
$btnGameGfx = New-Button 'Graphics settings'
$btnGameMode = New-Button 'Game Mode settings'
$lvGame = New-ListView $true @('Check', 210, 'Status', 80, 'Result', 380, 'What to do', 520)
$txtGame = New-DetailBox 104
Set-PageLayout $pgGame $lvGame @((New-ButtonBar @($btnGameFix, $btnGameScan, $btnGameGfx, $btnGameMode))) $txtGame
$GpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$GamingWork = {
    param($cfg)
    $rows = New-Object System.Collections.ArrayList
    function Add-G($Check, $Level, $Result, $Todo, $Fix = $null, $Rec = $false) { [void]$rows.Add([pscustomobject]@{ Check = $Check; Level = $Level; Result = $Result; Todo = $Todo; Fix = $Fix; Rec = $Rec }) }
    # Graphics cards, with the IDs Windows' GPU counters use
    $gpus = @{}
    foreach ($k in Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\DirectX' -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p.Description -or $p.Description -match 'Basic Render' -or -not $p.AdapterLuid) { continue }
        $l = [int64]$p.AdapterLuid
        $gpus[('0x{0:x8}_0x{1:x8}' -f ($l -shr 32), ($l -band 0xFFFFFFFFL))] = [pscustomobject]@{ Name = "$($p.Description)"; Discrete = ([int]$p.VendorId -eq 0x10DE -or ($p.Description -match 'Radeon RX|Radeon Pro|Arc A')) }
    }
    $hybrid = @($gpus.Values | Where-Object Discrete).Count -and @($gpus.Values | Where-Object { -not $_.Discrete }).Count
    # Who uses the 3D engine of which card (averaged over two seconds), and who uses the processor
    Set-JobProgress 'measuring graphics and processor use'
    # The WMI copy of the GPU counters has the same (English) names on every Windows language, unlike Get-Counter.
    $use = @{}
    $sample = { try { @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter "Name LIKE '%engtype_3D'" -OperationTimeoutSec 15 -ErrorAction Stop) } catch { @() } }
    [void](& $sample); Start-Sleep -Milliseconds 1000   # the first read only starts the measurement
    foreach ($s in & $sample) {
        if ("$($s.Name)" -match '^pid_(\d+)_luid_(0x[0-9a-f]+_0x[0-9a-f]+)_') { $key = "$($Matches[1])|$($Matches[2].ToLower())"; $use[$key] = [Math]::Min([double]100, [double]$use[$key] + [double]$s.UtilizationPercentage) }
    }
    $cpu1 = @{}; foreach ($p in Get-Process -ErrorAction SilentlyContinue) { try { $cpu1[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { } }
    Start-Sleep -Milliseconds 1500
    $cores = [Environment]::ProcessorCount
    $cpu = foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try { if ($cpu1.ContainsKey($p.Id)) { [pscustomobject]@{ Id = $p.Id; Name = $p.ProcessName; Pct = ($p.TotalProcessorTime.TotalMilliseconds - $cpu1[$p.Id]) / 15 / $cores; Path = "$($p.Path)" } } } catch { }
    }
    # Which running programs are games: inside a game library, or busy on the graphics card
    $libs = @()
    if ($cfg.Steam) { $libs += Join-Path $cfg.Steam 'steamapps\common'
        $vdf = Join-Path $cfg.Steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) { foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common' } } }
    foreach ($f in Get-ChildItem "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests" -Filter *.item -ErrorAction SilentlyContinue) { try { $libs += (Get-Content $f.FullName -Raw | ConvertFrom-Json).InstallLocation } catch { } }
    $libs += "${env:ProgramFiles(x86)}\Ubisoft\Ubisoft Game Launcher\games", "$env:ProgramFiles\EA Games", 'C:\XboxGames', "${env:ProgramFiles(x86)}\GOG Galaxy\Games", 'C:\Games'
    $libs = @($libs | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLower() + '\' } | Select-Object -Unique)
    $notGames = '^(dwm|explorer|msedge|chrome|firefox|brave|opera|vivaldi|Teams|ms-teams|Discord|steamwebhelper|EpicWebHelper|Spotify|vlc|Video\.UI|Photos|PhotosApp|SearchHost|ShellExperienceHost|StartMenuExperienceHost|TextInputHost|Widgets|ApplicationFrameHost|csrss|System|Idle|NVIDIA.*|nvcontainer|obs64|PC-TuneUp|powershell|Code|devenv)$'
    $games = @{}
    foreach ($p in $cpu) {
        $path = $p.Path.ToLower()
        $gpu3d = ($use.Keys | Where-Object { $_ -like "$($p.Id)|*" } | ForEach-Object { $use[$_] } | Measure-Object -Sum).Sum
        if (($path -and ($libs | Where-Object { $path.StartsWith($_) })) -or ($gpu3d -gt 25 -and $p.Name -notmatch $notGames)) {
            if ($p.Name -match '^(steam|EpicGamesLauncher|UnrealCEFSubProcess|CrashReport.*|.*Launcher.*)$') { continue }
            $games[$p.Id] = $p
        }
    }
    if (-not $games.Count) {
        Add-G 'Game' 'Info' 'No game running right now' 'Start your game, switch back here (Alt+Tab) and click "Check again" to see which graphics card it uses and what else is busy. The Windows settings below are checked either way.'
    }
    foreach ($g in $games.Values) {
        $per = @{}; foreach ($k in $use.Keys) { if ($k -like "$($g.Id)|*") { $per[($k -split '\|')[1]] = $use[$k] } }
        $top = $per.Keys | Sort-Object { $per[$_] } -Descending | Select-Object -First 1
        $card = if ($top) { $gpus[$top] }
        $title = $g.Name
        if (-not $card) { Add-G "Game: $title" 'Info' 'runs, but not drawing anything at the moment' 'Switch to the game for a moment (so it draws), then come back and click "Check again".'; continue }
        $busy = [int]$per[$top]
        if ($hybrid -and -not $card.Discrete) {
            Add-G "Game: $title" 'Problem' "runs on $($card.Name) - the slower, built-in graphics" `
                "Set it to use the fast graphics card (fix below), then restart the game. Same as Settings > System > Display > Graphics > (the game) > High performance." "gpu|$($g.Path)" $true
        } else {
            Add-G "Game: $title" 'OK' "runs on $($card.Name) ($busy% busy)" $(if ($busy -ge 95) { 'The graphics card is the limit (fully busy) - lower the graphics settings or the resolution in the game for more frames.' } else { 'Nothing to do.' })
        }
        $g | Add-Member -NotePropertyName Gpu -NotePropertyValue $busy -Force
    }
    # Other programs that take processor or graphics time away from the game
    $hogs = @($cpu | Where-Object { -not $games.ContainsKey($_.Id) -and $_.Name -notmatch '^(Idle|System|dwm|csrss|audiodg|MsMpEng|PC-TuneUp|powershell)$' -and $_.Pct -ge 8 } | Sort-Object Pct -Descending | Select-Object -First 3)
    foreach ($h in $hogs) { Add-G "Busy: $($h.Name)" 'Warning' ('uses {0:N0}% of the processor' -f $h.Pct) "Close $($h.Name) while you play, if you don't need it. (It may also be Windows doing updates or a virus scan - those finish by themselves.)" }
    foreach ($k in $use.Keys) {
        $pid2 = [int]($k -split '\|')[0]
        if ($games.ContainsKey($pid2) -or $use[$k] -lt 10) { continue }
        $pr = $cpu | Where-Object Id -eq $pid2 | Select-Object -First 1
        if ($pr -and $pr.Name -notmatch '^(dwm|csrss)$') { Add-G "Busy: $($pr.Name)" 'Warning' ('uses {0:N0}% of {1}' -f $use[$k], $(if ($gpus[($k -split '\|')[1]]) { $gpus[($k -split '\|')[1]].Name } else { 'a graphics card' })) "Close $($pr.Name) (videos, animated wallpapers and browser tabs use the graphics card too) while you play." }
    }
    # Power
    if ($cfg.OnBattery) { Add-G 'Power' 'Problem' 'on battery' 'Plug in the charger: on battery, laptops slow the processor and graphics card down a lot.' 'powermode' }
    elseif ($cfg.Mode -and $cfg.Mode -ne 'best performance') { Add-G 'Power mode' 'Warning' "$($cfg.Mode)" 'Set Power mode to "Best performance" while gaming (Settings > System > Power & battery) - the button opens it.' 'powermode' }
    else { Add-G 'Power' 'OK' "plugged in$(if ($cfg.Mode) { ", $($cfg.Mode)" })" 'Nothing to do.' }
    if ($cfg.MemFree -lt 20) { Add-G 'Memory' 'Warning' "only $($cfg.MemFree)% free" 'Close browsers and other big programs before playing - when memory is full, games stutter.' }
    # Windows settings that cost frames
    $gm = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled
    if ($gm -eq 0) { Add-G 'Game Mode' 'Warning' 'off' 'Game Mode gives the game priority and pauses Windows Update installs while you play. Turn it on (fix below).' 'gamemode' $true }
    else { Add-G 'Game Mode' 'OK' 'on' 'Nothing to do.' }
    $hist = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -ErrorAction SilentlyContinue).HistoricalCaptureEnabled
    if ($hist -eq 1) { Add-G 'Background recording' 'Warning' 'on ("Record what happened")' 'Windows keeps recording the last minutes of every game, which costs frames. Turn it off (fix below); you can still record by hand with Win+Alt+R.' 'record' $true }
    else { Add-G 'Background recording' 'OK' 'off' 'Nothing to do.' }
    $glob = "$((Get-ItemProperty $cfg.PrefKey -ErrorAction SilentlyContinue).DirectXUserGlobalSettings)"
    if ($glob -match 'SwapEffectUpgradeEnable=1') { Add-G 'Optimizations for windowed games' 'OK' 'on' 'Nothing to do.' }
    else { Add-G 'Optimizations for windowed games' 'Info' 'off' 'Lowers delay and allows Auto HDR / variable refresh rate for games in a window or borderless window. Turn it on (fix below).' 'windowed' $true }
    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue).HwSchMode
    Add-G 'Hardware-accelerated GPU scheduling' $(if ($hags -eq 2) { 'OK' } else { 'Info' }) $(switch ($hags) { 2 { 'on' } 1 { 'off' } default { 'Windows default' } }) `
        $(if ($hags -eq 2) { 'Nothing to do.' } else { 'Lets the graphics card schedule its own work - often a little smoother, and needed for DLSS frame generation. Needs administrator and a restart (fix below). If games stutter afterwards, undo it.' }) $(if ($hags -ne 2) { 'hags' })
    $over = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(Discord|gameoverlayui|NVIDIA Overlay|GameBar|RTSS|MSIAfterburner|Overwolf|Medal)$' } | ForEach-Object ProcessName | Select-Object -Unique)
    if ($over) { Add-G 'Overlays' 'Info' ($over -join ', ') 'Overlays draw on top of the game. Usually fine; if a game stutters or crashes, switch its overlay off first.' }
    [pscustomobject]@{ Rows = $rows; Games = @($games.Values) }
}
function Update-Gaming {
    $btnGameScan.Enabled = $false
    $txtGame.Text = 'Measuring (about 5 seconds)...'
    $q = $script:HealthQuick
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $cfg = @{ Steam = $(if ($steam) { $steam -replace '/', '\' })
              OnBattery = [Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline'; Mode = $(if ($q) { $q.Mode }); PrefKey = $GpuPrefKey
              MemFree = $(if ($q -and $q.TotalKB) { [int](100 * $q.FreeKB / $q.TotalKB) } else { 100 }) }
    Start-Bg -Label 'Checking for gaming' $GamingWork $cfg {
        param($r)
        $btnGameScan.Enabled = $true
        $r = @($r)[0]
        $lvGame.BeginUpdate(); $lvGame.Items.Clear()
        foreach ($g in $r.Rows | Sort-Object { $SecLevels[$_.Level] }) {
            $it = Add-Row $lvGame @($g.Check, $g.Level, $g.Result, $g.Todo) $g ($g.Rec -and $g.Fix)
            Set-RowStatus $it 1 $(switch ($g.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.Muted } })
        }
        # The graphics driver's age comes from the Drivers page, if it has loaded
        foreach ($d in @($lvDrv.Items | Where-Object { $_.Tag.Kind -eq 'Graphics' -and $_.Tag.Device -notmatch 'Intel|Basic' })) {
            $it = Add-Row $lvGame @('Graphics driver', $d.Tag.Level, "$($d.Tag.Device): $($d.Tag.Driver)", $(if ($d.Tag.Level -eq 'OK') { 'Nothing to do.' } else { $d.Tag.Todo })) ([pscustomobject]@{ Check = 'Graphics driver'; Level = $d.Tag.Level; Result = $d.Tag.Driver; Todo = $d.Tag.Todo; Fix = $null })
            $it.ForeColor = if ($d.Tag.Level -eq 'OK') { $Theme.Good } else { $Theme.Warn }
        }
        $lvGame.EndUpdate()
        if ($lvGame.Items.Count) { $lvGame.Items[0].Selected = $true }
    }
}
$lvGame.Add_SelectedIndexChanged({
    if (-not $lvGame.SelectedItems.Count) { return }
    $g = $lvGame.SelectedItems[0].Tag
    $txtGame.Text = "$($g.Check): $($g.Result)`r`n`r`nWhat to do: $($g.Todo)"
})
$btnGameFix.Add_Click({
    $picked = @($lvGame.CheckedItems | ForEach-Object { $_.Tag } | Where-Object Fix)
    if (-not $picked) { Show-Msg 'Check one or more rows that have a fix first.' | Out-Null; return }
    if ((@($picked | Where-Object Fix -eq 'hags')) -and -not $IsAdmin) { Show-Msg 'Hardware-accelerated GPU scheduling needs administrator rights - click "Restart as admin" first, or uncheck it.' 'OK' 'Warning' | Out-Null; return }
    if (-not (Confirm-Checked 'Apply these {0} fix(es)?' @($picked | ForEach-Object { T $_.Check }) 'You can undo this on the History page.')) { return }
    $done = @(); $restart = $false
    foreach ($g in $picked) {
        try {
            switch -Regex ($g.Fix) {
                '^powermode$' { Start-Process 'ms-settings:powersleep'; continue }
                '^gamemode$' { $old = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'; Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
                               Add-History 'Gaming' 'Game Mode' 'turned on' @{ Type = 'Reg'; Values = @(@{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; Old = $old; T = 'DWord' }) } }
                '^record$' { $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; $old = Get-RegValue $k 'HistoricalCaptureEnabled'; Set-RegValue $k 'HistoricalCaptureEnabled' 0
                             Add-History 'Gaming' 'Background recording' 'turned off' @{ Type = 'Reg'; Values = @(@{ P = $k; N = 'HistoricalCaptureEnabled'; Old = $old; T = 'DWord' }) } }
                '^windowed$' { $old = Get-RegValue $GpuPrefKey 'DirectXUserGlobalSettings'
                               $new = (("$old" -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' }) + 'SwapEffectUpgradeEnable=1') -join ';'
                               Set-RegValue $GpuPrefKey 'DirectXUserGlobalSettings' ($new + ';') 'String'
                               Add-History 'Gaming' 'Optimizations for windowed games' 'turned on' @{ Type = 'Reg'; Values = @(@{ P = $GpuPrefKey; N = 'DirectXUserGlobalSettings'; Old = $old; T = 'String' }) } }
                '^gpu\|(.+)$' { $exe = $Matches[1]; $old = Get-RegValue $GpuPrefKey $exe; Set-RegValue $GpuPrefKey $exe 'GpuPreference=2;' 'String'
                                Add-History 'Gaming' (Split-Path $exe -Leaf) 'set to use the fast graphics card' @{ Type = 'Reg'; Values = @(@{ P = $GpuPrefKey; N = $exe; Old = $old; T = 'String' }) } }
                '^hags$' { $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; $old = Get-RegValue $k 'HwSchMode'; Set-RegValue $k 'HwSchMode' 2; $restart = $true
                           Add-History 'Gaming' 'Hardware-accelerated GPU scheduling' 'turned on (after a restart)' @{ Type = 'Reg'; Values = @(@{ P = $k; N = 'HwSchMode'; Old = $old; T = 'DWord' }) } }
            }
            $done += $g.Check
        } catch { Show-Msg "Couldn't change $($g.Check): $($_.Exception.Message)" 'OK' 'Warning' | Out-Null }
    }
    Update-History; Update-Gaming
    Show-Msg "Done: $($done -join ', ').$(if ($restart) { ' Restart the PC for GPU scheduling to take effect.' }) Restart the game to feel the difference. Undo from the History page." | Out-Null
})
$btnGameScan.Add_Click({ Update-Gaming })
$btnGameGfx.Add_Click({ Start-Process 'ms-settings:display-advancedgraphics' })
$btnGameMode.Add_Click({ Start-Process 'ms-settings:gaming-gamemode' })

# ===========================================================================
# Right now: what is using the processor, memory and disk at this moment, in plain words. Refreshes every
# few seconds while the page is open; "End task" closes a program (never Windows itself).
# ===========================================================================
$pgNow = New-Page 'Right now' 'What is slowing the PC down at this moment: the programs using the most memory, processor and disk. Updates every few seconds while this page is open. Select a program and click End task to close it.'
$btnNowEnd = New-Button 'End task'
$btnNowPause = New-Button 'Pause'
$btnNowTM = New-Button 'Task Manager'
# Three meters (processor, memory, disk) above a one-line verdict.
$nowMeters = New-Object Windows.Forms.Panel
$nowMeters.Dock = 'Top'; $nowMeters.Height = 78; $nowMeters.BackColor = $Theme.Bg
try { $nowMeters.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($nowMeters, $true, $null) } catch { }
$NowMeterFont = New-Object Drawing.Font('Segoe UI Semibold', 15)
$nowMeters.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.Clear($Theme.Bg)
    $n = $script:Now
    $gap = Px 12; $w = [int](($s.Width - 2 * $gap) / 3); $h = $s.Height - (Px 8)
    $cells = @(
        @{ Name = 'Processor'; Pct = $(if ($n) { $n.Cpu }); Sub = $(if ($n) { (T '{0} cores').Replace('{0}', "$([Environment]::ProcessorCount)") }) }
        @{ Name = 'Memory'; Pct = $(if ($n) { 100 * $n.MemUsed / $n.MemTotal }); Sub = $(if ($n) { (T '{0} of {1} in use').Replace('{0}', (Format-Size $n.MemUsed)).Replace('{1}', (Format-Size $n.MemTotal)) }) }
        @{ Name = 'Disk'; Pct = $(if ($n) { $n.Disk }); Sub = $(if ($n) { (T '{0} per second').Replace('{0}', (Format-Size $n.DiskBytes)) }) }
    )
    for ($i = 0; $i -lt 3; $i++) {
        $c = $cells[$i]; $x = $i * ($w + $gap)
        $p = New-RoundRect ($x + 0.5) 0.5 ($w - 1.5) ($h - 1.5) (Px 8)
        $br = New-Object Drawing.SolidBrush($Theme.Soft); $g.FillPath($br, $p); $br.Dispose()
        $pen = New-Object Drawing.Pen($Theme.Hover); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
        $col = if ($null -eq $c.Pct) { $Theme.Muted } elseif ($c.Pct -ge 90) { $Theme.Bad } elseif ($c.Pct -ge 75) { $Theme.Warn } else { $Theme.Accent }
        $pad = Px 12
        [Windows.Forms.TextRenderer]::DrawText($g, (T $c.Name), $FontSmall, (New-Object Drawing.Rectangle(($x + $pad), (Px 8), ($w - 2 * $pad), (Px 18))), $Theme.Dim, 'Left, NoPrefix, EndEllipsis')
        $big = if ($null -eq $c.Pct) { '...' } else { '{0:N0}%' -f [Math]::Min([double]100, [double]$c.Pct) }
        [Windows.Forms.TextRenderer]::DrawText($g, $big, $NowMeterFont, (New-Object Drawing.Rectangle(($x + $pad), (Px 24), (Px 66), (Px 30))), $Theme.Text, 'Left, VerticalCenter, NoPrefix')
        if ($c.Sub) { [Windows.Forms.TextRenderer]::DrawText($g, $c.Sub, $Font, (New-Object Drawing.Rectangle(($x + $pad + (Px 68)), (Px 24), ($w - 2 * $pad - (Px 68)), (Px 30))), $Theme.Dim, 'Left, VerticalCenter, NoPrefix, EndEllipsis') }
        # The bar along the bottom of the card
        $by = [single]($h - (Px 16)); $bw = [single]($w - 2 * $pad); $bh = [single](Px 5)
        $t = New-RoundRect ($x + $pad) $by $bw $bh ($bh / 2); $br = New-Object Drawing.SolidBrush($Theme.Border); $g.FillPath($br, $t); $br.Dispose(); $t.Dispose()
        if ($null -ne $c.Pct -and $c.Pct -gt 0) {
            $f = New-RoundRect ($x + $pad) $by ([single][Math]::Max([double]$bh, $bw * [Math]::Min([double]1, [double]$c.Pct / 100))) $bh ($bh / 2)
            $br = New-Object Drawing.SolidBrush($col); $g.FillPath($br, $f); $br.Dispose(); $f.Dispose()
        }
    }
})
$nowMeters.Add_Resize({ $this.Invalidate() })
$lblNow = New-Object Windows.Forms.Label
$lblNow.Dock = 'Top'; $lblNow.Height = 40; $lblNow.TextAlign = 'MiddleLeft'; $lblNow.Padding = New-Object Windows.Forms.Padding(12, 0, 12, 0)
$lblNow.BackColor = $Theme.Soft; $lblNow.Text = 'Measuring...'
$nowGap = New-Object Windows.Forms.Panel; $nowGap.Dock = 'Top'; $nowGap.Height = 8
$lvNow = New-ListView $false @('Program', 260, 'Memory', 110, 'Processor', 90, 'Disk', 100, 'What to do', 540)
$txtNow = New-DetailBox 116
Set-PageLayout $pgNow $lvNow @((New-ButtonBar @($btnNowEnd, $btnNowPause, $btnNowTM)), $nowMeters, $lblNow, $nowGap) $txtNow
# Plain explanations for programs that are often busy. First match wins; anything else gets a general hint.
$NowHints = @(
    ,@('^(chrome|msedge|firefox|brave|opera|vivaldi|arc)$', 'Every open tab and extension uses memory. Close tabs you don''t need; Shift+Esc in the browser shows which tab uses the most.')
    ,@('^(MsMpEng|MpDefenderCoreService|NisSrv|MpCopyAccelerator)$', 'Windows Security checking for viruses. It finishes by itself - leave it running.')
    ,@('^(TiWorker|TrustedInstaller|wuauclt|MoUsoCoreWorker|usocoreworker|WaaSMedicAgent|SIHClient|UsoClient)$', 'Windows Update installing updates. Let it finish, and restart when Windows asks.')
    ,@('^(SearchIndexer|SearchProtocolHost|SearchFilterHost)$', 'Windows Search indexing your files so searching is quick. It slows down by itself while you use the PC.')
    ,@('^(OneDrive|Dropbox|GoogleDriveFS|iCloudDrive|iCloudServices)$', 'Syncing files with the cloud. It calms down when syncing is finished.')
    ,@('^(Teams|ms-teams|Zoom|Slack|Discord|WhatsApp)$', 'A chat app that keeps running in the background. Quit it from its icon next to the clock when you don''t need it.')
    ,@('^(steam|steamwebhelper|EpicGamesLauncher|EADesktop|Battle\.net|upc|UbisoftConnect)$', 'A game launcher. It downloads updates in the background; quit it when you are not playing.')
    ,@('^Memory Compression$', 'Windows squeezing memory to make room - a sign that memory is nearly full. Closing programs helps.')
    ,@('^dwm$', 'Windows drawing the screen. Busier with animations, videos and extra screens.')
    ,@('^WmiPrvSE$', 'Windows answering questions about the PC (PC Tune-Up asks it too, while this page is open).')
)
$NowWork = {
    param($cfg)
    $cores = [Environment]::ProcessorCount
    # Raw counters (the same on every Windows language): processor time and disk bytes so far, and private memory now.
    $take = {
        $s = @{ Procs = @{}; Ts = [int64]0; DiskIdle = $null; DiskTs = $null }
        foreach ($p in @(Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property Name, IDProcess, PercentProcessorTime, IODataBytesPersec, WorkingSetPrivate, Timestamp_Sys100NS -OperationTimeoutSec 15 -ErrorAction SilentlyContinue)) {
            if ($p.Name -eq '_Total') { continue }
            $s.Procs[[int]$p.IDProcess] = @([double]$p.PercentProcessorTime, [double]$p.IODataBytesPersec, [double]$p.WorkingSetPrivate, "$($p.Name)")
            $s.Ts = [int64]$p.Timestamp_Sys100NS
        }
        $d = Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -Property PercentIdleTime, Timestamp_Sys100NS -OperationTimeoutSec 15 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($d) { $s.DiskIdle = [double]$d.PercentIdleTime; $s.DiskTs = [double]$d.Timestamp_Sys100NS }
        $s
    }
    $prev = $cfg.Prev
    if (-not $prev) { $prev = & $take; Start-Sleep -Milliseconds 1000 }   # the first time: two readings a second apart
    $now = & $take
    $dt = [double]($now.Ts - $prev.Ts); if ($dt -le 0) { $dt = 1e7 }
    $info = @{}; foreach ($p in Get-Process -ErrorAction SilentlyContinue) { $info[$p.Id] = $p }
    $win = $cfg.Win.TrimEnd('\').ToLower() + '\'
    $groups = @{}; $idle = 0; $ioAll = 0
    foreach ($id in @($now.Procs.Keys)) {
        $c = $now.Procs[$id]; $o = $prev.Procs[$id]
        $cpu = if ($o) { [Math]::Max([double]0, ($c[0] - $o[0]) / $dt * 100 / $cores) } else { 0 }
        $io = if ($o) { [Math]::Max([double]0, ($c[1] - $o[1]) / ($dt / 1e7)) } else { 0 }
        if ($id -eq 0) { $idle = $cpu; continue }
        $ioAll += $io
        $p = $info[$id]
        $name = if ($p) { $p.ProcessName } else { $c[3] -replace '#\d+$', '' }
        $g = $groups[$name]
        if (-not $g) {
            $g = [pscustomobject]@{ Name = $name; Display = $name; Path = ''; Mem = 0.0; Cpu = 0.0; Io = 0.0; Count = 0; Ids = New-Object System.Collections.ArrayList; Window = $false; Service = $false; Self = $false }
            $groups[$name] = $g
        }
        $g.Mem += $c[2]; $g.Cpu += $cpu; $g.Io += $io; $g.Count++; [void]$g.Ids.Add($id)
        if ($id -eq $cfg.Self) { $g.Self = $true }
        if ($p) {
            if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $g.Window = $true }
            if ($p.SessionId -eq 0) { $g.Service = $true }
            if (-not $g.Path) { try { $g.Path = "$($p.Path)" } catch { } }
        }
    }
    $rows = @(foreach ($g in $groups.Values) {
        if ($g.Path) {
            if (-not $cfg.Desc.ContainsKey($g.Path)) { $cfg.Desc[$g.Path] = try { "$([Diagnostics.FileVersionInfo]::GetVersionInfo($g.Path).FileDescription)".Trim() } catch { '' } }
            if ($cfg.Desc[$g.Path]) { $g.Display = $cfg.Desc[$g.Path] }
        }
        # Windows' own parts, background services and PC Tune-Up itself are never ended from here.
        $g | Add-Member -NotePropertyName Protected -NotePropertyValue ($g.Self -or $g.Service -or -not $g.Path -or $g.Path.ToLower().StartsWith($win)) -Force
        $g
    })
    $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize -OperationTimeoutSec 15 -ErrorAction SilentlyContinue
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $disk = if ($null -ne $now.DiskIdle -and $null -ne $prev.DiskIdle -and $now.DiskTs -gt $prev.DiskTs) {
        [Math]::Max([double]0, [Math]::Min([double]100, 100 - 100 * ($now.DiskIdle - $prev.DiskIdle) / ($now.DiskTs - $prev.DiskTs))) } else { 0 }
    # Most "weight" first: processor share, memory share and disk traffic together.
    $top = @($rows | Sort-Object { - ($_.Cpu + 100 * $_.Mem / [Math]::Max([double]1, $total) + [Math]::Min([double]30, $_.Io / 1MB)) } | Select-Object -First 40)
    [pscustomobject]@{ Sample = $now; Cpu = [Math]::Min([double]100, [Math]::Max([double]0, 100 - $idle)); MemTotal = $total
                       MemUsed = $total - [double]$os.FreePhysicalMemory * 1KB; Disk = $disk; DiskBytes = $ioAll; Rows = $top }
}
# What to do about one program, in plain words.
function Get-NowHint($G) {
    foreach ($h in $NowHints) { if ($G.Name -match $h[0]) { return $h[1] } }
    if ($G.Self) { return 'PC Tune-Up itself.' }
    if ($G.Path -and $G.Path.ToLower().StartsWith($env:windir.ToLower().TrimEnd('\') + '\')) { return 'Part of Windows. Leave it running; if it stays busy for a long time, a restart usually helps.' }
    if ($G.Protected) { return 'A background service (part of Windows or of another program). Leave it running; the Services page shows which ones you can switch off.' }
    if ($G.Mem -ge 1.5GB) { return 'Uses a lot of memory. Close it when you don''t need it.' }
    if ($G.Cpu -ge 25) { return 'Keeps the processor busy. If you aren''t using it, close it.' }
    if ($G.Io -ge 20MB) { return 'Reading or writing a lot on the disk right now.' }
    'Nothing to do.'
}
# The one sentence above the list: the biggest reason the PC is slow right now, or that nothing is.
function Get-NowVerdict($N) {
    $mem = [int](100 * $N.MemUsed / [Math]::Max([double]1, $N.MemTotal))
    $pick = @($N.Rows | Where-Object { -not $_.Self -and $_.Name -notin 'WmiPrvSE', 'Idle', 'System', 'Memory Compression' })
    if ($mem -ge 85) {
        $t = $pick | Sort-Object Mem -Descending | Select-Object -First 1
        return @('Bad', ((T 'Memory is nearly full ({0}% in use) - that slows everything down. {1} uses the most ({2}).').Replace('{0}', "$mem").Replace('{1}', $t.Display).Replace('{2}', (Format-Size $t.Mem))))
    }
    if ($N.Cpu -ge 80) {
        $t = $pick | Sort-Object Cpu -Descending | Select-Object -First 1
        return @('Bad', ((T 'The processor is very busy ({0}%). {1} uses the most ({2}%).').Replace('{0}', ('{0:N0}' -f $N.Cpu)).Replace('{1}', $t.Display).Replace('{2}', ('{0:N0}' -f $t.Cpu))))
    }
    if ($N.Disk -ge 80) {
        $t = $pick | Sort-Object Io -Descending | Select-Object -First 1
        return @('Warn', ((T 'The disk is very busy ({0}%). {1} reads and writes the most.').Replace('{0}', ('{0:N0}' -f $N.Disk)).Replace('{1}', $t.Display)))
    }
    if ($mem -ge 75) { return @('Warn', ((T 'Memory is getting full ({0}% in use). Closing programs you don''t use keeps the PC quick.').Replace('{0}', "$mem"))) }
    @('Good', (T 'Nothing is slowing the PC down right now.'))
}
function Show-NowDetail {
    if (-not $lvNow.SelectedItems.Count) { $txtNow.Text = ''; return }
    $g = $lvNow.SelectedItems[0].Tag
    $txtNow.Text = (@("$($g.Display)  ($($g.Name))",
        (T '{0} process(es) - memory {1}, processor {2}%, disk {3}').Replace('{0}', "$($g.Count)").Replace('{1}', (Format-Size $g.Mem)).Replace('{2}', ('{0:N0}' -f $g.Cpu)).Replace('{3}', "$(Format-Size $g.Io)/s"),
        $(if ($g.Path) { $g.Path }), '', (T 'What to do: {0}').Replace('{0}', (T (Get-NowHint $g)))) | Where-Object { $null -ne $_ }) -join "`r`n"
}
# Redraws the list in place, so the selected program stays selected while the numbers change.
function Render-Now {
    $n = $script:Now
    if (-not $n) { return }
    $nowMeters.Invalidate()
    if ($script:NowEarlier) { return }   # the history is showing; only the meters stay live
    $v = Get-NowVerdict $n
    $lblNow.Text = $v[1]
    $lblNow.BackColor = if ($v[0] -eq 'Good') { $Theme.Soft } else { $Theme.WarnBg }
    $lblNow.ForeColor = if ($v[0] -eq 'Good') { $Theme.Text } else { $Theme.WarnText }
    $sel = if ($lvNow.SelectedItems.Count) { $lvNow.SelectedItems[0].Tag.Name }
    $rows = @($n.Rows)
    $lvNow.BeginUpdate()
    while ($lvNow.Items.Count -gt $rows.Count) { $lvNow.Items.RemoveAt($lvNow.Items.Count - 1) }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $g = $rows[$i]
        $cells = @($(if ($g.Count -gt 1) { "$($g.Display)  ($($g.Count))" } else { $g.Display }), (Format-Size $g.Mem), ('{0:N0}%' -f $g.Cpu), "$(Format-Size $g.Io)/s", (T (Get-NowHint $g)))
        if ($i -ge $lvNow.Items.Count) { $it = Add-Row $lvNow @($cells[0], '', '', '', '') $g }
        $it = $lvNow.Items[$i]
        $it.Tag = $g; $it.UseItemStyleForSubItems = $false
        for ($c = 0; $c -lt 5; $c++) { if ($it.SubItems[$c].Text -ne $cells[$c]) { $it.SubItems[$c].Text = $cells[$c] } }
        $it.SubItems[0].ForeColor = if ($g.Protected) { $Theme.Dim } else { $Theme.Text }
        $it.SubItems[1].ForeColor = if ($g.Mem -ge 0.25 * $n.MemTotal) { $Theme.Bad } elseif ($g.Mem -ge 1GB) { $Theme.Warn } else { $Theme.Text }
        $it.SubItems[2].ForeColor = if ($g.Cpu -ge 50) { $Theme.Bad } elseif ($g.Cpu -ge 15) { $Theme.Warn } else { $Theme.Text }
        $it.SubItems[3].ForeColor = if ($g.Io -ge 50MB) { $Theme.Bad } elseif ($g.Io -ge 10MB) { $Theme.Warn } else { $Theme.Text }
        $it.SubItems[4].ForeColor = $Theme.Dim
        $want = $g.Name -eq $sel
        if ($it.Selected -ne $want) { $it.Selected = $want }
    }
    $lvNow.EndUpdate()
    Show-NowDetail
}
$script:NowPrev = $null; $script:Now = $null; $script:NowDesc = @{}; $script:NowBusy = $false; $script:NowPaused = $false
function Update-Now {
    if ($script:NowBusy) { return }
    $script:NowBusy = $true
    Start-Bg $NowWork @{ Prev = $script:NowPrev; Desc = $script:NowDesc; Self = $PID; Win = $env:windir } {
        param($r)
        $script:NowBusy = $false
        $r = @($r)[0]
        if (-not $r) { return }
        $script:NowPrev = $r.Sample; $script:Now = $r
        Render-Now
    }
}
# Every 3 seconds while the page is on screen (not while it's hidden, minimised or paused); every 15 seconds while
# another window is in front, so a forgotten open page costs next to nothing.
$nowTimer = New-Object Windows.Forms.Timer; $nowTimer.Interval = 3000
$script:NowLast = [datetime]::MinValue
$nowTimer.Add_Tick({
    if (-not ($pgNow.Visible -and $form.Visible -and $form.WindowState -ne 'Minimized' -and -not $script:NowPaused -and -not ($simple -and $simple.Visible))) { return }
    if ([Windows.Forms.Form]::ActiveForm -ne $form -and ((Get-Date) - $script:NowLast).TotalSeconds -lt 15) { return }
    $script:NowLast = Get-Date
    Update-Now
})
$nowTimer.Start()
$lvNow.Add_SelectedIndexChanged({ Show-NowDetail })
$btnNowPause.Add_Click({
    $script:NowPaused = -not $script:NowPaused
    $this.Text = if ($script:NowPaused) { 'Resume' } else { 'Pause' }
    if (-not $script:NowPaused) { Update-Now }
})
$btnNowTM.Add_Click({ Start-Process taskmgr.exe })
function Stop-NowProgram {
    $g = Get-PickedRow $lvNow
    if (-not $g) { return }
    if ($g.Protected) { Show-Msg ((T '{0} is part of Windows or runs as a background service, so PC Tune-Up doesn''t end it.').Replace('{0}', $g.Display)) 'OK' 'Information' | Out-Null; return }
    $q = (T 'End {0}?').Replace('{0}', $g.Display) + "`r`n`r`n" + (T 'It closes straight away ({0} process(es)). Anything not saved in it is lost - save your work first.').Replace('{0}', "$($g.Count)")
    if ((Show-Msg $q 'YesNo' 'Question') -ne 'Yes') { return }
    $failed = 0
    foreach ($id in $g.Ids) { try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { $failed++ } }
    Add-History 'Right now' $g.Display 'ended'
    Update-History
    if ($failed -eq $g.Ids.Count) { Show-Msg ((T 'Couldn''t end {0} - it may need administrator rights, or it already closed.').Replace('{0}', $g.Display)) 'OK' 'Warning' | Out-Null }
    Update-Now
}
$btnNowEnd.Add_Click({ Stop-NowProgram })
$lvNow.Add_KeyDown({ if ($_.KeyCode -eq 'Delete') { Stop-NowProgram; $_.SuppressKeyPress = $true } })

# --- Memory over time: every 10 minutes while PC Tune-Up is open (and once per automatic maintenance) it notes how full
# memory is and the five programs using the most. Kept for 14 days in memory.jsonl. "Earlier" on this page shows it;
# the Upgrades page uses it to say whether more memory would help.
$MemFile = Join-Path $DataDir 'memory.jsonl'
$script:MemHistory = $null
# Read once, when first needed (one JSON parse for the whole file - per line would take a second); older than 14 days is dropped.
function Get-MemHistory {
    if ($null -ne $script:MemHistory) { return , $script:MemHistory }
    $script:MemHistory = New-Object System.Collections.ArrayList
    if (Test-Path $MemFile) {
        $lines = @(Get-Content $MemFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim().StartsWith('{') })
        # (ConvertFrom-Json returns a JSON array as ONE object in Windows PowerShell - foreach below unrolls it)
        $all = try { "[$($lines -join ',')]" | ConvertFrom-Json } catch { foreach ($l in $lines) { try { $l | ConvertFrom-Json } catch { } } }
        $cut = (Get-Date).AddDays(-14)
        foreach ($o in $all) { try { if ([datetime]$o.T -gt $cut) { [void]$script:MemHistory.Add($o) } } catch { } }
        if ($script:MemHistory.Count -lt $lines.Count) { try { Set-Content -Path $MemFile -Value @($script:MemHistory | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }) -Encoding UTF8 } catch { } }
    }
    , $script:MemHistory
}
$MemSampleWork = {
    $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize -OperationTimeoutSec 15 -ErrorAction SilentlyContinue
    if (-not $os -or -not $os.TotalVisibleMemorySize) { return }
    $by = @{}
    foreach ($p in @(Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property Name, IDProcess, WorkingSetPrivate -OperationTimeoutSec 15 -ErrorAction SilentlyContinue)) {
        if ($p.Name -in '_Total', 'Idle') { continue }
        $n = "$($p.Name)" -replace '#\d+$', ''
        if (-not $by.ContainsKey($n)) { $by[$n] = @{ MB = 0.0; Id = [int]$p.IDProcess } }
        $by[$n].MB += [double]$p.WorkingSetPrivate / 1MB
    }
    $top = @($by.Keys | Sort-Object { - $by[$_].MB } | Select-Object -First 5 | ForEach-Object {
        $name = $_
        $path = try { "$((Get-Process -Id $by[$_].Id -ErrorAction Stop).Path)" } catch { '' }
        if ($path) { $d = try { "$([Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileDescription)".Trim() } catch { '' }; if ($d) { $name = $d } }
        , @($name, [int]$by[$_].MB) })
    [pscustomobject]@{ T = (Get-Date).ToString('s'); P = [int](100 - 100 * [double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize); Top = $top }
}
function Save-MemSample {
    Start-Bg $MemSampleWork $null {
        param($r)
        $s = @($r)[0]
        if (-not $s) { return }
        [void](Get-MemHistory).Add($s)
        try { Add-Content -Path $MemFile -Value ($s | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8 } catch { }
        if ($script:NowEarlier) { Render-NowEarlier }
    }
}
# Over the last N days: how many samples, how often memory was nearly full (85%+), and the programs that used the most.
function Get-MemStats([int]$Days = 7) {
    $cut = (Get-Date).AddDays(-$Days)
    $s = @((Get-MemHistory) | Where-Object { [datetime]$_.T -gt $cut })
    if (-not $s) { return $null }
    $progs = @{}
    foreach ($x in $s) { foreach ($t in @($x.Top)) { $n = "$($t[0])"; if (-not $progs.ContainsKey($n)) { $progs[$n] = New-Object System.Collections.ArrayList }; [void]$progs[$n].Add([double]$t[1]) } }
    $rows = @($progs.Keys | ForEach-Object { $v = $progs[$_]; [pscustomobject]@{ Name = $_; Avg = ($v | Measure-Object -Average).Average; Max = ($v | Measure-Object -Maximum).Maximum; Share = [int](100 * $v.Count / $s.Count) } } |
              Where-Object { $_.Name -notin 'Memory Compression', 'System', 'Registry', 'Secure System' } | Sort-Object { - $_.Avg * $_.Share } | Select-Object -First 10)
    $first = @($s | ForEach-Object { [datetime]$_.T } | Sort-Object)[0]
    [pscustomobject]@{ Samples = $s.Count; FullPct = [int](100 * @($s | Where-Object { $_.P -ge 85 }).Count / $s.Count); AvgPct = [int]($s | Measure-Object P -Average).Average
                       Days = [Math]::Max(1, [int][Math]::Ceiling(((Get-Date) - $first).TotalDays)); Rows = $rows; Points = @($s | ForEach-Object { [pscustomobject]@{ X = [datetime]$_.T; Y = [double]$_.P } }) }
}
# "Earlier": a chart of the last 7 days and the programs that used the most memory, in place of the live list.
$btnNowEarlier = New-Button 'Earlier'
$btnNowPause.Parent.Controls.Add($btnNowEarlier); $btnNowPause.Parent.Controls.SetChildIndex($btnNowEarlier, 2)
$nowHist = New-Object Windows.Forms.Panel
$nowHist.Dock = 'Fill'; $nowHist.Visible = $false; $nowHist.BackColor = $Theme.Bg
$chartMem = New-Chart 170
$chartMem.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 8)
$lvMemHist = New-ListView $false @('Program', 300, 'On average', 120, 'At most', 120, 'Among the top 5', 560)
$nowHist.Controls.Add($lvMemHist); $nowHist.Controls.Add($chartMem)
$pgNow.Controls.Add($nowHist)
$script:NowEarlier = $false
function Render-NowEarlier {
    $m = Get-MemStats 7
    if (-not $m -or $m.Samples -lt 6) {
        Set-Chart $chartMem @() 100 '%' 'Memory in use, last 7 days' 'Not enough history yet - PC Tune-Up notes memory use every 10 minutes while it is open.'
        $lvMemHist.Items.Clear()
        $lblNow.Text = T 'Not enough history yet - PC Tune-Up notes memory use every 10 minutes while it is open.'
        $lblNow.BackColor = $Theme.Soft; $lblNow.ForeColor = $Theme.Text
        return
    }
    Set-Chart $chartMem @(@{ Name = 'Memory in use'; Color = $Theme.Accent; Points = $m.Points }) 100 '%' 'Memory in use, last 7 days'
    $lvMemHist.BeginUpdate(); $lvMemHist.Items.Clear()
    foreach ($r in $m.Rows) { [void](Add-Row $lvMemHist @($r.Name, (Format-Size ($r.Avg * 1MB)), (Format-Size ($r.Max * 1MB)), ((T '{0}% of the time').Replace('{0}', "$($r.Share)"))) $r) }
    $lvMemHist.EndUpdate()
    $top = @($m.Rows)[0]
    $lblNow.Text = (T 'Over the last {0} day(s) memory was nearly full {1}% of the time (on average {2}% in use).').Replace('{0}', "$($m.Days)").Replace('{1}', "$($m.FullPct)").Replace('{2}', "$($m.AvgPct)") +
                   $(if ($top) { '  ' + (T '{0} used the most.').Replace('{0}', $top.Name) })
    $lblNow.BackColor = if ($m.FullPct -ge 20) { $Theme.WarnBg } else { $Theme.Soft }; $lblNow.ForeColor = if ($m.FullPct -ge 20) { $Theme.WarnText } else { $Theme.Text }
}
$btnNowEarlier.Add_Click({
    $script:NowEarlier = -not $script:NowEarlier
    $this.Text = if ($script:NowEarlier) { 'Now' } else { 'Earlier' }
    $nowHist.Visible = $script:NowEarlier; $lvNow.Visible = -not $script:NowEarlier; $txtNow.Parent.Visible = -not $script:NowEarlier
    if ($script:NowEarlier) { $nowHist.BringToFront(); Render-NowEarlier } else { $lvNow.BringToFront(); Render-Now }
})
# Every 10 minutes, the first time a minute after the start.
$memTimer = New-Object Windows.Forms.Timer; $memTimer.Interval = 60000
$memTimer.Add_Tick({ $memTimer.Interval = 600000; if (-not $CliMode) { Save-MemSample } })
$memTimer.Start()

# ===========================================================================
# Search: finds pages, settings and rows on every page (Ctrl+F)
# ===========================================================================
$pgFind = New-Page 'Search' 'Everything that matches, on every page. Double-click a result (or select it and press Enter) to go there.'
$lvFind = New-ListView $false @('Found', 380, 'Page', 140, 'Details', 600)
$lblFind = New-Status
Set-PageLayout $pgFind $lvFind @() $lblFind
# Lower case without accents; hyphens joined, other punctuation becomes a space:
# "Wi-Fi" finds "wifi", "geïnstalleerd" finds "geinstalleerd", but "teams.teams" doesn't contain "steam".
$SearchMarks = [regex]'\p{Mn}'; $SearchJoin = [regex]"[-'\u2019]"; $SearchSpace = [regex]'[^\p{L}\p{N}]+'
function ConvertTo-SearchText([string]$Text) {
    $d = $SearchMarks.Replace($Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD), '')
    ' ' + $SearchSpace.Replace($SearchJoin.Replace($d, ''), ' ').Trim() + ' '
}
function Invoke-Search([string]$Query) {
    $words = @(foreach ($w in (ConvertTo-SearchText $Query).Trim() -split ' ') { if ($w) { $w } })
    if (-not $words) { return }
    $hit = { param($t) $n = ConvertTo-SearchText $t; foreach ($w in $words) { if (-not $n.Contains($w)) { return $false } }; $true }
    $lvFind.BeginUpdate(); $lvFind.Items.Clear()
    $n = 0
    $pages = @($script:Pages | Where-Object { $_ -ne $pgFind -and $script:NavButtons[$_.Name] })   # only pages that are in the sidebar
    # Pages whose name matches come first, then pages whose description matches, then rows
    foreach ($p in $pages | Sort-Object { -not (& $hit $_.Text) }) {
        $intro = (@($p.Tag.Controls) | ForEach-Object Text) -join ' '
        if (& $hit "$($p.Text) $intro") { [void](Add-Row $lvFind @($p.Text, $p.Text, $intro) @{ Page = $p; Item = $null }); $n++ }
    }
    foreach ($p in $pages) {
        foreach ($lv in @($p.Controls | Where-Object { $_ -is [Windows.Forms.ListView] })) {
            foreach ($it in $lv.Items) {
                if ($n -ge 300) { break }
                $all = ($it.SubItems | ForEach-Object Text) -join '  '
                if (& $hit $all) { [void](Add-Row $lvFind @($it.Text, $p.Text, (($it.SubItems | Select-Object -Skip 1 | ForEach-Object Text | Where-Object { $_ }) -join '  |  ')) @{ Page = $p; Item = $it; List = $lv }); $n++ }
            }
        }
    }
    foreach ($c in $setFlow.Controls) {   # Settings sections and their hints
        if ($c -is [Windows.Forms.Label] -and $c.Text -and (& $hit $c.Text)) { [void](Add-Row $lvFind @($c.Text, $pgSet.Text, '') @{ Page = $pgSet; Item = $null }); $n++ }
    }
    $lvFind.EndUpdate()
    $lblFind.Text = if ($n) { "$n result(s) for ""$Query""." } else { "Nothing found for ""$Query"". Pages still loading are searched once they are ready." }
    if ($pgFind.Visible -eq $false) { Show-Page $pgFind }
    if ($lvFind.Items.Count) { $lvFind.Items[0].Selected = $true }
}
function Open-SearchResult {
    if (-not $lvFind.SelectedItems.Count) { return }
    $t = $lvFind.SelectedItems[0].Tag
    Show-Page $t.Page
    if ($t.Item -and $t.List) { $t.List.SelectedItems.Clear(); $t.Item.Selected = $true; $t.Item.Focused = $true; $t.Item.EnsureVisible(); [void]$t.List.Focus() }
}
$lvFind.Add_DoubleClick({ Open-SearchResult })
$lvFind.Add_KeyDown({ if ($_.KeyCode -eq 'Return') { Open-SearchResult; $_.Handled = $true } })

# ===========================================================================
# 7. Upgrades: what could be added or replaced, and the exact spec to buy
# ===========================================================================
$pgUpg = New-Page 'Upgrades' 'What you could add or replace in this PC, with the specification to buy. Click a row for the full details. Always confirm with the service manual before buying.'
$btnUpgReload = New-Button 'Refresh'
$btnUpgSupport = New-Button 'Open support page'
$btnUpgManual = New-Button 'Find service manual'
$btnUpgCopy = New-Button 'Copy shopping list'
$lvUpg = New-ListView $false @('Part', 110, 'You have now', 290, 'Upgrade option', 220, 'Worth it?', 260, 'What to buy', 600)
$txtUpg = New-DetailBox 164
Set-PageLayout $pgUpg $lvUpg @((New-ButtonBar @($btnUpgReload, $btnUpgSupport, $btnUpgManual, $btnUpgCopy))) $txtUpg

# Two parts: $UpgradeCollectWork gathers raw hardware facts in the background (works on any make,
# desktop, laptop or VM); Get-UpgradeRows turns those facts into advice. Keeping the advice a pure
# function means it can be checked against made-up PCs, not just the one it runs on.
$UpgradeCollectWork = {
    # Hardware queries can crawl while a game has the GPU busy; give each one a time limit.
    $PSDefaultParameterValues = @{ 'Get-CimInstance:OperationTimeoutSec' = 15; 'Get-CimInstance:ErrorAction' = 'SilentlyContinue' }
    $cs = Get-CimInstance Win32_ComputerSystem
    $board = Get-CimInstance Win32_BaseBoard
    $os = Get-CimInstance Win32_OperatingSystem
    $arr = Get-CimInstance Win32_PhysicalMemoryArray | Where-Object Use -eq 3 | Select-Object -First 1   # 3 = system memory
    $mods = foreach ($m in Get-CimInstance Win32_PhysicalMemory) {
        [pscustomobject]@{ SizeGB = [int]($m.Capacity / 1GB); SmbiosType = [int]$m.SMBIOSMemoryType; MemoryType = [int]$m.MemoryType
                           Speed = [int]$(if ($m.ConfiguredClockSpeed) { $m.ConfiguredClockSpeed } else { $m.Speed }); FormFactor = [int]$m.FormFactor
                           VoltageMV = [int]$m.ConfiguredVoltage; ECC = ($m.TotalWidth -gt $m.DataWidth); Registered = [bool]([int]$m.TypeDetail -band 8192)
                           Maker = "$($m.Manufacturer)".Trim(); Part = "$($m.PartNumber)".Trim(); Locator = "$($m.DeviceLocator)".Trim() }
    }
    $sysDisk = try { "$((Get-Partition -DriveLetter C -ErrorAction Stop | Get-Disk).Number)" } catch { '' }
    $disks = foreach ($d in Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        [pscustomobject]@{ Name = "$($d.FriendlyName)".Trim(); SizeGB = [int]($d.Size / 1GB); Bus = "$($d.BusType)"; Media = "$($d.MediaType)"
                           Spindle = [long]$d.SpindleSpeed; IsSystem = ("$($d.DeviceId)" -eq $sysDisk) }
    }
    $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $batteries = @()
    $xml = Join-Path $env:TEMP "pctuneup-upg-battery-$PID.xml"
    powercfg /batteryreport /xml /output $xml 2>$null | Out-Null
    if (Test-Path $xml) {
        try {
            [xml]$x = Get-Content $xml
            $batteries = foreach ($b in @($x.BatteryReport.Batteries.Battery)) {
                if (-not $b -or [double]$b.DesignCapacity -le 0) { continue }
                [pscustomobject]@{ Wh = [Math]::Round([double]$b.DesignCapacity / 1000); Pct = [Math]::Min(100, [int](100 * [double]$b.FullChargeCapacity / [double]$b.DesignCapacity))
                                   Chem = "$($b.Chemistry)"; Maker = "$($b.Manufacturer)"; Id = "$($b.Id)".Trim() }
            }
        } catch { }
        Remove-Item $xml -ErrorAction SilentlyContinue
    }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $wifi = @(Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=TRUE' -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match 'Wi-?Fi|Wireless|WLAN|802\.11' -and $_.Name -notmatch 'Virtual|Direct|Bluetooth' } | ForEach-Object { $_.Name.Trim() })
    [pscustomobject]@{
        Maker = "$($cs.Manufacturer)".Trim(); Model = "$($cs.Model)".Trim(); Serial = "$((Get-CimInstance Win32_BIOS).SerialNumber)".Trim()
        BoardMaker = "$($board.Manufacturer)".Trim(); BoardProduct = "$($board.Product)".Trim()
        Chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes | ForEach-Object { [int]$_ })
        UsedPct = [int](100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
        Slots = [int]$arr.MemoryDevices; MaxKB = [long]$(if ($arr.MaxCapacityEx) { $arr.MaxCapacityEx } else { $arr.MaxCapacity })
        Modules = @($mods); Disks = @($disks); CFreePct = $(if ($c.Size) { [int](100 * $c.FreeSpace / $c.Size) } else { 100 })
        Usb4 = [bool](Get-CimInstance Win32_USBController -ErrorAction SilentlyContinue | Where-Object Name -match 'USB4|Thunderbolt')
        Batteries = @($batteries)
        Cpu = "$($cpu.Name)".Trim(); Cores = [int]$cpu.NumberOfCores; Threads = [int]$cpu.NumberOfLogicalProcessors
        Gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Meta|Mirage|DisplayLink' } | ForEach-Object { $_.Name.Trim() })
        WiFi = $wifi
    }
}

function Get-PcIdentity($Hw) {
    # Custom-built desktops leave the system name as a placeholder; the motherboard then identifies the PC.
    $placeholder = '^(To Be Filled|System (Product )?Name|System manufacturer|Default string|O\.?E\.?M|Not Applicable|None|x\.x|$)'
    $isVM = ("$($Hw.Maker) $($Hw.Model)" -match 'VMware|VirtualBox|innotek|QEMU|KVM|Xen|Parallels|HVM domU|Bochs') -or
            ($Hw.Maker -match '^Microsoft' -and $Hw.Model -match 'Virtual Machine')
    $custom = ($Hw.Model -match $placeholder) -or ($Hw.Maker -match $placeholder)
    $name = if ($custom -and $Hw.BoardProduct) { "$($Hw.BoardMaker) $($Hw.BoardProduct) (custom-built PC)" } else { "$($Hw.Maker) $($Hw.Model)".Trim() }
    $laptop = [bool]($Hw.Chassis | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 })
    if (-not $laptop -and -not ($Hw.Chassis | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 35, 36 }) -and $Hw.Batteries.Count) { $laptop = $true }   # unknown chassis + battery
    [pscustomobject]@{ Name = $name; IsVM = $isVM; Custom = $custom; Laptop = $laptop }
}

function Get-UpgradeRows($Hw) {
    $id = Get-PcIdentity $Hw
    $rows = New-Object System.Collections.ArrayList
    function Add-Upg($Part, $Now, $Option, $Worth, $Spec, $Why) {
        [void]$rows.Add([pscustomobject]@{ Part = $Part; Now = $Now; Option = $Option; Worth = $Worth; Spec = $Spec; Why = $Why })
    }
    $totalGB = ($Hw.Modules | Measure-Object SizeGB -Sum).Sum
    if ($id.IsVM) {
        Add-Upg 'Memory / disk' "$totalGB GB memory - this is a virtual machine" 'Change the VM settings' 'n/a' `
            'Nothing to buy - give the virtual machine more memory or disk space in VMware / VirtualBox / Hyper-V settings.' 'Physical upgrades belong to the computer that runs the VM.'
        return , $rows
    }

    # --- Memory ---
    $memTypes = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $jedec = @{ '2C' = 'Micron'; 'CE' = 'Samsung'; 'AD' = 'SK hynix'; '9B' = 'Crucial'; '98' = 'Kingston'; 'CB' = 'ADATA'; '9E' = 'Corsair'; 'CD' = 'G.Skill'; '4F' = 'Transcend'; 'C1' = 'Infineon'; 'FE' = 'Elpida' }
    $mods = @($Hw.Modules)
    if ($mods) {
        $m = $mods[0]
        $type = $memTypes[$m.SmbiosType]; if (-not $type) { $type = $memTypes[$m.MemoryType] }
        $guessed = $false
        if (-not $type) {   # older firmware doesn't say; the speed gives it away
            $guessed = $true
            $type = if ($m.Speed -ge 4800) { 'DDR5' } elseif ($m.Speed -ge 2133) { 'DDR4' } elseif ($m.Speed -ge 800) { 'DDR3' } else { 'DDR2' }
        }
        $speed = ($mods | Where-Object Speed | Measure-Object Speed -Minimum).Minimum   # mixed modules all run at the slowest one's speed
        $isRemovable = { param($x) $x.FormFactor -in 8, 12 -and -not ($memTypes[$x.SmbiosType] -like 'LP*') }
        $removable = @($mods | Where-Object { & $isRemovable $_ })
        $soldered = @($mods | Where-Object { -not (& $isRemovable $_) })
        $solderedGB = ($soldered | Measure-Object SizeGB -Sum).Sum
        $ff = if ($removable) { $removable[0].FormFactor } elseif ($id.Laptop) { 12 } else { 8 }
        $ffName = if ($ff -eq 12) { 'SO-DIMM (laptop size)' } else { 'DIMM (desktop size)' }
        $pins = @{ 'DDR5|12' = 262; 'DDR5|8' = 288; 'DDR4|12' = 260; 'DDR4|8' = 288; 'DDR3|12' = 204; 'DDR3|8' = 240; 'DDR2|12' = 200; 'DDR2|8' = 240 }["$type|$ff"]
        $volt = if ($m.VoltageMV) { '{0:0.0#} V' -f ($m.VoltageMV / 1000) } elseif ($type -eq 'DDR3') { '1.35 or 1.5 V (match the fitted module)' } else { '' }
        $kind = if ($m.Registered) { 'registered ECC (RDIMM)' } elseif ($m.ECC) { 'unbuffered ECC' } else { 'non-ECC' }
        $maker = $m.Maker
        if ($maker -match '^[0-9A-F]{4,}$') { $code = $maker.Substring(2, 2); if ($jedec[$code]) { $maker = $jedec[$code] } }
        $slots = [Math]::Max($Hw.Slots, $mods.Count)
        $maxGB = [int][Math]::Round($Hw.MaxKB / 1MB)
        if ($maxGB -lt $totalGB -or $maxGB -gt 2048) { $maxGB = 0 }   # firmware sometimes reports nonsense
        $free = $slots - $mods.Count
        $layout = (($mods | Group-Object SizeGB | ForEach-Object { "$($_.Count) x $($_.Name) GB" }) -join ' + ')
        $where = if (-not $removable -and -not $free) { 'soldered to the motherboard' }
                 elseif ($free) { "$(if ($solderedGB) { "$solderedGB GB soldered, " })$free of $slots slot(s) free" }
                 else { "$(if ($solderedGB) { "$solderedGB GB soldered, " })all $slots slot(s) used" }
        $now = "$totalGB GB: $layout $type-$speed ($maker $($m.Part)), $where"
        $check = 'Crucial''s free System Scanner (crucial.com) or the service manual lists the exact modules this PC accepts.'
        if (-not $removable -and -not $free) {
            Add-Upg 'Memory' $now 'Not upgradeable' 'n/a' 'Nothing to buy - this memory is soldered to the motherboard.' `
                "$type memory that isn't a removable module can't be swapped or added to. If memory is the bottleneck, the next PC needs more of it."
        } else {
            $tiers = if ($id.Laptop) { 8, 16, 32, 64 } else { 8, 16, 32, 64, 128 }
            $target = ($tiers | Where-Object { $_ -gt $totalGB } | Select-Object -First 1)
            if (-not $target) { $target = $totalGB }
            if ($maxGB -and $target -gt $maxGB) { $target = $maxGB }
            # Soldered LPDDR next to a slot: the slot itself takes normal DDR of the same generation.
            $buyType = if ($removable) { $type } else { $type -replace '^LP', '' }
            if ($buyType -ne $type) { $pins = @{ 'DDR5|12' = 262; 'DDR4|12' = 260; 'DDR3|12' = 204 }["$buyType|12"]; $volt = '' }
            $base = "$buyType-$speed $ffName$(if ($pins) { ", $pins-pin" })$(if ($volt) { ", $volt" }), $kind"
            if ($target -le $totalGB) {
                Add-Upg 'Memory' $now 'Already at the maximum' 'Not needed' "Nothing to buy - $totalGB GB is the most this PC supports." "The firmware reports a maximum of $maxGB GB."
            } else {
                $each = if ($removable) { $removable[0].SizeGB } else { [int](($target - $totalGB) / [Math]::Max(1, $free)) }
                if ($free -gt 0 -and ($totalGB + $free * $each) -ge $target) {
                    $n = [Math]::Ceiling(($target - $totalGB) / $each)
                    $option = "Add $n x $each GB (total $($totalGB + $n * $each) GB)"
                    $spec = "$n x $each GB $base - $(if ($removable) { 'match the module already fitted' } else { 'same speed as the built-in memory' }). Total afterwards: $($totalGB + $n * $each) GB."
                } else {
                    $remSlots = [Math]::Max(1, $slots - $soldered.Count)
                    $per = [Math]::Max(4, [int][Math]::Pow(2, [Math]::Ceiling([Math]::Log(($target - $solderedGB) / $remSlots, 2))))
                    $newTotal = $solderedGB + $remSlots * $per
                    if ($maxGB -and $newTotal -gt $maxGB) { $per = [int](($maxGB - $solderedGB) / $remSlots); $newTotal = $solderedGB + $remSlots * $per }
                    $option = "Replace with $remSlots x $per GB (total $newTotal GB)"
                    $spec = if ($remSlots -gt 1) { "A matched kit of $remSlots x $per GB $base. The current modules come out (keep or sell them)." }
                            else { "1 x $per GB $base in place of the current module$(if ($solderedGB) { " (the $solderedGB GB soldered memory stays)" })." }
                }
                if ($guessed) { $spec += " ($type worked out from the speed - double-check before buying.)" }
                $spec += " Faster-rated $type modules also work and simply run at $speed MT/s." + $(if ($maxGB) { " Most supported: $maxGB GB." })
                $single = $mods.Count -eq 1 -and $slots -ge 2
                $worth = if ($single) { 'Recommended - one module means single-channel; a matching second module roughly doubles memory speed' }
                         elseif ($totalGB -lt 8) { 'Strongly recommended' }
                         elseif ($totalGB -lt 16) { 'Recommended' }
                         elseif ($Hw.UsedPct -ge 80) { "Recommended - memory is $($Hw.UsedPct)% full right now" }
                         elseif ($totalGB -lt 32) { 'Optional - worth it for virtual machines, big spreadsheets, photo/video/CAD work or many browser tabs' }
                         else { 'Not needed' }
                Add-Upg 'Memory' $now $option $worth $spec "Memory is $($Hw.UsedPct)% used right now. Modules must match the type ($type) and size ($ffName). $check"
            }
        }
    }

    # --- Storage ---
    $internal = @($Hw.Disks | Where-Object { $_.Bus -notin 'USB', 'SD', 'MMC', 'File Backed Virtual' })
    foreach ($d in $internal) {
        $media = if ($d.Media -eq 'HDD' -or ($d.Media -notin 'SSD', 'SCM' -and $d.Spindle -gt 0 -and $d.Spindle -lt 100000)) { 'HDD' }
                 elseif ($d.Media -in 'SSD', 'SCM' -or $d.Name -match 'SSD|NVMe|Solid') { 'SSD' } else { 'drive' }
        $now = "$($d.Name): $($d.SizeGB) GB $($d.Bus) $media$(if ($d.IsSystem) { ", holds Windows (C: $($Hw.CFreePct)% free)" })"
        if ($media -eq 'HDD') {
            $spec = if ($id.Laptop) { '1 TB 2.5-inch SATA SSD (7 mm) in place of this hard disk, or an M.2 SSD if the laptop has an M.2 slot. Copy ("clone") the old drive with the SSD maker''s free tool.' }
                    else { '1 TB SSD: M.2 NVMe if the motherboard has an M.2 slot (fastest), otherwise a 2.5-inch SATA SSD. Put Windows on it and keep the hard disk for files.' }
            Add-Upg 'Drive' $now 'Replace with an SSD' $(if ($d.IsSystem) { 'Strongly recommended - the biggest speed-up an older PC can get' } else { 'Optional - only matters for files on this disk' }) $spec `
                'Hard disks are 20-50x slower than SSDs at the small reads Windows does all the time.'
        } elseif ($d.IsSystem) {
            $worth = if ($Hw.CFreePct -lt 15) { "Recommended - C: is only $($Hw.CFreePct)% free" } elseif ($d.SizeGB -lt 300) { 'Recommended - small drive' } else { 'Optional' }
            $form = if ($d.Bus -eq 'NVMe' -or $d.Name -match 'NVMe') { 'M.2 2280 NVMe SSD, PCIe Gen4 x4 (also works in Gen3 slots)' }
                    elseif ($d.Bus -eq 'SATA' -and -not $id.Laptop) { '2.5-inch SATA SSD, or M.2 NVMe if the motherboard has an M.2 slot' }
                    elseif ($d.Bus -eq 'SATA') { '2.5-inch SATA SSD, or M.2 if the laptop has an M.2 slot (check whether it takes SATA or NVMe M.2)' }
                    else { 'SSD of the same type as the current one' }
            $spec = "$form, 1 TB or 2 TB."
            $spec += if ($id.Laptop) { ' If the laptop has a free M.2 slot, add it as a second drive; if not, replace this drive with the bigger one and clone it.' }
                     else { ' Desktops usually have spare M.2 slots or 2.5/3.5-inch bays - add it as a second drive.' }
            Add-Upg 'Drive' $now 'Bigger or second SSD' $worth $spec 'Windows cannot see empty slots, so check the manual for a free one. Gen4 drives fall back to the slot''s speed, so they are always a safe pick.'
        }
    }
    Add-Upg 'External drive' $(if ($Hw.Usb4) { 'This PC has a USB4/Thunderbolt port' } else { 'USB ports' }) 'External SSD' 'Optional - no screwdriver needed, good for games, photos and backups' `
        $(if ($Hw.Usb4) { 'External NVMe SSD (or an NVMe enclosure) for USB4/Thunderbolt, 1-2 TB: up to ~3,000 MB/s on this PC.' } else { 'USB 3.2 Gen 2 external SSD, 1-2 TB (about 1,000 MB/s) - use a blue or "SS 10" USB port.' }) `
        'Use the fastest port: USB4/Thunderbolt (lightning symbol) > USB-C 10 Gbps > blue USB-A.'

    # --- Battery ---
    foreach ($b in $Hw.Batteries) {
        $worth = if ($b.Pct -lt 60) { 'Recommended - battery life is roughly halved' } elseif ($b.Pct -lt 80) { 'Optional' } else { 'Not needed' }
        Add-Upg 'Battery' "$($b.Wh) Wh $($b.Chem) battery ($($b.Maker)), now holds $($b.Pct)% of its original charge" 'Replacement battery' $worth `
            "Replacement battery for the $($id.Name): $($b.Wh) Wh $($b.Chem). It reports itself as '$($b.Id)' - search that, or the serial number, to find the exact part. Prefer the maker's original." `
            'Batteries wear with age and charge cycles. A worn battery doesn''t slow the PC down, it just runs out sooner.'
    }

    # --- Wi-Fi ---
    $w = @($Hw.WiFi)[0]
    if ($w) {
        $gen = if ($w -match 'BE\d{3}|Wi-?Fi 7') { 7 } elseif ($w -match 'AX2\d\d|AX4\d\d|6E') { 6 } elseif ($w -match 'AX\d|Wi-?Fi 6') { 6 }
               elseif ($w -match 'AC\d|\bAC\b|Wi-?Fi 5|802\.11 ?a?c') { 5 }
               elseif ($w -match '\bN\b|-N |802\.11 ?b?g?n|\bbgn\b|Wireless-N|Wireless N|\bN\d{3,4}') { 4 } else { 0 }
        $genName = @{ 7 = 'Wi-Fi 7'; 6 = 'Wi-Fi 6/6E'; 5 = 'Wi-Fi 5'; 4 = 'Wi-Fi 4' }[$gen]
        $spec = if ($id.Laptop) { 'M.2 2230 Wi-Fi 6E card with Bluetooth (e.g. Intel AX210). Most laptops let you swap it; a few have it soldered or only accept approved cards - check the manual.' }
                else { 'PCIe Wi-Fi 6E card with Bluetooth (e.g. Intel AX210 based), or a USB Wi-Fi 6 adapter if you''d rather not open the case.' }
        $worth = switch ($gen) { 4 { 'Recommended - Wi-Fi 4 is slow and crowded' } 5 { 'Optional - faster and steadier on a Wi-Fi 6 router' }
                                 0 { 'Optional - check which Wi-Fi standard this card supports' } default { 'Not needed' } }
        if ($gen -ge 6) { $spec = 'Nothing to buy - this Wi-Fi is already current.' }
        Add-Upg 'Wi-Fi' "$w$(if ($genName) { " ($genName)" })" $(if ($gen -ge 6) { 'Already modern' } else { 'Wi-Fi 6E card' }) $worth $spec 'Faster Wi-Fi only helps if your router supports it too.'
    } elseif (-not $id.Laptop) {
        Add-Upg 'Wi-Fi' 'No Wi-Fi adapter' 'Add Wi-Fi' 'Optional - only if you can''t use a cable' 'PCIe Wi-Fi 6E card with Bluetooth, or a USB Wi-Fi 6 adapter.' 'A network cable is still the fastest and steadiest connection.'
    }

    # --- Processor and graphics ---
    $cpuNow = "$($Hw.Cpu) - $($Hw.Cores) cores / $($Hw.Threads) threads"
    $gpuNow = if ($Hw.Gpus) { $Hw.Gpus -join ' + ' } else { 'Not read - Windows didn''t answer in time (busy with a game?). Click Refresh later.' }
    if ($id.Laptop) {
        Add-Upg 'Processor' $cpuNow 'Not upgradeable' 'n/a' 'Nothing to buy - laptop processors are soldered to the motherboard.' 'If the processor is too slow, the upgrade path is a new laptop.'
        Add-Upg 'Graphics' $gpuNow 'Not upgradeable' 'n/a' 'Nothing to buy - laptop graphics are soldered.' $(if ($Hw.Usb4) { 'An external graphics box over USB4/Thunderbolt is possible but costly.' } else { '' })
    } else {
        Add-Upg 'Processor' $cpuNow 'Depends on the motherboard' 'Rarely worth it' "Check the CPU support list of the motherboard ($($Hw.BoardMaker) $($Hw.BoardProduct)) on its maker's website." `
            'A new processor only fits the same socket and often needs a BIOS update first.'
        $integrated = $gpuNow -and -not ($Hw.Gpus | Where-Object { $_ -match 'NVIDIA|Radeon RX|Radeon Pro|Arc A|Arc B|GeForce|Quadro|FirePro' })
        Add-Upg 'Graphics' $gpuNow $(if ($integrated) { 'Add a graphics card' } else { 'Faster graphics card' }) $(if ($integrated) { 'Optional - for gaming, video editing or 3D' } else { 'Depends on use' }) `
            'Needs a free PCIe x16 slot, enough power-supply wattage and connectors, and room in the case - check all three first.' `
            'Office PCs from HP, Dell and Lenovo often have small power supplies; a low-profile card that needs no power cable is the safe choice there.'
    }
    , $rows
}

# Where to look up this exact PC: maker support pages take the serial number (copied to the clipboard).
function Get-SupportInfo($Hw) {
    $id = Get-PcIdentity $Hw
    $maker = if ($id.Custom) { $Hw.BoardMaker } else { $Hw.Maker }
    $pages = [ordered]@{
        'Dell'                 = "https://www.dell.com/support/home/en-us/product-support/servicetag/$($Hw.Serial)/overview"
        'Lenovo'               = 'https://pcsupport.lenovo.com/'
        'HP|Hewlett'           = 'https://support.hp.com/'
        'ASUS'                 = 'https://www.asus.com/support/'
        'Acer'                 = 'https://www.acer.com/support'
        'Micro-Star|MSI'       = 'https://www.msi.com/support'
        'Microsoft'            = 'https://support.microsoft.com/surface'
        'Samsung'              = 'https://www.samsung.com/support/'
        'Gigabyte'             = 'https://www.gigabyte.com/Support'
        'ASRock'               = 'https://www.asrock.com/support/'
        'Fujitsu'              = 'https://support.ts.fujitsu.com/'
        'Toshiba|Dynabook'     = 'https://support.dynabook.com/'
        'Razer'                = 'https://mysupport.razer.com/'
        'Medion'               = 'https://www.medion.com/support'
        'Framework'            = 'https://frame.work/support'
    }
    $url = $null
    foreach ($k in $pages.Keys) { if ($maker -match $k) { $url = $pages[$k]; break } }
    $serialOk = $Hw.Serial -and $Hw.Serial -notmatch '^(To Be Filled.*|Default string|System Serial.*|Serial.?Number|Not Specified|Chassis Serial.*|0+|None|N/A|123456789)$'
    $query = if ($id.Custom) { "$($Hw.BoardMaker) $($Hw.BoardProduct) motherboard manual" } else { "$($id.Name) service manual memory SSD upgrade" }
    [pscustomobject]@{ Name = $id.Name; Url = $url; Serial = $(if ($serialOk) { $Hw.Serial } else { '' })
                       Manual = 'https://www.bing.com/search?q=' + [uri]::EscapeDataString($query); Custom = $id.Custom }
}

function Update-Upgrades {
    $btnUpgReload.Enabled = $false
    $txtUpg.Text = 'Looking at this PC''s hardware...'
    Start-Bg -Label 'Reading the hardware' $UpgradeCollectWork $null {
        param($r)
        $btnUpgReload.Enabled = $true
        if (-not $r) { $txtUpg.Text = 'Could not read the hardware details.'; return }
        $script:UpgHw = $r[0]
        $script:UpgInfo = Get-SupportInfo $script:UpgHw
        $btnUpgSupport.Enabled = [bool]$script:UpgInfo.Url
        $btnUpgManual.Text = if ($script:UpgInfo.Custom) { 'Find motherboard manual' } else { 'Find service manual' }
        $lvUpg.BeginUpdate(); $lvUpg.Items.Clear()
        $ms = Get-MemStats 14
        foreach ($u in (Get-UpgradeRows $script:UpgHw)) {
            # What memory use has been like (from PC Tune-Up's own notes, once there are enough of them).
            if ($u.Part -eq 'Memory' -and $ms -and $ms.Samples -ge 36 -and $ms.Days -ge 2) {
                $line = if ($ms.FullPct -ge 20) { 'Over the last {0} day(s) memory was nearly full {1}% of the time - more memory would make a real difference.' }
                        elseif ($ms.FullPct -lt 5) { 'Over the last {0} day(s) memory was rarely nearly full ({1}% of the time) - more memory would hardly be noticed.' }
                        else { 'Over the last {0} day(s) memory was nearly full {1}% of the time.' }
                $u.Why = (($u.Why, (T $line).Replace('{0}', "$($ms.Days)").Replace('{1}', "$($ms.FullPct)")) | Where-Object { $_ }) -join "`r`n"
            }
            $it = Add-Row $lvUpg @($u.Part, $u.Now, $u.Option, $u.Worth, $u.Spec) $u
            if ($u.Worth -like 'Strongly*' -or $u.Worth -like 'Recommended*') { $it.ForeColor = $Theme.Bad }
            elseif ($u.Worth -in 'n/a', 'Not needed') { $it.ForeColor = $Theme.Muted }
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
$btnUpgSupport.Add_Click({
    $i = $script:UpgInfo
    if (-not $i.Url) { return }
    if ($i.Serial -and $i.Url -notmatch [regex]::Escape($i.Serial)) {
        [Windows.Forms.Clipboard]::SetText($i.Serial)
        Show-Msg "The serial number ($($i.Serial)) is copied - paste it into the support page's search box to see this exact PC's parts." | Out-Null
    }
    Start-Process $i.Url
})
$btnUpgManual.Add_Click({ if ($script:UpgInfo) { Start-Process $script:UpgInfo.Manual } })
$btnUpgCopy.Add_Click({
    $items = @($lvUpg.Items | ForEach-Object Tag | Where-Object { $_.Worth -notin 'n/a', 'Not needed' })
    if (-not $items) { Show-Msg 'Nothing worth upgrading was found.' | Out-Null; return }
    $text = "Upgrade shopping list for $($script:UpgInfo.Name)$(if ($script:UpgInfo.Serial) { " (serial $($script:UpgInfo.Serial))" })`r`n`r`n" + (($items | ForEach-Object { "- $($_.Part) ($($_.Worth)):`r`n  $($_.Spec)" }) -join "`r`n`r`n")
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
$lvHist = New-ListView $true @('When', 140, 'What', 100, 'Item', 270, 'Change', 300, 'Undo', 150)
$lblHist = New-Status
Set-PageLayout $pgHist $lvHist @((New-ButtonBar @($btnHistReload, $btnHistUndo, $btnHistLog))) $lblHist

function Get-UndoStatus($E) {
    if ($E.Undone) { 'undone' } elseif ($E.Undo.Type -eq 'Store') { 'reinstall from Store' } elseif ($E.Undo) { 'can undo' } else { '-' }
}
function Update-History {
    $entries = @(Get-History)
    $lvHist.BeginUpdate(); $lvHist.Items.Clear()
    foreach ($e in $entries | Sort-Object Time -Descending) {
        $status = Get-UndoStatus $e
        $it = Add-Row $lvHist @(([datetime]$e.Time).ToString('g'), $e.Kind, $e.Item, $e.Change, $status) $e
        if ($status -eq 'undone' -or $status -eq '-') { $it.ForeColor = $Theme.Muted }
    }
    $lvHist.EndUpdate()
    $script:LastClean = @($entries | Where-Object { $_.Kind -in 'Clean', 'Maintenance' } | ForEach-Object { [datetime]$_.Time } | Sort-Object -Descending)[0]   # for the clean-up reminder
    $n = @($entries | Where-Object { (Get-UndoStatus $_) -eq 'can undo' }).Count
    $lblHist.Text = if ($entries.Count) { "$($entries.Count) change(s) recorded, $n can be undone." } else { 'No changes yet. (Changes from before this version are in the text log.)' }
}
$btnHistReload.Add_Click({ Update-History })
$btnHistLog.Add_Click({ Open-ChangeLog })
$btnHistUndo.Add_Click({
    $picked = @($lvHist.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { (Get-UndoStatus $_) -in 'can undo', 'reinstall from Store' })
    if (-not $picked) { Show-Msg 'Check one or more rows that say "can undo" first.' | Out-Null; return }
    if ($IsAdmin -eq $false -and ($picked | Where-Object { $_.Undo.Type -eq 'Service' -or ($_.Undo.Type -eq 'Cmd' -and $_.Undo.Admin) -or $_.Undo.Type -eq 'Hosts' })) {
        Show-Msg 'Some of these changes need administrator rights to undo - use "Restart as administrator" first.' 'OK' 'Warning' | Out-Null; return
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
                'Task' {
                    if ($u.Enable) { [void](Enable-ScheduledTask -TaskPath $u.Path -TaskName $u.Name -ErrorAction Stop) }
                    else { [void](Disable-ScheduledTask -TaskPath $u.Path -TaskName $u.Name -ErrorAction Stop) }
                    $logs += , @('Undo', $e.Item, $(if ($u.Enable) { 'scheduled task switched back on' } else { 'scheduled task switched off again' }))
                }
                'Power' {
                    foreach ($a in @($u.Cmds)) { Invoke-PowerCfg $a }
                    $logs += , @('Undo', $e.Item, 'put back as it was')
                }
                'Hosts' {
                    Add-HostsLines @($u.Lines)
                    $logs += , @('Undo', $e.Item, 'put back as it was')
                }
                'PowerMode' {
                    Set-PowerMode ([bool]$u.Ac) $u.Old
                    $logs += , @('Undo', $e.Item, 'put back as it was')
                }
                'Cmd' {
                    $p = Start-Process $u.Exe -ArgumentList $u.Args -Wait -PassThru -WindowStyle Hidden
                    if ($p.ExitCode) { throw "$($u.Exe) $($u.Args): exit code $($p.ExitCode)" }
                    $logs += , @('Undo', $e.Item, 'put back as it was')
                }
                'Reg' {
                    foreach ($v in @($u.Values)) {
                        Set-RegValue $v.P $v.N $v.Old $v.T
                        $k = Get-Item -LiteralPath $v.P -ErrorAction SilentlyContinue
                        if ($v.Created -and $k -and -not $k.GetValueNames().Count -and -not $k.SubKeyCount) { Remove-Item -LiteralPath $v.P -ErrorAction SilentlyContinue }
                    }
                    $logs += , @('Undo', $e.Item, 'setting put back as it was')
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
# Settings / About
# ===========================================================================
$pgSet = New-Page 'Settings' 'How PC Tune-Up looks and behaves, where its files are, and what it is. Changes are saved straight away.'
$setFlow = New-Object Windows.Forms.FlowLayoutPanel
$setFlow.Dock = 'Fill'; $setFlow.FlowDirection = 'TopDown'; $setFlow.WrapContents = $false; $setFlow.AutoScroll = $true
Set-PageLayout $pgSet $setFlow @()
function Add-SetSection([string]$Title, [string]$Hint) {
    $t = New-Object Windows.Forms.Label
    $t.Text = $Title; $t.Font = $FontBold; $t.AutoSize = $true; $t.Margin = New-Object Windows.Forms.Padding(0, 16, 0, 2)
    $setFlow.Controls.Add($t)
    if ($Hint) {
        $h = New-Object Windows.Forms.Label
        $h.Text = $Hint; $h.ForeColor = $Theme.Dim; $h.AutoSize = $true; $h.MaximumSize = New-Object Drawing.Size((Px 720), 0)
        $h.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 4)
        $setFlow.Controls.Add($h)
    }
}
function Add-SetRow([object[]]$Controls) {
    $row = New-Object Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true; $row.WrapContents = $false; $row.Margin = New-Object Windows.Forms.Padding(0, 2, 0, 2)
    foreach ($c in $Controls) { $row.Controls.Add($c) }
    $setFlow.Controls.Add($row)
}
function New-Choice([string[]]$Labels, [string[]]$Values, [string]$Current) {
    $c = New-Object Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.Width = 270; $c.FlatStyle = 'Flat'; $c.BackColor = $Theme.Input; $c.ForeColor = $Theme.Text
    $c.Margin = New-Object Windows.Forms.Padding(0, 4, 10, 0)
    foreach ($l in $Labels) { [void]$c.Items.Add((T $l)) }
    $c.SelectedIndex = [Math]::Max(0, [array]::IndexOf($Values, $Current))
    $c.Tag = $Values
    $c.Add_HandleCreated({ Set-DarkChrome $this 'DarkMode_CFD' })
    $c
}
function New-Check([string]$Text, [bool]$Checked) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text = $Text; $c.Checked = $Checked; $c.AutoSize = $true; $c.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    $c
}
function Restart-App {
    if ($RunningAsExe) { Start-Process $SelfExe } else { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
    $form.Close()
}

Add-SetSection 'View' 'Simple view shows one calm screen with three big buttons and only safe fixes - best for most people. Advanced view shows every page.'
$cmbView = New-Choice @('Simple view', 'Advanced view') @('simple', 'full') $Settings.View
Add-SetRow @($cmbView)
$cmbView.Add_SelectedIndexChanged({ $v = $this.Tag[$this.SelectedIndex]; if ($v -ne $Settings.View) { Set-ViewMode $v } })

Add-SetSection 'Language' 'Takes effect when PC Tune-Up restarts.'
$cmbLang = New-Choice @('Automatic (Windows language)', 'English', 'Nederlands', 'Deutsch', 'Français', 'Español', 'Italiano', 'Polski') @('auto', 'en', 'nl', 'de', 'fr', 'es', 'it', 'pl') $Settings.Language
$btnLangRestart = New-Button 'Restart now'
Add-SetRow @($cmbLang, $btnLangRestart)
$cmbLang.Add_SelectedIndexChanged({ $Settings.Language = $this.Tag[$this.SelectedIndex]; Save-Settings })
$btnLangRestart.Add_Click({ Restart-App })

Add-SetSection 'Theme' 'Light, dark, or the same as Windows. Takes effect when PC Tune-Up restarts.'
$cmbTheme = New-Choice @('Same as Windows', 'Light', 'Dark') @('system', 'light', 'dark') $Settings.Theme
$btnThemeRestart = New-Button 'Restart now'
Add-SetRow @($cmbTheme, $btnThemeRestart)
$cmbTheme.Add_SelectedIndexChanged({ $Settings.Theme = $this.Tag[$this.SelectedIndex]; Save-Settings })
$btnThemeRestart.Add_Click({ Restart-App })

Add-SetSection 'Updates' "You have version $AppVersion. New versions come from github.com/$UpdateRepo and are checked against GitHub's checksum before they are installed."
$chkUpd = New-Check 'Check for updates when PC Tune-Up starts' ([bool]$Settings.CheckUpdates)
$chkUpd.Add_CheckedChanged({ $Settings.CheckUpdates = $this.Checked; Save-Settings })
$btnUpdate = New-Button 'Check for updates now'
Add-SetRow @($chkUpd); Add-SetRow @($btnUpdate)

Add-SetSection 'Safety' 'A restore point lets Windows roll the whole PC back to before a change (Settings > System > Recovery, or search "restore point"). Windows makes at most one per day.'
$chkRp = New-Check 'Create a restore point before Fix my PC, uninstalling and service changes (needs administrator)' ([bool]$Settings.RestorePoints)
$chkRp.Add_CheckedChanged({ $Settings.RestorePoints = $this.Checked; Save-Settings })
Add-SetRow @($chkRp)

Add-SetSection 'Automatic maintenance' 'PC Tune-Up cleans junk files and checks the PC by itself on Sunday around noon (or as soon as the PC is on and not in use), then shows a notification. Startup apps, services and programs are never changed without you.'
$cmbAuto = New-Choice @('Off', 'Every week', 'Every 4 weeks') @('off', 'weekly', 'monthly') $Settings.AutoMaintenance
$btnAutoNow = New-Button 'Run now'
Add-SetRow @($cmbAuto, $btnAutoNow)
$cmbAutoNote = New-Choice @('Notify me when something is new (recommended)', 'Notify me after every run', 'Never notify me') @('changes', 'always', 'never') $Settings.AutoNotify
$cmbAutoNote.Width = 380
$cmbAutoNote.Add_SelectedIndexChanged({ $Settings.AutoNotify = $this.Tag[$this.SelectedIndex]; Save-Settings })
Add-SetRow @($cmbAutoNote)
$lblAutoLast = New-Object Windows.Forms.Label
$lblAutoLast.AutoSize = $true; $lblAutoLast.ForeColor = $Theme.Dim; $lblAutoLast.Margin = New-Object Windows.Forms.Padding(0, 2, 0, 0)
$lblAutoLast.Text = if ($Settings.LastAuto) { "Last run: $($Settings.LastAuto)" } else { 'Not run yet.' }
$setFlow.Controls.Add($lblAutoLast)
$MaintTaskName = 'PC Tune-Up maintenance'
# The task runs the installed exe as this user (no administrator), only when the PC is idle, also on battery.
function Set-MaintenanceTask([string]$Mode) {
    if ($Mode -eq 'off') { Unregister-ScheduledTask -TaskName $MaintTaskName -Confirm:$false -ErrorAction SilentlyContinue; return $true }
    if ($IsInstalled) { $exe = $InstalledExe; $arg = '/auto' }
    elseif ($FromWinget) { $exe = $SelfExe; $arg = '/auto' }
    elseif (-not $RunningAsExe) { $exe = 'powershell.exe'; $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" /auto" }   # developer mode
    else { Show-Msg 'Install PC Tune-Up first (Settings > Installation): the automatic run needs it in a fixed place.' 'OK' 'Warning' | Out-Null; return $false }
    try {
        $action = New-ScheduledTaskAction -Execute $exe -Argument $arg
        $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval $(if ($Mode -eq 'monthly') { 4 } else { 1 }) -DaysOfWeek Sunday -At '12:00'
        $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfIdle -IdleDuration '00:05:00' -IdleWaitTimeout '04:00:00' `
                   -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
        $set.IdleSettings.StopOnIdleEnd = $false
        $who = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $MaintTaskName -Action $action -Trigger $trigger -Settings $set -Principal $who `
            -Description 'PC Tune-Up: clean junk files and check the PC, then show a notification. Change it in PC Tune-Up > Settings.' -Force -ErrorAction Stop | Out-Null
        $true
    } catch { Show-Msg "Couldn't set up automatic maintenance: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null; $false }
}
$cmbAuto.Add_SelectedIndexChanged({
    $mode = $this.Tag[$this.SelectedIndex]
    if ($mode -eq $Settings.AutoMaintenance) { return }
    if (Set-MaintenanceTask $mode) {
        $Settings.AutoMaintenance = $mode; Save-Settings
        Add-History 'Settings' 'Automatic maintenance' $(switch ($mode) { 'off' { 'switched off' } 'weekly' { 'every week' } default { 'every 4 weeks' } })
        Update-History
    } else { $this.SelectedIndex = [array]::IndexOf($this.Tag, $Settings.AutoMaintenance) }
})
$btnAutoNow.Add_Click({
    if ($RunningAsExe) { Start-Process $SelfExe '/auto' } else { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" /auto" }
    Show-Msg 'The maintenance run has started in the background. A notification appears when it is done (in a minute or two).' | Out-Null
})

Add-SetSection 'Installation' $(if ($FromWinget) { 'Installed with winget - update or remove it with winget (winget upgrade / winget uninstall MichaelKloprogge.PCTuneUp).' }
                                 elseif ($IsInstalled) { "Installed for you in $InstallDir - it appears in the Start menu and in Settings > Apps." }
                                 elseif ($RunningAsExe) { "Running from $SelfExe without installing. Install to get a Start-menu entry and uninstall it like any other app (no administrator needed)." }
                                 else { 'Running as a PowerShell script (developer mode) - install from PC-TuneUp.exe instead.' })
$btnInstall = New-Button $(if ($IsInstalled) { 'Uninstall PC Tune-Up' } else { 'Install on this PC' })
$btnInstall.Enabled = $RunningAsExe -and -not $FromWinget
Add-SetRow @($btnInstall)
$btnInstall.Add_Click({ if ($IsInstalled) { Uninstall-App } else { Install-App -Launch } })

Add-SetSection 'Files' "Settings, history, the keep list and the change log are kept in $DataDir."
$btnSetKeep = New-Button 'Keep list'; $btnSetLog = New-Button 'Change log'; $btnSetData = New-Button 'Open data folder'; $btnSetReport = New-Button 'Save report'
$btnSetErr = New-Button 'Error log'
Add-SetRow @($btnSetKeep, $btnSetLog, $btnSetErr, $btnSetData, $btnSetReport)
$btnSetErr.Add_Click({
    if (Test-Path $ErrorLogFile) { Start-Process notepad.exe "`"$ErrorLogFile`"" }
    else { Show-Msg 'No problems inside PC Tune-Up have been recorded.' | Out-Null }
})
$btnSetKeep.Add_Click({ Open-KeepList })
$btnSetLog.Add_Click({ Open-ChangeLog })
$btnSetData.Add_Click({ Start-Process explorer.exe "`"$DataDir`"" })
$btnSetReport.Add_Click({ Save-Report })

Add-SetSection 'Command line' 'For scripts and IT use (use "start /wait" so the window waits for it):'
$cliHelp = New-Object Windows.Forms.Label
$cliHelp.Font = New-Object Drawing.Font('Consolas', 9.5); $cliHelp.AutoSize = $true; $cliHelp.ForeColor = $Theme.Dim
$cliHelp.Text = "PC-TuneUp.exe /report[:file.html]   check everything and save a report`r`nPC-TuneUp.exe /fix                  run the safe Fix my PC steps without asking`r`nPC-TuneUp.exe /auto                 the automatic maintenance run (clean, check, notify)`r`nPC-TuneUp.exe /install | /uninstall  install or remove for this user"
$setFlow.Controls.Add($cliHelp)

# --- Report a problem / suggest an idea: a GitHub issue filled in with the version, Windows and recent errors ---
# Names, paths and the PC name are blanked out, and the person sees everything before anything is sent (on GitHub).
function Get-ProblemInfo {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = "$($cv.CurrentBuild).$($cv.UBR)"
    $prod = if ([int]$cv.CurrentBuild -ge 22000) { "$($cv.ProductName)" -replace 'Windows 10', 'Windows 11' } else { "$($cv.ProductName)" }
    $how = if ($FromWinget) { 'winget' } elseif ($IsInstalled) { 'installed' } elseif ($RunningAsExe) { 'exe, not installed' } else { 'script' }
    # Longest first: the PC name often contains the user name.
    $clean = { param($t) $t = "$t"; foreach ($p in @($env:USERPROFILE, $env:COMPUTERNAME, $env:USERNAME) | Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object Length -Descending) { $t = $t -ireplace [regex]::Escape($p), '<hidden>' }; $t }
    [pscustomobject]@{
        Version = "$AppVersion ($how, $(if ($IsAdmin) { 'administrator' } else { 'normal user' }), language $Lang)"
        Windows = "$prod $($cv.DisplayVersion) (build $build)"
        Errors  = (@(Get-AppErrors 14) | Select-Object -Last 15 | ForEach-Object { & $clean $_ }) -join "`n"
    }
}
function Open-ProblemReport([string]$Kind = 'bug') {
    $i = Get-ProblemInfo
    if ($Kind -eq 'bug') {
        $preview = "This opens GitHub with a new problem report, filled in with:`n`n  Version: $($i.Version)`n  Windows: $($i.Windows)`n  Recent errors: $(if ($i.Errors) { "$(@($i.Errors -split "`n").Count) line(s) (your name, folders and PC name are blanked out)" } else { 'none' })`n`nYou can read and change everything there before you press Submit. You need a free GitHub account."
        if ((Show-Msg $preview 'OKCancel' 'Information') -ne 'OK') { return }
        $q = "template=bug.yml&version=$([uri]::EscapeDataString($i.Version))&windows=$([uri]::EscapeDataString($i.Windows))"
        $err = $i.Errors; while ($err -and ([uri]::EscapeDataString($err)).Length -gt 5500) { $err = ($err -split "`n" | Select-Object -Skip 1) -join "`n" }   # URLs have a length limit
        if ($err) { $q += "&errors=$([uri]::EscapeDataString($err))" }
    } else { $q = "template=idea.yml&version=$([uri]::EscapeDataString($i.Version))" }
    Start-Process "https://github.com/$UpdateRepo/issues/new?$q"
}

# --- Move settings to another PC: one file with your choices; importing applies what exists on that PC ---
function Export-PcSettings([string]$Path) {   # -Path skips the save dialog (tests)
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = (T 'PC Tune-Up settings') + ' (*.json)|*.json'; $dlg.FileName = 'PC Tune-Up settings.json'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    if ($Path) { $dlg.FileName = $Path } elseif ($dlg.ShowDialog() -ne 'OK') { return }
    $hist = @(Get-History | Where-Object { -not $_.Undone })
    $x = [ordered]@{
        Format = 'PC Tune-Up settings'; Version = $AppVersion; Exported = (Get-Date).ToString('s')
        Settings = [ordered]@{ Language = $Settings.Language; Theme = $Settings.Theme; CheckUpdates = $Settings.CheckUpdates; RestorePoints = $Settings.RestorePoints; AutoNotify = $Settings.AutoNotify }
        KeepList = @(Get-Content $KeepFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' })
        Privacy  = @($PrivacyCatalog | Where-Object { (Get-PrivacyState $_) -eq 'Off' } | ForEach-Object Name)
        Tasks    = @($hist | Where-Object { $_.Kind -eq 'Task' -and $_.Undo.Type -eq 'Task' -and $_.Undo.Enable } | ForEach-Object { $_.Undo.Name } | Select-Object -Unique)
        Startup  = @($hist | Where-Object { $_.Kind -eq 'Startup' -and $_.Undo.Type -eq 'Startup' -and $_.Undo.Enable } | ForEach-Object { $_.Undo.Name } | Select-Object -Unique)
        Services = @($hist | Where-Object { $_.Kind -eq 'Service' -and $_.Undo.Type -eq 'Service' } | ForEach-Object { [ordered]@{ Name = $_.Undo.Name; Start = (($_.Change -split '->')[-1]).Trim() } })
    }
    $x | ConvertTo-Json -Depth 5 | Set-Content -Path $dlg.FileName -Encoding UTF8
    Show-Msg "Saved: $($dlg.FileName)`n`nIt holds your settings, keep list ($($x.KeepList.Count)), privacy choices ($($x.Privacy.Count)), switched-off scheduled tasks ($($x.Tasks.Count)), startup apps ($($x.Startup.Count)) and services ($($x.Services.Count)). No files, passwords or personal data. On the other PC: Settings > Move to another PC > Import." | Out-Null
}
function Import-PcSettings([string]$Path) {   # -Path skips the open dialog (tests)
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = (T 'PC Tune-Up settings') + ' (*.json)|*.json'; $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    if ($Path) { $dlg.FileName = $Path } elseif ($dlg.ShowDialog() -ne 'OK') { return }
    try { $x = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $x = $null }
    if (-not $x -or $x.Format -ne 'PC Tune-Up settings') { Show-Msg 'That is not a PC Tune-Up settings file.' 'OK' 'Warning' | Out-Null; return }
    # Only what exists on this PC, and only what isn't done already
    $priv = @($PrivacyCatalog | Where-Object { $_.Name -in @($x.Privacy) -and (Get-PrivacyState $_) -ne 'Off' -and -not ($_.Admin -and -not $IsAdmin) })
    $tasks = @(foreach ($n in @($x.Tasks)) { Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue | Where-Object State -ne 'Disabled' })
    $start = @($lvStart.Items | Where-Object { $_.Tag.On -and $_.Tag.Name -in @($x.Startup) })
    $svcs = @(foreach ($s in @($x.Services)) { $sv = Get-Service -Name $s.Name -ErrorAction SilentlyContinue; if ($sv -and "$($sv.StartType)" -ne $s.Start) { [pscustomobject]@{ Name = $s.Name; Start = $s.Start; From = "$($sv.StartType)" } } })
    $keep = @($x.KeepList | Where-Object { $_ -notin @(Get-Content $KeepFile -ErrorAction SilentlyContinue) })
    $lines = @(" - Settings: language, theme, updates, restore points, notifications")
    if ($keep) { $lines += " - Keep list: add $($keep.Count) program(s)" }
    if ($priv) { $lines += " - Privacy: turn off $($priv.Count) setting(s)" }
    if ($tasks) { $lines += " - Scheduled tasks: switch off $($tasks.Count)" }
    if ($start) { $lines += " - Startup: stop $($start.Count) app(s) starting with Windows" }
    if ($svcs) { $lines += $(if ($IsAdmin) { " - Services: change $($svcs.Count)" } else { " - Services: $($svcs.Count) skipped (needs administrator)" }) }
    if ((Show-Msg "Import from $(Split-Path $dlg.FileName -Leaf)?`n`n$($lines -join "`n")`n`nOnly what exists on this PC is changed. Everything can be undone from the History page." 'YesNo' 'Question') -ne 'Yes') { return }
    foreach ($p in 'Language', 'Theme', 'CheckUpdates', 'RestorePoints', 'AutoNotify') { if ($null -ne $x.Settings.$p) { $Settings[$p] = $x.Settings.$p } }
    Save-Settings
    if ($keep) { Add-Content -Path $KeepFile -Value $keep -Encoding UTF8 }
    foreach ($p in $priv) { $undo = @(); foreach ($v in @($p.V)) { $t = if ($v.T) { $v.T } else { 'DWord' }; $undo += @{ P = $v.P; N = $v.N; Old = (Get-RegValue $v.P $v.N); T = $t }; Set-RegValue $v.P $v.N $v.Off $t }
                            Add-History 'Privacy' $p.Name 'turned off (imported)' @{ Type = 'Reg'; Values = $undo } }
    foreach ($t in $tasks) { try { [void](Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop); Add-History 'Task' $t.TaskName 'switched off (imported)' @{ Type = 'Task'; Path = $t.TaskPath; Name = $t.TaskName; Enable = $true } } catch { } }
    foreach ($it in $start) { try { Set-StartupEntry $it.Tag $false } catch { } }
    if ($IsAdmin -and $svcs) { $orig = Get-ServiceOriginals; foreach ($s in $svcs) { try { Set-ServiceStart $s.Name $s.Start $s.From $orig } catch { } }; Save-ServiceOriginals $orig }
    Update-History; Update-Startup; if ($script:Loaded['Privacy']) { Update-Privacy }; if ($script:Loaded['Tasks']) { Update-Tasks }
    Show-Msg 'Imported. Language and theme take effect when PC Tune-Up restarts.' | Out-Null
}

# --- First-run tour: three short screens ---
$TourSteps = @(
    @{ Title = 'Welcome to PC Tune-Up'; Text = 'PC Tune-Up checks this PC and explains in plain language what slows it down. The "Start here" box on the Health page always shows the three most useful things to do right now. "Fix my PC" runs all the safe fixes in one go.' }
    @{ Title = 'Nothing changes without you'; Text = 'PC Tune-Up asks first and shows exactly what it will do. Every change is listed on the History page, and almost everything can be undone with one click. Security software, VPNs and drivers are never touched, and you can add your own programs to the keep list.' }
    @{ Title = 'A few handy things'; Text = 'Some fixes need administrator rights - click "Restart as admin" at the bottom left. Press Ctrl+F to search everything. In Settings you can switch on weekly maintenance, which cleans junk by itself and only tells you when something new turns up.' }
)
function Show-TourStep {
    $t = $script:Tour; $i = $t.I
    $t.Step.Text = (T 'Step {0} of {1}').Replace('{0}', "$($i + 1)").Replace('{1}', "$($TourSteps.Count)")
    $t.Title.Text = T $TourSteps[$i].Title; $t.Text.Text = T $TourSteps[$i].Text
    $t.Back.Visible = $i -gt 0
    $t.Next.Text = T $(if ($i -eq $TourSteps.Count - 1) { 'Get started' } else { 'Next' })
    $t.Skip.Visible = $i -lt $TourSteps.Count - 1
    $t.Back.Text = T 'Back'; $t.Skip.Text = T 'Skip'   # this window is made after the app's translation hook, so translate here
}
function Show-Tour {
    $w = New-Object Windows.Forms.Form
    $w.Text = 'PC Tune-Up'; $w.FormBorderStyle = 'FixedDialog'; $w.MaximizeBox = $false; $w.MinimizeBox = $false; $w.ShowInTaskbar = $false
    $w.StartPosition = 'CenterParent'; $w.ClientSize = New-Object Drawing.Size((Px 560), (Px 290)); $w.BackColor = $Theme.Bg; $w.ForeColor = $Theme.Text; $w.Font = $Font
    if ($form.Icon) { $w.Icon = $form.Icon }
    $step = New-Object Windows.Forms.Label; $step.Dock = 'Top'; $step.Height = (Px 34); $step.Padding = New-Object Windows.Forms.Padding((Px 24), (Px 14), 0, 0); $step.ForeColor = $Theme.Dim
    $title = New-Object Windows.Forms.Label; $title.Dock = 'Top'; $title.Height = (Px 44); $title.Font = $FontTitle; $title.Padding = New-Object Windows.Forms.Padding((Px 22), 0, 0, 0)
    $text = New-Object Windows.Forms.Label; $text.Dock = 'Fill'; $text.Padding = New-Object Windows.Forms.Padding((Px 24), (Px 4), (Px 24), 0)
    $bar = New-Object Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = (Px 56); $bar.FlowDirection = 'RightToLeft'; $bar.Padding = New-Object Windows.Forms.Padding((Px 16), (Px 8), (Px 16), 0)
    $next = New-Button 'Next'; $back = New-Button 'Back'; $skip = New-Button 'Skip'
    Set-Primary $next
    $bar.Controls.AddRange(@($next, $back, $skip))
    $w.Controls.AddRange(@($text, $bar, $title, $step))
    # Kept in a script variable (not closures): click handlers then still see the app's functions such as T.
    $script:Tour = @{ W = $w; Step = $step; Title = $title; Text = $text; Next = $next; Back = $back; Skip = $skip; I = 0 }
    $next.Add_Click({ if ($script:Tour.I -ge $TourSteps.Count - 1) { $script:Tour.W.Close() } else { $script:Tour.I++; Show-TourStep } })
    $back.Add_Click({ $script:Tour.I = [Math]::Max(0, $script:Tour.I - 1); Show-TourStep })
    $skip.Add_Click({ $script:Tour.W.Close() })
    $w.AcceptButton = $next; $w.CancelButton = $skip
    Show-TourStep
    $w.Add_HandleCreated({ if ($Dark) { $on = 1; try { [void][PcTuneUp.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$on, 4) } catch { } } })
    [void]$w.ShowDialog($form)
    $Settings.TourShown = $true; Save-Settings
}

Add-SetSection 'Move to another PC' 'Saves your choices to one file: settings, keep list, privacy settings you turned off, and the scheduled tasks, startup apps and services you switched off. Import it on another PC - only what exists there is changed, with undo.'
$btnExport = New-Button 'Export settings...'; $btnImport = New-Button 'Import settings...'
Add-SetRow @($btnExport, $btnImport)
$btnExport.Add_Click({ Export-PcSettings })
$btnImport.Add_Click({ Import-PcSettings })

Add-SetSection 'Help and feedback' 'Something not working, or an idea? It opens a report on GitHub with the version, Windows and recent errors already filled in (your name, folders and PC name are blanked out) - you see everything before you send it.'
$btnBug = New-Button 'Report a problem...'; $btnIdea = New-Button 'Suggest an idea...'; $btnTour = New-Button 'Show the tour again'; $btnSite = New-Button 'Website'
$btnHelper = New-Button 'Send a report to someone who helps you...'; $btnCopySum = New-Button 'Copy a short summary'
Add-SetRow @($btnHelper, $btnCopySum)
Add-SetRow @($btnBug, $btnIdea, $btnTour, $btnSite)
$btnHelper.Add_Click({ Send-HelperReport })
$btnCopySum.Add_Click({ Copy-PlainSummary })
$btnBug.Add_Click({ Open-ProblemReport 'bug' })
$btnIdea.Add_Click({ Open-ProblemReport 'idea' })
$btnTour.Add_Click({ Show-Tour })
$btnSite.Add_Click({ Start-Process "https://$(($UpdateRepo -split '/')[0]).github.io/$(($UpdateRepo -split '/')[1])/" })

Add-SetSection 'Keyboard' 'Ctrl+F  search everything      F5  reload this page      Ctrl+1 ... Ctrl+9  the first nine pages      Ctrl+PageDown / Ctrl+PageUp  next / previous page      Space  check or uncheck a row      Enter  open a search result'

Add-SetSection 'About' "PC Tune-Up $AppVersion - free and open source (MIT licence). Privacy: everything runs on this PC. The only internet use is the update check (GitHub), the speed test (Cloudflare) and winget's program list; nothing about this PC is sent anywhere."
$lnkRepo = New-Object Windows.Forms.LinkLabel
$lnkRepo.Text = "github.com/$UpdateRepo"; $lnkRepo.AutoSize = $true; $lnkRepo.LinkColor = $Theme.AccentText; $lnkRepo.ActiveLinkColor = $Theme.AccentText
$lnkRepo.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 12)
$lnkRepo.Add_LinkClicked({ Start-Process "https://github.com/$UpdateRepo" })
$setFlow.Controls.Add($lnkRepo)

# --- Install / uninstall (per user, like most modern apps: no administrator, no installer program) ---
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCTuneUp'
$StartMenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Tune-Up.lnk'
$DesktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'PC Tune-Up.lnk'
# COM objects are released straight away: left to the garbage collector, they can keep the process alive for a minute after it ends.
function Get-ShortcutTarget([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $sh = New-Object -ComObject WScript.Shell
    try { $sc = $sh.CreateShortcut($Path); $t = $sc.TargetPath; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sc); $t }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}
function New-Shortcut([string]$Path, [string]$Target) {
    $sh = New-Object -ComObject WScript.Shell
    try {
        $sc = $sh.CreateShortcut($Path)
        $sc.TargetPath = $Target; $sc.WorkingDirectory = Split-Path $Target; $sc.IconLocation = "$Target,0"
        $sc.Description = 'Check, clean and speed up this PC'
        $sc.Save()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sc)
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}
function Set-UninstallEntry {
    New-Item -Path $UninstallKey -Force | Out-Null
    $vals = [ordered]@{ DisplayName = 'PC Tune-Up'; DisplayVersion = $AppVersion; Publisher = 'PC Tune-Up (open source)'; DisplayIcon = "$InstalledExe,0"
                        InstallLocation = $InstallDir; UninstallString = "`"$InstalledExe`" /uninstall"; URLInfoAbout = "https://github.com/$UpdateRepo"
                        HelpLink = "https://github.com/$UpdateRepo/issues" }
    foreach ($k in $vals.Keys) { Set-ItemProperty -Path $UninstallKey -Name $k -Value $vals[$k] }
    foreach ($k in 'NoModify', 'NoRepair') { Set-ItemProperty -Path $UninstallKey -Name $k -Value 1 -Type DWord }
    $kb = [int]((Get-Item -LiteralPath $InstalledExe -ErrorAction SilentlyContinue).Length / 1KB)
    Set-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value $kb -Type DWord
}
function Install-App([switch]$Launch) {
    if (-not $RunningAsExe) { Show-Msg 'Install from PC-TuneUp.exe, not from the script.' | Out-Null; return }
    try {
        New-Item -ItemType Directory -Force $InstallDir | Out-Null
        if ($SelfExe -ne $InstalledExe) { Copy-Item -LiteralPath $SelfExe -Destination $InstalledExe -Force -ErrorAction Stop }
        New-Shortcut $StartMenuLink $InstalledExe
        New-Shortcut $DesktopLink $InstalledExe
        Set-UninstallEntry
        $Settings.AskedInstall = $true; Save-Settings
        Write-Log "Installed PC Tune-Up $AppVersion in $InstallDir"
    } catch { Show-Msg "Installing failed: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null; return }
    if ($Launch -and $SelfExe -ne $InstalledExe) {
        Show-Msg "PC Tune-Up is installed. It is in the Start menu and on the desktop, and you can uninstall it in Settings > Apps.`n`nThe installed copy opens now; you can delete the file you started this from." | Out-Null
        Start-Process $InstalledExe
        $form.Close()
    }
}
function Uninstall-App {
    if ((Show-Msg 'Remove PC Tune-Up from this PC?' 'YesNo' 'Question') -ne 'Yes') { return }
    $wipe = (Show-Msg 'Also delete its settings, keep list and change history?' 'YesNo' 'Question') -eq 'Yes'
    foreach ($l in $StartMenuLink, $DesktopLink) {
        try { if ((Get-ShortcutTarget $l) -eq $InstalledExe) { Remove-Item $l -Force } } catch { }
    }
    Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $MaintTaskName -Confirm:$false -ErrorAction SilentlyContinue
    if ($wipe) { Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue }
    $self = $SelfExe -eq $InstalledExe
    if (-not $self) { Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
    Show-Msg 'PC Tune-Up has been removed.' | Out-Null
    if ($self) {
        # A running program can't delete itself: a hidden helper waits until this process has ended, then removes the folder.
        # It retries for a while because antivirus often still holds the exe for a moment after it closes.
        $dir = $InstallDir -replace "'", "''"
        $cmd = "Wait-Process -Id $PID -Timeout 60 -ErrorAction SilentlyContinue; " +
               "for (`$i = 0; `$i -lt 20 -and (Test-Path -LiteralPath '$dir'); `$i++) { Start-Sleep 1; Remove-Item -LiteralPath '$dir' -Recurse -Force -ErrorAction SilentlyContinue }"
        Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$cmd`"" -WindowStyle Hidden -WorkingDirectory $env:TEMP
    }
    $form.Close()
}

# ===========================================================================
# Report: one HTML page with everything the tabs currently show, saved to Documents
# ===========================================================================
function ConvertTo-HtmlRows([object[]]$Headers, $Items, [int[]]$Cols) {
    $enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
    $h = ($Headers | ForEach-Object { "<th>$(& $enc (T $_))</th>" }) -join ''
    $rows = foreach ($it in $Items) {
        '<tr>' + (($Cols | ForEach-Object { "<td>$(& $enc $it.SubItems[$_].Text)</td>" }) -join '') + '</tr>'
    }
    if (-not $rows) { return "<p class='none'>$(T 'Nothing found.')</p>" }
    "<table><tr>$h</tr>$($rows -join '')</table>"
}
function Save-ReportNow([string]$Path, [switch]$NoOpen) {
    $enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
    $advice = if ($script:HealthAdvice) { '<ul class="advice">' + (($script:HealthAdvice | ForEach-Object { "<li>$(& $enc (T $_))</li>" }) -join '') + '</ul>' }
              else { "<p class='ok'>$(T 'No problems spotted.')</p>" }
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
<h1>$(T 'PC Tune-Up report')</h1>
<p class="sub">$(& $enc $PcName) - $(Get-Date -Format 'dddd d MMMM yyyy, HH:mm')</p>
<h2>$(T 'Health')</h2><pre>$(& $enc (($script:HealthLines | ForEach-Object { if ($_ -match '^([^:]+):\s+(.*)$') { "$(T $Matches[1]):  $(T $Matches[2])" } else { T $_ } }) -join "`r`n"))
$(& $enc $lblSpeed.Text)</pre>
<h2>$(T 'Advice')</h2>$advice
<h2>$(T 'Junk files that can be cleaned')</h2>$(ConvertTo-HtmlRows @('What', 'Size', 'Files', 'Note') $lvClean.Items @(0, 1, 2, 3))
<h2>$(T "Apps that start with Windows ($($startOn.Count) on)")</h2>$(ConvertTo-HtmlRows @('App', 'For', 'Advice') $startOn @(0, 1, 2))
<h2>$(T 'Bloatware found')</h2>$(ConvertTo-HtmlRows @('Name', 'Type', 'Category', 'Why', 'Size') $lvBloat.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Background services')</h2>$(ConvertTo-HtmlRows @('Service', 'What it is', 'Starts', 'Suggested') $svcTodo @(0, 1, 3, 5))
<h2>$(T 'Space savers')</h2>$(ConvertTo-HtmlRows @('Saver', 'Can free', 'Now', 'What it does - and what you give up') $lvSpace.Items @(0, 1, 2, 3))
<h2>$(T 'Right now')</h2>$(ConvertTo-HtmlRows @('Program', 'Memory', 'Processor', 'Disk', 'What to do') $lvNow.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Power settings')</h2>$(ConvertTo-HtmlRows @('Setting', 'Plugged in', 'On battery', 'What to do') $lvPower.Items @(0, 1, 2, 3))
<h2>$(T 'Gaming')</h2>$(ConvertTo-HtmlRows @('Check', 'Status', 'Result', 'What to do') $lvGame.Items @(0, 1, 2, 3))
<h2>$(T 'Browsers')</h2>$(ConvertTo-HtmlRows @('Item', 'Browser', 'Kind', 'Status', 'Details') $lvBrw.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Network')</h2>$(ConvertTo-HtmlRows @('Check', 'Status', 'Result', 'What to do') $lvNet.Items @(0, 1, 2, 3))
$(if ($HasBattery) { "<h2>$(T 'Battery')</h2>$(ConvertTo-HtmlRows @('Reading', 'Value', 'What it means') $lvBatt.Items @(0, 1, 2))" })
<h2>$(T 'Programs')</h2>$(ConvertTo-HtmlRows @('Program', 'Publisher', 'Size', 'Installed', 'Last used', 'Note') $lvProg.Items @(0, 1, 2, 3, 4, 5))
<h2>$(T 'Right-click menu')</h2>$(ConvertTo-HtmlRows @('Entry', 'Shown on', 'Made by', 'State', 'Details') $lvCtx.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Drivers')</h2>$(ConvertTo-HtmlRows @('Device', 'Kind', 'Status', 'Driver', 'What to do') ($lvDrv.Items | Where-Object { $_.Tag.Level -ne 'OK' }) @(0, 1, 2, 3, 4))
<h2>$(T 'Privacy')</h2>$(ConvertTo-HtmlRows @('Setting', 'State', 'What it does') $lvPriv.Items @(0, 1, 2))
<h2>$(T 'Backup')</h2>$(ConvertTo-HtmlRows @('Check', 'Status', 'Result', 'What to do') $lvBackup.Items @(0, 1, 2, 3))
<h2>$(T 'Scheduled tasks')</h2>$(ConvertTo-HtmlRows @('Task', 'Made by', 'Runs', 'State', 'Advice') $lvTasks.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Security')</h2>$(ConvertTo-HtmlRows @('Check', 'Status', 'Result', 'What to do') $lvSec.Items @(0, 1, 2, 3))
<h2>$(T 'Stability (last 30 days)')</h2>$(ConvertTo-HtmlRows @('Problem', 'What', 'Times', 'Last', 'What to do') $lvStab.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Program updates available')</h2>$(ConvertTo-HtmlRows @('Program', 'Installed', 'Available', 'Note') $lvUpd.Items @(0, 1, 2, 3))
<h2>$(T 'Upgrade options')</h2>$(ConvertTo-HtmlRows @('Part', 'You have now', 'Upgrade option', 'Worth it?', 'What to buy') $lvUpg.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Changes made by PC Tune-Up')</h2>$(ConvertTo-HtmlRows @('When', 'What', 'Item', 'Change', 'Undo') $histRows @(0, 1, 2, 3, 4))
<h2>$(T 'Problems inside PC Tune-Up (last 14 days)')</h2>$($errs = @(Get-AppErrors); if ($errs) { '<pre class="errors">' + (($errs | ForEach-Object { & $enc $_ }) -join "
") + '</pre>' } else { "<p class='none'>$(T 'None recorded.')</p>" })
</body></html>
"@
    $safeName = ($PcName -replace '[\\/:*?"<>|]', '').Trim()
    $file = if ($Path) { [IO.Path]::GetFullPath($Path) }
            else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("PC Tune-Up report - $safeName - $(Get-Date -Format 'yyyy-MM-dd HHmm').html") }
    Set-Content -Path $file -Value $html -Encoding UTF8
    Write-Log "Report saved: $file"
    if (-not $NoOpen) { Start-Process $file }
    $file
}
# A report covers every page, so pages that haven't loaded yet are loaded first; the timer saves it when all is done.
function Save-Report {
    $missing = @($script:PageLoaders.Keys | Where-Object { -not $script:Loaded[$_] })
    if (-not $missing -and -not $script:Jobs.Count) { [void](Save-ReportNow); return }
    foreach ($m in $missing) { Invoke-PageLoader $m }
    $script:ReportPending = $true
}

# ===========================================================================
# Fix my PC: the safe subset of every tab in one click
#   - clean temp, crash dumps, error reports, Windows Update cache, closed browsers' caches
#   - stop "safe to turn off" apps starting with Windows
#   - (admin) set known bloat services to their suggestion
# Never uninstalls anything. Everything except cleaned files can be undone from History.
# ===========================================================================
$script:SvcLoaded = $false
# Restore point first (when running as administrator and allowed in Settings), then the change itself.
function Start-WithRestorePoint([string]$Why, [scriptblock]$Then) {
    if (-not ($IsAdmin -and $Settings.RestorePoints)) { & $Then; return }
    $script:AfterRestorePoint = $Then; $script:RestorePointWhy = $Why
    Start-Bg -Label 'Creating a restore point first' {
        param($why)
        try {
            Checkpoint-Computer -Description "PC Tune-Up: before $why" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable w -WarningAction SilentlyContinue
            if ($w) { "skipped: $($w[0])" } else { 'ok' }   # Windows allows one per 24 hours
        } catch { "failed: $($_.Exception.Message)" }
    } $Why {
        param($r)
        $msg = "$($r[0])"
        if ($msg -eq 'ok') { Add-History 'Restore point' 'C:' "created before $($script:RestorePointWhy)" } else { Write-Log "Restore point $msg" }
        & $script:AfterRestorePoint
    }
}
function Invoke-FixMyPc {
    if ($IsAdmin -and -not $script:SvcLoaded) { Invoke-PageLoader 'Services'; Show-Msg 'Still checking services - try again in a few seconds.' | Out-Null; return }
    $clean = @($CleanTargets | Where-Object { $_.Fix -and -not ($_.Admin -and -not $IsAdmin) -and -not (Test-Open $_) })
    $openBrowsers = @($CleanTargets | Where-Object { $_.Fix -and (Test-Open $_) } | ForEach-Object Name)
    $startup = if ($script:AutoRun) { @() } else { @($lvStart.Items | Where-Object { $_.Tag.On -and $_.Tag.Advice -eq 'safe to turn off' }) }
    $svc = if ($IsAdmin) {
        @($lvSvc.Items | Where-Object { $_.Tag.Kind -eq 'known' -and $_.Tag.Suggest -and $StartRank[$_.Tag.Start] -gt $StartRank[$_.Tag.Suggest] })
    } else { @() }
    $plan = @('PC Tune-Up will:', " - Clean junk files: $(($clean | ForEach-Object Name) -join ', ')")
    if ($openBrowsers) { $plan += "     (skipping $($openBrowsers -join ', ') - close the browser first to include it)" }
    if ($startup) { $plan += " - Stop $($startup.Count) app(s) starting with Windows: $(($startup | ForEach-Object { $_.Tag.Name -replace '_[0-9A-F]{32}$', '' }) -join ', ')" }
    if ($svc) { $plan += " - Set $($svc.Count) background service(s) to their suggested setting: $(($svc | ForEach-Object Text) -join ', ')" }
    if ($IsAdmin -and $Settings.RestorePoints) { $plan += ' - Create a restore point first' }
    if (-not $IsAdmin) { $plan += '', 'Tip: "Restart as admin" first to also clean Windows files and trim background services.' }
    $plan += '', 'Nothing gets uninstalled. Startup and service changes can be undone from the History page.'
    $script:FixSimple = [bool]$script:SimpleRun
    if ($script:SimpleRun) {
        $plan = @('PC Tune-Up will now:', ' - delete leftover files that Windows and apps make again by themselves')
        if ($startup) { $plan += " - stop $($startup.Count) app(s) from starting by themselves (they stay installed)" }
        if ($svc) { $plan += ' - switch off background programs from the PC maker that are not needed' }
        $plan += '', 'Your documents, photos and programs are not touched. You can undo the other changes on the History page.'
    }
    if ((Show-Msg ($plan -join "`n") 'OKCancel' 'Question') -ne 'OK') { return }
    $script:FixPlan = @{ Clean = $clean; Startup = $startup; Svc = $svc }
    $script:FixBefore = Get-FixSnapshot
    $btnFix.Enabled = $false; $btnFix.Text = 'Fixing...'
    Start-WithRestorePoint 'Fix my PC' { Invoke-FixApply }
}
function Invoke-FixApply {
    $p = $script:FixPlan
    $nStart = 0; foreach ($it in $p.Startup) { try { Set-StartupEntry $it.Tag $false; $nStart++ } catch { } }
    $nSvc = 0
    if ($p.Svc) {
        $orig = Get-ServiceOriginals
        foreach ($it in $p.Svc) { try { Set-ServiceStart $it.Tag.Name $it.Tag.Suggest $it.Tag.Start $orig; $nSvc++ } catch { } }
        Save-ServiceOriginals $orig
    }
    $script:FixCounts = @{ Startup = $nStart; Services = $nSvc }
    Start-Bg -Label 'Fix my PC: cleaning' -Cancellable $DoCleanWork $p.Clean {
        param($results, $state)
        $freed = 0
        foreach ($r in $results) { $freed += $r.Freed; Add-History 'Clean' $r.Name (($(if ($script:AutoRun) { 'freed {0} (automatic)' } else { 'freed {0} (Fix my PC)' })) -f (Format-Size $r.Freed)) }
        $script:FixFreed = $freed
        $junk = @($lvBloat.Items | Where-Object { $_.Tag.Cat -eq 'Junk' }).Count
        $lines = @($(if ($state.Cancel) { 'Stopped early.' } else { 'Done!' }), '',
            " - Freed $(Format-Size $freed) of junk files",
            " - $($script:FixCounts.Startup) app(s) no longer start with Windows")
        if ($IsAdmin) { $lines += " - $($script:FixCounts.Services) background service(s) trimmed" }
        if ($junk) { $lines += " - $junk junk app(s) found - see the Bloatware page if you want them gone" }
        $lines += '', 'Startup changes take effect next time you sign in. Undo anything from the History page.'
        if ($script:FixSimple) { $lines = @("Done! $(Format-Size $freed) of leftover files removed.", '', $(if ($script:FixCounts.Startup) { 'Your PC will start a little faster next time.' } else { 'Your PC is tidier now.' })) }
        $btnFix.Text = 'Fix my PC'; $btnFix.Enabled = $true
        Start-CleanScan; Update-Startup; Update-Services; Update-History
        if ($CliMode) { Update-Health; Show-Msg ($lines -join "`n") | Out-Null; return }
        # Measure again (free space, score), then show what changed.
        $script:FixStopped = [bool]$state.Cancel
        Start-Bg -Label 'Measuring the result' $HealthQuickWork $null { param($r) if ($r) { $script:HealthQuick = $r[0] }; Render-Health; Complete-FixResult }
    }
}
# ---------------------------------------------------------------------------
# Before and after: what Fix my PC changed. Shown when it finishes, remembered in fixes.jsonl for the Health page,
# and the start-up time is compared after the next restart (Windows only shows those to administrators).
# ---------------------------------------------------------------------------
$FixFile = Join-Path $DataDir 'fixes.jsonl'
$script:LastFix = $null
if (Test-Path $FixFile) { try { $script:LastFix = Get-Content $FixFile -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -Last 1 | ConvertFrom-Json } catch { } }
function Get-FixSnapshot {
    $c = try { New-Object IO.DriveInfo($env:SystemDrive) } catch { $null }
    $boot = @($script:BootList | Where-Object { $_ })
    [pscustomobject]@{ Free = $(if ($c) { [double]$c.AvailableFreeSpace } else { $null }); Startup = @($lvStart.Items | Where-Object { $_.Tag.On }).Count
                       Score = $(if ($script:HealthQuick -and $script:HealthDeep) { Get-HealthScore } else { $null }); Advice = @($script:HealthAdvice).Count
                       Boot = $(if ($boot) { [double]$boot[-1].Y } else { $null }) }   # (an empty $() would be saved as {})
}
function Complete-FixResult {
    $b = $script:FixBefore; $a = Get-FixSnapshot
    if (-not $b) { $b = $a }
    $rec = [pscustomobject][ordered]@{ Time = (Get-Date).ToString('s'); Freed = [double]$script:FixFreed; Startup = $script:FixCounts.Startup; Services = $script:FixCounts.Services
        FreeBefore = $b.Free; FreeAfter = $a.Free; StartBefore = $b.Startup; StartAfter = $a.Startup; ScoreBefore = $b.Score; ScoreAfter = $a.Score
        AdviceBefore = $b.Advice; AdviceAfter = $a.Advice; BootBefore = $b.Boot; BootAfter = $null }
    try { Add-Content -Path $FixFile -Value ($rec | ConvertTo-Json -Compress) -Encoding UTF8 } catch { }
    $script:LastFix = $rec
    Render-Health
    Show-FixReport $rec $script:FixStopped
}
# The first full start after the last fix: its start-up time goes into the record (once).
function Update-FixBoot {
    $f = $script:LastFix
    if (-not $f -or $f.BootAfter -or -not $f.BootBefore) { return }
    $since = @($script:BootList | Where-Object { $_.X -gt [datetime]$f.Time }) | Select-Object -First 1
    if (-not $since) { return }
    $f.BootAfter = [double]$since.Y
    try {
        $all = @(Get-Content $FixFile -Encoding UTF8 | Where-Object { $_.Trim() })
        $all[-1] = $f | ConvertTo-Json -Compress
        Set-Content -Path $FixFile -Value $all -Encoding UTF8
    } catch { }
    Render-Health
}
# One line for the Health readings: when the last fix ran and what it did.
function Get-FixLines {
    $f = $script:LastFix
    if (-not $f) { return @() }
    $when = try { ([datetime]$f.Time).ToString('d MMM') } catch { '' }
    $lines = @("Last fix:  $((T '{0} - Fix my PC freed {1}').Replace('{0}', $when).Replace('{1}', (Format-Size $f.Freed)))")
    if ($f.BootAfter -and $f.BootBefore) { $lines += "Start-up:  $((T '{0} s now, {1} s before Fix my PC').Replace('{0}', ('{0:N0}' -f $f.BootAfter)).Replace('{1}', ('{0:N0}' -f $f.BootBefore)))" }
    $lines
}
function Format-Change([double]$Diff, [string]$Unit, [switch]$Fewer) {
    if ([Math]::Abs($Diff) -lt $(if ($Unit -eq 'size') { 1MB } else { 0.5 })) { return T 'same' }
    if ($Fewer) { if ($Diff -lt 0) { return (T '{0} fewer').Replace('{0}', ('{0:N0}' -f -$Diff)) } else { return (T '{0} more').Replace('{0}', ('{0:N0}' -f $Diff)) } }
    if ($Unit -eq 'size') { return $(if ($Diff -ge 0) { '+' } else { '-' }) + (Format-Size ([Math]::Abs($Diff))) }
    $(if ($Diff -gt 0) { '+' }) + ('{0:N0}' -f $Diff)
}
function Show-FixReport($R, [bool]$Stopped) {
    # Each row: what, before, after, change, and whether the change is good (up = better unless -Fewer is better).
    $tone = { param([double]$Diff, [double]$Same, [bool]$UpIsGood) if ([Math]::Abs($Diff) -lt $Same) { 'same' } elseif (($Diff -gt 0) -eq $UpIsGood) { 'good' } else { 'bad' } }
    $rows = @(,@('Junk files removed', '', (Format-Size $R.Freed), '', 'same'))
    if ($null -ne $R.FreeBefore -and $null -ne $R.FreeAfter) { $d = $R.FreeAfter - $R.FreeBefore; $rows += ,@((T 'Free space on {0}').Replace('{0}', $env:SystemDrive), (Format-Size $R.FreeBefore), (Format-Size $R.FreeAfter), (Format-Change $d 'size'), (& $tone $d 1MB $true)) }
    $d = $R.StartAfter - $R.StartBefore; $rows += ,@('Apps that start with Windows', "$($R.StartBefore)", "$($R.StartAfter)", (Format-Change $d -Fewer), (& $tone $d 0.5 $false))
    if ($IsAdmin) { $rows += ,@('Background services trimmed', '', "$($R.Services)", '', 'same') }
    if ($null -ne $R.ScoreBefore -and $null -ne $R.ScoreAfter) { $d = $R.ScoreAfter - $R.ScoreBefore; $rows += ,@('PC Tune-Up score', "$($R.ScoreBefore)/100", "$($R.ScoreAfter)/100", (Format-Change $d), (& $tone $d 0.5 $true)) }
    $d = $R.AdviceAfter - $R.AdviceBefore; $rows += ,@('Things worth a look', "$($R.AdviceBefore)", "$($R.AdviceAfter)", (Format-Change $d -Fewer), (& $tone $d 0.5 $false))
    if ($R.BootBefore) { $rows += ,@('Start-up time', "$('{0:N0}' -f $R.BootBefore) s", 'after the next restart', '', 'same') }
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'Fix my PC: before and after'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.StartPosition = 'CenterParent'; $dlg.BackColor = $Theme.Bg; $dlg.ForeColor = $Theme.Text; $dlg.Font = $Font
    $dlg.ClientSize = New-Object Drawing.Size((Px 620), (Px (180 + 29 * $rows.Count)))
    $dlg.Padding = New-Object Windows.Forms.Padding((Px 20), (Px 14), (Px 20), (Px 14))
    $dlg.Add_HandleCreated({ if ($Dark) { $on = 1; try { [void][PcTuneUp.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$on, 4) } catch { } } })
    $head = New-Object Windows.Forms.Label
    $head.Dock = 'Top'; $head.Height = Px 34; $head.Font = New-Object Drawing.Font('Segoe UI Semibold', 13)
    $head.Text = T $(if ($Stopped) { 'Stopped early - this is what changed so far' } else { 'Done! This is what changed' })
    $lv = New-ListView $false @('What', 210, 'Before', 100, 'After', 170, 'Change', 110)
    foreach ($c in $lv.Columns) { $c.Text = T $c.Text }
    foreach ($r in $rows) {
        $it = Add-Row $lv $r[0..3]; $it.UseItemStyleForSubItems = $false; $it.SubItems[0].ForeColor = $Theme.Dim
        $it.SubItems[3].ForeColor = switch ($r[4]) { 'good' { $Theme.Good } 'bad' { $Theme.Warn } default { $Theme.Dim } }
    }
    $note = New-Object Windows.Forms.Label
    $note.Dock = 'Bottom'; $note.Height = Px 40; $note.ForeColor = $Theme.Dim; $note.TextAlign = 'MiddleLeft'
    $note.Text = T 'Start-up changes take effect next time you sign in. Undo anything from the History page.'
    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'; $bar.Height = Px 40; $bar.FlowDirection = 'RightToLeft'; $bar.WrapContents = $false
    $ok = New-Button 'OK'; $ok.Text = T 'OK'; $ok.MinimumSize = New-Object Drawing.Size((Px 96), (Px 34)); $ok.DialogResult = 'OK'; Set-Primary $ok
    $hist = New-Button 'Open History'; $hist.Text = T 'Open History'; $hist.MinimumSize = New-Object Drawing.Size(0, (Px 34)); $hist.DialogResult = 'Retry'
    $bar.Controls.Add($ok); if (-not $script:FixSimple) { $bar.Controls.Add($hist) }   # the simple view has no History page
    $dlg.Controls.Add($lv); $dlg.Controls.Add($note); $dlg.Controls.Add($bar); $dlg.Controls.Add($head)
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $ok
    $res = $dlg.ShowDialog($form)
    $dlg.Dispose()
    if ("$res" -eq 'Retry') { Show-Page $pgHist }
}
$btnFix.Add_Click({ Invoke-FixMyPc })
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
        if ($FromWinget) {
            if ((Show-Msg "PC Tune-Up $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nIt was installed with winget, so winget updates it. Update now? (A window opens; start PC Tune-Up again afterwards.)" 'YesNo' 'Information') -eq 'Yes') {
                Start-Process cmd.exe '/c winget upgrade --id MichaelKloprogge.PCTuneUp --exact --accept-source-agreements & pause'
                $form.Close()
            }
            return
        }
        if (-not $RunningAsExe -or -not $r.Url) {
            if ((Show-Msg "PC Tune-Up $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nOpen the download page?" 'YesNo' 'Information') -eq 'Yes') { Start-Process $r.Page }
            return
        }
        if ((Show-Msg "PC Tune-Up $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nUpdate now? The app restarts by itself." 'YesNo' 'Information') -ne 'Yes') { return }
        $btnUpdate.Enabled = $false; $btnUpdate.Text = 'Downloading...'
        $script:UpdateInfo = $r
        Start-Bg -Label 'Downloading the update' $UpdateDownloadWork $r {
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

# ===========================================================================
# Sidebar: the page list (grouped), with counts, and the administrator notice
# ===========================================================================
$NavGroups = @(
    @{ Title = $null;      Pages = @('Health', 'Right now') }
    @{ Title = 'CLEAN UP'; Pages = @('Clean', 'Startup', 'Bloatware', 'Programs', 'Services', 'Tasks', 'Right-click', 'Privacy', 'Disk', 'Space savers') }
    @{ Title = 'CHECK';    Pages = @('Updates', 'Drivers', 'Security', 'Browsers', 'Stability', 'Network', 'Gaming', $(if ($HasBattery) { 'Battery' }), 'Power', 'Backup', 'Upgrades') }
    @{ Title = $null;      Pages = @('History', 'Settings'); Bottom = $true }   # pinned under the list, side by side, so they never scroll away
)
$script:NavButtons = @{}
function Show-Page($Page) {
    foreach ($p in $script:Pages) { $p.Visible = ($p -eq $Page) }
    foreach ($b in $script:NavButtons.Values) {
        $on = $b.Tag -eq $Page
        $b.BackColor = if ($on) { $Theme.AccentSoft } else { $Theme.Side }
        $b.ForeColor = if ($on) { $Theme.AccentText } else { $Theme.Text }
        $b.Font = if ($on) { $FontBold } else { $Font }
        $b.Invalidate()
    }
    Invoke-PageLoader $Page.Name   # load a page's data the first time it is opened
}
function Set-NavBadge([string]$Name, $Count) {
    $b = $script:NavButtons[$Name]
    if ($b) { $b.Text = if ($Count) { "$Name  ($Count)" } else { $Name } }
}
# The three most useful next steps, most urgent first. Buttons only open the page - every change is still made there.
function Update-StartHere {
    if (-not $script:StartRows) { return }
    if ($simple) { Update-SimpleView }
    $c = @(Get-NextSteps)
    $top = @($c | Select-Object -First 3)
    $key = ($top | ForEach-Object { $_.Text }) -join '|'
    if ($key -eq $script:StartDrawn) { return }
    $script:StartDrawn = $key
    $startHere.SuspendLayout()
    for ($i = 0; $i -lt 3; $i++) {
        $row = $script:StartRows[$i]
        $row.Later.Visible = $i -lt $top.Count -and [bool]$top[$i].Remind; $row.Later.Tag = $(if ($i -lt $top.Count -and $top[$i].Remind) { $top[$i] }); $row.Later.Enabled = [bool]$row.Later.Tag
        # Without a Later button, the button takes both columns, so all buttons line up on the right.
        $startHere.SetColumnSpan($row.Button, $(if ($row.Later.Tag) { 1 } else { 2 })); $row.Button.Anchor = 'Right'
        if ($i -lt $top.Count) { $row.Label.Text = "$($i + 1).  $($top[$i].Text)"; $row.Button.Text = $top[$i].Btn; $row.Button.Tag = $top[$i]; $row.Label.Visible = $true; $row.Button.Visible = $true }
        elseif ($i -eq 0) { $row.Label.Text = 'Nothing urgent - this PC looks good.'; $row.Label.Visible = $true; $row.Button.Visible = $false }
        else { $row.Label.Visible = $false; $row.Button.Visible = $false }
    }
    $startHere.ResumeLayout()
}
# Counts next to page names: things waiting for attention.
function Update-NavBadges {
    Set-NavBadge 'Updates' @($lvUpd.Items).Count
    Set-NavBadge 'Security' @($lvSec.Items | Where-Object { $_.Tag.Level -in 'Problem', 'Warning' }).Count
    Set-NavBadge 'Stability' @($lvStab.Items | Where-Object { $_.Tag.Level -eq 'Problem' }).Count
    Set-NavBadge 'Bloatware' @($lvBloat.Items).Count
    Set-NavBadge 'Tasks' $script:TasksActive
    Set-NavBadge 'Backup' $script:BackupProblems
    Set-NavBadge 'Drivers' $script:DriverIssues
    Set-NavBadge 'Privacy' $script:PrivacyOn
    Set-NavBadge 'Browsers' $script:BrowserRisky
    Set-NavBadge 'Network' $script:NetProblems
    Set-NavBadge 'Right-click' $script:CtxLeftovers
    Set-NavBadge 'Battery' $script:BatteryWorn
    Set-NavBadge 'Power' $script:PowerIssues
    Update-StartHere
}

$nav = New-Object Windows.Forms.FlowLayoutPanel
$nav.Dock = 'Fill'; $nav.FlowDirection = 'TopDown'; $nav.WrapContents = $false; $nav.AutoScroll = $true
$nav.Padding = New-Object Windows.Forms.Padding(12, 8, 12, 2)
$appName = New-Object Windows.Forms.Label
$appName.Text = 'PC Tune-Up'; $appName.Font = New-Object Drawing.Font('Segoe UI Semibold', 13); $appName.AutoSize = $true
$appName.Margin = New-Object Windows.Forms.Padding(6, 0, 0, 0); $appName.AutoSize = $false; $appName.Padding = New-Object Windows.Forms.Padding(4, 0, 0, 0); $appName.Dock = 'Fill'; $appName.TextAlign = 'MiddleLeft'
# Next to the name: back to the simple view (an icon button, so it fits in every language).
$appHead = New-Object Windows.Forms.Panel; $appHead.Width = 178; $appHead.Height = 26; $appHead.Margin = New-Object Windows.Forms.Padding(0)
$btnToSimple = New-Object Windows.Forms.Button
$btnToSimple.Dock = 'Right'; $btnToSimple.Width = 28; $btnToSimple.FlatStyle = 'Flat'; $btnToSimple.FlatAppearance.BorderSize = 0; $btnToSimple.UseVisualStyleBackColor = $false
$btnToSimple.BackColor = $Theme.Side; $btnToSimple.Cursor = [Windows.Forms.Cursors]::Hand; $btnToSimple.AccessibleName = 'Simple view'
$btnToSimple.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.Clear($Theme.Side)
    if ($script:HotButton -eq $s) { $p = New-RoundRect 0.5 0.5 ($s.Width - 1.5) ($s.Height - 1.5) (Px 5); $br = New-Object Drawing.SolidBrush($Theme.Hover); $g.FillPath($br, $p); $br.Dispose(); $p.Dispose() }
    [Windows.Forms.TextRenderer]::DrawText($g, [string][char]0xE80F, $IconFont, $s.ClientRectangle, $(if ($script:HotButton -eq $s) { $Theme.AccentText } else { $Theme.Dim }), 'VerticalCenter, HorizontalCenter, NoPrefix')
    if ($s.Focused -and $s.ShowFocusCues) { $fp = New-RoundRect 1.5 1.5 ($s.Width - 3.5) ($s.Height - 3.5) (Px 4); $pen = New-Object Drawing.Pen($Theme.Accent); $pen.DashStyle = 'Dot'; $g.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose() }
})
$btnToSimple.Add_MouseEnter({ $script:HotButton = $this; $this.Invalidate(); $toSimpleTip.SetToolTip($this, (T 'Back to the simple view')) })
$btnToSimple.Add_MouseLeave({ if ($script:HotButton -eq $this) { $script:HotButton = $null }; $this.Invalidate() })
$btnToSimple.Add_Click({ Set-ViewMode 'simple' })
$toSimpleTip = New-Object Windows.Forms.ToolTip
$appHead.Controls.AddRange(@($appName, $btnToSimple))
$appVer = New-Object Windows.Forms.Label
$appVer.Text = "Version $AppVersion"; $appVer.ForeColor = $Theme.Dim; $appVer.AutoSize = $true
$appVer.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 2)
# Search box (Ctrl+F): results appear on the Search page as you type.
$txtSearch = New-Object Windows.Forms.TextBox
$txtSearch.Width = 178; $txtSearch.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 4); $txtSearch.BorderStyle = 'FixedSingle'; $txtSearch.AccessibleName = 'Search'
$txtSearch.BackColor = $Theme.Input; $txtSearch.ForeColor = $Theme.Text
$txtSearch.Add_HandleCreated({   # grey hint text inside the empty box (EM_SETCUEBANNER)
    $h = [Runtime.InteropServices.Marshal]::StringToHGlobalUni((T 'Search  (Ctrl+F)'))
    try { [void][PcTuneUp.Native]::SendMessage($this.Handle, 0x1501, [IntPtr]1, $h) } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($h) }
})
$searchTimer = New-Object Windows.Forms.Timer; $searchTimer.Interval = 400
$searchTimer.Add_Tick({ $searchTimer.Stop(); if ($txtSearch.Text.Trim().Length -ge 2) { Invoke-Search $txtSearch.Text.Trim() } })
$txtSearch.Add_TextChanged({ $searchTimer.Stop(); $searchTimer.Start() })
$txtSearch.Add_KeyDown({
    if ($_.KeyCode -eq 'Return') { $searchTimer.Stop(); if ($txtSearch.Text.Trim()) { Invoke-Search $txtSearch.Text.Trim(); if ($lvFind.Items.Count) { [void]$lvFind.Focus() } }; $_.SuppressKeyPress = $true }
    elseif ($_.KeyCode -eq 'Down' -and $lvFind.Items.Count) { [void]$lvFind.Focus(); $_.SuppressKeyPress = $true }
    elseif ($_.KeyCode -eq 'Escape') { $txtSearch.Clear(); Show-Page $pgHealth; $_.SuppressKeyPress = $true }
})
$nav.Controls.AddRange(@($appHead, $txtSearch))
# Keyboard: Ctrl+F searches, F5 reloads the page you are on.
$form.KeyPreview = $true
$form.Add_KeyDown({
    $order = @($NavGroups | ForEach-Object { $_.Pages } | Where-Object { $_ -and $script:NavButtons[$_] } | ForEach-Object { $script:NavButtons[$_].Tag })
    $cur = $script:Pages | Where-Object Visible | Select-Object -First 1
    if ($_.Control -and $_.KeyCode -eq 'F') { [void]$txtSearch.Focus(); $txtSearch.SelectAll(); $_.SuppressKeyPress = $true }
    elseif ($_.Control -and $_.KeyCode -ge 'D1' -and $_.KeyCode -le 'D9') { $k = [int]$_.KeyCode - [int][Windows.Forms.Keys]::D1; if ($k -lt $order.Count) { Show-Page $order[$k] }; $_.SuppressKeyPress = $true }
    elseif ($_.Control -and $_.KeyCode -in 'Next', 'PageDown', 'Prior', 'PageUp') {
        $i = [array]::IndexOf($order, $cur); $d = if ($_.KeyCode -in 'Next', 'PageDown') { 1 } else { -1 }
        Show-Page $order[(($i + $d) % $order.Count + $order.Count) % $order.Count]; $_.SuppressKeyPress = $true
    }
    elseif ($_.KeyCode -eq 'F5') {
        $cur = $script:Pages | Where-Object Visible | Select-Object -First 1
        if ($cur -eq $pgHealth) { Update-Health } elseif ($cur -eq $pgHist) { Update-History } elseif ($cur -and $script:PageLoaders.ContainsKey($cur.Name)) { & $script:PageLoaders[$cur.Name] }
        $_.SuppressKeyPress = $true
    }
})
# Icons from the font built into Windows 11 (Segoe Fluent Icons) or Windows 10 (Segoe MDL2 Assets).
$IconFontName = if ((New-Object Drawing.Text.InstalledFontCollection).Families.Name -contains 'Segoe Fluent Icons') { 'Segoe Fluent Icons' } else { 'Segoe MDL2 Assets' }
$IconFont = New-Object Drawing.Font($IconFontName, 11)
$NavIcons = @{ Health = 0xE95E; 'Right now' = 0xEC4A; Clean = 0xEA99; Startup = 0xE7E8; Bloatware = 0xE74D; Programs = 0xE71D; Services = 0xE9F5; Tasks = 0xE823
               'Right-click' = 0xE7C9; Privacy = 0xE890; Disk = 0xEDA2; 'Space savers' = 0xF012; Updates = 0xE895; Drivers = 0xE950
               Security = 0xEA18; Browsers = 0xE774; Stability = 0xE9D9; Network = 0xE701; Gaming = 0xE7FC; Battery = 0xE83F; Power = 0xE945
               Backup = 0xE753; Upgrades = 0xEEA0; History = 0xE81C; Settings = 0xE713 }
function Draw-NavButton($B, $G) {
    $G.SmoothingMode = 'AntiAlias'
    $G.Clear($Theme.Side)
    $on = $B.BackColor.ToArgb() -eq $Theme.AccentSoft.ToArgb()   # Show-Page marks the open page this way
    if ($on -or $script:HotNav -eq $B) {
        $p = New-RoundRect 0.5 0.5 ($B.Width - 1.5) ($B.Height - 1.5) (Px 5)
        $br = New-Object Drawing.SolidBrush($(if ($on) { $Theme.AccentSoft } else { $Theme.Hover })); $G.FillPath($br, $p); $br.Dispose(); $p.Dispose()
    }
    if ($on) {   # the blue bar on the left, like Windows 11 Settings
        $h = [single]($B.Height * 0.5); $bar = New-RoundRect 1 (($B.Height - $h) / 2) (Px 3) $h (Px 2)
        $br = New-Object Drawing.SolidBrush($Theme.Accent); $G.FillPath($br, $bar); $br.Dispose(); $bar.Dispose()
    }
    $code = $NavIcons[$B.AccessibleName]
    $small = $B.Parent -eq $navBottom   # History and Settings sit side by side, so they get a tighter layout
    $x = if ($small) { Px 2 } else { Px 10 }
    if ($code) {
        $ir = New-Object Drawing.Rectangle($x, 0, (Px 20), $B.Height)
        [Windows.Forms.TextRenderer]::DrawText($G, [string][char]$code, $IconFont, $ir, $(if ($on) { $Theme.AccentText } else { $Theme.Dim }), 'VerticalCenter, HorizontalCenter, NoPrefix')
        $x += if ($small) { Px 22 } else { Px 30 }
    }
    $f = if ($small -and $script:NavBottomFont) { $script:NavBottomFont[[int]$on] } else { $B.Font }
    $text = $B.Text; $right = $B.Width - (Px 4)
    # A count ("Updates  (14)") is drawn as a small pill on the right, so a long (translated) name keeps its room.
    if ($text -match '^(.*?)\s+\((\d+)\)$') {
        $text = $Matches[1]; $count = $Matches[2]
        $pw = [Windows.Forms.TextRenderer]::MeasureText($count, $FontSmall).Width + (Px 8); $ph = Px 17
        $px = $B.Width - (Px 6) - $pw; $py = [int](($B.Height - $ph) / 2)
        $pill = New-RoundRect $px $py $pw $ph ($ph / 2)
        $br = New-Object Drawing.SolidBrush($(if ($on) { $Theme.Bg } else { $Theme.Hover })); $G.FillPath($br, $pill); $br.Dispose(); $pill.Dispose()
        [Windows.Forms.TextRenderer]::DrawText($G, $count, $FontSmall, (New-Object Drawing.Rectangle($px, $py, $pw, $ph)), $(if ($on) { $Theme.AccentText } else { $Theme.Dim }), 'VerticalCenter, HorizontalCenter, NoPrefix')
        $right = $px - (Px 4)
    }
    $tr = New-Object Drawing.Rectangle($x, 0, ($right - $x), $B.Height)
    if ($NavSmallFonts -and [Windows.Forms.TextRenderer]::MeasureText($text, $f).Width -gt $tr.Width) { $f = $NavSmallFonts[[int]$on] }   # a long name: a size smaller rather than cut off
    if ($script:NavIconOnly -ne $B) { [Windows.Forms.TextRenderer]::DrawText($G, $text, $f, $tr, $B.ForeColor, 'VerticalCenter, Left, EndEllipsis, NoPrefix') }
    if ($B.Focused -and $B.ShowFocusCues) { $fp = New-RoundRect 1.5 1.5 ($B.Width - 3.5) ($B.Height - 3.5) (Px 4); $pen = New-Object Drawing.Pen($Theme.Accent); $pen.DashStyle = 'Dot'; $G.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose() }
}
$navBottom = New-Object Windows.Forms.FlowLayoutPanel
$navBottom.Dock = 'Bottom'; $navBottom.AutoSize = $true; $navBottom.WrapContents = $false; $navBottom.Padding = New-Object Windows.Forms.Padding(8, 2, 0, 0)
foreach ($g in $NavGroups) {
    if ($g.Title) {
        $cap = New-Object Windows.Forms.Label
        $cap.Text = $g.Title; $cap.Font = $FontSmall; $cap.ForeColor = $Theme.Dim; $cap.AutoSize = $true
        $cap.Margin = New-Object Windows.Forms.Padding(10, 4, 0, 0)
        $nav.Controls.Add($cap)
    }
    foreach ($name in $g.Pages) {
        $page = $script:Pages | Where-Object Name -eq $name | Select-Object -First 1
        if (-not $page) { continue }
        $b = New-Object Windows.Forms.Button
        $b.Text = $name; $b.Tag = $page; $b.Width = 178; $b.Height = 23; $b.TextAlign = 'MiddleLeft'
        $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $Theme.Hover
        $b.BackColor = $Theme.Side; $b.Padding = New-Object Windows.Forms.Padding(10, 0, 0, 0); $b.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 1)   # 24 pages only fit with 1 px between them
        $b.Cursor = [Windows.Forms.Cursors]::Hand
        $b.Add_Click({ Show-Page $this.Tag })
        $b.AccessibleName = $name
        $b.Add_Paint({ param($sender, $e) Draw-NavButton $sender $e.Graphics })
        $b.Add_MouseEnter({ $script:HotNav = $this; $this.Invalidate() })
        $b.Add_MouseLeave({ if ($script:HotNav -eq $this) { $script:HotNav = $null }; $this.Invalidate() })
        $b.Add_GotFocus({ $this.Invalidate() }); $b.Add_LostFocus({ $this.Invalidate() })
        $script:NavButtons[$name] = $b
        if ($g.Bottom) { $b.AutoSize = $true; $b.MinimumSize = New-Object Drawing.Size(60, 23); $b.Width = 60; $b.AutoSize = $false; $b.Margin = New-Object Windows.Forms.Padding(0, 1, 2, 1); $navBottom.Controls.Add($b) } else { $nav.Controls.Add($b) }   # bottom buttons are sized to their (translated) text
    }
}
$sidebar.Controls.Add($nav)
$sidebar.Controls.Add($navBottom)
# History and Settings: as wide as icon + (translated) text, measured once the texts are final
# If both don't fit (long words in some languages), they use a slightly smaller font; if even that is too wide,
# Settings shows only its icon, with its name as a tooltip.
$NavSmallFonts = @((New-Object Drawing.Font('Segoe UI', 9)), (New-Object Drawing.Font('Segoe UI Semibold', 9)))
$navBottomTip = New-Object Windows.Forms.ToolTip
function Resize-NavBottom {
    $btns = @($navBottom.Controls)
    $avail = $sidebar.Width - $navBottom.Padding.Horizontal - 2 * $btns.Count
    # Measured in screen pixels, but the whole window is scaled for the display afterwards - so undo the scaling here.
    $measure = { param($f) @(foreach ($b in $btns) { [int]([Windows.Forms.TextRenderer]::MeasureText((T $b.Text), $f).Width / $DpiScale) + 28 }) }
    $script:NavBottomFont = $null; $script:NavIconOnly = $null
    $w = & $measure $FontBold
    if (($w | Measure-Object -Sum).Sum -gt $avail) { $script:NavBottomFont = $NavSmallFonts; $w = & $measure $NavSmallFonts[1] }
    if (($w | Measure-Object -Sum).Sum -gt $avail -and $btns) { $script:NavIconOnly = $btns[-1]; $w[-1] = 28; $navBottomTip.SetToolTip($btns[-1], (T $btns[-1].Text)) }
    for ($i = 0; $i -lt $btns.Count; $i++) { $btns[$i].Width = $w[$i]; $btns[$i].Height = 24 }
}
if (-not $IsAdmin) {
    $adm = New-Object Windows.Forms.Panel
    # Kept small: with 20+ pages the sidebar needs the room.
    # Just the button (the explanation is its tooltip): with 25 pages the sidebar needs every pixel.
    $adm.Dock = 'Bottom'; $adm.Height = 44; $adm.Padding = New-Object Windows.Forms.Padding(16, 6, 14, 6)
    $admB = New-Button 'Restart as admin'
    $admB.AutoSize = $false; $admB.Dock = 'Bottom'; $admB.Height = 32
    $admB.Add_MouseEnter({ $admTip.SetToolTip($this, (T 'Some fixes need administrator rights.')) })
    $admTip = New-Object Windows.Forms.ToolTip
    $admB.Add_Click({
        try {
            if ($RunningAsExe) { Start-Process $SelfExe -Verb RunAs }
            else { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
            $form.Close()
        } catch { }   # user said no to the UAC prompt
    })
    $adm.Controls.Add($admB)
    $sidebar.Controls.Add($adm)
}
# Each page's main action stands out.
foreach ($b in @($btnClean, $btnStartApply, $btnBloatRemove, $btnSvcApply, $btnDiskScan, $btnUpdRun, $btnSecOpen, $btnUpgCopy, $btnHistUndo, $btnStabFix, $btnTaskOff, $btnBkOpen, $btnPrivOff, $btnDrvGet, $btnBattUsage, $btnBrwExt, $btnProgUn, $btnNetScan, $btnCtxHide, $btnSpaceApply, $btnGameFix, $btnNowEnd, $btnPowerFix)) { Set-Primary $b }

# ---------------------------------------------------------------------------
# Activity bar: what is running in the background, its progress, and Cancel
# ---------------------------------------------------------------------------
$activity = New-Object Windows.Forms.Panel
$activity.Dock = 'Bottom'; $activity.Height = 42; $activity.BackColor = $Theme.Soft; $activity.Visible = $false
$activity.Padding = New-Object Windows.Forms.Padding(26, 7, 26, 7)
$actText = New-Object Windows.Forms.Label
$actText.Dock = 'Fill'; $actText.TextAlign = 'MiddleLeft'; $actText.AutoEllipsis = $true
# A slim rounded bar in the theme's colours (instead of Windows' old green one): filled to the progress, or a moving
# piece when the length of the job is unknown.
$actBar = New-Object Windows.Forms.PictureBox
$actBar.Dock = 'Right'; $actBar.Width = 220; $actBar.BackColor = $Theme.Soft
$script:ActProg = @{ Max = 0; Value = 0; Pos = 0.0 }
$actBar.Add_Paint({ param($sender, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $h = [single](Px 6); $y = ($sender.Height - $h) / 2; $w = [single]($sender.Width - 2)
    $track = New-RoundRect 1 $y $w $h ($h / 2); $br = New-Object Drawing.SolidBrush($Theme.Border); $g.FillPath($br, $track); $br.Dispose(); $track.Dispose()
    $p = $script:ActProg
    if ($p.Max -gt 0) { $x0 = 1; $fw = [single]([Math]::Max([double]$h, $w * [Math]::Min([double]1, [double]$p.Value / [double]$p.Max))) }
    else { $fw = [single]($w * 0.3); $x0 = 1 + ($w - $fw) * (0.5 - 0.5 * [Math]::Cos($p.Pos)) }
    $fill = New-RoundRect $x0 $y $fw $h ($h / 2); $br = New-Object Drawing.SolidBrush($Theme.Accent); $g.FillPath($br, $fill); $br.Dispose(); $fill.Dispose()
})
$actAnim = New-Object Windows.Forms.Timer; $actAnim.Interval = 40
$actAnim.Add_Tick({ if ($activity.Visible -and $script:ActProg.Max -le 0) { $script:ActProg.Pos += 0.08; $actBar.Invalidate() } })
$actAnim.Start()
$actGap = New-Object Windows.Forms.Panel; $actGap.Dock = 'Right'; $actGap.Width = 10
$actCancel = New-Button 'Cancel'
$actCancel.AutoSize = $false; $actCancel.Dock = 'Right'; $actCancel.Width = 96
$activity.Controls.Add($actText); $activity.Controls.Add($actBar); $activity.Controls.Add($actGap); $activity.Controls.Add($actCancel)
$content.Controls.Add($activity); $activity.SendToBack()   # docked before the pages, so they fill the space above it
$actCancel.Add_Click({ if ($this.Tag) { $this.Tag.State.Cancel = $true; Update-ActivityBar } })
function Update-ActivityBar {
    $running = @($script:Jobs | Where-Object { $_.Label } | Sort-Object { -[int]$_.Cancellable })
    if (-not $running) { if ($activity.Visible) { $activity.Visible = $false }; return }
    $j = $running[0]
    $more = $running.Count - 1 + $script:LoadQueue.Count
    $t = $j.Label + $(if ($j.State.Text) { ": $($j.State.Text)" }) + $(if ($more -gt 0) { "      ($more more waiting)" })
    if ($actText.Text -ne $t) { $actText.Text = $t }
    $script:ActProg.Max = [Math]::Max(0, $j.State.Max); $script:ActProg.Value = [Math]::Max(0, $j.State.Value); $actBar.Invalidate()
    $actCancel.Visible = $j.Cancellable; $actCancel.Tag = $j
    $actCancel.Enabled = -not $j.State.Cancel
    $actCancel.Text = if ($j.State.Cancel) { 'Stopping...' } else { 'Cancel' }
    if (-not $activity.Visible) { $activity.Visible = $true }
}

# ---------------------------------------------------------------------------
# Page data loads in the background after the window opens, or straight away when a page is opened
# ---------------------------------------------------------------------------
$script:PageLoaders = @{ Security = { Update-Security }; Stability = { Update-Stability }; Bloatware = { Start-BloatScan }; Services = { Update-Services }
                         Clean = { Start-CleanScan }; Updates = { Start-UpdScan }; Upgrades = { Update-Upgrades }
                         Tasks = { Update-Tasks }; Backup = { Update-Backup }; Drivers = { Update-Drivers }; Privacy = { Update-Privacy }
                         Programs = { Update-Programs }; Browsers = { Update-Browsers }; Network = { Update-Network }; Battery = { Update-Battery }; 'Right-click' = { Update-Context }
                         Startup = { Update-Boot }; 'Space savers' = { Update-Space }; Gaming = { Update-Gaming }; 'Right now' = { Update-Now }; Power = { Update-Power } }
$script:Loaded = @{}
function Invoke-PageLoader([string]$Name) {
    if ($script:Loaded[$Name] -or -not $script:PageLoaders.ContainsKey($Name)) { return }
    $script:Loaded[$Name] = $true
    [void]$script:LoadQueue.Remove($Name)
    & $script:PageLoaders[$Name]
}
function Start-Everything {
    Update-Health; Update-Startup; Update-History
    $script:EverythingStarted = $true
    # Slowest first (hardware ~4 s, winget, logs), so the last one doesn't hold everything up; Security/Stability feed Health.
    [void]$script:LoadQueue.AddRange(@('Security', 'Stability', 'Upgrades', 'Drivers', 'Network', 'Updates', 'Programs', 'Browsers', 'Backup', 'Services', 'Bloatware', 'Tasks', 'Right-click', 'Privacy', 'Space savers', 'Startup', 'Gaming', 'Power', 'Clean'))
    if ($HasBattery) { [void]$script:LoadQueue.Insert(5, 'Battery') }
}
# ===========================================================================
# Simple mode: one calm screen for people who don't want 23 pages - a status in plain words, three big buttons,
# and only safe fixes that can be undone. "Advanced view" switches to the full app (the house icon next to the name switches back).
# ===========================================================================
# ---------------------------------------------------------------------------
# Reminders: things that matter more the longer they wait (a pending restart, a long-ago clean-up, updates left lying).
# They join "Start here" and the simple view, and the weekly maintenance notifies when one first appears.
# "Later" hides one for a few days. reminders.json remembers when each was first seen and what was put off.
# ---------------------------------------------------------------------------
$ReminderFile = Join-Path $DataDir 'reminders.json'
$script:ReminderState = @{ Seen = @{}; Later = @{} }
if (Test-Path $ReminderFile) {
    try {
        $j = Get-Content $ReminderFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in @($j.Seen.PSObject.Properties)) { $script:ReminderState.Seen[$p.Name] = "$($p.Value)" }
        foreach ($p in @($j.Later.PSObject.Properties)) { $script:ReminderState.Later[$p.Name] = "$($p.Value)" }
    } catch { }
}
function Save-ReminderState { try { $script:ReminderState | ConvertTo-Json -Compress | Set-Content -Path $ReminderFile -Encoding UTF8 } catch { } }
# Days since this reminder's condition was first seen (0 the first time); forgets it when the condition is gone.
function Get-ReminderAge([string]$Id, [bool]$Now) {
    $seen = $script:ReminderState.Seen
    if (-not $Now) { if ($seen.ContainsKey($Id)) { $seen.Remove($Id); Save-ReminderState }; return $null }
    if (-not $seen.ContainsKey($Id)) { $seen[$Id] = (Get-Date).ToString('s'); Save-ReminderState }
    [int]((Get-Date) - [datetime]$seen[$Id]).TotalDays
}
function Test-ReminderLater([string]$Id) {
    $l = $script:ReminderState.Later[$Id]
    $l -and [datetime]$l -gt (Get-Date)
}
function Set-ReminderLater([string]$Id, [int]$Days) {
    $script:ReminderState.Later[$Id] = (Get-Date).AddDays($Days).ToString('s'); Save-ReminderState
    $script:StepsCache = $null
    $script:StartDrawn = $null; $script:SimpleSig = $null
    Update-StartHere; Update-SimpleView
}
# Each: Id, P (priority, as in Get-NextSteps), Text, Plain, Btn, Fix, Page, Later (days to hide).
function Get-Reminders {
    $r = New-Object System.Collections.ArrayList
    $add = { param($id, $p, $text, $plain, $btn, $fix, $page, $later) if (-not (Test-ReminderLater $id)) { [void]$r.Add([pscustomobject]@{ Id = $id; P = $p; Text = $text; Plain = $plain; Btn = $btn; Fix = $fix; Page = $page; Later = $later; Remind = $true }) } }
    # A restart Windows is waiting for, to finish installing updates
    # Checked at most once a minute, straight through .NET (Test-Path on HKLM takes ~20 ms, and this runs on every redraw).
    if (-not $script:PendingAt -or ((Get-Date) - $script:PendingAt).TotalSeconds -gt 60) {
        $lm = [Microsoft.Win32.Registry]::LocalMachine
        $script:Pending = [bool]((@('SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired', 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') |
            Where-Object { $k = $lm.OpenSubKey($_); if ($k) { $k.Dispose(); $true } }))
        $script:PendingAt = Get-Date
    }
    $pending = $script:Pending
    $age = Get-ReminderAge 'restart-updates' $pending
    if ($pending -and $age -ge 2) { & $add 'restart-updates' 32 "Windows has been waiting $age day(s) for a restart to finish updates" "Windows has been waiting $age day(s) for a restart to finish installing updates. Save your work and restart." 'Restart' 'restart' $pgHealth 1 }
    # No restart for a long time
    $q = $script:HealthQuick
    if ($q -and $q.Boot -and -not ($pending -and $age -ge 2)) {
        $up = [int]((Get-Date) - $q.Boot).TotalDays
        if ($up -ge 7) { & $add 'restart' 58 "The PC hasn't restarted in $up days" "Your PC hasn't been restarted in $up days. A restart clears out a lot of slowness." 'Restart' 'restart' $pgHealth 3 }
    }
    # Windows Update hasn't installed anything for a long time
    if ($script:HealthDeep -and $script:HealthDeep.WuDays -ge 45) { & $add 'winupdate' 40 "Windows hasn't installed updates in $($script:HealthDeep.WuDays) days" "Windows hasn't updated itself in $($script:HealthDeep.WuDays) days. Open Windows Update and let it check." 'Open Windows Update' 'winupdate' $pgHealth 7 }
    # The last clean-up was long ago (only when there is something to clean, and the bigger "junk" step isn't showing already)
    if ($script:LastClean -and $script:JunkBytes -ge 300MB -and $script:JunkBytes -le 1GB) {
        $d = [int]((Get-Date) - $script:LastClean).TotalDays
        if ($d -ge 30) { & $add 'cleanup' 52 "Last clean-up was $d days ago ($(Format-Size $script:JunkBytes) of junk now)" "It has been $d days since the last clean-up; $(Format-Size $script:JunkBytes) of leftover files have piled up." 'Clean' 'clean' $pgClean 7 }
    }
    # Program updates left waiting
    $n = @($lvUpd.Items).Count
    $age = if ($script:UpdScanned) { Get-ReminderAge 'updates' ([bool]$n) }   # (not before winget has answered: an empty list then means "not checked yet")
    if ($n -and $age -ge 14) { & $add 'updates' 50 "$n program update(s) have been waiting for $age days" "$n program(s) have had a newer version waiting for $age days - updates fix security holes." 'Update' 'updates' $pgUpd 7 }
    @($r)
}
# What a reminder's button does. Every action asks first.
function Invoke-Reminder($Step) {
    switch ($Step.Fix) {
        'restart' {
            if ((Show-Msg "Restart the PC now?`n`nSave your work first: open programs are closed, and programs with unsaved work will ask you first." 'YesNo' 'Question') -ne 'Yes') { return }
            Start-Process shutdown.exe '/r /t 0'
        }
        'winupdate' { Start-Process 'ms-settings:windowsupdate' }
        'clean' { Invoke-FixMyPc }
        'updates' { Start-ProgramUpdates }
    }
}

# Everything worth doing, most urgent first, for both "Start here" (full view) and simple mode.
# Plain = one everyday sentence; Fix = a safe change with undo that simple mode may offer as "Fix this".
function Get-NextSteps {
    # One redraw asks for this several times (readings, sidebar counts, Start here, simple view): reuse it for a moment.
    if ($script:StepsCache -and ((Get-Date) - $script:StepsCacheAt).TotalMilliseconds -lt 250) { return $script:StepsCache }
    $r = @(Get-NextStepsNow)
    $script:StepsCache = $r; $script:StepsCacheAt = Get-Date
    $r
}
function Get-NextStepsNow {
    $c = New-Object System.Collections.ArrayList
    $add = { param($p, $text, $btn, $page, $plain, $fix) [void]$c.Add([pscustomobject]@{ P = $p; Text = $text; Btn = $btn; Page = $page; Plain = $plain; Fix = $fix }) }
    $n = @($lvSec.Items | Where-Object { $_.Tag.Level -eq 'Problem' }).Count
    if ($n) { & $add 10 "Security: $n problem(s) to fix" 'Fix' $pgSec "Your PC's protection has a gap ($n problem(s)). It is worth letting someone who knows computers take a look." $null }
    if ($script:ExtraAdvice['Backup']) { & $add 15 'Nothing backs up your files yet' 'Set up backup' $pgBackup 'Your photos and documents are not backed up anywhere. If the PC breaks or is stolen, they are gone.' $null }
    if ($script:BrowserRisky) { & $add 20 "$($script:BrowserRisky) browser item(s) look like adware" 'Review' $pgBrw 'Your web browser has add-ons that look like advertising software.' $null }
    $n = @($lvDrv.Items | Where-Object { $_.Tag.Level -eq 'Problem' }).Count
    if ($n) { & $add 25 "$n device(s) have a driver problem" 'Check' $pgDrv 'A part of your PC (a device) is not working properly.' $null }
    $n = @($lvStab.Items | Where-Object { $_.Tag.Level -eq 'Problem' }).Count
    if ($n) { & $add 30 "$n kind(s) of crashes or errors keep happening" 'See fixes' $pgStab 'Programs or Windows crashed several times recently.' $null }
    $c0 = @($script:HealthQuick.Disks | Where-Object { $_.Id -eq 'C:' })[0]
    if ($c0 -and $c0.Size -and $c0.Free / $c0.Size -lt 0.1) { & $add 35 "Drive C: is almost full ($(Format-Size $c0.Free) free)" 'Free up space' $pgSpace "Your PC is almost full - only $(Format-Size $c0.Free) is left. That makes it slow." 'clean' }
    $q0 = $script:HealthQuick
    if ($q0 -and $q0.TotalKB -and $q0.FreeKB / $q0.TotalKB -lt 0.15) { & $add 38 "Memory is $([int](100 - 100 * $q0.FreeKB / $q0.TotalKB))% full - see what is using it" 'See' $pgNow 'The PC''s memory is almost full, which makes everything slow. Closing programs you don''t use helps.' $null }
    if ($script:NetProblems) { & $add 40 'The network has a problem' 'Check' $pgNet 'Your internet connection has a problem.' $null }
    if ($script:JunkBytes -gt 1GB) { & $add 45 "Clean up $(Format-Size $script:JunkBytes) of junk files" 'Clean' $pgClean "There are $(Format-Size $script:JunkBytes) of leftover files you don't need." 'clean' }
    if ($script:SpaceFree -gt 3GB) { & $add 48 "Free up to $(Format-Size $script:SpaceFree) with space savers" 'Review' $pgSpace "Windows keeps up to $(Format-Size $script:SpaceFree) for things you may not need." $null }
    $n = @($lvStart.Items | Where-Object { $_.Tag.On -and $_.Tag.Advice -eq 'safe to turn off' }).Count
    if ($n) { & $add 50 "Stop $n app(s) starting with Windows" 'Review' $pgStartup "$n app(s) start by themselves every time you turn on the PC, which makes starting slower." 'startup' }
    $n = @($lvUpd.Items).Count
    if ($n) { & $add 55 "$n program update(s) available" 'Update' $pgUpd "$n program(s) have a newer version with fixes." 'updates' }
    if ($script:PrivacyOn) { & $add 60 "Turn off $($script:PrivacyOn) Windows ads, tips and tracking settings" 'Turn off' $pgPriv "Windows shows you ads and tips, and shares more about you than needed ($($script:PrivacyOn) settings)." 'privacy' }
    if ($script:PowerIssues) { & $add 62 "Fix $($script:PowerIssues) power setting(s)" 'Review' $pgPower "$($script:PowerIssues) power setting(s) make the PC slower or empty the battery faster than needed." $null }
    if ($script:TasksActive) { & $add 65 "Switch off $($script:TasksActive) junk scheduled task(s)" 'Review' $pgTasks "$($script:TasksActive) helper program(s) from other companies run in the background by themselves." 'tasks' }
    if ($script:BatteryWorn) { & $add 70 'The battery is worn out - see how to replace it' 'See' $pgBatt "Your battery is worn out and doesn't last as long any more. A new battery fixes that." $null }
    if ($script:CtxLeftovers) { & $add 75 "Hide $($script:CtxLeftovers) leftover right-click menu entr(y/ies)" 'Review' $pgCtx 'Removed programs left old entries in your right-click menu.' 'context' }
    $rem = @(Get-Reminders)
    foreach ($x in $rem) { [void]$c.Add($x) }
    # A reminder about waiting updates replaces the plain "updates available" step.
    if ($rem | Where-Object Fix -eq 'updates') { $c = @($c | Where-Object { $_.Remind -or $_.Fix -ne 'updates' }) }
    @($c | Sort-Object P)
}

$SimpleFont = New-Object Drawing.Font('Segoe UI', 11)
$SimpleBig = New-Object Drawing.Font('Segoe UI Semibold', 20)
$SimpleTileFont = New-Object Drawing.Font('Segoe UI Semibold', 12)
$SimpleIcon = New-Object Drawing.Font($IconFontName, 14)
$SimpleIconBig = New-Object Drawing.Font($IconFontName, 24)
# Panels that paint themselves (cards) would flicker while the window is resized without this.
function Set-DoubleBuffered($Control) { try { $Control.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($Control, $true, $null) } catch { } }
# A card: rounded, in its own BackColor, with a faint edge. Its children use the same BackColor.
function Draw-Card($C, $G) {
    $G.SmoothingMode = 'AntiAlias'; $G.Clear($C.Parent.BackColor)
    $p = New-RoundRect 0.5 0.5 ($C.Width - 1.5) ($C.Height - 1.5) (Px 10)
    $br = New-Object Drawing.SolidBrush($C.BackColor); $G.FillPath($br, $p); $br.Dispose()
    $pen = New-Object Drawing.Pen($Theme.Hover); $G.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
}
# An icon in a tinted circle, as used by the status card, the tiles and the rows.
function Draw-IconDisc($G, [single]$X, [single]$Y, [single]$D, [int]$Glyph, $Color, $Font, [int]$Alpha = 38) {
    $G.SmoothingMode = 'AntiAlias'
    $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($Alpha, $Color)); $G.FillEllipse($br, $X, $Y, $D, $D); $br.Dispose()
    $r = New-Object Drawing.Rectangle([int]$X, [int]$Y, [int]$D, [int]$D)
    [Windows.Forms.TextRenderer]::DrawText($G, [string][char]$Glyph, $Font, $r, $Color, 'VerticalCenter, HorizontalCenter, NoPrefix')
}
$simple = New-Object Windows.Forms.Panel
$simple.Dock = 'Fill'; $simple.BackColor = $Theme.Bg; $simple.Visible = $false; $simple.Font = $SimpleFont
$sCol = New-Object Windows.Forms.Panel   # the centred column
$sCol.Width = 860; $sCol.Height = 700; $sCol.Font = $SimpleFont
$simple.Controls.Add($sCol)
# The column takes the window's width up to a comfortable reading width, and is worked out again from the window
# every time (not from its own last width: the window is tiny for a moment while it opens, and a maximized window
# then kept a narrow column).
function Resize-SimpleColumn {
    $cw = $simple.ClientSize.Width; $ch = $simple.ClientSize.Height
    if ($cw -le 0 -or $ch -le 0) { return }
    $sCol.Width = [int][Math]::Max([double](Px 360), [Math]::Min([double](Px 960), [double]($cw - (Px 48))))
    $sCol.Left = [int][Math]::Max([double](Px 16), ($cw - $sCol.Width) / 2)
    $sCol.Top = Px 12; $sCol.Height = [int][Math]::Max([double](Px 300), [double]($ch - (Px 24)))
    # Compact when the tall layout would leave room for fewer than four items in the list (the default window size).
    $compact = ($ch / $DpiScale) - 446 -lt 4 * 78
    # (Set every time: the first resize comes before the window is scaled for the screen, which would scale these twice.)
    if ($sStatus) {
        $sStatus.Height = Px $(if ($compact) { 108 } else { 136 }); $sDot.Width = Px $(if ($compact) { 86 } else { 104 })
        $sTiles.Height = Px $(if ($compact) { 118 } else { 176 })
    }
    if ($compact -ne $script:SimpleCompact) { $script:SimpleCompact = $compact; foreach ($t in @($sFast, $sCheck, $sHelp)) { if ($t) { $t.Invalidate() } } }
}
$simple.Add_Resize({ Resize-SimpleColumn })
$simple.Add_VisibleChanged({ Resize-SimpleColumn })
$form.Add_Shown({ Resize-SimpleColumn })
# Top: logo, name and the way to the advanced view
$sTop = New-Object Windows.Forms.Panel; $sTop.Dock = 'Top'; $sTop.Height = 58
$sLogo = New-Object Windows.Forms.PictureBox; $sLogo.Dock = 'Left'; $sLogo.Width = 40
$sLogo.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $d = [single](Px 34); $y = [single](($s.Height - $d) / 2)
    $p = New-RoundRect 0 $y $d $d (Px 9); $br = New-Object Drawing.SolidBrush($Theme.Accent); $g.FillPath($br, $p); $br.Dispose(); $p.Dispose()
    $r = New-Object Drawing.Rectangle(0, [int]$y, [int]$d, [int]$d)
    [Windows.Forms.TextRenderer]::DrawText($g, [string][char]0xE95E, $SimpleIcon, $r, [Drawing.Color]::White, 'VerticalCenter, HorizontalCenter, NoPrefix')
})
$sName = New-Object Windows.Forms.Label; $sName.Text = 'PC Tune-Up'; $sName.Font = $FontTitle; $sName.TextAlign = 'MiddleLeft'; $sName.Padding = New-Object Windows.Forms.Padding(6, 0, 0, 2); $sName.AutoEllipsis = $true
$sAll = New-Button 'Advanced view'
$sAll.Font = $FontBold; $sAll.MinimumSize = New-Object Drawing.Size(0, 38); $sAll.Padding = New-Object Windows.Forms.Padding(34, 0, 14, 0); $sAll.Margin = New-Object Windows.Forms.Padding(0)
$sAll.BackColor = $Theme.AccentSoft; $sAll.ForeColor = $Theme.AccentText; $sAll.FlatAppearance.MouseOverBackColor = $Theme.Hover
$sAll.Add_Paint({ param($s, $e)   # (after Draw-Button) the icon in front of the text
    $r = New-Object Drawing.Rectangle([int]($s.Padding.Left - (Px 26)), 0, [int](Px 20), $s.Height)
    [Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string][char]0xE8A9, $IconFont, $r, $s.ForeColor, 'VerticalCenter, HorizontalCenter, NoPrefix')
})
$sAll.Add_Click({ Set-ViewMode 'full' })
$sAllTip = New-Object Windows.Forms.ToolTip
$sAll.Add_MouseEnter({ $sAllTip.SetToolTip($this, (T 'Show every page and tool. You can come back to this simple view at any time.')) })
$sTop.Controls.AddRange(@($sName, $sLogo, $sAll))
$sTop.Add_Layout({
    $sAll.Left = $sTop.ClientSize.Width - $sAll.Width - 1; $sAll.Top = [int](($sTop.ClientSize.Height - $sAll.Height) / 2)
    $sName.SetBounds($sLogo.Width, 0, [Math]::Max(10, $sAll.Left - $sLogo.Width - 8), $sTop.ClientSize.Height)
})
$sAll.Add_SizeChanged({ $sTop.PerformLayout() })
# Status: a ring in the status colour with an icon, a headline and one sentence
$sStatus = New-Object Windows.Forms.Panel; $sStatus.Dock = 'Top'; $sStatus.Height = 136; $sStatus.BackColor = $Theme.Soft; $sStatus.Padding = New-Object Windows.Forms.Padding(22, 16, 18, 16)
Set-DoubleBuffered $sStatus
$sStatus.Add_Paint({ param($s, $e) Draw-Card $s $e.Graphics })
$sDot = New-Object Windows.Forms.PictureBox; $sDot.Dock = 'Left'; $sDot.Width = 104; $sDot.BackColor = $Theme.Soft
$script:SimpleColor = $Theme.Muted; $script:SimpleGlyph = 0xE721; $script:SimpleBusy = $true; $script:SimpleSpin = 0.0
$sDot.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $pw = [single](Px 7); $d = [single]([Math]::Min($s.Width, $s.Height) - $pw - (Px 4)); $x = [single](($s.Width - $d) / 2); $y = [single](($s.Height - $d) / 2)
    $c = $script:SimpleColor
    $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(22, $c)); $g.FillEllipse($br, $x, $y, $d, $d); $br.Dispose()
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(50, $c), $pw); $g.DrawEllipse($pen, $x, $y, $d, $d); $pen.Dispose()
    $pen = New-Object Drawing.Pen($c, $pw); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    if ($script:SimpleBusy) { $g.DrawArc($pen, $x, $y, $d, $d, [single]$script:SimpleSpin, [single]100) } else { $g.DrawEllipse($pen, $x, $y, $d, $d) }
    $pen.Dispose()
    $r = New-Object Drawing.Rectangle(0, 0, $s.Width, $s.Height)
    [Windows.Forms.TextRenderer]::DrawText($g, [string][char]$script:SimpleGlyph, $SimpleIconBig, $r, $c, 'VerticalCenter, HorizontalCenter, NoPrefix')
})
$sText = New-Object Windows.Forms.Panel; $sText.Dock = 'Fill'; $sText.Padding = New-Object Windows.Forms.Padding(18, 10, 0, 0); $sText.BackColor = $Theme.Soft
$sHead = New-Object Windows.Forms.Label; $sHead.Dock = 'Top'; $sHead.Height = 46; $sHead.Font = $SimpleBig; $sHead.Text = 'Checking your PC...'; $sHead.AutoEllipsis = $true
$sSub = New-Object Windows.Forms.Label; $sSub.Dock = 'Fill'; $sSub.ForeColor = $Theme.Dim; $sSub.Text = 'This takes about half a minute.'
$sText.Controls.AddRange(@($sSub, $sHead)); $sStatus.Controls.AddRange(@($sText, $sDot))
# While checking, the ring turns; when the last check is done the status updates by itself.
$sSpin = New-Object Windows.Forms.Timer; $sSpin.Interval = 40
$sSpin.Add_Tick({
    if ($Settings.View -ne 'simple') { return }
    $y = -$sList.AutoScrollPosition.Y; if ($y -ne $script:SimpleScrollY) { $script:SimpleScrollY = $y; $sBar.Invalidate() }   # follow the mouse wheel
    if (-not $script:SimpleBusy) { return }
    $script:SimpleSpin = ($script:SimpleSpin + 8) % 360; $sDot.Invalidate()
    if (-not ($script:Jobs.Count -or $script:LoadQueue.Count -or -not $script:EverythingStarted)) { Update-SimpleView }
})
$sSpin.Start()
# Three big tiles: an icon, a title and one line about what it does
$sTiles = New-Object Windows.Forms.TableLayoutPanel; $sTiles.Dock = 'Top'; $sTiles.Height = 176; $sTiles.ColumnCount = 3; $sTiles.Padding = New-Object Windows.Forms.Padding(0, 16, 0, 4)
foreach ($k in 1..3) { [void]$sTiles.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 33.3))) }
$sTiles.RowCount = 1; [void]$sTiles.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))   # the tiles follow the height (compact or tall)
$script:SimpleTab = 'check'
function Draw-SimpleTile($B, $G) {
    $G.SmoothingMode = 'AntiAlias'; $G.Clear($B.Parent.BackColor)
    $primary = $B.Name -eq 'fast'; $hot = $script:HotButton -eq $B; $sel = $script:SimpleTab -eq $B.Name
    $fill = if ($primary) { if ($hot) { $Theme.AccentDark } else { $Theme.Accent } } elseif ($sel) { $Theme.AccentSoft } elseif ($hot) { $Theme.Hover } else { $Theme.Soft }
    $p = New-RoundRect 0.5 0.5 ($B.Width - 1.5) ($B.Height - 1.5) (Px 12)
    $br = New-Object Drawing.SolidBrush($fill); $G.FillPath($br, $p); $br.Dispose()
    if (-not $primary) { $pen = New-Object Drawing.Pen($(if ($sel) { $Theme.Accent } else { $Theme.Hover }), [single]$(if ($sel) { Px 2 } else { 1 })); $G.DrawPath($pen, $p); $pen.Dispose() }
    $p.Dispose()
    $fore = if ($primary) { [Drawing.Color]::White } else { $Theme.Text }
    $iconC = if ($primary) { [Drawing.Color]::White } else { $Theme.AccentText }
    $pad = [int](Px 18); $d = [single](Px 42)
    $lines = @("$($B.Text)" -split "\r?\n", 2 | ForEach-Object { $_.Trim() })
    $dc = if ($primary) { [Drawing.Color]::FromArgb(225, 255, 255, 255) } else { $Theme.Dim }
    # Low tiles (small window): the icon beside the text; tall tiles: the icon above it.
    $compact = $B.Height -lt (Px 140)
    if ($compact) { $pad = [int](Px 14); $d = [single](Px 38) }
    $tx = if ($compact) { $pad + [int]$d + [int](Px 12) } else { $pad }
    $w = $B.Width - $tx - $pad
    $th = [Windows.Forms.TextRenderer]::MeasureText($G, $lines[0], $SimpleTileFont, (New-Object Drawing.Size($w, 999)), 'WordBreak, NoPrefix').Height
    $dh = if ($lines.Count -gt 1) { [Windows.Forms.TextRenderer]::MeasureText($G, $lines[1], $Font, (New-Object Drawing.Size($w, 999)), 'WordBreak, NoPrefix').Height } else { 0 }
    if ($compact) {
        Draw-IconDisc $G $pad (($B.Height - $d) / 2) $d ([int]$B.Tag) $iconC $SimpleIcon $(if ($primary) { 60 } else { 34 })
        $ty = [int][Math]::Max([double]$pad / 2, ($B.Height - $th - $dh - (Px 2)) / 2)
    } else {
        Draw-IconDisc $G $pad $pad $d ([int]$B.Tag) $iconC $SimpleIcon $(if ($primary) { 60 } else { 34 })
        $ty = $pad + [int]$d + [int](Px 12)
    }
    [Windows.Forms.TextRenderer]::DrawText($G, $lines[0], $SimpleTileFont, (New-Object Drawing.Rectangle($tx, $ty, $w, $th)), $fore, 'WordBreak, NoPrefix')
    if ($lines.Count -gt 1) {
        $dy = $ty + $th + [int](Px 2)
        [Windows.Forms.TextRenderer]::DrawText($G, $lines[1], $Font, (New-Object Drawing.Rectangle($tx, $dy, $w, [int][Math]::Max(1.0, [double]($B.Height - $dy - $pad / 2)))), $dc, 'WordBreak, EndEllipsis, NoPrefix')
    }
    if ($B.Focused -and $B.ShowFocusCues) {
        $fp = New-RoundRect 3.5 3.5 ($B.Width - 7.5) ($B.Height - 7.5) (Px 9)
        $pen = New-Object Drawing.Pen($(if ($primary) { [Drawing.Color]::White } else { $Theme.Accent })); $pen.DashStyle = 'Dot'; $G.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose()
    }
}
function New-Tile([string]$Text, [int]$Icon, [string]$Key) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text; $b.Name = $Key; $b.Tag = $Icon; $b.Dock = 'Fill'; $b.Margin = New-Object Windows.Forms.Padding(0, 0, 14, 0)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.UseVisualStyleBackColor = $false; $b.BackColor = $Theme.Bg; $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.Add_Paint({ param($sender, $e) Draw-SimpleTile $sender $e.Graphics })
    $b.Add_MouseEnter({ $script:HotButton = $this; $this.Invalidate() })
    $b.Add_MouseLeave({ if ($script:HotButton -eq $this) { $script:HotButton = $null }; $this.Invalidate() })
    $b.Add_GotFocus({ $this.Invalidate() }); $b.Add_LostFocus({ $this.Invalidate() })
    $b
}
$sFast = New-Tile "Make my PC faster`nRemoves leftover files and stops apps you don't need" 0xE945 'fast'
$sCheck = New-Tile "Check for problems`nShows what could be better, in plain words" 0xE9D9 'check'
$sHelp = New-Tile "Get help`nSend a report to someone who helps you" 0xE897 'help'
$sHelp.Margin = New-Object Windows.Forms.Padding(0)
$sTiles.Controls.Add($sFast, 0, 0); $sTiles.Controls.Add($sCheck, 1, 0); $sTiles.Controls.Add($sHelp, 2, 0)
# Below: what the last tile showed
$sArea = New-Object Windows.Forms.Panel; $sArea.Dock = 'Fill'; $sArea.Padding = New-Object Windows.Forms.Padding(0, 14, 0, 0)
$sAreaHead = New-Object Windows.Forms.Label; $sAreaHead.Dock = 'Top'; $sAreaHead.Height = 38; $sAreaHead.Font = $SimpleTileFont
$sList = New-Object Windows.Forms.FlowLayoutPanel; $sList.FlowDirection = 'TopDown'; $sList.WrapContents = $false; $sList.AutoScroll = $true
# Windows' own scroll bar can't be made dark on a panel like this, so it is pushed just outside the visible area
# and a slim one in the theme's colours is drawn instead (the mouse wheel and dragging work as usual).
$sClip = New-Object Windows.Forms.Panel; $sClip.Dock = 'Fill'
$sBar = New-Object Windows.Forms.PictureBox; $sBar.BackColor = $Theme.Bg; $sBar.Cursor = [Windows.Forms.Cursors]::Hand
$sClip.Controls.AddRange(@($sBar, $sList))
function Get-SimpleScroll {
    $view = $sList.ClientSize.Height; $total = $sList.DisplayRectangle.Height
    if ($total -le $view + 1) { return $null }
    $h = $sBar.Height; $thumb = [Math]::Max([double](Px 36), [double]$h * $view / $total)
    @{ View = $view; Total = $total; Thumb = $thumb; Track = [double]($h - $thumb); Pos = [double](-$sList.AutoScrollPosition.Y) }
}
$sBar.Add_Paint({ param($s, $e)
    $k = Get-SimpleScroll; if (-not $k) { return }
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $y = $k.Track * $k.Pos / [Math]::Max(1.0, [double]($k.Total - $k.View)); $w = [single](Px 6); $x = [single](($s.Width - $w) / 2)
    $p = New-RoundRect $x ([single]$y) $w ([single]$k.Thumb) ($w / 2)
    $br = New-Object Drawing.SolidBrush($(if ($script:SimpleBarHot) { $Theme.Dim } else { $Theme.Border })); $g.FillPath($br, $p); $br.Dispose(); $p.Dispose()
})
$sBar.Add_MouseEnter({ $script:SimpleBarHot = $true; $sBar.Invalidate() })
$sBar.Add_MouseLeave({ $script:SimpleBarHot = $false; $sBar.Invalidate() })
$sBar.Add_MouseDown({ Move-SimpleScroll $_.Y }); $sBar.Add_MouseMove({ if ($_.Button -eq 'Left') { Move-SimpleScroll $_.Y } })
function Move-SimpleScroll([int]$Y) {
    $k = Get-SimpleScroll; if (-not $k) { return }
    $f = [Math]::Min(1.0, [Math]::Max(0.0, ($Y - $k.Thumb / 2) / [Math]::Max(1.0, $k.Track)))
    $sList.AutoScrollPosition = New-Object Drawing.Point(0, [int]($f * ($k.Total - $k.View))); $sBar.Invalidate()
}
function Resize-SimpleList {
    $w = $sClip.ClientSize.Width; $h = $sClip.ClientSize.Height
    $sList.SetBounds(0, 0, $w + [Windows.Forms.SystemInformation]::VerticalScrollBarWidth, $h)
    $sBar.SetBounds($w - (Px 10), 0, (Px 10), $h)
    foreach ($r in $sList.Controls) { $r.Width = $w - (Px 18) }
    $sBar.Invalidate()
}
$sClip.Add_Resize({ Resize-SimpleList })
$sList.Add_Layout({ $sBar.Invalidate() })
$sArea.Controls.AddRange(@($sClip, $sAreaHead))
$sCol.Controls.AddRange(@($sArea, $sTiles, $sStatus, $sTop))
$form.Controls.Add($simple); $simple.BringToFront()

# One row in the list: an icon, a sentence and (maybe) a button. Made at run time, so texts are translated here.
# Tone picks the icon's colour: Accent (can be fixed), Bad (needs attention), Good, or Muted.
function Add-SimpleRow([string]$Text, [string]$Button, [scriptblock]$OnClick, $Tag, [int]$Icon = 0xE946, [string]$Tone = 'Accent', [scriptblock]$Later) {
    $row = New-Object Windows.Forms.Panel
    $row.Width = $sClip.ClientSize.Width - (Px 18); $row.Height = (Px 70); $row.Margin = New-Object Windows.Forms.Padding(0, 0, 0, (Px 8)); $row.BackColor = $Theme.Soft
    $row.Padding = New-Object Windows.Forms.Padding((Px 14), (Px 13), (Px 14), (Px 13))
    Set-DoubleBuffered $row
    $row.Add_Paint({ param($s, $e) Draw-Card $s $e.Graphics })
    $ic = New-Object Windows.Forms.PictureBox; $ic.Dock = 'Left'; $ic.Width = (Px 44); $ic.BackColor = $Theme.Soft
    $ic.Tag = @{ Glyph = $Icon; Color = $(if ($Tone -eq 'Accent') { $Theme.AccentText } else { $Theme[$Tone] }) }
    $ic.Add_Paint({ param($s, $e) $d = [single](Px 40); Draw-IconDisc $e.Graphics 0 (($s.Height - $d) / 2) $d $s.Tag.Glyph $s.Tag.Color $IconFont })
    $l = New-Object Windows.Forms.Label; $l.Dock = 'Fill'; $l.Text = T $Text; $l.TextAlign = 'MiddleLeft'; $l.AutoEllipsis = $true; $l.BackColor = $Theme.Soft
    $l.Padding = New-Object Windows.Forms.Padding((Px 10), 0, (Px 10), 0)
    if ($Button) {
        $b = New-Button (T $Button); $b.Dock = 'Right'; $b.AutoSize = $false; $b.Margin = New-Object Windows.Forms.Padding(0); $b.Tag = $Tag
        # As wide as the (translated) text needs, at least 150 - measured in bold, as "Fix this" is a primary button.
        $b.Width = [Math]::Max((Px 150), [Windows.Forms.TextRenderer]::MeasureText($b.Text, $FontBold).Width + (Px 36))
        $b.Add_Click($OnClick); $row.Controls.Add($b)
        if ($Button -eq 'Fix this' -or $Tag.Remind) { Set-Primary $b }
    }
    if ($Later) {   # a smaller "Later" button left of the main one (not made as wide as the others)
        $gap = New-Object Windows.Forms.Panel; $gap.Dock = 'Right'; $gap.Width = (Px 8); $gap.BackColor = $Theme.Soft
        $lb = New-Button (T 'Later'); $lb.Dock = 'Right'; $lb.AutoSize = $false; $lb.Margin = New-Object Windows.Forms.Padding(0); $lb.Tag = $Tag; $lb.AccessibleDescription = 'later'
        $lb.Width = [Windows.Forms.TextRenderer]::MeasureText($lb.Text, $Font).Width + (Px 36)
        $lb.Add_Click($Later); $row.Controls.Add($gap); $row.Controls.Add($lb)
    }
    $row.Controls.Add($ic); $row.Controls.Add($l); $l.BringToFront()
    $sList.Controls.Add($row)
}
# All buttons in the list as wide as the widest, so they line up.
function Set-SimpleButtonWidths {
    $btns = @($sList.Controls | ForEach-Object { $_.Controls } | Where-Object { $_ -is [Windows.Forms.Button] -and $_.AccessibleDescription -ne 'later' })
    if ($btns) { $w = ($btns | Measure-Object Width -Maximum).Maximum; foreach ($b in $btns) { $b.Width = $w } }
}
function Set-SimpleTab([string]$Tab) {
    if ($script:SimpleTab -eq $Tab) { return }
    $script:SimpleTab = $Tab; $script:SimpleSig = $null; foreach ($t in @($sFast, $sCheck, $sHelp)) { $t.Invalidate() }
}
function Show-SimpleProblems {
    Set-SimpleTab 'check'
    $steps = @(Get-NextSteps)
    $busy = $script:Jobs.Count -or $script:LoadQueue.Count -or -not $script:EverythingStarted
    # Rebuild only when something changed, so the list doesn't flicker each time a check finishes.
    $sig = "$busy|" + (($steps | ForEach-Object { "$($_.Plain)|$($_.Fix)" }) -join '||')
    if ($sig -eq $script:SimpleSig -and $sList.Controls.Count) { return }
    $sList.SuspendLayout(); $sList.Controls.Clear()
    $sAreaHead.Text = if ($steps) { T 'What could be better' } elseif ($busy) { T 'Checking your PC...' } else { T 'Nothing to do' }
    if (-not $steps) {
        if ($busy) { Add-SimpleRow 'Checking your PC - the list appears here in a moment.' $null $null $null 0xE721 'Muted' }
        else { Add-SimpleRow 'Everything looks fine. PC Tune-Up checks again next time you open it.' $null $null $null 0xE73E 'Good' }
    }
    foreach ($s in $steps) {
        $glyph = if ($s.Page -and $NavIcons[$s.Page.Name]) { $NavIcons[$s.Page.Name] } else { 0xE946 }
        $tone = if ($s.P -le 35) { 'Bad' } else { 'Accent' }
        if ($s.Remind) { Add-SimpleRow $s.Plain $s.Btn { Invoke-SimpleFix $this.Tag } $s $glyph $tone { Set-ReminderLater $this.Tag.Id $this.Tag.Later } }
        elseif ($s.Fix) { Add-SimpleRow $s.Plain 'Fix this' { Invoke-SimpleFix $this.Tag } $s $glyph $tone }
        else { Add-SimpleRow $s.Plain 'Show me' { Set-ViewMode 'full'; Show-Page $this.Tag.Page } $s $glyph $tone }
    }
    Set-SimpleButtonWidths; $sList.ResumeLayout()
    $script:SimpleSig = $sig
}
function Show-SimpleHelp {
    Set-SimpleTab 'help'
    $sList.SuspendLayout(); $sList.Controls.Clear()
    $sAreaHead.Text = T 'Get help'
    Add-SimpleRow 'Send a report about this PC to a family member or friend who helps you - by email, with the report attached.' 'Send by email' { Send-HelperReport } $null 0xE715
    Add-SimpleRow 'Copy a short summary to paste into WhatsApp, a text message or a chat.' 'Copy summary' { Copy-PlainSummary } $null 0xE8C8
    Add-SimpleRow 'Something in PC Tune-Up itself not working? Tell the people who make it.' 'Report a problem' { Open-ProblemReport 'bug' } $null 0xED15
    Add-SimpleRow 'See the short introduction again.' 'Show the tour' { Show-Tour } $null 0xE7BE
    Set-SimpleButtonWidths; $sList.ResumeLayout()
}
# The big status: red when something needs attention, orange when things could be better, green when all is well.
function Update-SimpleView {
    if ($Settings.View -ne 'simple') { return }   # (not .Visible: that is false while the window itself is hidden)
    $steps = @(Get-NextSteps)
    $busy = [bool]($script:Jobs.Count -or $script:LoadQueue.Count -or -not $script:EverythingStarted)
    $urgent = @($steps | Where-Object { $_.P -le 35 })
    if ($urgent) { $script:SimpleColor = $Theme.Bad; $script:SimpleGlyph = 0xE7BA; $sHead.Text = T 'Something needs attention'; $sSub.Text = T $urgent[0].Plain }
    elseif ($steps) { $script:SimpleColor = $Theme.Warn; $script:SimpleGlyph = 0xE82F; $sHead.Text = (T '{0} thing(s) could be better').Replace('{0}', "$($steps.Count)"); $sSub.Text = T 'Most can be fixed with one click - see the list below.' }
    elseif ($busy) { $script:SimpleColor = $Theme.Accent; $script:SimpleGlyph = 0xE721; $sHead.Text = T 'Checking your PC...'; $sSub.Text = T 'This takes about half a minute.' }
    else { $script:SimpleColor = $Theme.Good; $script:SimpleGlyph = 0xE73E; $sHead.Text = T 'Your PC is in good shape'; $sSub.Text = T 'Nothing needs doing right now.' }
    if ($busy -and ($steps -or $urgent)) { $sSub.Text += '  ' + (T '(Still checking...)') }
    $script:SimpleBusy = $busy
    $sDot.Invalidate()
    if ($script:SimpleTab -eq 'check') { Show-SimpleProblems }   # keep the open list current
}
# Safe fixes, each with a plain question first. All of them can be undone from History.
function Invoke-SimpleFix($Step) {
    $script:SimpleRun = $true
    try {
        switch ($Step.Fix) {
            'restart' { Invoke-Reminder $Step }
            'winupdate' { Invoke-Reminder $Step }
            'clean' { Invoke-FixMyPc }
            'updates' { Start-ProgramUpdates }
            'startup' {
                $items = @($lvStart.Items | Where-Object { $_.Tag.On -and $_.Tag.Advice -eq 'safe to turn off' })
                $names = ($items | ForEach-Object { $_.Tag.Name -replace '_[0-9A-F]{32}$', '' }) -join ', '
                if ((Show-Msg "Stop these apps from starting by themselves?`n`n$names`n`nThey stay installed - you can still open them whenever you want. You can undo this on the History page." 'YesNo' 'Question') -ne 'Yes') { return }
                foreach ($it in $items) { try { Set-StartupEntry $it.Tag $false } catch { } }
                Update-History; Update-Startup
                Show-Msg 'Done. Your PC will start a little faster next time.' | Out-Null
            }
            'privacy' {
                if ((Show-Msg "Turn off Windows ads, tips and extra data sharing?`n`nYour files and programs are not touched. You can undo this on the History page." 'YesNo' 'Question') -ne 'Yes') { return }
                foreach ($it in $lvPriv.Items) { $it.Checked = $it.Tag.Rec -and -not ($it.Tag.Admin -and -not $IsAdmin) -and (Get-PrivacyState $it.Tag) -ne 'Off' }
                Set-Privacy $true
            }
            'tasks' {
                if ((Show-Msg "Switch off helper programs from other companies that run in the background by themselves (updaters and data collection)?`n`nThe programs themselves keep working. You can undo this on the History page." 'YesNo' 'Question') -ne 'Yes') { return }
                foreach ($it in $lvTasks.Items) { $it.Checked = $it.Tag.Kind -eq 'known' -and $it.Tag.State -ne 'Disabled' }
                Set-Tasks $false
            }
            'context' {
                foreach ($it in $lvCtx.Items) { $it.Checked = $it.Tag.Missing -and -not $it.Tag.Hidden }
                Set-ContextEntries $true
            }
        }
    } finally { $script:SimpleRun = $false; Update-SimpleView }
}
function Set-ViewMode([string]$Mode) {
    $Settings.View = $Mode; Save-Settings
    $isSimple = $Mode -eq 'simple'
    $simple.Visible = $isSimple; $content.Visible = -not $isSimple; $sidebar.Visible = -not $isSimple
    # Docking follows the z-order: the Fill panel must be in front, so it is laid out last and gets only the space
    # the sidebar leaves. (Bringing the sidebar to the front last made the page slide underneath it.)
    if ($isSimple) { $simple.BringToFront(); Update-SimpleView } else { $sidebar.BringToFront(); $content.BringToFront() }
    if ($cmbView) { $cmbView.SelectedIndex = [Math]::Max(0, [array]::IndexOf($cmbView.Tag, $Mode)) }
}
$sFast.Add_Click({ $script:SimpleRun = $true; try { Invoke-FixMyPc } finally { $script:SimpleRun = $false } })
$sCheck.Add_Click({ Show-SimpleProblems })
$sHelp.Add_Click({ Show-SimpleHelp })

# ===========================================================================
# Send a report to the person who helps you: by email with the report attached, or a short summary to paste
# ===========================================================================
function Get-PlainSummary {
    $steps = @(Get-NextSteps)
    $q = $script:HealthQuick
    $lines = @((T 'PC Tune-Up report for {0}').Replace('{0}', $PcName), (T 'Date: {0}').Replace('{0}', (Get-Date).ToString('g')), '')
    if ($q) { $lines += (T 'Memory: {0}% used, drive C: {1} free').Replace('{0}', "$([int](100 * (1 - $q.FreeKB / $q.TotalKB)))").Replace('{1}', $(@($q.Disks | Where-Object Id -eq 'C:' | ForEach-Object { Format-Size $_.Free })[0])) }
    $lines += $(if ($steps) { T 'Could be better:' } else { T 'Everything looks fine.' })
    foreach ($s in $steps | Select-Object -First 8) { $lines += " - $(T $s.Plain)" }
    $lines -join "`r`n"
}
function Copy-PlainSummary {
    try { [Windows.Forms.Clipboard]::SetText((Get-PlainSummary)); Show-Msg 'A short summary is copied. Paste it (Ctrl+V) into WhatsApp, a text message or an email to the person who helps you.' | Out-Null }
    catch { Show-Msg "Couldn't copy: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null }
}
function Send-HelperReport {
    $name = 'PC Tune-Up report {0} {1}.html' -f ($PcName -replace '[\\/:*?"<>|]', ''), (Get-Date -Format 'yyyy-MM-dd')
    $file = Join-Path ([Environment]::GetFolderPath('MyDocuments')) $name
    if ((Show-Msg "This saves a report about this PC in Documents and starts an email to the person who helps you.`n`nThe report shows how the PC is doing, what it found and which programs are installed. It contains no passwords, no files and no browsing history." 'OKCancel' 'Information') -ne 'OK') { return }
    try { [void](Save-ReportNow -Path $file -NoOpen) } catch { Show-Msg "Couldn't save the report: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null; return }
    $subject = T 'My PC - report from PC Tune-Up'
    $body = (T 'Hi, could you have a look at my PC? The report from PC Tune-Up is attached.') + "`r`n`r`n" + (Get-PlainSummary)
    # Outlook (the classic app) can attach the file itself; other mail apps get the text and an Explorer window with the file.
    $sent = $false
    try {
        $ol = New-Object -ComObject Outlook.Application -ErrorAction Stop
        $mail = $ol.CreateItem(0); $mail.Subject = $subject; $mail.Body = $body; [void]$mail.Attachments.Add($file); $mail.Display()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($mail); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ol); $sent = $true
    } catch { }
    if (-not $sent) {
        $body2 = $body + "`r`n`r`n" + (T '(The full report is the file "{0}" in my Documents folder - I will attach it.)').Replace('{0}', $name)
        try { Start-Process ("mailto:?subject=$([uri]::EscapeDataString($subject))&body=$([uri]::EscapeDataString($body2.Substring(0, [Math]::Min(1500, $body2.Length))))") } catch { }
        Start-Process explorer.exe "/select,`"$file`""
        Show-Msg "An email has been started, and the report is selected in File Explorer.`n`nDrag the file ""$name"" into the email (or use the paperclip), then send it." | Out-Null
    }
    Add-History 'Help' 'Report' "saved to Documents for sending ($name)"; Update-History
}

# ===========================================================================
# Plain words: hovering over a row that uses a technical term explains it in one everyday sentence
# ===========================================================================
$Glossary = [ordered]@{
    'telemetry'            = 'Telemetry: information about how you use your PC that is sent to the maker.'
    'scheduled task'       = 'Scheduled task: a small job Windows starts by itself at set times, often an updater.'
    'service'              = 'Service: a program that runs in the background without a window.'
    'DNS'                  = 'DNS: the internet''s phone book - it turns website names into addresses.'
    'hibernat'             = 'Hibernation file: a hidden file where Windows saves everything when the PC goes into deep sleep.'
    'paging file'          = 'Paging file: space on the drive that Windows uses when the memory is full.'
    'BIOS'                 = 'BIOS: the built-in software that starts the PC before Windows.'
    'driver'               = 'Driver: the small program that lets Windows talk to a part of the PC, such as the screen or Wi-Fi.'
    'restore point'        = 'Restore point: a snapshot of Windows'' settings you can go back to if something goes wrong.'
    'reserved storage'     = 'Reserved storage: disk space Windows keeps free so updates always have room.'
    'Storage Sense'        = 'Storage Sense: Windows'' own automatic clean-up.'
    'winget'               = 'winget: Windows'' built-in tool for installing and updating programs.'
    'policy'               = 'Policy: a setting that is forced on the PC, normally by a company''s IT department.'
    'extension'            = 'Extension: an add-on for a web browser.'
    'Fast startup'         = 'Fast startup: Windows saves part of itself when you shut down, so it starts quicker.'
    'bloatware'            = 'Bloatware: programs the PC maker installed that most people never use.'
    'cache'                = 'Cache: copies a program keeps to work faster. Safe to delete - they come back when needed.'
    'crash dump'           = 'Crash dump: a record saved when a program crashed, only useful to its makers.'
    'GPU'                  = 'GPU: the graphics card - the part that draws everything on the screen.'
    'adware'               = 'Adware: software that shows you advertisements or changes your browser to make money.'
    'firmware'             = 'Firmware: software built into a part of the PC, such as the BIOS or the drive.'
}
$GlossaryRx = @(foreach ($k in $Glossary.Keys) { @{ Rx = [regex]::new('(?i)\b' + [regex]::Escape($k)); Text = $Glossary[$k] } })
function Get-GlossaryTip([object[]]$Cells) {
    $all = ($Cells | ForEach-Object { "$_" }) -join ' '
    $tips = @(foreach ($g in $GlossaryRx) { if ($g.Rx.IsMatch($all)) { T $g.Text } }) | Select-Object -First 2
    $tips -join "`n"
}

Enable-Translation $form
Show-Page $pgHealth

# ---------------------------------------------------------------------------
# Command line: /install, /uninstall, /? and the windowless /report and /fix
# ---------------------------------------------------------------------------
function Write-Cli([string]$Text) { try { [Console]::Out.WriteLine((T $Text)) } catch { } }
if ($Cli.Install) { Install-App; Write-Cli "PC Tune-Up installed in $InstallDir"; return }
if ($Cli.Uninstall) { Uninstall-App; return }
# Things worth telling about, each with a stable key, so the automatic run can say what is NEW since last time.
# Numbers are left out of the keys ("17 updates" and "18 updates" are the same thing); crashes keep their count, so "more crashes" shows up too.
$WatchFile = Join-Path $DataDir 'watch.json'
function Get-WatchFacts {
    $f = @{}
    $norm = { param($t) ("$t" -replace '\(.*?\)', '' -replace '\d+([.,]\d+)?', '#' -replace '\s+', ' ').Trim() }
    foreach ($a in @($script:HealthAdvice)) { $f["advice|$(& $norm $a)"] = @{ Text = "$a"; Count = 0 } }
    foreach ($it in $lvStab.Items) { if ($it.Tag.Level -in 'Problem', 'Warning') { $f["stab|$($it.Tag.Problem)|$(& $norm $it.Tag.What)"] = @{ Text = "$($it.Tag.What)"; Count = [int]$it.Tag.Count } } }
    foreach ($it in $lvBrw.Items) {
        if ($it.Tag.Kind -eq 'Extension') { $f["ext|$($it.Tag.Browser)|$($it.Tag.Item)"] = @{ Text = "New browser extension: $($it.Tag.Item) ($($it.Tag.Browser))"; Count = 0 } }
        elseif ($it.Tag.Level -eq 'Risky') { $f["brw|$($it.Tag.Item)"] = @{ Text = "$($it.Tag.Item) ($($it.Tag.Browser))"; Count = 0 } }
    }
    foreach ($it in $lvSec.Items) { if ($it.Tag.Level -eq 'Problem') { $f["sec|$($it.Tag.Check)"] = @{ Text = "Security: $($it.Tag.Check) - $($it.Tag.Result)"; Count = 0 } } }
    foreach ($it in $lvDrv.Items) { if ($it.Tag.Level -eq 'Problem') { $f["drv|$($it.Tag.Device)"] = @{ Text = "Device problem: $($it.Tag.Device)"; Count = 0 } } }
    foreach ($r in @(Get-Reminders)) { $f["remind|$($r.Id)"] = @{ Text = $r.Text; Count = 0 } }
    $f
}
# Compares with the last run and remembers this one. Returns the lines worth a notification ($null on the very first run).
function Compare-WatchFacts {
    $now = Get-WatchFacts
    $old = $null
    if (Test-Path $WatchFile) { try { $old = @{}; (Get-Content $WatchFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $old[$_.Name] = [int]$_.Value } } catch { $old = $null } }
    $save = [ordered]@{}; foreach ($k in $now.Keys) { $save[$k] = $now[$k].Count }
    try { $save | ConvertTo-Json -Compress | Set-Content -Path $WatchFile -Encoding UTF8 } catch { }
    if ($null -eq $old) { return $null }
    $new = foreach ($k in $now.Keys) {
        if (-not $old.ContainsKey($k)) { $now[$k].Text }
        elseif ($k -like 'stab|*' -and $now[$k].Count -ge $old[$k] + 3) { "More often: $($now[$k].Text) (+$($now[$k].Count - $old[$k]))" }
    }
    , @($new)
}
if ($Cli.Auto) {
    # Scheduled maintenance: clean like Fix my PC (no startup or service changes), save a report, then a notification.
    $script:AutoRun = $true
    function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { if ($Buttons -eq 'YesNo') { 'Yes' } else { 'OK' } }
    $deadline = (Get-Date).AddMinutes(20)
    function Wait-Idle { do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while (($script:Jobs.Count -or $script:LoadQueue.Count) -and (Get-Date) -lt $deadline) }
    Start-Everything; Save-MemSample; Wait-Idle
    $script:FixFreed = 0
    Invoke-FixMyPc; Wait-Idle
    Update-Health -Quick; Wait-Idle
    $reportFile = Join-Path $DataDir 'last-report.html'
    try { [void](Save-ReportNow -Path $reportFile -NoOpen) } catch { }
    $look = @($script:HealthAdvice)
    $news = Compare-WatchFacts                         # $null = first run, nothing to compare with
    $summary = "freed $(Format-Size $script:FixFreed)$(if ($news) { ", $(@($news).Count) new thing(s)" } elseif ($null -ne $news) { ', nothing new' } elseif ($look) { ", $($look.Count) thing(s) worth a look" })"
    Add-History 'Maintenance' 'Automatic' $summary
    $Settings.LastAuto = "$((Get-Date).ToString('g')) - $(T $summary)"; Save-Settings
    $notify = switch ($Settings.AutoNotify) { 'never' { $false } 'always' { $true } default { $null -eq $news -or @($news).Count -gt 0 } }
    if (-not $notify) { $JobTimer.Stop(); return }
    # A tray notification (shows as a Windows notification); clicking it opens PC Tune-Up.
    $tray = New-Object Windows.Forms.NotifyIcon
    $tray.Icon = if ($RunningAsExe) { [Drawing.Icon]::ExtractAssociatedIcon($SelfExe) } else { [Drawing.SystemIcons]::Information }
    $tray.Text = 'PC Tune-Up'; $tray.Visible = $true
    $tray.BalloonTipTitle = T 'PC Tune-Up maintenance'
    $text = if ($news) {
        $list = (@($news) | Select-Object -First 3 | ForEach-Object { T $_ }) -join '; '
        if (@($news).Count -gt 3) { $list += '; ' + (T "and $(@($news).Count - 3) more") }
        (T 'New since last time: {0}').Replace('{0}', $list)
    } elseif ($look) { T "Cleaned $(Format-Size $script:FixFreed). $($look.Count) thing(s) worth a look - click to see." }
    else { T "Cleaned $(Format-Size $script:FixFreed). Everything looks fine." }
    $tray.BalloonTipText = if ($text.Length -gt 250) { $text.Substring(0, 247) + '...' } else { $text }   # Windows cuts notifications at about 255 characters
    $script:AutoOpen = $false
    $tray.Add_BalloonTipClicked({ $script:AutoOpen = $true }); $tray.Add_Click({ $script:AutoOpen = $true })
    $tray.ShowBalloonTip(15000)
    $until = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $until -and -not $script:AutoOpen) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    $tray.Visible = $false; $tray.Dispose()
    if ($script:AutoOpen) { if ($RunningAsExe) { Start-Process $SelfExe } else { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" } }
    $JobTimer.Stop()
    return
}
if ($CliMode) {
    if ($RunningAsExe -and [PcTuneUp.Native]::AttachConsole(-1)) {   # print into the console the exe was started from
        $w = New-Object IO.StreamWriter([Console]::OpenStandardOutput()); $w.AutoFlush = $true; [Console]::SetOut($w)
    }
    if ($Cli.Help) {
        Write-Cli "PC Tune-Up $AppVersion`n`n  PC-TuneUp.exe /report[:file.html]   check everything and save a report (default: Documents)`n  PC-TuneUp.exe /fix                  run the safe Fix my PC steps without asking`n  PC-TuneUp.exe /fix /report          both`n  PC-TuneUp.exe /auto                 the automatic maintenance run (clean, check, notify)`n  PC-TuneUp.exe /install | /uninstall  install or remove for this user`n`nRun as administrator to include Windows files and services. Use 'start /wait' in a command prompt."
        return
    }
    # No window: messages go to the console, and questions are answered Yes.
    function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { Write-Cli $Text; if ($Buttons -eq 'YesNo') { 'Yes' } else { 'OK' } }
    function Wait-Idle([int]$Seconds = 900) {
        $deadline = (Get-Date).AddSeconds($Seconds)
        do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while (($script:Jobs.Count -or $script:LoadQueue.Count) -and (Get-Date) -lt $deadline)
    }
    Write-Cli "PC Tune-Up $AppVersion - checking this PC$(if (-not $IsAdmin) { ' (not as administrator: Windows files and services are skipped)' })..."
    Start-Everything; Wait-Idle
    if ($Cli.Fix) { Invoke-FixMyPc; Wait-Idle }
    if ($null -ne $Cli.Report) { Write-Cli "Report saved: $(Save-ReportNow -Path $Cli.Report -NoOpen)" }
    Write-Cli ''
    if ($script:HealthAdvice) { Write-Cli 'Worth a look:'; $script:HealthAdvice | ForEach-Object { Write-Cli "  - $_" } } else { Write-Cli 'No problems spotted.' }
    $JobTimer.Stop()
    return
}

# ---------------------------------------------------------------------------
# New users start in simple view; people who already used PC Tune-Up keep all tools.
if ($Settings.View -notin 'simple', 'full') { $Settings.View = if ($Settings.TourShown -or $Settings.AskedInstall -or (Test-Path $HistoryFile)) { 'full' } else { 'simple' }; Save-Settings }
Set-ViewMode $Settings.View
Resize-NavBottom
$form.Add_Shown({
    Start-Everything
    if ($Settings.CheckUpdates) { Start-UpdateCheck -Silent }
    if ($IsInstalled) { try { Set-ItemProperty -Path $UninstallKey -Name DisplayVersion -Value $AppVersion -ErrorAction Stop } catch { } }   # keep Settings > Apps current after self-updates
    $oldExe = [IO.Path]::ChangeExtension($SelfExe, '.old.exe')
    if ($RunningAsExe -and (Test-Path -LiteralPath $oldExe)) { Start-Bg $OldExeCleanupWork $oldExe { } }
    # First start from a downloaded file: offer to install (once).
    if ($RunningAsExe -and -not $IsInstalled -and -not $FromWinget -and -not $Settings.AskedInstall) {
        $Settings.AskedInstall = $true; Save-Settings
        $q = "Install PC Tune-Up on this PC?`n`nIt adds PC Tune-Up to the Start menu and to Settings > Apps (so it can be uninstalled like any app), and it keeps itself up to date. No administrator rights needed.`n`nYou can also do this later in Settings."
        if ((Show-Msg $q 'YesNo' 'Question') -eq 'Yes') { Install-App -Launch }
    }
    if (-not $Settings.TourShown -and $form.Visible) { Show-Tour }
})
# Grow every control by the screen scaling (fonts already scale on their own; list columns, row heights and grid
# columns were sized with Px). Then cap the window to the screen.
if ($DpiScale -ne 1) { $form.Scale((New-Object Drawing.SizeF($DpiScale, $DpiScale))) }
$work = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = New-Object Drawing.Size([Math]::Min($form.Width, $work.Width - 40), [Math]::Min($form.Height, $work.Height - 40))
$form.MinimumSize = New-Object Drawing.Size((Px 960), (Px 600))
[void]$form.ShowDialog()
$JobTimer.Stop()
