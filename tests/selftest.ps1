# Chargement complet d'Orbit sous Windows (fenetres, dessins, code natif),
# sans lancer la boucle : orbit.ps1 s'arrete juste avant grace a ORBIT_SELFTEST.
param([switch]$Fresh)
. (Join-Path $PSScriptRoot 'common.ps1')
$appData = Join-Path ([IO.Path]::GetTempPath()) 'orbit-selftest'
if ($Fresh -and (Test-Path $appData)) { Remove-Item -Recurse -Force $appData }
New-Item -ItemType Directory -Force -Path $appData | Out-Null
$env:APPDATA = $appData
$env:ORBIT_SELFTEST = '1'

Section 'Chargement'
$sw = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $Root 'orbit.ps1')
$ErrorActionPreference = 'Stop'
Write-Host "  (charge en $($sw.ElapsedMilliseconds) ms)"
Check 'la fenetre principale est creee' ($window -is [Windows.Window])
Check 'les fonctions natives sont disponibles' $Native
Check 'le code natif est garde en cache' (@(Get-ChildItem (Join-Path $appData 'Orbit') -Filter 'native-*.dll').Count -eq 1)
Check 'le carnet (tableaux) est cree' ($panel -is [Windows.Window])
Check 'les blagues sont chargees (1000+)' ($Jokes.Count -ge 1000)

Section 'Dessins (construits a la demande)'
foreach ($k in @($Skins.Keys | Where-Object { $_ -ne 'Custom' })) {
    try {
        Set-Skin $k -Quiet
        Set-Mood 'Focus'; Update-Pill; Update-Bits 1.5; On-Frame
        $clock = $ui[$Skins[$k].Clock]
        Check "$k : construit, chrono affiche" ($LoadedSkins.Count -eq 1 -and $clock -and $clock.Text)
        $missing = @(@($Skins[$k].Root) + @($Skins[$k].Eyes | ForEach-Object { $_[0] }) + @($Skins[$k].Fill) + @($Skins[$k].Stroke) +
                     @($Skins[$k].Beacons) + @($Skins[$k].Glows) | Where-Object { $_ -and -not $ui[$_] })
        Check "$k : tous ses elements sont trouves" ($missing.Count -eq 0) ($missing -join ',')
    } catch { Check "$k : sans erreur" $false $_.Exception.Message }
}
$img = Join-Path $appData 'test.png'
$bmp = New-Object System.Drawing.Bitmap 40, 40
$bmp.SetPixel(5, 5, [System.Drawing.Color]::Red); $bmp.Save($img, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$Config.CustomImage = $img
try { Set-Skin 'Custom' -Quiet; Check 'image personnalisee affichee' ($O.Skin -eq 'Custom' -and $ui.CustomImg.Source) } catch { Check 'image personnalisee' $false $_.Exception.Message }
Set-Skin 'Satellite' -Quiet
Check 'changer de dessin libere les autres' ($LoadedSkins.Count -eq 1 -and -not $ui.CustomImg)

Section 'Sons'
foreach ($st in 0, 1, 2, 3, 4, 10) {
    $wav = [OrbitNative]::Synth($st, 1, 0.5, $false)
    Check "son style $st genere" ($wav.Length -gt 1000)
}

Section 'Tableaux et focus avec la vraie interface'
try {
    Add-Todo 'Carte de test !2'
    $t = $NB.Todos | Where-Object { $_.text -eq 'Carte de test' } | Select-Object -First 1
    Set-CardFocus $t.id $true
    $b = Get-CurrentBoard
    $col = New-KanbanColumn $b (Get-Column $b $t.col)
    Check 'une colonne Kanban se construit' ($col -is [Windows.Controls.Border])
    Start-EditTodo $t.id; $col = New-KanbanColumn $b (Get-Column $b $t.col); End-EditTodo -NoRender
    Check 'l''editeur de carte se construit' ($col -is [Windows.Controls.Border])
    Start-Focus
    Check 'focus lance avec la carte liee' ($O.State -eq 'Focus' -and $ui.BubbleText.Text -match 'Carte de test')
    $O.EndsAt = (Get-Date).AddSeconds(-1); On-Second
    Check 'fin du focus : question de pause' ($O.State -eq 'AwaitBreak' -and $t.pomos -eq 1)
    On-Second
    Check 'etat enregistre pour une reprise' (Test-Path $StateFile)
    Complete-FocusTask
    Check 'C''est fait : carte terminee' ($t.done)
    Start-Break; Check 'pause lancee' ($O.State -eq 'Break')
    Stop-Cycle; On-Second; Check 'arret : plus d''etat a reprendre' (-not (Test-Path $StateFile))
} catch { Check 'scenario sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Copier-coller et fichiers'
Add-Clip 'text' 'bonjour selftest' @()
Check 'enregistrement du presse-papiers differe' ($NB.ClipPending)
Flush-Notebook
Check 'ecrit a la fermeture' ((Get-Content (Get-ClipFile) -Raw) -match 'bonjour selftest')
Save-Settings; Save-Stats
Check 'reglages et stats ecrits' ((Test-Path $SettingsFile) -and (Test-Path $StatsFile))
Write-Log ('x' * 2000)
1..600 | ForEach-Object { Write-Log ('ligne de remplissage ' + ('y' * 2000)) }
Check 'journal limite a ~1 Mo' ((Get-Item $LogFile).Length -lt 1.1MB -and (Test-Path (Join-Path $DataDir 'orbit.old.log')))

Section 'Memoire'
$O.TrimCount = 0; Trim-Memory
Check 'menage memoire effectue' ($O.TrimCount -eq 1)
$line = Get-Content $LogFile | Where-Object { $_ -match 'Memoire' } | Select-Object -Last 1
Write-Host "  $line"

$panel.Close(); $NB.Quitting = $true
Finish
