# PC Tune-Up

**Check, clean and speed up any Windows 10/11 PC - whatever the brand - with one click, and undo anything.**

![Clean page](docs/screenshots/clean.png)

PC Tune-Up is a small, free app for the jobs that make a PC feel new again: clearing junk, stopping
apps that start with Windows, removing pre-installed bloatware, keeping programs up to date, and
spotting what is really wrong (a crashing add-on, a worn battery, a full drive). It explains every
suggestion in plain language, shows you the list before it changes anything, and keeps a history
you can undo.

## What it does

| Page | |
|---|---|
| **Health** | CPU, memory, disk, drive health, battery wear, Windows Update status, power mode, internet speed - and **Fix my PC**, which runs all the safe fixes at once |
| **Clean** | temp files, crash dumps, browser caches (Chrome, Edge, Brave, Firefox), Windows Update leftovers, old drivers, Windows.old |
| **Startup** | stop apps from launching with Windows |
| **Bloatware** | find and remove pre-installed junk, trial antivirus and PC-maker extras (Dell, HP, Lenovo, ASUS, Acer, MSI...) |
| **Services** | trim background services from PC makers, updaters and telemetry, with one-click restore |
| **Disk** | see which folders fill the drive |
| **Updates** | update outdated programs through winget; safe updates are pre-selected |
| **Security** | is Windows still supported, can it run Windows 11, are antivirus, firewall, encryption, Secure Boot and TPM on |
| **Stability** | crashes, freezes, blue screens and errors from the last 30 days, grouped by what really caused them, with the fix |
| **Upgrades** | which memory, drive and battery upgrades fit, the exact specification to buy, and whether it is worth it |
| **History** | every change, with Undo |

Security software, VPNs, drivers and databases are never touched, and you can add your own programs
to a keep list. English and Dutch, light and dark theme.

| | |
|---|---|
| ![Security page in dark theme](docs/screenshots/security-dark.png) | ![Upgrades page](docs/screenshots/upgrades.png) |

## Download

Get **PC-TuneUp.exe** from the [latest release](../../releases/latest) and run it. It offers to
install itself for you (Start menu, Settings > Apps; no administrator rights needed) and keeps
itself up to date. Without installing, the exe runs as-is from anywhere.

Windows SmartScreen may warn the first time because the exe is not code-signed yet: click
**More info > Run anyway**.

Some fixes (Windows' own files, services, restore points) need administrator rights: use
**Restart as admin** in the app.

## Command line

```
PC-TuneUp.exe /report[:file.html]    check everything and save a report (default: Documents)
PC-TuneUp.exe /fix                   run the safe "Fix my PC" steps without asking
PC-TuneUp.exe /install | /uninstall  install or remove for the current user
```

Use `start /wait PC-TuneUp.exe /report` in a command prompt so it waits for the result.

## Privacy

Everything runs on your PC. PC Tune-Up only goes online to check for its own updates (GitHub), for
the speed test (Cloudflare) and through winget's program list. Nothing about your PC is sent
anywhere. Settings, the change history and the keep list are stored in `%LOCALAPPDATA%\PCTuneUp`.

## How it is built

The app is one PowerShell script (`pc-tuneup.ps1`, Windows Forms) embedded in a tiny C# host, compiled
with the .NET Framework compiler that ships with Windows - nothing to install to build it.

```powershell
.\build-exe.ps1                       # -> dist\PC-TuneUp.exe
.\tests\Test-Upgrades.ps1 -Check      # upgrade advice on made-up PCs
.\tests\Test-Translation.ps1          # Dutch translation
.\tests\Run-Headless.ps1              # run every check on this PC without showing the window
.\tests\Screenshots.ps1 -Out shots    # a PNG of every page
.\publish-release.ps1                 # after bumping $AppVersion and adding a CHANGELOG entry
```

GitHub Actions builds, tests and publishes every release ([workflow](.github/workflows/release.yml)).
See the [changelog](CHANGELOG.md) for what is new. MIT licensed.
