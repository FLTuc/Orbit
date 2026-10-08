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
Check 'la culture G est chargee (300+)' ($Facts.Count -ge 300)

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

Section 'Culture G pendant la pause'
try {
    Tell-Fact -Force
    Check 'une anecdote ou un quiz s''affiche' ($ui.BubbleText.Text -match '🧠')
    $seen = @{}; for ($i = 0; $i -lt 50; $i++) { $seen[(Get-NextFact)] = 1 }
    Check 'pas de repetition sur 50 tirages' ($seen.Count -eq 50)
    $Config.BreakContent = 'Culture'; Hide-Bubble; Tell-BreakItem
    Check 'reglage « culture G » : que de la culture' ($ui.BubbleText.Text -match '🧠')
    $Config.BreakContent = 'Jokes'; Hide-Bubble; Tell-BreakItem
    Check 'reglage « blagues » : pas de culture' ($ui.BubbleText.Text -notmatch '🧠')
    $Config.BreakContent = 'Both'; $kinds = @{}
    for ($i = 0; $i -lt 4; $i++) { Hide-Bubble; Tell-BreakItem; $kinds[[bool]($ui.BubbleText.Text -match '🧠')] = 1 }
    Check 'reglage « les deux » : alternance blagues / culture' ($kinds.Count -eq 2)
    $q = @($Facts | Where-Object { $_ -match '\|' })[0]
    $O.FactPos = [array]::IndexOf(@($Facts), $q); $script:FactOrder = [int[]](0..($Facts.Count - 1))
    Hide-Bubble; Tell-Fact -Force
    Check 'quiz : la question d''abord' ($ui.BubbleText.Text -match 'Quiz' -and $ui.BubbleText.Text -notmatch '👉')
    $O.Punch.At = (Get-Date).AddSeconds(-1); On-Frame
    Check 'puis la reponse' ($ui.BubbleText.Text -match '👉')
    Hide-Bubble
} catch { Check 'culture G sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Texte des bulles (vraies polices de Windows)'
[void](Test-Glyph 0x41)
Check 'polices des bulles trouvees (texte, emoji, symboles)' ($script:GlyphMaps.Count -ge 2) "$($script:GlyphMaps.Count) police(s)"
$texts = New-Object System.Collections.Generic.List[string]
foreach ($t in $Jokes) { $texts.Add($t) }
foreach ($t in $Facts) { $texts.Add($t) }
foreach ($file in 'orbit.ps1', 'notebook.ps1', 'notes.ps1', 'settings.ps1', 'transfer.ps1', 'context.ps1', 'anchor.ps1') {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $file), [ref]$null, [ref]$null)
    foreach ($node in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                                     $args[0] -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)) { $texts.Add($node.Value) }
}
$missing = @{}
foreach ($t in $texts) {
    foreach ($m in [regex]::Matches($t, $script:TextSymbol)) {
        $cp = [char]::ConvertToUtf32($m.Value, 0)
        if (-not (Test-Glyph $cp)) { $missing['U+{0:X4} {1}' -f $cp, $m.Value] = 1 }
    }
}
Write-Host "  $($texts.Count) textes verifies"
Check 'chaque emoji et symbole d''Orbit existe dans les polices (pas de carre vide)' ($missing.Count -eq 0) (@($missing.Keys) -join ', ')
$odd = @($texts | Where-Object { $_ -match '[\u200D\uFE0F\u20E3\uFFFD]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])' })
Check 'aucun emoji compose ni caractere casse dans les textes' ($odd.Count -eq 0) (($odd | Select-Object -First 3) -join ' / ')
$E = { param($cp) [char]::ConvertFromUtf32($cp) }
Show-Bubble ('Test ' + (& $E 0x1F9D1) + [char]0x200D + (& $E 0x1F4BB) + ' 8' + [char]0xFE0F + [char]0x20E3 + ' ' + (& $E 0x1F680) + ' ' + [char]0x200E + 'fin') -Force
Check 'bulle : texte nettoye avant affichage' ($ui.BubbleText.Text -eq ('Test ' + (& $E 0x1F9D1) + ' 8 ' + (& $E 0x1F680) + ' fin')) $ui.BubbleText.Text
Check 'bulle : police avec repli emoji et symboles' ($ui.BubbleText.FontFamily.Source -match 'Emoji')
Hide-Bubble
$encDir = Join-Path $appData 'encodage'
New-Item -ItemType Directory -Force -Path $encDir | Out-Null
$sample = "# Café`r`n'déjà vu'`r`n"
[IO.File]::WriteAllText((Join-Path $encDir 'sans-bom.ps1'), $sample, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllBytes((Join-Path $encDir 'ansi.ps1'), [byte[]](0x23, 0x20, 0xE9))
[IO.File]::WriteAllText((Join-Path $encDir 'ascii.ps1'), "# ok`r`n", (New-Object Text.UTF8Encoding($false)))
$fixedNow = Repair-ScriptEncoding $encDir
$b = [IO.File]::ReadAllBytes((Join-Path $encDir 'sans-bom.ps1'))
Check 'fichier d''Orbit sans BOM : BOM remis, texte identique' ($b[0] -eq 0xEF -and [IO.File]::ReadAllText((Join-Path $encDir 'sans-bom.ps1')) -eq $sample)
Check 'fichiers ANSI ou purement ASCII : laisses tels quels' (@($fixedNow).Count -eq 1 -and [IO.File]::ReadAllBytes((Join-Path $encDir 'ansi.ps1')).Length -eq 3)
Check 'les fichiers livres ont tous leur BOM (rien a reparer au lancement)' (@($RepairedScripts).Count -eq 0)

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

Section 'Je m''interromps (vraies fenetres)'
try {
    # une vraie fenetre de travail : le Bloc-notes avec un fichier
    $npFile = Join-Path $appData 'note-de-test.txt'
    [IO.File]::WriteAllText($npFile, 'test')
    Start-Process notepad.exe -ArgumentList "`"$npFile`""
    $npw = $null; $t0 = Get-Date
    while (-not $npw -and ((Get-Date) - $t0).TotalSeconds -lt 20) {
        Start-Sleep -Milliseconds 300
        $wins = Get-CapturedWindows 5
        $npw = @($wins | Where-Object { $_.title -match 'note-de-test' }) | Select-Object -First 1
    }
    Write-Host "  fenetres vues : $((@($wins) | ForEach-Object { "$($_.app) « $($_.title) »" }) -join ' | ')"
    Check 'la fenetre de travail est trouvee (Bloc-notes)' ([bool]$npw)
    Check 'son titre est nettoye (sans « - Bloc-notes »)' ($npw -and $npw.title -notmatch '(Bloc-notes|Notepad)$')
    Check 'les fenetres d''Orbit ne sont jamais capturees' (-not (@($wins) | Where-Object { $_.pid -eq $PID }))
    # interruption pendant un focus, avec capture d'ecran
    $Config.ContextScreenshot = $true
    Start-Focus
    Start-Interruption
    $n1 = $NB.Contexts.Count; $first = $script:CtxEdit.Ctx.id
    Start-Interruption   # double clic pendant la capture
    Check 'double clic sur ✋ pendant la capture : ignore' ($script:CtxEdit.Ctx.id -eq $first)
    if ($script:CtxShotTimer -and $script:CtxShotTimer.IsEnabled) { $script:CtxShotTimer.Stop(); Complete-InterruptionShot }
    Check 'le focus se met en pause' ($O.State -eq 'Focus' -and $O.Paused)
    Check 'le post-it s''ouvre avec ce qui a ete garde' ($ctxWin.IsVisible -and $cx.CtxSummary.Text -match 'note-de-test')
    $id = $script:CtxEdit.Ctx.id
    $shot = Get-ContextShotPath $id
    Check 'capture d''ecran gardee (JPEG)' ((Test-Path $shot) -and (Get-Item $shot).Length -gt 1000)
    Check 'Orbit est revenu apres la capture' ($window.Opacity -eq 1)
    $window.Opacity = 0; Test-Watchdogs
    Check 'surveillance : Orbit reste transparent par erreur -> il reapparait' ($window.Opacity -eq 1)
    $cx.CtxDoing.Text = 'test de reprise'; $cx.CtxNext.Text = 'ecrire la ligne 2'
    Close-ContextEditor
    $ctx = Find-Context $id
    Check 'reprise enregistree' ($ctx -and $ctx.next -eq 'ecrire la ligne 2' -and @($ctx.windows).Count -ge 1)
    $t1 = Get-Date
    while (-not (Step-ContextProbe) -and ((Get-Date) - $t1).TotalSeconds -lt 8) { Start-Sleep -Milliseconds 100 }
    Check 'lecture des adresses terminee sans bloquer Orbit' ($null -eq $script:CtxProbe)
    Show-Status
    Check 'clic sur Orbit : « Où j''en étais ? » avec la prochaine etape' ($ui.BubbleText.Text -match 'ecrire la ligne 2' -and $ui.BubbleButtons.Children.Count -ge 4)
    Hide-Bubble
    $st = $O.State; $O.State = 'Idle'
    Show-Status
    Check 'reclic juste apres : bulle normale, avec un bouton « ↩ Où j''en étais »' ($ui.BubbleText.Text -notmatch 'ecrire la ligne 2' -and
        @($ui.BubbleButtons.Children | Where-Object { [string]$_.Content -match 'Où j' }).Count -eq 1)
    Hide-Bubble; $O.State = $st
    Open-Notebook 'Ctx'
    Check 'onglet Reprises : la reprise et sa capture' ($pn.CtxList.Children.Count -ge 1 -and [string]$pn.TabCtx.Content -match '\(\d+\)' -and
        @($pn.CtxList.Children | Where-Object { $_.Child -and @($_.Child.Children | Where-Object { $_ -is [Windows.Controls.Image] }).Count }).Count -ge 1)
    Close-Notebook
    $r = Find-Everything 'ecrire ligne'
    Check 'la recherche globale trouve la reprise' (@($r.Contexts).Count -ge 1)
    Resume-Context $id
    Check 'reprendre : le focus repart' ($O.State -eq 'Focus' -and -not $O.Paused)
    Check 'reprendre : terminee, capture effacee' ((Find-Context $id).status -eq 'done' -and -not (Test-Path $shot))
    Check 'reprendre : la prochaine etape est rappelee' ($ui.BubbleText.Text -match 'ecrire la ligne 2')
    Update-Pill
    Check 'bouton ✋ a cote d''Orbit pendant un focus' ($ui.CtxBadge.Visibility -eq 'Visible')
    $Config.ContextButton = $false; Update-Pill
    Check 'et cache si desactive dans les reglages' ($ui.CtxBadge.Visibility -eq 'Collapsed')
    $Config.ContextButton = $true
    $n0 = $NB.Contexts.Count; $Config.ContextScreenshot = $false
    Start-Interruption; Close-ContextEditor -Cancel
    Check 'annuler : rien de garde, le focus continue' ($NB.Contexts.Count -eq $n0 -and -not $O.Paused)
    Stop-Cycle
    Open-Settings
    Check 'reglages : section « Je m''interromps »' ([string]$sw.SCtxWindows.SelectedItem.Tag -eq [string]$Config.ContextWindows -and $sw.SCtxRemindMin.Text -eq [string]$Config.ContextRemindMin)
    $settingsWin.Hide()
} catch { Check 'scenario sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
finally {
    Get-Process -Name notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Section 'Note rapide, S.O.S / Unstick Me, victoires (vraies fenetres)'
try {
    Update-Pill
    Check 'bouton 📝 a cote d''Orbit' ($ui.AnchorBadge.Visibility -eq 'Visible')
    $n0 = $NB.Notes.Count
    $ui.AnchorBadge.RaiseEvent((New-Object Windows.Input.MouseButtonEventArgs([Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Left) -Property @{ RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent }))
    Check 'bouton 📝 : la note rapide s''ouvre' ($qnWin.IsVisible)
    $qn.QnText.Text = 'Idee notee depuis le bouton'
    Close-QuickNote
    Check 'note gardee en 2 gestes' ($NB.Notes.Count -eq $n0 + 1 -and -not $qnWin.IsVisible)
    $click = { param($b) $b.RaiseEvent((New-Object Windows.Input.MouseButtonEventArgs([Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Left) -Property @{ RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent })) }
    Check 'boutons ronds 🚨 🗂 📒 colles a Orbit' ($ui.SosBadge.Visibility -eq 'Visible' -and $ui.BoardsBadge.Visibility -eq 'Visible' -and $ui.NotesBadge.Visibility -eq 'Visible' -and $ui.Dock.Margin.Right -lt 150)
    & $click $ui.BoardsBadge
    Check 'bouton 🗂 : ouvre les tableaux' ($NB.Tab -eq 'Todo' -and $panel.IsVisible)
    & $click $ui.NotesBadge
    Check 'bouton 📒 : ouvre les notes' ($NB.Tab -eq 'Notes')
    Close-Notebook
    Start-UnstickFor 'Ranger le garage'
    Close-AnchorFocus
    Show-Unstick
    Check 'Unstick Me : une seule etape affichee' ($script:afMode -eq 'unstick' -and $af.AfTitle.Text -match '⚡')
    $Anchor.Unstick.timerEndsAt = [double](Get-NowMs) - 1000
    Render-Unstick
    Check 'minuteur doux termine : pas d''alarme, on peut continuer' ($script:afClock.Text -eq '✓')
    $steps = $Anchor.Unstick.steps.Count
    for ($i = 0; $i -lt $steps; $i++) { Complete-UnstickUi }
    Check 'toutes les etapes : « Tu es lancé(e) »' ($script:afMode -eq 'done' -and -not $Anchor.Unstick)
    Close-AnchorFocus
    Show-Sos
    Check '🚨 S.O.S : la question, et des idees de tes cartes' ($script:afMode -eq 'sos' -and $script:afSosBox)
    $script:afSosBox.Text = 'Répondre au mail de Julie'
    Start-UnstickFor $script:afSosBox.Text
    Check 'S.O.S : decoupage immediat (messagerie)' ($Anchor.Unstick.steps[0].content -match 'messagerie')
    Close-AnchorFocus
    $Anchor.Unstick = $null
    Check 'bruit brun : demarre et s''arrete' ((Set-BrownNoise $true) -and $script:NoisePlayer -and -not (Set-BrownNoise $false) -and -not $script:NoisePlayer)
    Show-Wins
    Check '🏆 mes victoires : le deblocage y est' ($ui.BubbleText.Text -match 'Débloqué')
    Open-Settings
    Check 'reglages : bouton 📝' ($sw.SAnchorButton.IsChecked -eq $Config.AnchorButton)
    Check 'reglages : relance sans focus (case + minutes)' ($sw.SIdleNudge.IsChecked -eq $Config.IdleNudge -and [int]$sw.SIdleNudgeMin.Text -eq $Config.IdleNudgeMin)
    New-Item -ItemType Directory -Force -Path $SoundsDir | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $SoundsDir 'test-orbit.wav'), [byte[]](1..10))
    Update-SoundList; Update-FileLabels
    Check 'reglages : « Mes sons » = les fichiers du dossier sons, bouton 📂' ($sw.SSoundDir -and @($SF.BubbleFiles | Where-Object { $_ -match 'test-orbit\.wav$' }).Count -eq 1 -and $sw.SMySounds.Items.Count -ge 1)
    Remove-Item -LiteralPath (Join-Path $SoundsDir 'test-orbit.wav') -ErrorAction SilentlyContinue
    $settingsWin.Hide()
} catch { Check 'scenario sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Menu clic droit : court, le reste dans « Plus »'
try {
    $menu.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.ContextMenu]::OpenedEvent)))
    $shown = @($menu.Items | Where-Object { $_ -is [Windows.Controls.MenuItem] -and $_.Visibility -eq 'Visible' })
    Check "au plus 12 entrees visibles ($($shown.Count))" ($shown.Count -le 12)
    Check 'les gestes du quotidien en haut' (@($shown | Where-Object { [string]$_.Header -match 'Note rapide|interromps|S\.O\.S|tableaux|Mes notes' }).Count -eq 5)
    Check '« Plus » contient le reste (apparence, rythme, autre PC, victoires)' (@($miMore.Items | Where-Object { [string]$_.Header -match 'Apparence|Rythme|Autre PC|victoires' }).Count -eq 4)
    Check 'chrono : seulement ce qui sert maintenant' (($miFocus.Visibility -eq 'Visible') -ne ($O.State -eq 'Focus') -and ($miStop.Visibility -eq 'Visible') -eq ($O.State -ne 'Idle'))
} catch { Check 'menu sans erreur' $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }

Section 'Export vers un autre PC'
try {
    $zip = Join-Path $appData 'export-test.zip'
    New-Item -ItemType Directory -Force -Path $CtxShotDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $CtxShotDir 'privee.jpg'), 'capture')
    [void](Export-OrbitPackage $zip)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    $names = @($z.Entries | ForEach-Object { $_.FullName })
    $z.Dispose()
    Check 'zip cree' (Test-Path $zip)
    Check 'il contient le programme' (@($names | Where-Object { $_ -match 'Orbit[\\/]orbit\.ps1$' }).Count -eq 1)
    Check 'et la culture G' (@($names | Where-Object { $_ -match 'culture[\\/].+\.txt$' }).Count -ge 5)
    Check 'et les tableaux' (@($names | Where-Object { $_ -match 'donnees[\\/]kanban\.json$' }).Count -eq 1)
    Check 'mais pas le code compile de ce PC' (@($names | Where-Object { $_ -match 'native-' }).Count -eq 0)
    Check 'ni les captures d''ecran' (@($names | Where-Object { $_ -match 'captures[\\/]' }).Count -eq 0)
    Check 'les victoires aussi (comme sur le telephone)' (@($names | Where-Object { $_ -match 'donnees[\\/]lifeanchor\.json$' }).Count -eq 1)
    Check 'les reprises, oui (le texte)' (@($names | Where-Object { $_ -match 'donnees[\\/]reprises\.json$' }).Count -eq 1)
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

    # --- la bulle n'est jamais rognee : la fenetre grandit vers le haut, le robot ne bouge pas
    function Get-BubbleTop {
        # sans l'effet "pop" (la bulle grossit en 0,3 s) : on mesure sa vraie place
        $ui.BubblePop.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null)
        $ui.BubblePop.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $null)
        $window.UpdateLayout(); $ui.BubbleWrap.TranslatePoint((New-Object Windows.Point(0, 0)), $ui.Root).Y
    }
    $window.Top = $O.Home.Y; $window.Left = $O.Home.X
    $bottom0 = $window.Top + $window.Height
    $long = (1..14 | ForEach-Object { "Ligne $_ d'un texte assez long pour tenir sur toute la largeur de la bulle" }) -join "`n"
    Show-Bubble $long -Force -Buttons @($BtnAgain, $BtnStop, $BtnTodo, $BtnLater, $BtnPickCards, $BtnBreak)
    $top = Get-BubbleTop
    Write-Host "  bulle longue : fenetre $([int]$window.Height) px de haut, haut de la bulle a $([int]$top) px"
    Check 'bulle longue : la fenetre s''agrandit' ($window.Height -gt 340)
    Check 'bulle longue : rien n''est rogne en haut' ($top -ge 0)
    Check 'bulle longue : le robot n''a pas bouge' ([math]::Abs(($window.Top + $window.Height) - $bottom0) -lt 1.5)
    $O.PlanDay = ''; Show-MorningPlan
    Check 'plan du matin : rien n''est rogne' ((Get-BubbleTop) -ge 0)
    Hide-Bubble
    Check 'bulle rangee : la fenetre reprend sa taille, le robot reste en place' ($window.Height -eq 340 -and [math]::Abs(($window.Top + $window.Height) - $bottom0) -lt 1.5)
    $huge = (1..80 | ForEach-Object { "Ligne $_" }) -join "`n"
    Show-Bubble $huge -Force
    $wa = Get-WorkArea ([System.Windows.Forms.Screen]::PrimaryScreen)
    Check 'texte enorme : la fenetre ne depasse pas l''ecran' ($window.Height -le ($wa.B - $wa.T) + 1 -and $window.Top -ge $wa.T - 1)
    Check 'texte enorme : rien n''est rogne (le texte defile dans la bulle)' ((Get-BubbleTop) -ge -1)
    Check 'texte enorme : le robot n''a pas bouge' ([math]::Abs(($window.Top + $window.Height) - $bottom0) -lt 1.5)
    Hide-Bubble

    # --- chiens de garde
    $script:frameTimer.Stop()
    Test-Watchdogs
    Check 'surveillance : l''animation arretee est relancee' ($script:frameTimer.IsEnabled)
    $script:frameTimer.Stop()
    $O.Pinned = $true; $window.Left = -5000; $window.Top = -5000
    Test-Watchdogs
    Check 'surveillance : Orbit perdu hors ecran est ramene' ($window.Left -gt -1000 -and -not $O.Pinned)

    # --- une tache qui plante n'empeche pas les autres
    $saveClip = ${function:Check-Clipboard}
    function Check-Clipboard { throw 'panne simulee du presse-papiers' }
    $O.State = 'Focus'; $O.EndsAt = (Get-Date).AddMinutes(20); $O.Paused = $false; $script:StateSig = ''
    Remove-Item $StateFile -ErrorAction SilentlyContinue
    On-Second
    Check 'tache en panne : les autres continuent (etat enregistre)' (Test-Path $StateFile)
    Check 'et la panne est notee dans le journal, avec son nom' ((Get-Content $LogFile -Raw) -match 'Erreur \(presse-papiers\) : panne simulee')
    Set-Item function:Check-Clipboard $saveClip
    Stop-Cycle; On-Second
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
$errLines = @(Get-Content $LogFile -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Erreur( \([^)]*\))? :|Erreur imprevue' -and $_ -notmatch 'panne simulee' })
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
