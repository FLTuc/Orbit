# Lancement reel d'Orbit (comme un double-clic) : il doit tourner SANS fenetre de console.
# Sous Windows 11, Windows Terminal ignore « -WindowStyle Hidden » : Orbit passe par
# conhost.exe --headless. On verifie qui a lance le processus d'Orbit.
. (Join-Path $PSScriptRoot 'common.ps1')
$appData = Join-Path ([IO.Path]::GetTempPath()) 'orbit-launch'
if (Test-Path $appData) { Remove-Item -Recurse -Force $appData }
New-Item -ItemType Directory -Path $appData | Out-Null
$env:APPDATA = $appData
Remove-Item Env:ORBIT_SELFTEST, Env:ORBIT_HEADLESS, Env:WT_SESSION -ErrorAction SilentlyContinue
$log = Join-Path $appData 'Orbit\orbit.log'

function Get-OrbitProcs { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'orbit\.ps1' }) }
function Stop-Orbits { foreach ($p in Get-OrbitProcs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep -Seconds 2 }
function Wait-Until([scriptblock]$cond, [int]$seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500 }
    return [bool](& $cond)
}
function Get-Parent($p) { Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" }

Section 'Double-clic sur Orbit.cmd'
Stop-Orbits
Start-Process -FilePath (Join-Path $Root 'Orbit.cmd') -WorkingDirectory $Root -WindowStyle Hidden
Check 'Orbit tourne' (Wait-Until { @(Get-OrbitProcs).Count -ge 1 } 30)
$p = @(Get-OrbitProcs)[0]
if ($p) {
    $parent = Get-Parent $p
    Write-Host "  lance par : $($parent.Name) $($parent.CommandLine)"
    Check 'lance par conhost --headless : aucune fenetre de console' ($parent.Name -eq 'conhost.exe' -and $parent.CommandLine -match '--headless')
}
Check 'Orbit a bien demarre (journal)' (Wait-Until { (Test-Path $log) -and ((Get-Content $log -Raw) -match 'Orbit demarre') } 60)
Check 'une seule copie d''Orbit' (@(Get-OrbitProcs).Count -eq 1)
Stop-Orbits

Section 'Lance dans Windows Terminal (simule) : il se relance sans fenetre'
$env:WT_SESSION = 'test-terminal'
Remove-Item $log -ErrorAction SilentlyContinue
$first = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -PassThru -WindowStyle Hidden `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$(Join-Path $Root 'orbit.ps1')`"")
Check 'la copie lancee dans le terminal se ferme aussitot (et ferme son onglet)' ($first.WaitForExit(30000))
$others = @(Get-OrbitProcs | Where-Object { $_.ProcessId -ne $first.Id })
Check 'une copie sans fenetre a pris le relais' (Wait-Until { @(Get-OrbitProcs | Where-Object { $_.ProcessId -ne $first.Id }).Count -ge 1 } 20)
$p = @(Get-OrbitProcs | Where-Object { $_.ProcessId -ne $first.Id })[0]
if ($p) {
    $parent = Get-Parent $p
    Check 'via conhost --headless' ($parent.Name -eq 'conhost.exe' -and $parent.CommandLine -match '--headless')
}
Check 'et elle demarre normalement (pas de boucle de relance)' (Wait-Until { (Test-Path $log) -and ((Get-Content $log -Raw) -match 'Orbit demarre') } 60)
Start-Sleep -Seconds 3
Check 'toujours une seule copie' (@(Get-OrbitProcs).Count -eq 1)
Stop-Orbits
Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue
Finish
