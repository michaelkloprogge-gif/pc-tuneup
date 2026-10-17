# PC Tune-Up

A small Windows app that speeds up and cleans any Windows 10/11 PC, whatever the brand.

- **Fix my PC** – one click for all the safe fixes, with a preview first
- **Health** – CPU, memory, disk, drive health, battery wear, Windows Update status, power mode, internet speed
- **Clean** – temp files, crash dumps, browser caches, Windows Update leftovers, old drivers, Windows.old
- **Startup** – stop apps launching with Windows
- **Bloatware** – find and remove pre-installed junk, trial antivirus and OEM extras
- **Services** – trim background services from PC makers, updaters and telemetry
- **Disk** – see which folders fill the drive
- **History** – every change, with Undo

Security software, VPNs, drivers and databases are never touched, and you can add your own
programs to a keep list.

## Download

Get `PC-TuneUp.exe` from the [latest release](../../releases/latest) and run it. It is a single
file with nothing to install, and it updates itself when a new release is published.

Windows SmartScreen may warn the first time because the exe is not code-signed: click
**More info → Run anyway**.

## Build

```powershell
.\build-exe.ps1                              # -> dist\PC-TuneUp.exe
.\publish-release.ps1 -Notes "What changed"  # after bumping $AppVersion in pc-tuneup.ps1
```

The exe is a tiny C# host (compiled with the .NET Framework compiler built into Windows) that runs
the embedded `pc-tuneup.ps1`.
