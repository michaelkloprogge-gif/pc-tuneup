# Changelog

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
