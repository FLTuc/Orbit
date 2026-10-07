@echo off
rem Lance Orbit sans installation ni droits administrateur.
rem Astuce : "Orbit.cmd -Demo" pour tester avec un focus de 1 min et une pause de 30 s.
rem
rem Sous Windows 11, la console par defaut est Windows Terminal, qui ignore l'option
rem "fenetre cachee" de PowerShell : une fenetre powershell.exe restait ouverte.
rem conhost.exe --headless (fourni avec Windows) lance PowerShell sans aucune fenetre.
set "ORBIT_HEADLESS=1"
set "ORBIT_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\System32\conhost.exe" (
    start "" "%SystemRoot%\System32\conhost.exe" --headless "%ORBIT_PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0orbit.ps1" %*
) else (
    start "" "%ORBIT_PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0orbit.ps1" %*
)
