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
function Show-Bubble { param($Text, $Buttons, [switch]$Force, $Seconds, [switch]$Thought) $script:Bubble = @{ Text = $Text; Buttons = @($Buttons | ForEach-Object { $_.Label }); Actions = @($Buttons | ForEach-Object { $_.Action }) } }
function Render-Todos {}; function Fit-Notebook {}; function Confirm-Action { $true }; function Set-Mood {}; function Update-Pill {}
$Lines = @{ FocusStart = @('Focus {0} !'); FocusEnd = @('Fini ({0}).'); BreakEnd = @('Pause finie, focus {0} ?') }
$Config = @{ FocusMinutes = 50; MotivationEveryMin = 9; ReminderEveryMin = 4 }
$O = @{ State = 'Idle'; TaskReminders = $true; SessionMin = 50; Paused = $false; Remaining = [timespan]::Zero; EndsAt = [datetime]::MinValue }
$DefaultPrio = 5
$TodoFile = "$T/todo.json"; $KanbanFile = "$T/kanban.json"; $TodoMd = "$T/todo.md"; $TodoArchive = "$T/todo-archive.md"
$BackupDir = "$T/sauvegardes"; $BackupKeep = 7; $UndoKeep = 5; $StateFile = "$T/etat.json"
$NB = @{ Todos = New-Object System.Collections.ArrayList; Boards = New-Object System.Collections.ArrayList; BoardId = ''; EditId = ''
         BackupDay = ''; LoadNotice = ''; FocusCards = New-Object System.Collections.ArrayList; LastAddedId = ''; MdPending = $false
         Upcoming = New-Object System.Collections.ArrayList; Templates = New-Object System.Collections.ArrayList }
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

Section 'Sous-taches'
$NB.BoardId = $NB.Boards[0].id
Add-Todo 'Preparer la reunion'
$c = Card 'Preparer la reunion'
Add-CardCheck $c.id 'Ordre du jour'; Add-CardCheck $c.id 'Salle'; Add-CardCheck $c.id '  '
Check 'deux sous-taches ajoutees (le vide est ignore)' ($c.checks.Count -eq 2)
Set-CardCheck $c.id 0 $true
Check 'cocher une sous-tache' ($c.checks[0].done -and -not $c.checks[1].done)
Set-CardCheck $c.id 1 $true
Check 'tout coche : Orbit propose de la terminer' ($script:Bubble.Text -match 'sous-tâches' -and $script:Bubble.Buttons -contains '✅ Oui, terminée')
Remove-CardCheck $c.id 1
Load-Todos; $c = Card 'Preparer la reunion'
Check 'sous-taches relues du disque' ($c.checks.Count -eq 1 -and $c.checks[0].text -eq 'Ordre du jour' -and $c.checks[0].done)

Section 'Cartes recurrentes'
$fri = [datetime]'2026-10-02'   # un vendredi
$d = Get-NextOccurrence 'workdays' $fri.AddDays(-400)
Check 'jour ouvre : jamais un samedi ni un dimanche, et apres aujourd''hui' ($d -gt (Get-Date).Date -and $d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday')
$w = Get-NextOccurrence 'weekly' ((Get-Date).Date.AddDays(-3))
Check 'chaque semaine : meme jour, la semaine suivante' ($w -eq (Get-Date).Date.AddDays(4))
$m = Get-NextOccurrence 'monthly' ((Get-Date).Date.AddDays(-1))
Check 'chaque mois : un mois apres l''echeance' ($m -eq (Get-Date).Date.AddDays(-1).AddMonths(1))
Check 'ne se repete pas : rien' ($null -eq (Get-NextOccurrence '' (Get-Date)))
Add-Todo 'Rapport hebdo'
$r = Card 'Rapport hebdo'
$r.due = (Get-Date).ToString('yyyy-MM-dd'); Set-CardRepeat $r.id 'weekly'
Add-CardCheck $r.id 'Chiffres'; Set-CardCheck $r.id 0 $true
Set-TodoDone $r.id $true
$up = @($NB.Upcoming | Where-Object { $_.text -eq 'Rapport hebdo' })
Check 'terminee : la prochaine est mise de cote' ($up.Count -eq 1 -and $up[0].showAt -eq (Get-Date).Date.AddDays(7).ToString('yyyy-MM-dd'))
Check 'la prochaine a son echeance decalee et ses sous-taches decochees' ($up[0].due -eq $up[0].showAt -and -not $up[0].checks[0].done)
Check 'la bulle annonce le retour' ($script:Bubble.Text -match 'reviendra')
Set-TodoDone $r.id $false; Set-TodoDone $r.id $true
Check 'rouverte puis refinie : pas de doublon' (@($NB.Upcoming | Where-Object { $_.text -eq 'Rapport hebdo' }).Count -eq 1)
Load-Todos
Check 'les cartes a venir sont relues du disque' (@($NB.Upcoming).Count -eq 1)
$NB.Upcoming[0].showAt = (Get-Date).ToString('yyyy-MM-dd')
$back = @(Release-Upcoming)
$again = @($NB.Todos | Where-Object { $_.text -eq 'Rapport hebdo' -and -not $_.done })
Check 'le jour venu, elle revient dans la 1re colonne' ($back.Count -eq 1 -and $again.Count -eq 1 -and $again[0].col -eq (Get-OpenColumn (Get-Board $again[0].board)).id)
Check 'et elle se repete toujours' ($again[0].repeat -eq 'weekly' -and @($NB.Upcoming).Count -eq 0)

Section 'Modeles de cartes'
function Show-Prompt { param($a, $b, $c) 'Nouveau client' }
$src = Card 'Preparer la reunion'
$src.desc = 'Appeler, devis, contrat'
Save-CardAsTemplate $src.id
Check 'modele enregistre' ($NB.Templates.Count -eq 1 -and $NB.Templates[0].name -eq 'Nouveau client' -and -not $NB.Templates[0].checks[0].done)
$col = (Get-OpenColumn (Get-CurrentBoard)).id
New-CardFromTemplate $NB.Templates[0].id $col
$n = Find-Todo $NB.LastAddedId
Check 'nouvelle carte depuis le modele (texte, description, sous-taches)' ($n.text -eq 'Preparer la reunion' -and $n.desc -match 'devis' -and $n.checks.Count -eq 1 -and $n.col -eq $col)
Load-Todos
Check 'modeles relus du disque' ($NB.Templates.Count -eq 1)
Remove-Template $NB.Templates[0].id
Check 'supprimer un modele' ($NB.Templates.Count -eq 0)

Section 'Plan du matin'
$saved = @($NB.Todos); $NB.Todos.Clear(); $NB.FocusCards.Clear()
$pb = $NB.Boards[0]; $NB.BoardId = $pb.id
Add-Todo 'Peu urgent !9'
Add-Todo 'Tres prioritaire !1'
Add-Todo 'En retard !7'; (Card 'En retard').due = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
Add-Todo 'Pour aujourd hui !8'; (Card 'Pour aujourd hui').due = (Get-Date).ToString('yyyy-MM-dd')
$plan = @(Get-PlanCards 3)
Check 'le plan propose 3 cartes' ($plan.Count -eq 3)
Check 'ordre : en retard, puis pour aujourd''hui, puis la plus prioritaire' ($plan[0].Card.text -eq 'En retard' -and $plan[1].Card.text -eq 'Pour aujourd hui' -and $plan[2].Card.text -eq 'Tres prioritaire')
Check 'avec la raison' ($plan[0].Why -match 'retard' -and $plan[1].Why -match "aujourd'hui")
$NB.Todos.Clear(); foreach ($x in $saved) { [void]$NB.Todos.Add($x) }

Section 'Recherche globale'
foreach ($a3 in Get-ScriptAssignments (Join-Path $Root 'notebook.ps1') '^\$SearchFold') { . ([scriptblock]::Create($a3)) }
$NB.Clips = New-Object System.Collections.ArrayList; $NB.Favs = New-Object System.Collections.ArrayList
[void]$NB.Clips.Add([pscustomobject]@{ time = '09:12'; kind = 'text'; text = 'Numéro de dossier 4471'; files = @() })
[void]$NB.Favs.Add([pscustomobject]@{ kind = 'text'; text = 'Signature : Bien à vous'; files = @() })
Add-Todo 'Réunion budget'; (Card 'Réunion budget').desc = 'avec la compta'
Add-Content -Path $TodoArchive -Value "`r`n## 2026-09-01 — Mon tableau`r`n- [x] Budget 2025 envoyé" -Encoding UTF8
$r = Find-Everything 'reunion'
Check 'accents ignores (reunion trouve Réunion)' (@($r.Cards | Where-Object { $_.text -eq 'Réunion budget' }).Count -eq 1)
$r = Find-Everything 'budget compta'
Check 'plusieurs mots : tous doivent y etre (titre + description)' ($r.Cards.Count -eq 1)
$r = Find-Everything 'ordre du jour'
Check 'cherche aussi dans les sous-taches' (@($r.Cards).Count -ge 1)
$r = Find-Everything '4471'
Check 'cherche dans les copier-coller' ($r.Clips.Count -eq 1)
$r = Find-Everything 'SIGNATURE'
Check 'cherche dans les favoris (majuscules ignorees)' ($r.Clips.Count -eq 1)
$r = Find-Everything 'budget 2025'
Check 'cherche dans les archives' ($r.Archives.Count -eq 1 -and $r.Archives[0].section -match '2026-09-01')
Check 'rien pour un mot absent' (@((Find-Everything 'zzzz').Cards).Count -eq 0)

Section 'Notes rapides'
foreach ($def in Get-ScriptFunctions (Join-Path $Root 'notes.ps1')) { . ([scriptblock]::Create($def)) }
foreach ($a4 in Get-ScriptAssignments (Join-Path $Root 'notes.ps1') '^\$Notes') { . ([scriptblock]::Create($a4)) }
function Render-Notes {}
$NB.Notes = New-Object System.Collections.ArrayList; $NB.NotesTrash = New-Object System.Collections.ArrayList; $NB.NotesBackupDay = ''
$n1 = Add-Note "  Appeler le garage`nPour le controle technique  "
Check 'note ajoutee (espaces retires)' ($NB.Notes.Count -eq 1 -and $n1.text.StartsWith('Appeler') -and $n1.text.EndsWith('technique'))
Check 'note vide ignoree' ($null -eq (Add-Note '   '))
$n2 = Add-Note 'Idee : reunion du lundi plus courte'
Set-NotePinned $n1.id $true
Check 'epinglee en premier' ((Get-SortedNotes)[0].id -eq $n1.id)
Update-Note $n2.id 'Idee : reunion du lundi en 15 min'
Check 'note modifiee' ((Find-Note $n2.id).text -match '15 min')
Load-Notes
Check 'notes relues du disque' ($NB.Notes.Count -eq 2 -and (Find-Note $n1.id).pinned)
Check 'copie lisible notes.md' ((Get-Content $NotesMd -Raw) -match 'Appeler le garage')
Check 'titre = 1re ligne' ((Get-NoteTitle (Find-Note $n1.id)) -eq 'Appeler le garage')
Check 'la recherche trouve les notes' (@((Find-Everything 'reunion lundi').Notes).Count -eq 1)
$card = Convert-NoteToCard $n1.id
Check 'note -> carte : 1re ligne = titre, le reste = description' ($card.text -eq 'Appeler le garage' -and $card.desc -match 'controle technique')
Check 'et la note disparait' ($null -eq (Find-Note $n1.id) -and $NB.Notes.Count -eq 1)
Update-Note $n2.id '   '
Check 'vider une note la supprime' ($NB.Notes.Count -eq 0)

Section 'Sauvegarde des notes'
$Config = $Config + @{ NotesMirror = '' }
function Save-Settings {}
Check 'une note videe part a la corbeille' ($NB.NotesTrash.Count -eq 1 -and $NB.NotesTrash[0].text -match '15 min')
Restore-TrashedNote $NB.NotesTrash[0].id
Check 'recuperee depuis la corbeille' ($NB.Notes.Count -eq 1 -and $NB.NotesTrash.Count -eq 0)
Load-Notes
Check 'corbeille relue du disque (vide)' ($NB.NotesTrash.Count -eq 0 -and $NB.Notes.Count -eq 1)
# copie du jour : faite avant la 1re modification de la journee
$NB.NotesBackupDay = ''
[void](Add-Note 'Note du jour')
$dayFile = Join-Path $BackupDir "notes-$((Get-Date).ToString('yyyy-MM-dd')).json"
Check 'copie du jour dans sauvegardes' (Test-Path $dayFile)
$backs = @(Get-NoteBackupFiles)
Check 'la copie est proposee a la restauration' ($backs.Count -ge 1 -and $backs[0].Label -match "aujourd'hui")
function Confirm-Action { $true }
$before = $NB.Notes.Count
Check 'restaurer la copie du matin' ((Restore-Notes $dayFile 'test') -and $NB.Notes.Count -eq $before - 1)
$undo = @(Get-NoteBackupFiles | Where-Object { $_.Label -match 'avant la restauration' })
Check 'et pouvoir annuler' ($undo.Count -eq 1 -and (Restore-Notes $undo[0].Path 'annuler') -and $NB.Notes.Count -eq $before)
# copie automatique dans un dossier
$mir = Join-Path $T 'OneDrive'; New-Item -ItemType Directory -Path $mir | Out-Null
Set-NotesMirror $mir
Check 'copie automatique : .md lisible et .json' ((Get-Content (Join-Path $mir 'Orbit-notes.md') -Raw) -match 'Note du jour' -and (Test-Path (Join-Path $mir 'Orbit-notes.json')))
[void](Add-Note 'Encore une')
Check 'mise a jour a chaque modification' ((Get-Content (Join-Path $mir 'Orbit-notes.md') -Raw) -match 'Encore une')
Check 'la copie automatique est proposee a la restauration' (@(Get-NoteBackupFiles | Where-Object { $_.Label -match 'copie automatique' }).Count -eq 1)
Remove-Item -Recurse -Force $mir
[void](Add-Note 'Cle USB debranchee')
Check 'dossier absent : pas d''erreur, les notes restent enregistrees' ((Find-Everything 'cle usb').Notes.Count -eq 1)
Set-NotesMirror ''
# enregistrer une copie
$copy = Export-NotesCopy (Join-Path $T 'mes-notes.txt')
Check 'enregistrer une copie lisible' ((Get-Content $copy -Raw) -match 'Encore une')
# fichier abime
[IO.File]::WriteAllText($NotesFile, '[{"text": "casse...')
Load-Notes
Check 'notes.json abime : repris de la sauvegarde' ($NB.Notes.Count -ge 1 -and $NB.LoadNotice -match 'notes')
Check 'et le fichier abime est garde a part' (@(Get-ChildItem $T -Filter 'notes-illisible-*').Count -eq 1)

Section 'Tests unitaires des petites fonctions'
Check 'Limit-Prio : 0 -> 1, 11 -> 10, texte -> 5' ((Limit-Prio 0) -eq 1 -and (Limit-Prio 11) -eq 10 -and (Limit-Prio 'abc') -eq 5)
Check 'Short-Text coupe proprement' ((Short-Text 'abcdefghij' 5).Length -le 5 -and (Short-Text 'court' 50) -eq 'court')
Check 'Get-SearchKey : accents et majuscules' ((Get-SearchKey 'ÉCOLE Été Ça Œuvre') -eq 'ecole ete ca oeuvre')
Check 'Format-Due : aujourd''hui, demain, en retard' ((Format-Due (Get-Date).ToString('yyyy-MM-dd')) -eq "aujourd'hui" -and (Format-Due (Get-Date).AddDays(1).ToString('yyyy-MM-dd')) -eq 'demain' -and (Format-Due (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')) -match 'retard')
Check 'To-IsoString accepte une date ou un texte' ((To-IsoString ([datetime]'2026-01-02 03:04:05')) -eq '2026-01-02T03:04:05' -and (To-IsoString 'abc') -eq 'abc')
$mo = Get-NextOccurrence 'monthly' ([datetime]'2027-01-31')
Check 'mensuel le 31 : fin de mois respectee (28 ou 29 fevrier)' ($mo.Month -eq 2 -and $mo.Day -ge 28)
$ck = ConvertTo-Checks @([pscustomobject]@{ text = 'a'; done = $true }, $null, [pscustomobject]@{ text = ''; done = $true }) -Reset
Check 'ConvertTo-Checks : ignore le vide, -Reset decoche' ($ck.Count -eq 1 -and -not $ck[0].done)
Check 'Get-SafeId : accepte un id normal, refuse le reste' ((Get-SafeId 'abc_123-X') -eq 'abc_123-X' -and (Get-SafeId "a'; b") -ne "a'; b" -and (Get-SafeId '') -match '^[a-f0-9]{32}$')
$NB.LastAddedId = ''; Add-Todo 'Rendez-vous @25h !11'
$rv = Find-Todo $NB.LastAddedId
Check 'raccourcis invalides (@25h, !11) laisses dans le texte' ($rv.text -eq 'Rendez-vous @25h !11' -and -not $rv.remindAt -and $rv.prio -eq 5)
Remove-Todo $rv.id
Check 'Get-PlanCards sans carte : liste vide' ($(
    $sv = @($NB.Todos); $NB.Todos.Clear(); $r0 = @(Get-PlanCards 3).Count; foreach ($x in $sv) { [void]$NB.Todos.Add($x) }; $r0) -eq 0)
Check 'Find-Everything : recherche vide = aucun resultat' (@((Find-Everything '   ').Cards).Count -eq 0)

Section 'Securite : tentatives d''attaque (elles doivent toutes echouer)'
function Ensure-Visible {}; function Play-Sound {}; function Show-Tray {}
foreach ($def in Get-ScriptFunctions (Join-Path $Root 'transfer.ps1')) { . ([scriptblock]::Create($def)) }
foreach ($a5 in Get-ScriptAssignments (Join-Path $Root 'transfer.ps1') '^\$Export') { . ([scriptblock]::Create($a5)) }
$pwned = Join-Path $T 'PIRATE.txt'
# 1. un fichier kanban.json trafique : du code cache dans l'identifiant d'une carte
$evilId = "x'; Set-Content -LiteralPath '$pwned' -Value 1 #"
$evil = [ordered]@{
    current = 'b1'
    boards = @(@{ id = 'b1'; name = 'Tableau'; columns = @(@{ id = 'c1'; name = 'A faire'; done = $false }, @{ id = 'c2'; name = 'Fini'; done = $true }) },
               @{ id = "b2'; Remove-Item x; '"; name = 'Piege'; columns = @(@{ id = 'c3'; name = 'X'; done = $false }) })
    cards = @(@{ id = $evilId; text = 'Carte piegee'; prio = 3; board = 'b1'; col = 'c1'; order = 0; remindAt = (Get-Date).AddMinutes(-1).ToString('s') })
    focus = @($evilId)
}
$savedKanban = [IO.File]::ReadAllText($KanbanFile)
[IO.File]::WriteAllText($KanbanFile, (ConvertTo-Json -InputObject $evil -Depth 6))
Load-Todos
$pc = Card 'Carte piegee'
Check 'id piege remplace par un id neuf au chargement' ($pc -and $pc.id -match '^[a-f0-9]{32}$')
Check 'tableau a id piege ignore' (-not ($NB.Boards | Where-Object { $_.name -eq 'Piege' }))
Check 'id piege retire des cartes liees au focus' (-not ($NB.FocusCards | Where-Object { $_ -match "'" }))
$NB.Upcoming.Clear()
Check-TaskReminders
Check 'le rappel s''affiche' ($script:Bubble.Text -match 'Carte piegee')
& $script:Bubble.Actions[0]
Check 'bouton « C''est fait » : la carte est terminee' ((Card 'Carte piegee').done)
Check 'et AUCUN code cache n''a ete execute' (-not (Test-Path $pwned))
# 2. du code dans le texte d'une carte ou d'une note : garde tel quel, jamais execute
$payload = '$(Set-Content -LiteralPath "' + $pwned + '" -Value 2) `"guillemets`" ''apostrophes'' ; & calc.exe'
$NB.LastAddedId = ''; Add-Todo $payload
$pt = Find-Todo $NB.LastAddedId
$nn = Add-Note $payload
Save-Todos; Load-Todos; Load-Notes
Check 'texte de carte garde a l''identique' ((Find-Todo $pt.id).text -eq $payload.Trim())
Check 'texte de note garde a l''identique' ((Find-Note $nn.id).text -eq $payload.Trim())
Check 'recherche sur ce texte sans effet de bord' (@((Find-Everything 'guillemets').Cards).Count -ge 1 -and -not (Test-Path $pwned))
[IO.File]::WriteAllText($KanbanFile, $savedKanban); Load-Todos
# 3. une note avec un id piege
[IO.File]::WriteAllText($NotesFile, (ConvertTo-Json -InputObject @(@{ id = "n'; calc; '"; text = 'note piegee'; updated = (Get-Date).ToString('s') })))
Load-Notes
Check 'note a id piege : id remplace' ($NB.Notes.Count -eq 1 -and $NB.Notes[0].id -match '^[a-f0-9]{32}$')
# 4. un export recu de quelqu'un : chemins reseau et fichier de code
$foreign = Join-Path $T 'export-etranger'
New-Item -ItemType Directory -Force -Path $foreign | Out-Null
[IO.File]::WriteAllText((Join-Path $foreign 'orbit-export.json'), '{"from":"C:\\Users\\autre\\AppData\\Roaming\\Orbit","date":"2026-01-01T10:00:00"}')
[IO.File]::WriteAllText((Join-Path $foreign 'settings.json'), (ConvertTo-Json -InputObject ([ordered]@{
    notesMirror = '\\serveur-pirate\partage'; customImage = '\\serveur-pirate\img.png'
    endSoundFile = 'C:\Windows\Media\chimes.wav'; bubbleSoundFiles = @('\\serveur-pirate\a.wav', (Join-Path (Join-Path $T 'pc-victime') 'sons/ok.wav')); skin = 'Robot' })))
Set-Content -Path (Join-Path $foreign 'native-0123456789abcdef.dll') -Value 'faux code'
Set-Content -Path (Join-Path $foreign 'etat.json') -Value '{}'
$OldData2 = $DataDir
$DataDir = Join-Path $T 'pc-victime'; New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
[void](Import-OrbitData $foreign -NoConfirm)
$imp = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $DataDir 'settings.json')))
Check 'import : copie des notes vers un partage reseau supprimee' (-not $imp.notesMirror)
Check 'import : image sur un partage reseau supprimee' (-not $imp.customImage)
Check 'import : son hors du dossier d''Orbit supprime' (-not $imp.endSoundFile -and @($imp.bubbleSoundFiles).Count -eq 1)
Check 'import : le reste des reglages est garde' ($imp.skin -eq 'Robot')
Check 'import : aucun fichier de code (dll) copie' (@(Get-ChildItem $DataDir -Filter 'native-*').Count -eq 0)
Check 'import : pas d''etat de chrono importe' (-not (Test-Path (Join-Path $DataDir 'etat.json')))
[IO.File]::WriteAllText((Join-Path $foreign 'settings.json'), '{ pas du json')
[void](Import-OrbitData $foreign -NoConfirm)
Check 'import : reglages illisibles ecartes (pas appliques a l''aveugle)' (-not (Test-Path (Join-Path $DataDir 'settings.json')))
$DataDir = $OldData2
# 5. archive zip piegee (« zip slip ») : un fichier qui essaie de sortir du dossier
try {
    foreach ($asm in 'System.IO.Compression', 'System.IO.Compression.FileSystem') { try { Add-Type -AssemblyName $asm } catch {} }
    $zdir = Join-Path ([IO.Path]::GetTempPath()) ('orbit-zip-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $zdir | Out-Null
    $zp = Join-Path $zdir 'piege.zip'
    $fs = [IO.File]::Open($zp, 'Create')
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        $en = $za.CreateEntry('../ECHAPPE.txt'); $w = New-Object IO.StreamWriter($en.Open()); $w.Write('x'); $w.Dispose()
        $za.Dispose()
    } finally { $fs.Dispose() }
    $dest = Join-Path $zdir 'extraction'
    $blocked = $false
    try { [IO.Compression.ZipFile]::ExtractToDirectory($zp, $dest) } catch { $blocked = $true }
    Check 'zip piege : extraction refusee, rien ecrit hors du dossier' ($blocked -and -not (Test-Path (Join-Path $zdir 'ECHAPPE.txt')))
    Remove-Item -Recurse -Force $zdir -ErrorAction SilentlyContinue
} catch { Check 'zip piege' $false $_.Exception.Message }

Section 'Robustesse : fichiers en lecture seule, gros textes'
$ro = Get-Item $KanbanFile
$ro.IsReadOnly = $true
$ok = $true
try { Add-Todo 'Pendant lecture seule'; Save-Todos } catch { $ok = $false }
$ro.IsReadOnly = $false
Check 'fichier en lecture seule : pas de plantage (erreur notee dans le journal)' $ok
$big = 'x' * 200000
$NB.LastAddedId = ''; Add-Todo 'Carte avec tres longue description'; (Find-Todo $NB.LastAddedId).desc = $big; Save-Todos; Load-Todos
Check 'description de 200 000 caracteres : enregistree et relue' ((Card 'Carte avec tres longue description').desc.Length -eq 200000)

Section 'Transfert vers un autre PC'
foreach ($def in Get-ScriptFunctions (Join-Path $Root 'transfer.ps1')) { . ([scriptblock]::Create($def)) }
foreach ($a2 in Get-ScriptAssignments (Join-Path $Root 'transfer.ps1') '^\$Export') { . ([scriptblock]::Create($a2)) }
function Save-Stats {}; function Save-Settings {}; function Flush-Notebook {}
New-Item -ItemType Directory -Force -Path (Join-Path $T 'sons') | Out-Null
Set-Content -Path (Join-Path $T 'sons/bip.wav') -Value 'x'
Set-Content -Path (Join-Path $T 'orbit.log') -Value 'journal'
Set-Content -Path (Join-Path $T 'native-1234.dll') -Value 'dll'
$set = [ordered]@{ customImage = (Join-Path $T 'mon-image.png'); bubbleSoundFiles = @((Join-Path $T 'sons/bip.wav')) }
[IO.File]::WriteAllText((Join-Path $T 'settings.json'), (ConvertTo-Json -InputObject $set))
$stage = Join-Path $T 'paquet'
$app = New-OrbitPackageFolder $stage $Root
Check 'le paquet contient le programme' ((Test-Path (Join-Path $app 'orbit.ps1')) -and (Test-Path (Join-Path $app 'Orbit.cmd')) -and (Test-Path (Join-Path $app 'jokes')))
Check 'le paquet contient les donnees' ((Test-Path (Join-Path $app 'donnees/kanban.json')) -and (Test-Path (Join-Path $app 'donnees/sons/bip.wav')))
Check 'mais pas le journal ni le code compile de ce PC' (-not (Test-Path (Join-Path $app 'donnees/orbit.log')) -and -not (Test-Path (Join-Path $app 'donnees/native-1234.dll')))
$OldData = $DataDir
$DataDir = Join-Path $T 'autre-pc'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Check 'import sur un PC neuf' (Import-OrbitData (Join-Path $app 'donnees'))
Check 'tableaux recuperes' (Test-Path (Join-Path $DataDir 'kanban.json'))
$js = [IO.File]::ReadAllText((Join-Path $DataDir 'settings.json'))
$sj = ConvertFrom-Json $js
Check 'chemins de l''image et des sons adaptes au nouveau PC' ($sj.customImage -eq (Join-Path $DataDir 'mon-image.png') -and @($sj.bubbleSoundFiles)[0] -eq (Join-Path $DataDir 'sons/bip.wav'))
Check 'pas de manifeste laisse dans les donnees' (-not (Test-Path (Join-Path $DataDir 'orbit-export.json')))
Check 'deuxieme import : les donnees actuelles sont gardees a part' ((Import-OrbitData (Join-Path $app 'donnees') -NoConfirm) -and @(Get-ChildItem $DataDir -Directory -Filter 'avant-import-*').Count -eq 1)
$DataDir = $OldData

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
