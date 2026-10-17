# Changelog

## 1.11.0

- **Notifications only when something is new**: the automatic maintenance run remembers what it found last time and only shows a notification for new things - a new crash, a new browser extension, a device problem, a security problem, or a crash that happens a lot more often - for example "New since last time: New browser extension: ... (Chrome)". Choose in Settings: when something is new (default), after every run, or never.
- **Error log**: when something goes wrong inside PC Tune-Up itself, it is written to `errors.log` (Settings > Files > Error log), and "Save report" includes the last 14 days - handy to send along with a question. The exe also records errors that would otherwise vanish silently.
- Fixed with the help of the new log: the browser home-page check never ran, and one kind of scheduled task made the Tasks page skip its "Runs" text.
- Every release is now tested on a clean Windows machine: GitHub Actions opens every page in English and Dutch and fails on errors, pages that never finish loading, long freezes and missing report sections (`tests\Test-Pages.ps1`).
## 1.10.0

- **Start here** on the Health page: the three most useful next steps from all pages (for example "Clean up 1.6 GB of junk files", "Free up to 4 GB with space savers", "17 program updates available"), most urgent first, each with a button that opens the right page.
- **Start-up time** on the Startup page: a graph of how long Windows took to start, from its own log (shown to administrators), the split between Windows itself and start-up apps, the 30-day average, and which apps, drivers or services slowed it down. Also explains Fast startup.
- New **Space savers** page: the hibernation file (shrink on laptops, switch off on desktops), Windows' reserved storage (about 7 GB), compressing Windows' own files, freeing OneDrive copies kept on the PC, and turning on Storage Sense - each with what you give up, and all except the OneDrive one can be undone from History. The paging file and extra Windows languages are explained.
- Smoother loading: when several checks finish at once, the window updates them one after another instead of freezing.
## 1.9.2

- Programs page: games and other programs started through a launcher (Steam, Wargaming, Epic...) no longer look unused - a recent change in the program's own files now counts as use too. The label now says "no sign of use" instead of "not opened", because some programs (such as 7-Zip from the right-click menu) are used without being opened.

## 1.9.1

- Ready for **winget** (`winget install MichaelKloprogge.PCTuneUp`): an app installed with winget doesn't offer to install itself again, and its updates go through `winget upgrade` so winget stays in charge. Automatic maintenance works from the winget location too.

## 1.9.0

- New **Battery** page (laptops): how much charge the battery still holds, a graph of its wear since it was new, wear over the last year, time on a full charge, and where your PC maker hides the "stop charging at 80%" setting (Dell, Lenovo, HP, ASUS, Acer, MSI, Samsung, Surface, Razer, Framework). Links to battery use per app, the full battery report and a replacement search.
- New **Browsers** page: extensions in Chrome, Edge, Brave, Vivaldi and Firefox with what they can do (read every website, change the search engine, proxy, ...) and whether they came from a store; the search engine, home page and start-up pages; and settings forced through browser "policies" on a home PC - a classic adware trick - which can be removed (with undo). Opens each browser's extensions or reset page.
- New **Programs** page: every installed program with its size, install date and when you last opened it (from Windows' own record), sorted by size or last use; uninstall several in one go, and leftover folders go to the Recycle Bin.
- New **Network** page: Wi-Fi signal and band (tips when a 5 GHz-capable card sits on 2.4 GHz), delays and lost packets to the router and the internet, DNS speed compared with Cloudflare and Google, Wi-Fi drops in the last 30 days and network-card errors; Flush DNS cache and Reset network.
- New **Right-click** page: entries other programs add to Explorer's right-click menu, with leftovers of removed programs pre-checked; hide or show them again (with undo, no administrator needed).
- **Disk** page: find large files (100 MB+) and duplicate files (compared by content) and move them to the Recycle Bin; one copy of each duplicate is always kept, and cloud-only OneDrive files are never opened.
- **Health over time**: a score out of 100 saved every day (also by automatic maintenance), shown in a graph next to Windows' own stability rating.
- History and Settings stay at the bottom of the sidebar, so every page fits.
- How the exe could be code-signed: see `docs/SIGNING.md`.
## 1.8.0

- **Automatic maintenance** (Settings): every week or every 4 weeks, PC Tune-Up cleans junk files and checks the PC by itself - only when the PC is idle, and catching up if it was off - then shows a notification ("Cleaned 1.2 GB. 2 things worth a look"); click it to open the app. It never changes startup apps, services or programs by itself. Uses a normal scheduled task for your account (no administrator needed); uninstalling removes it. Also available as `PC-TuneUp.exe /auto`.
- New **Privacy** page: switch off Windows' ads, tips and tracking - advertising ID, tailored experiences, tips pop-ups, suggestions in Settings and Start, "finish setting up" screens, apps installed without asking, lock-screen promos, search highlights, web results in Start search, feedback requests, typing personalisation; as administrator also optional diagnostic data, activity history and Recall. Recommended ones are pre-checked; every change can be undone from History or with *Turn back on*.
- New **Drivers** page: devices Windows reports a problem with (error codes explained, with what to do - e.g. a USB device that keeps failing), and the drivers that matter most (graphics, network, audio, Bluetooth, storage, BIOS) with their age. *Get driver updates* opens the PC maker's driver page for this exact model. Health mentions devices with problems.
- Stability's driver fix now opens the Drivers page.
- More compact sidebar, so all pages fit without scrolling.
## 1.7.0

- **One-click fixes on the Stability page**: select a problem and click *Fix selected problem* - turn off NVIDIA nView (or uninstall it), repair the Visual C++ runtimes, reset Windows Update, repair Windows system files (sfc + DISM), check the drive, schedule a memory test, or jump to driver and Store updates. Everything asks first and is recorded in History; turning off nView can be undone.
- Stability recognises when nView is already switched off and no longer counts its old crashes as a problem.
- New **Backup** page: checks whether Desktop, Documents and Pictures are backed up to OneDrive, Dropbox or iCloud, whether OneDrive is running, File History, backup programs and restore points (with a *Create restore point now* button). Health warns when nothing backs up your files.
- New **Tasks** page: scheduled tasks from other companies - updaters, telemetry and promo helpers (Adobe, Google, Zoom, Edge, Dell, HP, Lenovo, Windows tips...). Known junk is pre-checked; switching a task off can be undone from History, and the keep list is respected.
- Windows Update error codes are shown in the usual form (0x800F0820 instead of 0xFFFFFFFF800F0820).
## 1.6.1

- **Faster and smoother**: the window no longer freezes while checks finish (longest freeze down from about 4 seconds to under 0.3 s). Health readings are gathered in the background and the page only redraws what changed.
- All checks are ready about 40% sooner (four run at the same time, slowest first).
- Starts a little quicker: the PC name comes from the registry, and the exe no longer compiles helper code at every start.
- New `tests\Profile.ps1` shows where the time goes.

## 1.6.0

- **Installer**: install for the current user (no administrator needed) with a Start-menu entry, a desktop shortcut and an entry in Settings > Apps to uninstall it. The first start from a downloaded file offers to install.
- **Progress and Cancel**: an activity bar shows what is running, how far it is, and lets you stop long jobs (cleaning, uninstalling, updating programs, measuring folders, checking for updates).
- **Faster start**: the window opens straight away; each page's checks run in the background, or immediately when you open that page.
- **Restore point first**: when running as administrator, Fix my PC, uninstalling and service changes create a Windows restore point first (can be switched off in Settings).
- **Sharp on scaled screens** (125%, 150%...) instead of blurry, and a **dark theme** that follows Windows.
- **Nederlands**: the whole app is available in Dutch (Settings > Language), including dates and numbers.
- **Settings page**: language, theme, updates, safety, installation, files, command line and About.
- **Command line**: `PC-TuneUp.exe /report[:file]`, `/fix`, `/install`, `/uninstall`, `/?`.
- Releases are now built and tested by GitHub Actions.

## 1.5.0

- Tidier interface: sidebar navigation grouped into Clean up and Check with counts, page titles, one highlighted main button per page, Health readings in a neat grid, lists that fit the window.

## 1.4.0

- New **Updates** page (outdated programs via winget, safe ones pre-selected), **Security** page (Windows support status, Windows 11 readiness, antivirus, firewall, encryption, Secure Boot, TPM and more) and **Stability** page (crashes, freezes, blue screens and errors from the last 30 days, grouped by cause).

## 1.3.0

- The Upgrades page works on any PC: desktops and custom builds, soldered memory, older PCs, ECC workstations and virtual machines; Wi-Fi advice; support pages for 15 PC makers.

## 1.2.0

- New **Upgrades** page: which memory, drive and battery upgrades fit, the exact specification to buy, and whether it is worth it.

## 1.1.2

- After updating, the old copy of the app is cleaned up automatically.

## 1.1.1

- Release script fix.

## 1.1.0

- First release: Fix my PC, health check, cleaning (including browser caches and Windows leftovers), startup apps, bloatware, services, disk usage, history with undo, saveable report and self-update.
