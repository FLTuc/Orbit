@echo off
rem Lance Orbit sans installation ni droits administrateur.
rem Astuce : "Orbit.cmd -Demo" pour tester avec un focus de 1 min et une pause de 30 s.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0orbit.ps1" %*
