#Requires -Version 5.1
# PC Tune-Up: speed up and clean any Windows 10/11 PC, whatever the brand.
#   Health    - CPU / RAM / disk / uptime, biggest programs, internet speed test
#   Clean     - temp files, Windows Update cache, crash dumps, Recycle Bin
#   Startup   - turn startup apps on/off (same flags Task Manager uses)
#   Bloatware - find pre-installed junk (OEM tools, trial antivirus, promo apps) and uninstall it
#   Services  - background services from PC makers, updaters and telemetry, with one-click restore
#   Tasks     - scheduled tasks from other companies (updaters, telemetry), switch off/on with undo
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
try { [void][PcTuneUp.Native]::SetProcessDPIAware() } catch { }
[Windows.Forms.Application]::EnableVisualStyles()
$DpiScale = try { [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96 } catch { 1 }
function Px([double]$Pixels) { [int][Math]::Round($Pixels * $DpiScale) }   # for sizes WinForms doesn't scale itself

# Command line (PC-TuneUp.exe /fix /report[:file] /install /uninstall /?). The exe host passes $AppArgs.
$CliArgs = if ($AppArgs) { @($AppArgs) } else { @($args) }
$Cli = @{ Fix = $false; Report = $null; Help = $false; Install = $false; Uninstall = $false }
foreach ($a in $CliArgs) {
    switch -Regex ("$a") {
        '^[/-](\?|h|help)$' { $Cli.Help = $true }
        '^[/-]fix$' { $Cli.Fix = $true }
        '^[/-]report(:(.+))?$' { $Cli.Report = "$($Matches[2])" }
        '^[/-]install$' { $Cli.Install = $true }
        '^[/-]uninstall$' { $Cli.Uninstall = $true }
    }
}
$CliMode = $Cli.Help -or $Cli.Fix -or ($null -ne $Cli.Report)

$AppVersion = '1.7.0'                 # bump for every release; publish-release.ps1 tags it as v<version>
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
$SettingsFile = Join-Path $DataDir 'settings.json'
$Settings = [ordered]@{ Language = 'auto'; Theme = 'system'; CheckUpdates = $true; RestorePoints = $true; AskedInstall = $false }
if (Test-Path $SettingsFile) {
    try { (Get-Content $SettingsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { if ($Settings.Contains($_.Name)) { $Settings[$_.Name] = $_.Value } } } catch { }
}
function Save-Settings { $Settings | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8 }
# ---------------------------------------------------------------------------
# Language. Code and data stay English; T() translates text on its way to the screen.
# Table: English <TAB> Dutch, one per line; {0}, {1}... stand for values filled in at run time.
# ---------------------------------------------------------------------------
$Lang = switch ($Settings.Language) { 'nl' { 'nl' } 'en' { 'en' } default { if ((Get-UICulture).TwoLetterISOLanguageName -eq 'nl') { 'nl' } else { 'en' } } }
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
Program	Programma
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
Installed	Geïnstalleerd
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
Open driver updates in Windows Update	Stuurprogramma-updates openen in Windows Update
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
'@
# Case-sensitive lookups: "Claude" (a program) and "claude" (a process) are different texts.
$script:TExact = New-Object Collections.Hashtable([StringComparer]::Ordinal)
$script:TCache = New-Object Collections.Hashtable([StringComparer]::Ordinal)
$script:TPatterns = @()
# Dates and numbers in the chosen language too (3,5 / okt 2028).
$UiCulture = if ($Lang -eq 'nl') { [Globalization.CultureInfo]::GetCultureInfo('nl-NL') } else { [Globalization.CultureInfo]::CurrentCulture }
[Threading.Thread]::CurrentThread.CurrentCulture = $UiCulture
if ($Lang -eq 'nl') {
    $pats = foreach ($line in $NLTable -split "`r?`n") {
        if (-not $line.Trim()) { continue }
        $en, $nl = $line -split "`t", 2
        if ($en -notmatch '\{\d+\}') { $script:TExact[$en] = $nl; continue }
        $rx = '^' + ([regex]::Escape($en) -replace '\\\{(\d+)}', '(?<p$1>.+?)') + '$'
        @{ Rx = [regex]::new($rx); Nl = $nl; N = ([regex]::Matches($en, '\{\d+\}')).Count; Lit = ($en -replace '\{\d+\}', '').Length }
    }
    $script:TPatterns = @($pats | Sort-Object { $_.Lit } -Descending)   # most specific first; "{0}: {1}" comes last
}
function T([string]$Text, [int]$Depth = 0) {
    if ($Lang -ne 'nl' -or -not $Text -or $Depth -gt 3) { return $Text }
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
    if ($Lang -ne 'nl') { return }
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
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        [void]$script:Jobs.Remove($j)
        try { $result = @($j.PS.EndInvoke($j.Handle)) }
        catch { $result = @(); Show-Msg "Something went wrong:`n$($_.Exception.Message)" 'OK' 'Warning' | Out-Null }
        $j.PS.Dispose(); $j.RS.Dispose()
        & $j.Done $result $j.State
    }
    while ($script:LoadQueue.Count -and $script:Jobs.Count -lt 4) {   # four checks at a time
        $next = $script:LoadQueue[0]; $script:LoadQueue.RemoveAt(0)
        Invoke-PageLoader $next
    }
    if ($activity) { Update-ActivityBar }
    if ($script:ReportPending -and -not $script:Jobs.Count -and -not $script:LoadQueue.Count) { $script:ReportPending = $false; Save-ReportNow }
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
    # Windows draws disabled text in a fixed grey that is unreadable on dark backgrounds; draw it ourselves.
    $b.Add_Paint({
        param($sender, $e)
        if ($sender.Enabled) { return }
        $e.Graphics.Clear($sender.BackColor)
        $pen = New-Object Drawing.Pen($Theme.Border); $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1); $pen.Dispose()
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $sender.Text, $sender.Font, $sender.ClientRectangle, $Theme.Muted, 'HorizontalCenter, VerticalCenter, EndEllipsis')
    })
    $b
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
function New-ListView([bool]$Checks, [object[]]$Columns) {
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $Checks; $lv.Dock = 'Fill'
    $lv.BorderStyle = 'None'; $lv.HeaderStyle = 'Nonclickable'; $lv.BackColor = $Theme.Bg; $lv.ForeColor = $Theme.Text
    $rows = New-Object Windows.Forms.ImageList; $rows.ImageSize = New-Object Drawing.Size(1, (Px 26))   # taller rows
    $lv.SmallImageList = $rows
    for ($i = 0; $i -lt $Columns.Count; $i += 2) { [void]$lv.Columns.Add($Columns[$i], (Px $Columns[$i + 1])) }
    if ($Dark) {   # the native header ignores colours, so draw it; rows still draw themselves
        $lv.OwnerDraw = $true
        $lv.Add_DrawColumnHeader({
            param($sender, $e)
            $brush = New-Object Drawing.SolidBrush($Theme.Side); $e.Graphics.FillRectangle($brush, $e.Bounds); $brush.Dispose()
            $r = $e.Bounds; $r.X += (Px 5); $r.Width -= (Px 5)
            [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $sender.Font, $r, $Theme.Dim, 'VerticalCenter, Left, EndEllipsis')
        })
        $lv.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $true })
        $lv.Add_DrawSubItem({ param($sender, $e) $e.DrawDefault = $true })
    }
    $lv.Add_HandleCreated({
        Set-DarkChrome $this
        $header = [PcTuneUp.Native]::SendMessage($this.Handle, 0x101F, [IntPtr]::Zero, [IntPtr]::Zero)   # LVM_GETHEADER
        if ($Dark -and $header -ne [IntPtr]::Zero) { try { [void][PcTuneUp.Native]::SetWindowTheme($header, 'DarkMode_ItemsView', $null) } catch { } }
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
function Add-Row($Lv, [object[]]$Cells, $Tag = $null, [bool]$Checked = $false) {
    $it = New-Object Windows.Forms.ListViewItem([string]$Cells[0])
    $it.Text = T ([string]$Cells[0])
    foreach ($c in $Cells[1..($Cells.Count - 1)]) { [void]$it.SubItems.Add((T ([string]$c))) }
    $it.Tag = $Tag; $it.Checked = $Checked
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
$lblProcCap = New-Object Windows.Forms.Label
$lblProcCap.Dock = 'Top'; $lblProcCap.Height = 30; $lblProcCap.TextAlign = 'BottomLeft'; $lblProcCap.Font = $FontBold
$lblProcCap.Text = 'Programs using the most memory'
$lvProc = New-ListView $false @('Program', 300, 'Memory (MB)', 120, 'Processes', 100)
Set-PageLayout $pgHealth $lvProc @((New-ButtonBar @($btnFix, $btnRefresh, $btnSpeed, $btnWU, $btnReport, $btnLog, $btnKeep)), $gridHealth, $lblAdvice, $lblSpeed, $lblProcCap)

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
    foreach ($k in 'Backup', 'Security', 'Stability', 'Updates') { if ($script:ExtraAdvice[$k]) { $advice += $script:ExtraAdvice[$k] } }
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
    Start-Bg -Label 'Checking drive, battery and updates' $HealthDeepWork $null { param($r) if ($r) { $script:HealthDeep = $r[0] }; Render-Health }
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
            $it = Add-Row $lvStart @($display, $s.Scope, $advice, $e.Cmd) @{ Src = $s; Name = $e.Name; On = $on; Advice = $advice } $on
            if ($advice -like 'keep*') { $it.ForeColor = $Theme.Good }
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
$pgDisk = New-Page 'Disk' 'Find what is filling the drive. Pick a place and Scan; double-click a row to look inside it. This only looks - it never deletes.'
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
$btnUpdRun.Add_Click({
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
})

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
            $it.ForeColor = switch ($r.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.Muted } }
        }
        $lvSec.EndUpdate()
        $p = @($rows | Where-Object Level -eq 'Problem').Count; $w = @($rows | Where-Object Level -eq 'Warning').Count
        $lblSec.Text = "$(@($rows | Where-Object Level -eq 'OK').Count) of $($rows.Count) checks fine" + $(if ($p) { ", $p problem(s)" }) + $(if ($w) { ", $w worth a look" }) + '.'
        if ($p) { $script:ExtraAdvice['Security'] = "Security: $p problem(s) - see the Security tab." } else { $script:ExtraAdvice.Remove('Security') }
        if ($lvSec.Items.Count) { $lvSec.Items[0].Selected = $true }
        Update-Health -Quick
    }
}
function Open-SecSetting {
    if (-not $lvSec.SelectedItems.Count) { return }
    $link = $lvSec.SelectedItems[0].Tag.Link
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
        [void]$rows.Add([pscustomobject]@{ Problem = $Problem; Level = $Level; What = $What; Count = @($Events).Count; Last = $last; Todo = $Todo; Search = $Search; Fix = $Fix })
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

    $index = $null
    try { $index = (Get-CimInstance Win32_ReliabilityStabilityMetrics -OperationTimeoutSec 15 -ErrorAction Stop | Sort-Object TimeGenerated -Descending | Select-Object -First 1).SystemStabilityIndex } catch { }
    [pscustomobject]@{ Rows = $rows; Index = $index }
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
    drivers   = @{ Label = 'Open driver updates in Windows Update'; Admin = $false }
    store     = @{ Label = 'Open Store app updates'; Admin = $false }
    appupdate = @{ Label = 'Look for an update on the Updates page'; Admin = $false }
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
        'drivers'   { Start-Process 'ms-settings:windowsupdate-optionalupdates'; return }
        'store'     { Start-Process 'ms-windows-store://downloadsandupdates'; return }
        'appupdate' { Show-Page $pgUpd; return }
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
    if (-not $lvStab.SelectedItems.Count) { return }
    $q = $lvStab.SelectedItems[0].Tag.Search
    if ($q) { Start-Process ('https://www.bing.com/search?q=' + [uri]::EscapeDataString($q)) }
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
        $text = "$($t.TaskPath)$($t.TaskName) | $($t.Author)"
        $exe = [Environment]::ExpandEnvironmentVariables("$(@($t.Actions)[0].Execute)".Trim('"'))
        $company = if ($exe -and (Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue)) { try { [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).CompanyName } catch { '' } } else { '' }
        $maker = if ($t.Author -and $t.Author -notmatch '\\') { "$($t.Author)" } elseif ($company) { $company } elseif ($soft) { 'Microsoft (Windows)' } else { '' }
        $known = $cfg.Catalog | Where-Object { $text -match $_.Match } | Select-Object -First 1
        if (-not $known -and $cfg.UserKeep -and "$text $company" -match $cfg.UserKeep) { continue }
        if (-not $known -and "$text $company" -match $cfg.Keep) { continue }
        $kind = if ($known) { 'known' } elseif ($t.TaskName -match $cfg.Likely) { 'likely' } else { 'review' }
        $why = if ($known) { $known.Why } elseif ($kind -eq 'likely') { 'looks like an updater or telemetry - usually safe to turn off' } else { 'review: only turn off if you know what it is' }
        $runs = (@($t.Triggers | ForEach-Object { $c = $_.CimClass.CimClassName; if ($c -eq 'MSFT_TaskTimeTrigger') { if ($_.Repetition.Interval) { 'repeatedly' } else { 'once' } } elseif ($when[$c]) { $when[$c] } else { 'on a schedule' } } | Select-Object -Unique))
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
function Set-Tasks([bool]$Enable) {
    $picked = @($lvTasks.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { ($_.State -eq 'Disabled') -eq $Enable })
    if (-not $picked) { Show-Msg $(if ($Enable) { 'Check one or more tasks that are off first.' } else { 'Check one or more tasks that are on first.' }) | Out-Null; return }
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
$btnTaskOff.Add_Click({ Set-Tasks $false })
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
            $it.ForeColor = switch ($b.Level) { 'Problem' { $Theme.Bad } 'Warning' { $Theme.Warn } 'OK' { $Theme.Good } default { $Theme.Muted } }
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
    if (-not $lvBackup.SelectedItems.Count) { return }
    $link = $lvBackup.SelectedItems[0].Tag.Link
    if (-not $link) { return }
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
        foreach ($u in (Get-UpgradeRows $script:UpgHw)) {
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
                'Task' {
                    if ($u.Enable) { [void](Enable-ScheduledTask -TaskPath $u.Path -TaskName $u.Name -ErrorAction Stop) }
                    else { [void](Disable-ScheduledTask -TaskPath $u.Path -TaskName $u.Name -ErrorAction Stop) }
                    $logs += , @('Undo', $e.Item, $(if ($u.Enable) { 'scheduled task switched back on' } else { 'scheduled task switched off again' }))
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
        $h.Text = $Hint; $h.ForeColor = $Theme.Dim; $h.AutoSize = $true; $h.MaximumSize = New-Object Drawing.Size((Px 780), 0)
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

Add-SetSection 'Language' 'Takes effect when PC Tune-Up restarts.'
$cmbLang = New-Choice @('Automatic (Windows language)', 'English', 'Nederlands') @('auto', 'en', 'nl') $Settings.Language
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

Add-SetSection 'Installation' $(if ($IsInstalled) { "Installed for you in $InstallDir - it appears in the Start menu and in Settings > Apps." }
                                 elseif ($RunningAsExe) { "Running from $SelfExe without installing. Install to get a Start-menu entry and uninstall it like any other app (no administrator needed)." }
                                 else { 'Running as a PowerShell script (developer mode) - install from PC-TuneUp.exe instead.' })
$btnInstall = New-Button $(if ($IsInstalled) { 'Uninstall PC Tune-Up' } else { 'Install on this PC' })
$btnInstall.Enabled = $RunningAsExe
Add-SetRow @($btnInstall)
$btnInstall.Add_Click({ if ($IsInstalled) { Uninstall-App } else { Install-App -Launch } })

Add-SetSection 'Files' "Settings, history, the keep list and the change log are kept in $DataDir."
$btnSetKeep = New-Button 'Keep list'; $btnSetLog = New-Button 'Change log'; $btnSetData = New-Button 'Open data folder'; $btnSetReport = New-Button 'Save report'
Add-SetRow @($btnSetKeep, $btnSetLog, $btnSetData, $btnSetReport)
$btnSetKeep.Add_Click({ $btnKeep.PerformClick() })
$btnSetLog.Add_Click({ $btnLog.PerformClick() })
$btnSetData.Add_Click({ Start-Process explorer.exe "`"$DataDir`"" })
$btnSetReport.Add_Click({ Save-Report })

Add-SetSection 'Command line' 'For scripts and IT use (use "start /wait" so the window waits for it):'
$cliHelp = New-Object Windows.Forms.Label
$cliHelp.Font = New-Object Drawing.Font('Consolas', 9.5); $cliHelp.AutoSize = $true; $cliHelp.ForeColor = $Theme.Dim
$cliHelp.Text = "PC-TuneUp.exe /report[:file.html]   check everything and save a report`r`nPC-TuneUp.exe /fix                  run the safe Fix my PC steps without asking`r`nPC-TuneUp.exe /install | /uninstall  install or remove for this user"
$setFlow.Controls.Add($cliHelp)

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
<h2>$(T 'Backup')</h2>$(ConvertTo-HtmlRows @('Check', 'Status', 'Result', 'What to do') $lvBackup.Items @(0, 1, 2, 3))
<h2>$(T 'Scheduled tasks')</h2>$(ConvertTo-HtmlRows @('Task', 'Made by', 'Runs', 'State', 'Advice') $lvTasks.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Security')</h2>$(ConvertTo-HtmlRows @('Check', 'Status', 'Result', 'What to do') $lvSec.Items @(0, 1, 2, 3))
<h2>$(T 'Stability (last 30 days)')</h2>$(ConvertTo-HtmlRows @('Problem', 'What', 'Times', 'Last', 'What to do') $lvStab.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Program updates available')</h2>$(ConvertTo-HtmlRows @('Program', 'Installed', 'Available', 'Note') $lvUpd.Items @(0, 1, 2, 3))
<h2>$(T 'Upgrade options')</h2>$(ConvertTo-HtmlRows @('Part', 'You have now', 'Upgrade option', 'Worth it?', 'What to buy') $lvUpg.Items @(0, 1, 2, 3, 4))
<h2>$(T 'Changes made by PC Tune-Up')</h2>$(ConvertTo-HtmlRows @('When', 'What', 'Item', 'Change', 'Undo') $histRows @(0, 1, 2, 3, 4))
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
    $startup = @($lvStart.Items | Where-Object { $_.Tag.On -and $_.Tag.Advice -eq 'safe to turn off' })
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
    if ((Show-Msg ($plan -join "`n") 'OKCancel' 'Question') -ne 'OK') { return }
    $script:FixPlan = @{ Clean = $clean; Startup = $startup; Svc = $svc }
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
        foreach ($r in $results) { $freed += $r.Freed; Add-History 'Clean' $r.Name ('freed {0} (Fix my PC)' -f (Format-Size $r.Freed)) }
        $junk = @($lvBloat.Items | Where-Object { $_.Tag.Cat -eq 'Junk' }).Count
        $lines = @($(if ($state.Cancel) { 'Stopped early.' } else { 'Done!' }), '',
            " - Freed $(Format-Size $freed) of junk files",
            " - $($script:FixCounts.Startup) app(s) no longer start with Windows")
        if ($IsAdmin) { $lines += " - $($script:FixCounts.Services) background service(s) trimmed" }
        if ($junk) { $lines += " - $junk junk app(s) found - see the Bloatware page if you want them gone" }
        $lines += '', 'Startup changes take effect next time you sign in. Undo anything from the History page.'
        $btnFix.Text = 'Fix my PC'; $btnFix.Enabled = $true
        Update-Health; Start-CleanScan; Update-Startup; Update-Services; Update-History
        Show-Msg ($lines -join "`n") | Out-Null
    }
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
    @{ Title = $null;      Pages = @('Health') }
    @{ Title = 'CLEAN UP'; Pages = @('Clean', 'Startup', 'Bloatware', 'Services', 'Tasks', 'Disk') }
    @{ Title = 'CHECK';    Pages = @('Updates', 'Security', 'Stability', 'Backup', 'Upgrades') }
    @{ Title = 'MORE';     Pages = @('History', 'Settings') }
)
$script:NavButtons = @{}
function Show-Page($Page) {
    foreach ($p in $script:Pages) { $p.Visible = ($p -eq $Page) }
    foreach ($b in $script:NavButtons.Values) {
        $on = $b.Tag -eq $Page
        $b.BackColor = if ($on) { $Theme.AccentSoft } else { $Theme.Side }
        $b.ForeColor = if ($on) { $Theme.AccentText } else { $Theme.Text }
        $b.Font = if ($on) { $FontBold } else { $Font }
    }
    Invoke-PageLoader $Page.Name   # load a page's data the first time it is opened
}
function Set-NavBadge([string]$Name, $Count) {
    $b = $script:NavButtons[$Name]
    if ($b) { $b.Text = if ($Count) { "$Name  ($Count)" } else { $Name } }
}
# Counts next to page names: things waiting for attention.
function Update-NavBadges {
    Set-NavBadge 'Updates' @($lvUpd.Items).Count
    Set-NavBadge 'Security' @($lvSec.Items | Where-Object { $_.Tag.Level -in 'Problem', 'Warning' }).Count
    Set-NavBadge 'Stability' @($lvStab.Items | Where-Object { $_.Tag.Level -eq 'Problem' }).Count
    Set-NavBadge 'Bloatware' @($lvBloat.Items).Count
    Set-NavBadge 'Tasks' $script:TasksActive
    Set-NavBadge 'Backup' $script:BackupProblems
}

$nav = New-Object Windows.Forms.FlowLayoutPanel
$nav.Dock = 'Fill'; $nav.FlowDirection = 'TopDown'; $nav.WrapContents = $false; $nav.AutoScroll = $true
$nav.Padding = New-Object Windows.Forms.Padding(12, 18, 12, 8)
$appName = New-Object Windows.Forms.Label
$appName.Text = 'PC Tune-Up'; $appName.Font = New-Object Drawing.Font('Segoe UI Semibold', 13); $appName.AutoSize = $true
$appName.Margin = New-Object Windows.Forms.Padding(6, 0, 0, 0)
$appVer = New-Object Windows.Forms.Label
$appVer.Text = "Version $AppVersion"; $appVer.ForeColor = $Theme.Dim; $appVer.AutoSize = $true
$appVer.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 8)
$nav.Controls.AddRange(@($appName, $appVer))
foreach ($g in $NavGroups) {
    if ($g.Title) {
        $cap = New-Object Windows.Forms.Label
        $cap.Text = $g.Title; $cap.Font = $FontSmall; $cap.ForeColor = $Theme.Dim; $cap.AutoSize = $true
        $cap.Margin = New-Object Windows.Forms.Padding(10, 14, 0, 4)
        $nav.Controls.Add($cap)
    }
    foreach ($name in $g.Pages) {
        $page = $script:Pages | Where-Object Name -eq $name | Select-Object -First 1
        if (-not $page) { continue }
        $b = New-Object Windows.Forms.Button
        $b.Text = $name; $b.Tag = $page; $b.Width = 178; $b.Height = 34; $b.TextAlign = 'MiddleLeft'
        $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $Theme.Hover
        $b.BackColor = $Theme.Side; $b.Padding = New-Object Windows.Forms.Padding(10, 0, 0, 0); $b.Margin = New-Object Windows.Forms.Padding(0, 1, 0, 1)
        $b.Cursor = [Windows.Forms.Cursors]::Hand
        $b.Add_Click({ Show-Page $this.Tag })
        $script:NavButtons[$name] = $b
        $nav.Controls.Add($b)
    }
}
$sidebar.Controls.Add($nav)
if (-not $IsAdmin) {
    $adm = New-Object Windows.Forms.Panel
    $adm.Dock = 'Bottom'; $adm.Height = 140; $adm.Padding = New-Object Windows.Forms.Padding(16, 10, 14, 16)
    $admT = New-Object Windows.Forms.Label
    $admT.Text = 'Limited mode'; $admT.Font = $FontBold; $admT.Dock = 'Top'; $admT.Height = 22
    $admD = New-Object Windows.Forms.Label
    $admD.Text = 'Some fixes need administrator rights.'; $admD.ForeColor = $Theme.Dim; $admD.Dock = 'Top'; $admD.Height = 58
    $admB = New-Button 'Restart as admin'
    $admB.AutoSize = $false; $admB.Dock = 'Bottom'; $admB.Height = 34
    $admB.Add_Click({
        try {
            if ($RunningAsExe) { Start-Process $SelfExe -Verb RunAs }
            else { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
            $form.Close()
        } catch { }   # user said no to the UAC prompt
    })
    $adm.Controls.Add($admB); $adm.Controls.Add($admD); $adm.Controls.Add($admT)
    $sidebar.Controls.Add($adm)
}
# Each page's main action stands out.
foreach ($b in @($btnClean, $btnStartApply, $btnBloatRemove, $btnSvcApply, $btnDiskScan, $btnUpdRun, $btnSecOpen, $btnUpgCopy, $btnHistUndo, $btnStabFix, $btnTaskOff, $btnBkOpen)) { Set-Primary $b }

# ---------------------------------------------------------------------------
# Activity bar: what is running in the background, its progress, and Cancel
# ---------------------------------------------------------------------------
$activity = New-Object Windows.Forms.Panel
$activity.Dock = 'Bottom'; $activity.Height = 42; $activity.BackColor = $Theme.Soft; $activity.Visible = $false
$activity.Padding = New-Object Windows.Forms.Padding(26, 7, 26, 7)
$actText = New-Object Windows.Forms.Label
$actText.Dock = 'Fill'; $actText.TextAlign = 'MiddleLeft'; $actText.AutoEllipsis = $true
$actBar = New-Object Windows.Forms.ProgressBar
$actBar.Dock = 'Right'; $actBar.Width = 220; $actBar.Style = 'Marquee'; $actBar.MarqueeAnimationSpeed = 30
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
    if ($j.State.Max -gt 0) {
        if ($actBar.Style -ne 'Continuous') { $actBar.Style = 'Continuous' }
        $actBar.Maximum = $j.State.Max; $actBar.Value = [Math]::Min($j.State.Max, [Math]::Max(0, $j.State.Value))
    } elseif ($actBar.Style -ne 'Marquee') { $actBar.Style = 'Marquee' }
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
                         Tasks = { Update-Tasks }; Backup = { Update-Backup } }
$script:Loaded = @{}
function Invoke-PageLoader([string]$Name) {
    if ($script:Loaded[$Name] -or -not $script:PageLoaders.ContainsKey($Name)) { return }
    $script:Loaded[$Name] = $true
    [void]$script:LoadQueue.Remove($Name)
    & $script:PageLoaders[$Name]
}
function Start-Everything {
    Update-Health; Update-Startup; Update-History
    # Slowest first (hardware ~4 s, winget, logs), so the last one doesn't hold everything up; Security/Stability feed Health.
    [void]$script:LoadQueue.AddRange(@('Security', 'Stability', 'Upgrades', 'Updates', 'Backup', 'Services', 'Bloatware', 'Tasks', 'Clean'))
}
Enable-Translation $form
Show-Page $pgHealth

# ---------------------------------------------------------------------------
# Command line: /install, /uninstall, /? and the windowless /report and /fix
# ---------------------------------------------------------------------------
function Write-Cli([string]$Text) { try { [Console]::Out.WriteLine((T $Text)) } catch { } }
if ($Cli.Install) { Install-App; Write-Cli "PC Tune-Up installed in $InstallDir"; return }
if ($Cli.Uninstall) { Uninstall-App; return }
if ($CliMode) {
    if ($RunningAsExe -and [PcTuneUp.Native]::AttachConsole(-1)) {   # print into the console the exe was started from
        $w = New-Object IO.StreamWriter([Console]::OpenStandardOutput()); $w.AutoFlush = $true; [Console]::SetOut($w)
    }
    if ($Cli.Help) {
        Write-Cli "PC Tune-Up $AppVersion`n`n  PC-TuneUp.exe /report[:file.html]   check everything and save a report (default: Documents)`n  PC-TuneUp.exe /fix                  run the safe Fix my PC steps without asking`n  PC-TuneUp.exe /fix /report          both`n  PC-TuneUp.exe /install | /uninstall  install or remove for this user`n`nRun as administrator to include Windows files and services. Use 'start /wait' in a command prompt."
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
$form.Add_Shown({
    Start-Everything
    if ($Settings.CheckUpdates) { Start-UpdateCheck -Silent }
    if ($IsInstalled) { try { Set-ItemProperty -Path $UninstallKey -Name DisplayVersion -Value $AppVersion -ErrorAction Stop } catch { } }   # keep Settings > Apps current after self-updates
    $oldExe = [IO.Path]::ChangeExtension($SelfExe, '.old.exe')
    if ($RunningAsExe -and (Test-Path -LiteralPath $oldExe)) { Start-Bg $OldExeCleanupWork $oldExe { } }
    # First start from a downloaded file: offer to install (once).
    if ($RunningAsExe -and -not $IsInstalled -and -not $Settings.AskedInstall) {
        $Settings.AskedInstall = $true; Save-Settings
        $q = "Install PC Tune-Up on this PC?`n`nIt adds PC Tune-Up to the Start menu and to Settings > Apps (so it can be uninstalled like any app), and it keeps itself up to date. No administrator rights needed.`n`nYou can also do this later in Settings."
        if ((Show-Msg $q 'YesNo' 'Question') -eq 'Yes') { Install-App -Launch }
    }
})
# Grow every control by the screen scaling (fonts already scale on their own; list columns, row heights and grid
# columns were sized with Px). Then cap the window to the screen.
if ($DpiScale -ne 1) { $form.Scale((New-Object Drawing.SizeF($DpiScale, $DpiScale))) }
$work = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = New-Object Drawing.Size([Math]::Min($form.Width, $work.Width - 40), [Math]::Min($form.Height, $work.Height - 40))
$form.MinimumSize = New-Object Drawing.Size((Px 960), (Px 600))
[void]$form.ShowDialog()
$JobTimer.Stop()