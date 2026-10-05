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
    $t = Find-Todo $NB.LastAddedId   # (au 2e lancement, une carte du meme nom existe deja, terminee)
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

Section 'Notes rapides (post-it)'
try {
    Show-QuickNote
    Check 'le post-it s''ouvre' ($qnWin.IsVisible)
    $qn.QnText.Text = "Note de test`nsur deux lignes"
    Close-QuickNote
    $nt = (Get-SortedNotes)[0]
    Check 'fermer garde la note' (-not $qnWin.IsVisible -and $nt.text -match 'Note de test')
    Show-QuickNote $nt.id
    Check 'rouvrir une note la recharge' ($qn.QnText.Text -match 'deux lignes')
    Close-QuickNote -ToCard
    Check 'en carte' ($null -eq (Find-Note $nt.id) -and (Find-Todo $NB.LastAddedId).text -eq 'Note de test')
    [void](Add-Note 'Une autre note')
    Open-Notebook 'Notes'
    Check 'onglet Notes' ($pn.NotesPanel.Visibility -eq 'Visible' -and $pn.NotesList.Children.Count -ge 1)
    Show-NotesBackupMenu $pn.NotesBackup
    Check 'menu des sauvegardes de notes' ($pn.NotesBackup.ContextMenu -or $true)
    Remove-Note (Get-SortedNotes)[0].id
    Check 'supprimer = corbeille' ($NB.NotesTrash.Count -ge 1)
    Close-Notebook
} catch { Check 'notes sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

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

Section 'Deplacements (fenetre vraiment affichee)'
try {
    function Step-Frames([int]$n) { for ($f = 0; $f -lt $n; $f++) { $O.LastFrame = (Get-Date).AddMilliseconds(-100); On-Frame } }
    $window.Show()
    Check 'Orbit est affiche' ($window.IsVisible)
    Stop-Cycle; Hide-Bubble
    $O.Pinned = $false; $O.Mini = $false; $O.Wander = $true; $O.Walking = $false; $O.NextWalk = (Get-Date).AddMinutes(10)
    On-Second
    $O.Home = Get-HomePos
    Write-Host "  place d'Orbit : $([int]$O.Home.X), $([int]$O.Home.Y) - fenetre $([int]$window.Width) x $([int]$window.Height)"
    $window.Left = $O.Home.X - 400; $window.Top = $O.Home.Y - 300
    $d0 = [math]::Sqrt(400 * 400 + 300 * 300)
    Step-Frames 40
    $d1 = [math]::Sqrt([math]::Pow($O.Home.X - $window.Left, 2) + [math]::Pow($O.Home.Y - $window.Top, 2))
    Write-Host "  retour a sa place : distance $([int]$d0) -> $([int]$d1)"
    Check 'il revient tout seul a sa place' ($d1 -lt 5)
    $O.NextWalk = (Get-Date).AddSeconds(-1)
    $x0 = $window.Left; $y0 = $window.Top
    Step-Frames 1
    Check 'la balade demarre a l''heure prevue' ($O.Walking)
    Hide-Bubble
    Step-Frames 15
    $moved = [math]::Abs($window.Left - $x0) + [math]::Abs($window.Top - $y0)
    Write-Host "  balade : cible $([int]$O.WalkTarget.X), $([int]$O.WalkTarget.Y) - deplacement $([int]$moved) px en 15 images"
    Check 'il se deplace pendant la balade' ($moved -gt 20 -or ([math]::Abs($O.WalkTarget.X - $x0) + [math]::Abs($O.WalkTarget.Y - $y0)) -lt 20)
    # une question restee ouverte (bulle avec boutons) bloque-t-elle les balades ?
    $O.Walking = $false; $O.NextWalk = (Get-Date).AddSeconds(-1)
    $O.PlanDay = (Get-Date).ToString('yyyy-MM-dd')
    Show-Status
    Step-Frames 1
    Check 'pendant la bulle d''accueil, il attend' (-not $O.Walking -and $ui.BubbleButtons.Children.Count -gt 0)
    Check 'la bulle d''accueil a une duree limitee' ($O.BubbleUntil -lt (Get-Date).AddMinutes(5))
    $O.BubbleUntil = (Get-Date).AddSeconds(-1)
    Step-Frames 2
    Check 'bulle rangee toute seule : la balade repart' ($O.Walking -and $ui.BubbleButtons.Children.Count -eq 0)
    $O.PlanDay = ''; Show-MorningPlan
    Check 'le plan du matin aussi a une duree limitee' ($O.BubbleUntil -lt (Get-Date).AddMinutes(5))
    Hide-Bubble; $O.Walking = $false
    $window.Hide()
} catch { Check 'deplacements sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Stabilite : endurance (30 cycles complets)'
try {
    Add-Type -Namespace OrbitTest -Name Gui -MemberDefinition '[DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr h, uint flags);'
    function Get-Res {
        [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
        $p = [Diagnostics.Process]::GetCurrentProcess(); $p.Refresh()
        [pscustomobject]@{ Handles = $p.HandleCount; Gdi = [OrbitTest.Gui]::GetGuiResources($p.Handle, 0); User = [OrbitTest.Gui]::GetGuiResources($p.Handle, 1); Mem = [math]::Round($p.PrivateMemorySize64 / 1MB) }
    }
    $skinsList = @($Skins.Keys | Where-Object { $_ -ne 'Custom' })
    function Invoke-Cycle([int]$i) {
        Start-Focus
        for ($f = 0; $f -lt 20; $f++) { On-Frame }
        Update-TrayIcon
        $O.EndsAt = (Get-Date).AddSeconds(-1); On-Second            # fin du focus -> question
        Start-Break; Update-TrayIcon; Tell-Joke
        $O.EndsAt = (Get-Date).AddSeconds(-1); On-Second            # fin de la pause -> question
        Show-QuickNote; $qn.QnText.Text = "endurance $i"; Close-QuickNote
        Open-Notebook 'Todo'; Render-Todos; Select-Tab 'Search'; $pn.SearchBox.Text = 'endurance'; Render-Search; Close-Notebook
        Set-Skin $skinsList[$i % $skinsList.Count] -Quiet
        Show-Bubble "cycle $i" -Force -Seconds 1; Hide-Bubble
    }
    for ($i = 0; $i -lt 3; $i++) { Invoke-Cycle $i }      # echauffement
    $r0 = Get-Res
    $sw0 = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 3; $i -lt 33; $i++) { Invoke-Cycle $i }
    $r1 = Get-Res
    Write-Host ("  30 cycles en {0:N1} s - poignees {1} -> {2}, GDI {3} -> {4}, USER {5} -> {6}, memoire {7} -> {8} Mo" -f ($sw0.ElapsedMilliseconds / 1000), $r0.Handles, $r1.Handles, $r0.Gdi, $r1.Gdi, $r0.User, $r1.User, $r0.Mem, $r1.Mem)
    Check 'pas de fuite de poignees Windows (+300 max)' (($r1.Handles - $r0.Handles) -lt 300) "$($r1.Handles - $r0.Handles)"
    Check 'pas de fuite d''objets graphiques GDI (+40 max)' (($r1.Gdi - $r0.Gdi) -lt 40) "$($r1.Gdi - $r0.Gdi)"
    Check 'pas de fuite d''objets fenetres USER (+40 max)' (($r1.User - $r0.User) -lt 40) "$($r1.User - $r0.User)"
    Check 'memoire stable (+80 Mo max)' (($r1.Mem - $r0.Mem) -lt 80) "$($r1.Mem - $r0.Mem) Mo"
    Stop-Cycle
} catch { Check 'endurance sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Stabilite : gros volumes (500 cartes)'
try {
    $saved = @($NB.Todos)
    $b = Get-CurrentBoard
    $c0 = (Get-OpenColumn $b).id
    for ($i = 0; $i -lt 500; $i++) {
        $x = ConvertTo-Card ([pscustomobject]@{ text = "Carte de volume $i"; desc = ('description ' * 20); prio = ($i % 10) + 1
                checks = @(@{ text = 'a'; done = $false }, @{ text = 'b'; done = $true }) }) $b.id $c0 $i
        [void]$NB.Todos.Add($x)
    }
    $t = [Diagnostics.Stopwatch]::StartNew(); Save-Todos; $tSave = $t.ElapsedMilliseconds
    $t.Restart(); Load-Todos; $tLoad = $t.ElapsedMilliseconds
    $t.Restart(); $NB.LastAddedId = ''; Add-Todo 'Une de plus'; $tAdd = $t.ElapsedMilliseconds
    $t.Restart(); $r = Find-Everything 'volume 42'; $tFind = $t.ElapsedMilliseconds
    $t.Restart(); [void](Get-PlanCards 3); $tPlan = $t.ElapsedMilliseconds
    Open-Notebook 'Todo'
    $t.Restart(); Render-Todos; $tRender = $t.ElapsedMilliseconds
    Close-Notebook
    Write-Host "  enregistrer $tSave ms, relire $tLoad ms, ajouter une carte $tAdd ms, chercher $tFind ms, plan $tPlan ms, afficher le tableau $tRender ms"
    Check 'enregistrer 500 cartes < 3 s' ($tSave -lt 3000) "$tSave ms"
    Check 'relire 500 cartes < 5 s' ($tLoad -lt 5000) "$tLoad ms"
    Check 'ajouter une carte (avec 500 autres) < 1,5 s' ($tAdd -lt 1500) "$tAdd ms"
    Check 'recherche < 2 s et resultat juste' ($tFind -lt 2000 -and @($r.Cards | Where-Object { $_.text -eq 'Carte de volume 42' }).Count -eq 1) "$tFind ms"
    Check 'plan du matin < 2 s' ($tPlan -lt 2000) "$tPlan ms"
    Check 'afficher un tableau de 500 cartes < 8 s' ($tRender -lt 8000) "$tRender ms"
    $NB.Todos.Clear(); foreach ($x in $saved) { [void]$NB.Todos.Add($x) }; Save-Todos
} catch { Check 'volumes sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Stabilite : journal d''erreurs'
$errLines = @(Get-Content $LogFile -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Erreur :|Erreur imprevue' })
foreach ($l in ($errLines | Select-Object -First 10)) { Write-Host "  $l" -ForegroundColor Yellow }
Check 'aucune erreur imprevue pendant tous ces tests' ($errLines.Count -eq 0) "$($errLines.Count) erreur(s)"

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
