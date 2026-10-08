# Endurance en conditions reelles : Orbit est lance pour de vrai (sa vraie boucle, ses vrais
# minuteurs) en mode demo (focus 1 min, pause 30 s) et en « pilote automatique » : il enchaine
# seul focus, pauses, balades, petites phrases, notes, tableaux... pendant plusieurs minutes.
# On mesure toutes les 15 s sa memoire et ses ressources Windows, et on lit son journal.
param([int]$Minutes = 5)
. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -Namespace OrbitSoak -Name Gui -MemberDefinition '[DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr h, uint flags);'
$appData = Join-Path ([IO.Path]::GetTempPath()) 'orbit-soak'
if (Test-Path $appData) { Remove-Item -Recurse -Force $appData }
New-Item -ItemType Directory -Path $appData | Out-Null
$env:APPDATA = $appData
$env:ORBIT_AUTOPILOT = '1'
$env:ORBIT_HEADLESS = '1'
Remove-Item Env:ORBIT_SELFTEST, Env:WT_SESSION -ErrorAction SilentlyContinue
$log = Join-Path $appData 'Orbit\orbit.log'

Section "Orbit tourne seul pendant $Minutes minutes (mode demo + pilote automatique)"
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$proc = Start-Process -FilePath $ps -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $Root 'orbit.ps1')`"", '-Demo')
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 60 -and -not ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'Orbit demarre'))) { Start-Sleep -Milliseconds 500 }
Check 'Orbit a demarre' ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'Orbit demarre'))

$samples = @()
$end = (Get-Date).AddMinutes($Minutes)
$alive = $true
while ((Get-Date) -lt $end) {
    Start-Sleep -Seconds 15
    if ($proc.HasExited) { $alive = $false; break }
    $proc.Refresh()
    $samples += [pscustomobject]@{
        T = [int]((Get-Date) - $t0).TotalSeconds
        Mem = [math]::Round($proc.PrivateMemorySize64 / 1MB)
        Handles = $proc.HandleCount
        Gdi = [OrbitSoak.Gui]::GetGuiResources($proc.Handle, 0)
        User = [OrbitSoak.Gui]::GetGuiResources($proc.Handle, 1)
    }
}
$samples | Format-Table -AutoSize | Out-String | Write-Host
Check "Orbit tourne sans interruption pendant $Minutes minutes" $alive
$stats = try { ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $appData 'Orbit\stats.json'))) } catch { $null }
$focus = if ($stats) { [int]$stats.focus } else { 0 }
Write-Host "  sessions de focus terminees : $focus"
if ($focus -lt 2 -and (Test-Path $log)) { Get-Content $log -Tail 15 | ForEach-Object { Write-Host "  | $_" } }
Check 'il a enchaine plusieurs cycles focus / pause tout seul' ($focus -ge 2)
if ($samples.Count -ge 4) {
    $third = [math]::Max(1, [math]::Floor($samples.Count / 3))
    $early = $samples | Select-Object -First $third
    $late = $samples | Select-Object -Last $third
    $grow = { param($prop) ($late | Measure-Object $prop -Maximum).Maximum - ($early | Measure-Object $prop -Maximum).Maximum }
    $dh = & $grow 'Handles'; $dg = & $grow 'Gdi'; $du = & $grow 'User'; $dm = & $grow 'Mem'
    Write-Host "  evolution entre le debut et la fin : poignees $dh, GDI $dg, USER $du, memoire $dm Mo"
    Check 'pas de fuite de poignees Windows' ($dh -lt 150) "$dh"
    Check 'pas de fuite d''objets graphiques (GDI)' ($dg -lt 25) "$dg"
    Check 'pas de fuite de fenetres (USER)' ($du -lt 25) "$du"
    Check 'memoire stable' ($dm -lt 100) "$dm Mo"
}
$content = if (Test-Path $log) { Get-Content $log } else { @() }
$errs = @($content | Where-Object { $_ -match 'Erreur( \([^)]*\))? :|Erreur imprevue|Arret inattendu' })
foreach ($l in ($errs | Select-Object -First 10)) { Write-Host "  $l" -ForegroundColor Yellow }
Check 'aucune erreur dans le journal' ($errs.Count -eq 0) "$($errs.Count) erreur(s)"
Check 'le pilote automatique a bien tourne' (@($content | Where-Object { $_ -match 'Autopilote' }).Count -ge 2)
Check 'des interruptions « Je m''interromps » ont ete enregistrees et reprises' (@($content | Where-Object { $_ -match 'Autopilote : .*reprises [1-9]' }).Count -ge 1)

if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
Remove-Item Env:ORBIT_AUTOPILOT, Env:ORBIT_HEADLESS -ErrorAction SilentlyContinue
Finish
