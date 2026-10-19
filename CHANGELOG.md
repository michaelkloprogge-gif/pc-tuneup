# Changelog

## 1.20.0

- **Reminders** for things that matter more the longer they wait: Windows waiting days for a restart to finish updates, no restart for a week or more, Windows not updating itself for 45 days, the last clean-up a month ago with junk piling up again, and program updates left waiting for two weeks.
- They show up in **Start here** and in the simple view with a one-click action (Restart, Clean, Update, Open Windows Update - each asks first) and a **Later** button that hides the reminder for a few days.
- The weekly automatic maintenance sends a notification when a reminder first appears.
## 1.19.0

- The **Browsers** page now also checks Windows itself, for every browser at once:
  - **Hosts file:** lines that send well-known websites (Google, Microsoft, banks, PayPal...) to another server, lines that block security and update sites (a malware trick), and a hosts file that was moved. Ad and tracking blockers and names in your own network are recognised as normal.
  - **Proxy:** a proxy server or proxy script that all your browsing goes through - normal at work, often adware on a home PC.
  - **Fake root certificates** known from adware (Superfish, eDellRoot, PrivDog and others) that let it read secure websites.
- **Remove checked** (was "Remove checked policies") also removes checked hosts file lines (as administrator) and switches off checked proxy settings (no administrator needed). Everything can be undone from History.
## 1.18.0

- New page **Power** (under Check): the power mode, power plan, when the screen turns off and the PC goes to sleep, what closing the lid does, the highest processor speed allowed, USB power saving, hibernate and Fast startup - each for plugged in and on battery, with what to do. The aim: quick when plugged in, lasting on battery. Recommended fixes are pre-checked, and every change can be undone from History. The power mode for the power source the PC is on now can be changed without administrator rights.
- The sidebar fits 25 pages: the "Restart as admin" box is smaller, and History and Settings no longer get cut off in Dutch, German and French (a slightly smaller font, or just the Settings icon when even that is too wide).
- Button texts in other languages are no longer cut off with "..." when they are long.
- Website: the new pages and the before-and-after overview, with new screenshots in all four languages.
## 1.17.0

- New page **Right now** (under Health): what is slowing the PC down at this moment. Three meters (processor, memory, disk), one plain sentence about the biggest cause ("Memory is nearly full - Chrome uses the most"), and the programs using the most, each with what to do about it. It refreshes every few seconds while the page is open (Pause stops it), and **End task** closes the selected program after asking - Windows itself and background services are never ended. The Health page's memory link and "Start here" now lead there when memory is nearly full.
- **Fix my PC** now ends with a before-and-after overview: junk removed, free space, apps that start with Windows, the PC Tune-Up score and the things worth a look - before, after and the change. The Health page remembers the last fix, and (as administrator) compares the start-up time after the next restart with the one before.

## 1.16.3

- **Turn off checked** (Tasks and Privacy) and **Apply checked fixes** (Gaming) now ask first and list what they will change, like the other pages do. Everything stays undoable from the History page.

## 1.16.2

- Fixed: some buttons did nothing when clicked - **Keep list** and **Change log** in Settings, **Change log** on the History page, and **Fix this** for program updates in the simple view. They handed the click on to a button on another (hidden) page, which Windows ignores.
- **Open setting** (Security, Backup) and **Search selected online** (Stability, Drivers) now say "Select a row in the list first" instead of silently doing nothing when no row is selected.
- New test: every button in the app is clicked on every release (in a sandbox where nothing on the PC can change), and the build fails if one does nothing.

## 1.16.1

- Fixed: in a maximized window the simple view was squeezed into a narrow strip in the middle. It now uses the width of the window (up to a comfortable reading width).
- In a normal-sized window the simple view is more compact (a lower status card, tiles with the icon beside the text), so more of the list fits.
- French: the advanced view is called "Affichage avancé", to match "Affichage simple".

## 1.16.0

- **A fresh look for the simple view**: a status ring with an icon (it turns while the PC is being checked), three tiles with an icon each, and rounded cards for every item with an icon that shows what it is about. The list of things that could be better now shows straight away, and it no longer flickers while checks finish.
- **Advanced view button**: the simple view has a clear "Advanced view" button at the top right. In the advanced view, the house icon next to the name goes back to the simple view. (Settings calls the two views "Simple view" and "Advanced view".)
- A slim scroll bar in the app's colours in the simple view, also in dark mode. Buttons are as wide as their text, so longer translations are no longer cut off.

## 1.15.1

- Dark mode: the empty end of every list header (above the scroll bar) is dark now too, instead of a light grey strip.

## 1.15.0

- **A cleaner, more modern look**: an icon for every page in the sidebar and a blue bar next to the open page (like Windows 11 Settings); rounded, softer buttons; a slim progress bar in the app's colours; a light highlight under the mouse in every list, with a little more room per row.
- **Status as a coloured dot**: lists show "● OK", "● Warning" or "● Problem" in the status column, so the rest of the row stays easy to read.
- **Health page**: the readings get more room, so lines like the PC name and the free disk space no longer wrap; the memory list (which didn't fit) is behind "Show the programs using the most memory".
- The sidebar's "Limited mode" note is one short line, and History and Settings fit side by side in every language.

## 1.14.2

- Fixed: in 1.14.0 the left edge of every page was hidden under the sidebar (the page title, the first buttons and the start of each line). The page test now checks that pages always start next to the sidebar.

## 1.14.0

- **Simple view** - for people who don't want 23 pages: one calm screen with a big status in plain words (green: "Your PC is in good shape", orange: "5 things could be better", red: "Something needs attention") and three big buttons: **Make my PC faster**, **Check for problems** (each finding in one everyday sentence, with "Fix this" only for safe changes that can be undone) and **Get help**. New users start in simple view; "Show all tools" (or Settings > View) switches to the full app.
- **Plain words**: hover over a row to see what technical terms mean in one everyday sentence ("Service: a program that runs in the background without a window"). Fix my PC and the clean-up confirmations say plainly what is NOT touched: your documents, photos and programs.
- **Send a report to someone who helps you** (Get help, or Settings > Help and feedback): saves a report in Documents and starts an email - with the report attached when classic Outlook is installed, otherwise with the file ready to drag in - or copies a short summary to paste into WhatsApp or a text message.
- All of it in English, Nederlands, Deutsch and Français.
## 1.13.0

- **Deutsch and Français**: the whole app is now also available in German and French (Settings > Language, or automatic from the Windows language), with the menu names German and French Windows really use.
- **Report a problem** and **Suggest an idea** (Settings > Help and feedback): opens a GitHub issue with the app version, Windows version and recent errors already filled in - your name, folders and PC name are blanked out, and you see everything before you send it. When something goes wrong inside the app, it offers to report it.
- **Move to another PC** (Settings): export your settings, keep list, privacy choices and the scheduled tasks, startup apps and services you switched off to one file, and import it on another PC - only what exists there is changed, with undo.
- **First-run tour**: three short screens the first time PC Tune-Up starts (Settings > Show the tour again).
- **Keyboard**: Ctrl+1 to Ctrl+9 open the first nine pages, Ctrl+PageDown / Ctrl+PageUp the next or previous page, and Tab moves through each page from top to bottom; the sidebar shows which page has keyboard focus, and lists have names for screen readers.
- **Website in Dutch**: https://michaelkloprogge-gif.github.io/pc-tuneup/nl/
- Every release is now also tested in German and French.
## 1.12.0

- **Search** (Ctrl+F): a search box at the top of the sidebar finds pages, settings and rows on every page as you type - "battery", "Chrome", "hibernation", "Steam" - and Enter or a double-click takes you straight to the row. F5 reloads the page you are on.
- New **Gaming** page: start a game and click Check again - it shows which graphics card the game really uses (with a one-click fix when a laptop runs it on the slower built-in graphics), other programs taking processor or graphics time, power mode and memory, and the Windows settings that cost frames: Game Mode, background recording, optimizations for windowed games and hardware-accelerated GPU scheduling. Recommended fixes are pre-checked and can be undone from History.
- New **website**: https://michaelkloprogge-gif.github.io/pc-tuneup/ - what the app does, screenshots, and a download button.
- The version number moved from the sidebar to the window title and Settings, to make room for the search box.
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
