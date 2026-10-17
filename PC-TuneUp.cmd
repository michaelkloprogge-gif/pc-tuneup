@echo off
rem Double-click to open PC Tune-Up (no console window).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0pc-tuneup.ps1"
