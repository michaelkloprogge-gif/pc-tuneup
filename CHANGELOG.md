# Changelog

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
