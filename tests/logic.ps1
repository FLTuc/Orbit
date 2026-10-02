# Logique sans interface : tableaux Kanban, lien cartes <-> focus, sauvegardes,
# ecritures sures, reprise du cycle apres un plantage.
. (Join-Path $PSScriptRoot 'common.ps1')
$T = New-TempDir
$DataDir = $T

# --- fonctions reelles d'Orbit + doublures pour l'interface ---
foreach ($def in Get-ScriptFunctions (Join-Path $Root 'notebook.ps1')) { . ([scriptblock]::Create($def)) }
$want = 'Write-FileSafe', 'Short-Text', 'Format-Min', 'Start-Focus', 'Ask-Break', 'Complete-FocusTask', 'Complete-FocusMessage',
        'Ask-Focus', 'Get-AwaitBreakButtons', 'Save-State', 'Restore-State', 'Get-StateMood'
foreach ($def in Get-ScriptFunctions (Join-Path $Root 'orbit.ps1') $want) { . ([scriptblock]::Create($def)) }
foreach ($a in Get-ScriptAssignments (Join-Path $Root 'orbit.ps1') '^\$Btn(TaskDone|CardsDone|Break|Stop|Again|PickCards)\s') { . ([scriptblock]::Create($a)) }
$script:Logs = @(); function Write-Log($m) { $script:Logs += $m }
function Pick($l) { $l[0] }
$script:Bubble = $null
function Show-Bubble { param($Text, $Buttons, [switch]$Force, $Seconds, [switch]$Thought) $script:Bubble = @{ Text = $Text; Buttons = @($Buttons | ForEach-Object { $_.Label }) } }
function Render-Todos {}; function Fit-Notebook {}; function Confirm-Action { $true }; function Set-Mood {}; function Update-Pill {}
$Lines = @{ FocusStart = @('Focus {0} !'); FocusEnd = @('Fini ({0}).'); BreakEnd = @('Pause finie, focus {0} ?') }
$Config = @{ FocusMinutes = 50; MotivationEveryMin = 9; ReminderEveryMin = 4 }
$O = @{ State = 'Idle'; TaskReminders = $true; SessionMin = 50; Paused = $false; Remaining = [timespan]::Zero; EndsAt = [datetime]::MinValue }
$DefaultPrio = 5
$TodoFile = "$T/todo.json"; $KanbanFile = "$T/kanban.json"; $TodoMd = "$T/todo.md"; $TodoArchive = "$T/todo-archive.md"
$BackupDir = "$T/sauvegardes"; $BackupKeep = 7; $UndoKeep = 5; $StateFile = "$T/etat.json"
$NB = @{ Todos = New-Object System.Collections.ArrayList; Boards = New-Object System.Collections.ArrayList; BoardId = ''; EditId = ''
         BackupDay = ''; LoadNotice = ''; FocusCards = New-Object System.Collections.ArrayList; LastAddedId = ''; MdPending = $false }
function Card([string]$text) { $NB.Todos | Where-Object { $_.text -eq $text } | Select-Object -First 1 }
function ColNames { $b = Get-CurrentBoard; ($b.columns | ForEach-Object { "$($_.name):" + ((Get-ColumnCards $_.id | ForEach-Object { $_.text }) -join ',') }) -join ' | ' }

Section 'Ecriture sure'
Write-FileSafe "$T/x.json" '{"a":1}'; Write-FileSafe "$T/x.json" '{"a":2}'
Check 'le fichier contient la derniere version' ((Get-Content "$T/x.json" -Raw) -match '"a":2')
Check 'aucun fichier temporaire ne traine' (-not (Test-Path "$T/x.json.tmp"))

Section 'Reprise de l''ancienne to-do'
[IO.File]::WriteAllText($TodoFile, '[{"text":"Rapport client","prio":3,"done":false},{"text":"Appeler Paul","prio":5,"done":true}]')
Load-Todos
$b = Get-CurrentBoard
Check 'un tableau « Mon tableau » est cree' ($b.name -eq 'Mon tableau')
Check 'la tache ouverte est dans la 1re colonne' ((Card 'Rapport client').col -eq $b.columns[0].id)
Check 'la tache finie est dans Termine' ((Card 'Appeler Paul').done)
Check 'chaque carte a un identifiant' (-not ($NB.Todos | Where-Object { -not $_.id }))
Check 'l''ancien fichier est renomme' (Test-Path "$T/todo-ancienne-version.json")

Section 'Cartes et colonnes'
$todo = $b.columns[0]; $doing = $b.columns[1]; $done = $b.columns[2]
Add-Todo 'Mails !3'; Add-Todo 'Budget' 5 $doing.id; Add-Todo 'Slides @14h' 2 $doing.id
Check 'raccourci !3 = priorite 3' ((Card 'Mails').prio -eq 3)
Check 'raccourci @14h = rappel' ([bool](Card 'Slides').remindAt)
Move-Card (Card 'Slides').id $doing.id 0
Check 'reordonner dans une colonne' ((Get-ColumnCards $doing.id)[0].text -eq 'Slides')
Move-Card (Card 'Mails').id $done.id
Check 'deplacer dans Termine = carte finie' ((Card 'Mails').done)
Set-TodoDone (Card 'Appeler Paul').id $false
Check 'rouvrir une carte finie' (-not (Card 'Appeler Paul').done)
$b2 = New-BoardObject 'Perso'; [void]$NB.Boards.Add($b2)
Move-Card (Card 'Budget').id (Get-OpenColumn $b2).id
Check 'envoyer une carte vers un autre tableau' ((Card 'Budget').board -eq $b2.id)
Remove-BoardColumn $doing.id
Check 'supprimer une colonne garde ses cartes' ((Card 'Slides') -and (Card 'Slides').col -ne $doing.id)
Clear-DoneTodos
Check 'archiver les cartes finies' (-not (Card 'Mails') -and ((Get-Content $TodoArchive -Raw) -match 'Mails'))
$n = $NB.Todos.Count; Load-Todos
Check 'relecture du disque identique' ($NB.Todos.Count -eq $n -and $NB.Boards.Count -eq 2)
Check 'todo.md est ecrit' ((Get-Content $TodoMd -Raw) -match 'Rapport client')

Section 'Lien cartes <-> focus'
$NB.BoardId = $NB.Boards[0].id
Add-Todo 'Rapport final !1'
$O.State = 'Focus'; Start-Focus
Check 'sans carte liee, la plus prioritaire est prise' ((Get-FocusCards -Open)[0].text -eq 'Rapport final')
Check 'la bulle annonce l''objectif' ($script:Bubble.Text -match 'Rapport final')
$O.State = 'AwaitBreak'; [void](Add-FocusToCards 50); Ask-Break
Check 'fin du focus : une tomate et 50 min' ((Card 'Rapport final').pomos -eq 1 -and (Card 'Rapport final').focusMin -eq 50)
Check 'une carte : bouton C''est fait' ($script:Bubble.Buttons -contains "✅ C'est fait !")
Set-CardFocus (Card 'Slides').id $true
$O.State = 'Focus'; Start-Focus
Check 'deux cartes au programme' ($script:Bubble.Text -match 'Rapport final' -and $script:Bubble.Text -match 'Slides')
$O.State = 'AwaitBreak'; [void](Add-FocusToCards 50); Ask-Break
Check 'plusieurs cartes : bouton Cocher les cartes finies' ($script:Bubble.Buttons -contains '✅ Cocher les cartes finies')
Check 'la 1re carte a 2 focus, la 2e 1' ((Card 'Rapport final').pomos -eq 2 -and (Card 'Slides').pomos -eq 1)
function Show-CardPicker { param($a, $b, $c, $d, $e, [switch]$AllowNew) return , @((Card 'Rapport final').id) }
Choose-DoneFocusCards
Check 'carte cochee = terminee et deliee' ((Card 'Rapport final').done -and -not (Test-CardInFocus (Card 'Rapport final').id))
Check 'l''autre reste liee au focus suivant' (Test-CardInFocus (Card 'Slides').id)
function Show-CardPicker { param($a, $b, $c, $d, $e, [switch]$AllowNew) Add-Todo 'Nouvelle'; return , @((Card 'Slides').id, $NB.LastAddedId) }
$O.State = 'AwaitFocus'; Choose-FocusCards
Check 'choisir des cartes + en creer une' (@(Get-FocusCards).Count -eq 2 -and (Test-CardInFocus (Card 'Nouvelle').id))
Load-Todos
Check 'les liens survivent a la relecture' (@(Get-FocusCards).Count -eq 2)

Section 'Une seule carte (piege de PowerShell 5.1 : une liste d''un element perd son .Count)'
$solo = New-BoardObject 'Solo'; [void]$NB.Boards.Add($solo); $NB.BoardId = $solo.id
$saved = @($NB.Todos); $NB.Todos.Clear()
Add-Todo 'Unique'
Check 'la carte suivante est trouvee' ((Get-NextTodo).text -eq 'Unique')
Add-Todo 'Deuxieme'
Check 'ordre de la 2e carte = 1' ((Card 'Deuxieme').order -eq 1)
Move-Card (Card 'Unique').id (Get-DoneColumn $solo).id
Clear-DoneTodos
Check 'archiver une seule carte finie' (-not (Card 'Unique'))
$NB.FocusCards.Clear(); Set-CardFocus (Card 'Deuxieme').id $true
Check 'compte des cartes liees = 1' ($script:Bubble.Text -match '\(1 carte')
$O.State = 'AwaitBreak'; Ask-Break
Check 'une carte liee : bouton C''est fait' ($script:Bubble.Buttons -contains "✅ C'est fait !")
$NB.Todos.Clear(); foreach ($x in $saved) { [void]$NB.Todos.Add($x) }; $NB.FocusCards.Clear(); $NB.BoardId = $NB.Boards[0].id
Save-Todos

Section 'Sauvegardes quotidiennes'
$NB.BackupDay = ''; Save-Todos
$today = Join-Path $BackupDir "kanban-$((Get-Date).ToString('yyyy-MM-dd')).json"
Check 'une sauvegarde du jour existe' (Test-Path $today)
1..9 | ForEach-Object {
    $f = Join-Path $BackupDir "kanban-$((Get-Date).AddDays(-$_).ToString('yyyy-MM-dd')).json"
    Copy-Item $KanbanFile $f; (Get-Item $f).LastWriteTime = (Get-Date).AddDays(-$_)
}
$NB.BackupDay = ''; Save-Todos
Check '7 jours gardes au maximum' (@(Get-ChildItem $BackupDir -Filter 'kanban-*.json').Count -eq 7)
$before = $NB.Todos.Count
Add-Todo 'Carte du jour'
$old = Get-ChildItem $BackupDir -Filter 'kanban-*.json' | Sort-Object Name | Select-Object -First 1
Restore-Kanban $old.FullName
Check 'restaurer une sauvegarde' (-not (Card 'Carte du jour'))
$undo = Get-BackupFiles | Where-Object { $_.Name -like 'avant-restauration-*' } | Select-Object -First 1
Restore-Kanban $undo.FullName
Check 'annuler la restauration' ([bool](Card 'Carte du jour'))
[IO.File]::WriteAllText($KanbanFile, '{"boards":[{"id": ...')
Load-Todos
Check 'fichier abime : repris depuis une sauvegarde' ($NB.Boards.Count -ge 1 -and $NB.Todos.Count -gt 0 -and $NB.LoadNotice)
Check 'fichier abime : mis de cote' (@(Get-ChildItem $T -Filter 'kanban-illisible-*').Count -eq 1)

Section 'Reprise du cycle apres un plantage'
$Restarted = $false
$O.State = 'Focus'; $O.Paused = $false; $O.EndsAt = (Get-Date).AddMinutes(12); $O.SessionMin = 50
Save-State
$O.State = 'Idle'; $O.EndsAt = [datetime]::MinValue
$note = Restore-State
Check 'le focus en cours est repris' ($O.State -eq 'Focus' -and [math]::Abs(($O.EndsAt - (Get-Date).AddMinutes(12)).TotalSeconds) -lt 5)
Check 'Orbit annonce la reprise' ($note -match '12 min')
$O.State = 'Break'; $O.Paused = $true; $O.Remaining = [timespan]::FromMinutes(3); Save-State
$O.State = 'Idle'; [void](Restore-State)
Check 'une pause en pause est reprise' ($O.State -eq 'Break' -and $O.Paused -and [math]::Round($O.Remaining.TotalMinutes) -eq 3)
$O.State = 'Idle'; Save-State
Check 'etat Idle : rien a reprendre' (-not (Test-Path $StateFile))
[IO.File]::WriteAllText($StateFile, (ConvertTo-Json @{ state = 'Focus'; paused = $false; endsAt = (Get-Date).AddMinutes(5).ToString('o'); remainingSec = 0; sessionMin = 50; savedAt = (Get-Date).AddHours(-6).ToString('o') }))
$O.State = 'Idle'; [void](Restore-State)
Check 'etat trop ancien (6 h) : ignore' ($O.State -eq 'Idle')

Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
Finish
