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
$loadClock = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $Root 'orbit.ps1')
$ErrorActionPreference = 'Stop'
Write-Host "  (charge en $($loadClock.ElapsedMilliseconds) ms)"
Check 'la fenetre principale est creee' ($window -is [Windows.Window])
Check 'les fonctions natives sont disponibles' $Native
Check 'le code natif est garde en cache' (@(Get-ChildItem (Join-Path $appData 'Orbit') -Filter 'native-*.dll').Count -eq 1)
Check 'le carnet n''est pas construit au demarrage (a la demande)' ($null -eq $panel)
Check 'la fenetre des reglages non plus' ($null -eq $settingsWin)
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

Section 'Fenetres a la demande, recherche, sous-taches'
try {
    Open-Settings
    Check 'reglages construits a la 1re ouverture' ($settingsWin -is [Windows.Window] -and $sw.SMorning)
    $settingsWin.Hide()
    Open-Notebook 'Todo'
    Check 'carnet construit a la 1re ouverture' ($panel -is [Windows.Window] -and $pn.TodoList)
    $b = Get-CurrentBoard
    Add-Todo 'Carte avec sous-taches'
    $t2 = Find-Todo $NB.LastAddedId
    Add-CardCheck $t2.id 'etape 1'; Add-CardCheck $t2.id 'etape 2'
    Start-EditTodo $t2.id
    Check 'editeur avec sous-taches et repetition' ($pn.TodoList.Children.Count -ge 2)
    End-EditTodo
    Render-Todos
    Check 'tableau affiche' ($pn.TodoList.Children.Count -ge 2)
    Select-Tab 'Search'
    $pn.SearchBox.Text = 'etape'
    Render-Search
    Check 'recherche : la carte est trouvee par sa sous-tache' ($pn.SearchList.Children.Count -ge 2)
    Reveal-Card $t2.id
    Check 'ouvrir un resultat : retour au tableau, carte en edition' ($NB.Tab -eq 'Todo' -and $NB.EditId -eq $t2.id)
    End-EditTodo
    Close-Notebook
} catch { Check 'fenetres sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Plan du matin et icone pres de l''horloge'
try {
    $O.State = 'Idle'; $O.PlanDay = ''
    Check 'le plan est du (1re apparition du jour)' ((Get-Date).Hour -lt 5 -or (Test-MorningPlanDue))
    Show-MorningPlan
    Check 'la bulle du plan s''affiche' ($ui.BubbleText.Text -match 'plan|vides')
    Check 'pas deux fois le meme jour' (-not (Test-MorningPlanDue))
    Start-Focus; Update-TrayIcon
    Check 'icone : chrono du focus' ($script:TrayKey -like 'Focus|*')
    Toggle-Pause; Update-TrayIcon
    Check 'icone : chrono en pause' ($script:TrayKey -like 'Paused|*')
    Stop-Cycle; Update-TrayIcon
    Check 'icone : satellite au repos' ($script:TrayKey -eq 'Idle|')
} catch { Check 'plan et icone sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Export vers un autre PC'
try {
    $zip = Join-Path $appData 'export-test.zip'
    [void](Export-OrbitPackage $zip)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    $names = @($z.Entries | ForEach-Object { $_.FullName })
    $z.Dispose()
    Check 'zip cree' (Test-Path $zip)
    Check 'il contient le programme' (@($names | Where-Object { $_ -match 'Orbit[\\/]orbit\.ps1$' }).Count -eq 1)
    Check 'et les tableaux' (@($names | Where-Object { $_ -match 'donnees[\\/]kanban\.json$' }).Count -eq 1)
    Check 'mais pas le code compile de ce PC' (@($names | Where-Object { $_ -match 'native-' }).Count -eq 0)
    Write-Host "  ($([math]::Round((Get-Item $zip).Length / 1KB)) Ko, $($names.Count) fichiers)"
} catch { Check 'export sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

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

$NB.Quitting = $true; if ($panel) { $panel.Close() }
Finish
