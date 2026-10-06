<#
    Carnet d'Orbit : tableaux Kanban (facon Trello) + historique des copier-coller de la journee.
    Ce fichier est charge par orbit.ps1 (il ne se lance pas tout seul).
#>

$TodoFile = Join-Path $DataDir 'todo.json'          # ancienne to-do (reprise automatiquement)
$KanbanFile = Join-Path $DataDir 'kanban.json'
$TodoMd = Join-Path $DataDir 'todo.md'
$TodoArchive = Join-Path $DataDir 'todo-archive.md'
$BackupDir = Join-Path $DataDir 'sauvegardes'
$BackupKeep = 7      # jours de sauvegarde gardes
$UndoKeep = 5        # copies "avant restauration" gardees
$ClipDir = Join-Path $DataDir 'clipboard'
$FavFile = Join-Path $DataDir 'clipboard-favoris.json'
if (-not (Test-Path $ClipDir)) { New-Item -ItemType Directory -Path $ClipDir | Out-Null }

$NB = @{
    Todos      = New-Object System.Collections.ArrayList   # les cartes de tous les tableaux
    Boards     = New-Object System.Collections.ArrayList
    BoardId    = ''
    DragId     = ''
    DragStart  = $null
    PendingMove = $null
    Rendering  = $false
    KanbanW    = 0
    FocusCol   = ''
    Clips      = New-Object System.Collections.ArrayList
    ClipDay    = (Get-Date).ToString('yyyy-MM-dd')
    ClipSeq    = [uint32]0
    ClipPaused = $false
    LastClip   = ''
    Tab        = 'Todo'
    EditId     = ''
    EditOrig   = ''
    ClipDirty  = $true
    MaxClips   = 150
    MaxClipLen = 10000
    Favs       = New-Object System.Collections.ArrayList
    DeadlineDay = ''
    Quitting   = $false
    TodoDirty  = $true
    BackupDay  = ''
    FocusCards = New-Object System.Collections.ArrayList   # cartes liees au focus en cours / au prochain
    Upcoming   = New-Object System.Collections.ArrayList   # prochaines occurrences des cartes recurrentes
    Templates  = New-Object System.Collections.ArrayList   # modeles de cartes
    LastAddedId = ''
    MdPending  = $false
    ClipPending = $false
    LoadNotice = ''
    RenderedBoard = ''
}

function ConvertTo-JsonArray($list) {
    if ($list.Count -eq 0) { return '[]' }
    return ConvertTo-Json -InputObject @($list) -Depth 4
}

# ---------------------------------------------------------------------------
#  To-do
# ---------------------------------------------------------------------------
# Certaines versions de PowerShell transforment les dates du JSON en [datetime] : on les remet en texte ISO
function To-IsoString($v) {
    if ($v -is [datetime]) { return $v.ToString('s') }
    return [string]$v
}

# Priorite : 1 = la plus urgente ... 10 = la moins urgente (5 par defaut)
$DefaultPrio = 5
function To-DayString($v) {
    if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd') }
    $s = [string]$v
    if ($s.Length -ge 10) { return $s.Substring(0, 10) }
    return ''
}

function Limit-Prio($p) {
    $n = 0
    if (-not [int]::TryParse([string]$p, [ref]$n)) { return $DefaultPrio }
    return [math]::Min(10, [math]::Max(1, $n))
}

# ---------------------------------------------------------------------------
#  Tableaux Kanban : plusieurs tableaux, chacun avec ses colonnes. Les cartes
#  gardent tout ce qu'avaient les taches (priorite, description, echeance, rappel).
#  Une carte est "terminee" quand elle est dans une colonne marquee comme terminee.
# ---------------------------------------------------------------------------
function New-Id { [guid]::NewGuid().ToString('N') }

# Identifiant lu sur le disque : seulement lettres, chiffres, - et _ (sinon on en cree un neuf).
# Protege contre un fichier trafique (par ex. dans un export recu de quelqu'un d'autre).
function Get-SafeId($v) {
    $s = [string]$v
    if ($s -match '^[A-Za-z0-9_-]{1,64}$') { return $s }
    return (New-Id)
}
function Test-SafeId($v) { return ([string]$v -match '^[A-Za-z0-9_-]{1,64}$') }

function New-Column([string]$name, [bool]$done = $false) { [pscustomobject]@{ id = (New-Id); name = $name; done = $done } }

function New-BoardObject([string]$name) {
    $cols = New-Object System.Collections.ArrayList
    [void]$cols.Add((New-Column 'À faire')); [void]$cols.Add((New-Column 'En cours')); [void]$cols.Add((New-Column 'Terminé' $true))
    [pscustomobject]@{ id = (New-Id); name = $name; columns = $cols }
}

function Get-Board([string]$id) { foreach ($b in $NB.Boards) { if ($b.id -eq $id) { return $b } } }
function Get-CurrentBoard {
    $b = Get-Board $NB.BoardId
    if (-not $b) { $b = $NB.Boards[0]; $NB.BoardId = $b.id }
    return $b
}
function Get-Column($board, [string]$colId) { foreach ($c in $board.columns) { if ($c.id -eq $colId) { return $c } } }
function Find-ColumnBoard([string]$colId) { foreach ($b in $NB.Boards) { if (Get-Column $b $colId) { return $b } } }
function Get-DoneColumn($board) {
    foreach ($c in $board.columns) { if ($c.done) { return $c } }
    return $board.columns[$board.columns.Count - 1]
}
function Get-OpenColumn($board) {
    foreach ($c in $board.columns) { if (-not $c.done) { return $c } }
    return $board.columns[0]
}
function Get-ColumnCards([string]$colId) { @($NB.Todos | Where-Object { $_.col -eq $colId } | Sort-Object -Property @{ e = { [double]$_.order } }) }

function ConvertTo-Card($t, [string]$board, [string]$col, [double]$order) {
    [pscustomobject]@{
        id = (Get-SafeId $t.id); text = [string]$t.text; desc = [string]$t.desc; prio = Limit-Prio $t.prio
        due = To-DayString $t.due; remindAt = To-IsoString $t.remindAt; reminded = [bool]$t.reminded
        done = [bool]$t.done; created = To-IsoString $t.created; doneAt = To-IsoString $t.doneAt
        board = $board; col = $col; order = $order
        pomos = [int]$t.pomos; focusMin = [int]$t.focusMin; lastFocus = To-IsoString $t.lastFocus
        checks = ConvertTo-Checks $t.checks; repeat = [string]$t.repeat; spawned = [bool]$t.spawned
    }
}

# sous-taches d'une carte : liste de { text ; done }
function ConvertTo-Checks($list, [switch]$Reset) {
    $r = New-Object System.Collections.ArrayList
    foreach ($c in @($list)) {
        if ($null -eq $c -or -not [string]$c.text) { continue }
        [void]$r.Add([pscustomobject]@{ text = [string]$c.text; done = $(if ($Reset) { $false } else { [bool]$c.done }) })
    }
    return , $r
}

function Import-KanbanData($data) {
    $NB.Todos.Clear(); $NB.Boards.Clear()
    foreach ($b in $data.boards) {
        $cols = New-Object System.Collections.ArrayList
        if (-not (Test-SafeId $b.id)) { continue }
        foreach ($c in $b.columns) { if (Test-SafeId $c.id) { [void]$cols.Add([pscustomobject]@{ id = [string]$c.id; name = [string]$c.name; done = [bool]$c.done }) } }
        if ($cols.Count) { [void]$NB.Boards.Add([pscustomobject]@{ id = [string]$b.id; name = [string]$b.name; columns = $cols }) }
    }
    $NB.BoardId = [string]$data.current
    $NB.FocusCards.Clear()
    foreach ($id in @($data.focus)) { if (Test-SafeId $id) { [void]$NB.FocusCards.Add([string]$id) } }
    $NB.Upcoming.Clear(); $NB.Templates.Clear()
    foreach ($u in @($data.upcoming)) {
        if (-not $u -or -not $u.showAt) { continue }
        $c = ConvertTo-Card $u ([string]$u.board) '' 0
        $c | Add-Member -NotePropertyName showAt -NotePropertyValue (To-DayString $u.showAt)
        [void]$NB.Upcoming.Add($c)
    }
    foreach ($m in @($data.templates)) {
        if (-not $m -or -not $m.name) { continue }
        [void]$NB.Templates.Add((New-TemplateObject ([string]$m.name) $m))
    }
    foreach ($t in $data.cards) {
        $b = Get-Board ([string]$t.board)
        if (-not $b) { continue }
        $card = ConvertTo-Card $t $b.id ([string]$t.col) ([double]$t.order)
        $col = Get-Column $b $card.col
        if (-not $col) { $col = Get-OpenColumn $b; $card.col = $col.id }
        $card.done = [bool]$col.done
        [void]$NB.Todos.Add($card)
    }
}

function Load-Todos {
    $NB.Todos.Clear(); $NB.Boards.Clear()
    if (Test-Path -LiteralPath $KanbanFile) {
        try { Import-KanbanData (ConvertFrom-Json ([IO.File]::ReadAllText($KanbanFile))) }
        catch {
            Write-Log "Lecture tableaux : $($_.Exception.Message)"
            Recover-Kanban
        }
    }
    if ($NB.Boards.Count -eq 0) {
        # premier lancement, ou reprise de l'ancienne to-do dans "Mon tableau"
        $b = New-BoardObject 'Mon tableau'
        [void]$NB.Boards.Add($b); $NB.BoardId = $b.id
        if (Test-Path $TodoFile) {
            try {
                $i = 0
                foreach ($t in (ConvertFrom-Json ([IO.File]::ReadAllText($TodoFile)))) {
                    $col = if ([bool]$t.done) { (Get-DoneColumn $b).id } else { (Get-OpenColumn $b).id }
                    [void]$NB.Todos.Add((ConvertTo-Card $t $b.id $col ($i++)))
                }
                Move-Item -LiteralPath $TodoFile -Destination (Join-Path $DataDir 'todo-ancienne-version.json') -Force
            } catch { Write-Log "Reprise de la to-do : $($_.Exception.Message)" }
        }
        Save-Todos
    }
    [void](Get-CurrentBoard)
}

# ---------------------------------------------------------------------------
#  Plan du matin : les cartes les plus urgentes du jour, tous tableaux confondus
#  (en retard, a rendre aujourd'hui ou demain, rappel du jour, deja commencees,
#  puis priorite). Renvoie @{ Card ; Score ; Why } du plus urgent au moins urgent.
# ---------------------------------------------------------------------------
function Get-PlanCards([int]$count = 3) {
    $today = (Get-Date).Date
    $scored = foreach ($t in @(Get-OpenTodos)) {
        $score = (11 - [int]$t.prio) * 20
        $why = @()
        if ($t.due) {
            $days = ([datetime]::ParseExact($t.due, 'yyyy-MM-dd', $null) - $today).Days
            if ($days -lt 0) { $score += 1000 + [math]::Min(30, -$days) * 10; $why += '⚠ en retard' }
            elseif ($days -eq 0) { $score += 800; $why += "📅 à rendre aujourd'hui" }
            elseif ($days -eq 1) { $score += 500; $why += '📅 pour demain' }
            elseif ($days -le 3) { $score += 300; $why += "📅 pour $(Format-Due $t.due)" }
            elseif ($days -le 7) { $score += 100 }
        }
        if ($t.remindAt -and -not $t.reminded) {
            try { if (([datetime]$t.remindAt).Date -eq $today) { $score += 100; $why += "⏰ rappel $(Format-When $t.remindAt)" } } catch {}
        }
        $b = Get-Board $t.board
        if ($b -and $t.col -ne (Get-OpenColumn $b).id) { $score += 150; $why += '▶ déjà commencée' }
        if ($NB.FocusCards.Contains($t.id)) { $score += 60 }
        if ([int]$t.prio -le 2) { $why += "🔥 P$($t.prio)" }
        [pscustomobject]@{ Card = $t; Score = $score; Why = ($why -join ' · ') }
    }
    return @($scored | Sort-Object -Property @{ e = { $_.Score }; Descending = $true }, @{ e = { [int]$_.Card.prio } } | Select-Object -First $count)
}

# ---------------------------------------------------------------------------
#  Cartes recurrentes : quand une carte qui se repete est terminee, sa prochaine
#  occurrence est mise de cote (NB.Upcoming) et reapparait toute seule dans la
#  1re colonne de son tableau le jour venu, avec ses sous-taches decochees.
# ---------------------------------------------------------------------------
$RepeatChoices = [ordered]@{
    ''         = 'Ne se répète pas'
    'workdays' = 'Chaque jour ouvré (lun.–ven.)'
    'daily'    = 'Chaque jour'
    'weekly'   = 'Chaque semaine'
    'biweekly' = 'Toutes les 2 semaines'
    'monthly'  = 'Chaque mois'
}

function Get-RepeatLabel($t) {
    if (-not $t.repeat) { return '' }
    $ref = Get-RepeatReference $t
    switch ($t.repeat) {
        'weekly'   { return "chaque $($DayFull[[int]$ref.DayOfWeek])" }
        'biweekly' { return "un $($DayFull[[int]$ref.DayOfWeek]) sur deux" }
        'monthly'  { return "le $($ref.Day) de chaque mois" }
        default    { return $RepeatChoices[$t.repeat].ToLower() }
    }
}

# jour de reference : l'echeance si la carte en a une, sinon le jour de sa creation
function Get-RepeatReference($t) {
    if ($t.due) { return [datetime]::ParseExact($t.due, 'yyyy-MM-dd', $null) }
    if ($t.created) { try { return ([datetime]$t.created).Date } catch {} }
    return (Get-Date).Date
}

# Prochaine date apres $from, et forcement apres aujourd'hui
function Get-NextOccurrence([string]$repeat, [datetime]$from) {
    $d = $from.Date
    $today = (Get-Date).Date
    for ($guard = 0; $guard -lt 4000; $guard++) {
        switch ($repeat) {
            'daily'    { $d = $d.AddDays(1) }
            'workdays' { do { $d = $d.AddDays(1) } while ($d.DayOfWeek -eq 'Saturday' -or $d.DayOfWeek -eq 'Sunday') }
            'weekly'   { $d = $d.AddDays(7) }
            'biweekly' { $d = $d.AddDays(14) }
            'monthly'  { $d = $from.Date.AddMonths($guard + 1) }
            default    { return $null }
        }
        if ($d -gt $today) { return $d }
    }
    return $null
}

function Add-NextOccurrence($t) {
    if (-not $t.repeat -or $t.spawned) { return $null }
    $next = Get-NextOccurrence $t.repeat (Get-RepeatReference $t)
    if (-not $next) { return $null }
    $t.spawned = $true
    $c = ConvertTo-Card ([pscustomobject]@{
        id = (New-Id); text = $t.text; desc = $t.desc; prio = $t.prio; repeat = $t.repeat
        due = $(if ($t.due) { $next.ToString('yyyy-MM-dd') } else { '' })
        checks = (ConvertTo-Checks $t.checks -Reset); created = (Get-Date).ToString('s')
    }) $t.board '' 0
    $c | Add-Member -NotePropertyName showAt -NotePropertyValue $next.ToString('yyyy-MM-dd')
    [void]$NB.Upcoming.Add($c)
    return $c
}

# Fait apparaitre les occurrences du jour (au demarrage et toutes les 10 s). Renvoie les cartes revenues.
function Release-Upcoming {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $back = @()
    foreach ($u in @($NB.Upcoming)) {
        if ($u.showAt -gt $today) { continue }
        $b = Get-Board $u.board
        if (-not $b) { $b = $NB.Boards[0] }
        if (-not $b) { continue }
        $col = Get-OpenColumn $b
        $card = ConvertTo-Card $u $b.id $col.id (@(Get-ColumnCards $col.id).Count)
        $card.created = (Get-Date).ToString('s'); $card.done = $false; $card.spawned = $false
        [void]$NB.Todos.Add($card)
        $NB.Upcoming.Remove($u)
        $back += $card
    }
    if ($back.Count) { Save-Todos; Render-Todos -Cols @($back | ForEach-Object { $_.col }) }
    return $back
}

function Get-BoardUpcoming([string]$boardId) { @($NB.Upcoming | Where-Object { $_.board -eq $boardId } | Sort-Object showAt) }

function Remove-Upcoming([string]$id) {
    foreach ($u in @($NB.Upcoming)) { if ($u.id -eq $id) { $NB.Upcoming.Remove($u) } }
    Save-Todos
    Update-KanbanFooter (Get-CurrentBoard)
    Show-Bubble "Ok, cette carte ne reviendra plus 🔁✖" -Force -Seconds 3
}

function Show-Upcoming([string]$id) {
    foreach ($u in @($NB.Upcoming)) { if ($u.id -eq $id) { $u.showAt = (Get-Date).ToString('yyyy-MM-dd') } }
    [void](Release-Upcoming)
}

# Menu des cartes a venir (clic sur le compteur en bas du tableau)
function Show-UpcomingMenu($target) {
    $list = Get-BoardUpcoming (Get-CurrentBoard).id
    if (-not $list.Count) { return }
    $m = New-Object Windows.Controls.ContextMenu
    foreach ($u in $list) {
        $it = New-Object Windows.Controls.MenuItem
        $it.Header = "🔁 $(Short-Text $u.text 40) — $(Format-Due $u.showAt)"
        [void]$it.Items.Add((New-TaggedItem '⤴  La faire apparaître maintenant' $u.id { param($s, $e) Invoke-Safe { Show-Upcoming $s.Tag } }))
        [void]$it.Items.Add((New-TaggedItem '🗑  Ne plus la répéter' $u.id { param($s, $e) Invoke-Safe { Remove-Upcoming $s.Tag } }))
        [void]$m.Items.Add($it)
    }
    $m.PlacementTarget = $target
    $m.IsOpen = $true
}

# --- sous-taches ---
function Add-CardCheck([string]$id, [string]$text) {
    $t = Find-Todo $id
    $text = $text.Trim()
    if (-not $t -or -not $text) { return }
    [void]$t.checks.Add([pscustomobject]@{ text = $text; done = $false })
    $NB.FocusChecklist = $id
    Save-Todos
    Render-Todos -Cols $t.col
}

function Set-CardCheck([string]$id, [int]$index, [bool]$done) {
    $t = Find-Todo $id
    if (-not $t -or $index -ge $t.checks.Count) { return }
    $t.checks[$index].done = $done
    Save-Todos
    $n = @($t.checks | Where-Object { $_.done }).Count
    if ($done -and $n -eq $t.checks.Count -and -not $t.done) {
        $script:BubbleCardId = $t.id
        Show-Bubble "Toutes les sous-tâches de « $(Short-Text $t.text 40) » sont cochées ✅ Tu la ranges dans Terminé ?" -Force -AutoHide -Seconds 15 -Buttons @(
            # (securite : l'identifiant passe par une variable, jamais dans du code genere)
            @{ Label = '✅ Oui, terminée'; Action = { End-EditTodo -NoRender; Set-TodoDone $script:BubbleCardId $true }; Primary = $true },
            @{ Label = 'Pas encore'; Action = { } })
    }
}

function Remove-CardCheck([string]$id, [int]$index) {
    $t = Find-Todo $id
    if (-not $t -or $index -ge $t.checks.Count) { return }
    $t.checks.RemoveAt($index)
    Save-Todos
    Render-Todos -Cols $t.col
}

function Set-CardRepeat([string]$id, [string]$repeat) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $t.repeat = $repeat
    $t.spawned = $false
    Save-Todos
}

# ---------------------------------------------------------------------------
#  Modeles de cartes : une carte type (texte, description, sous-taches,
#  priorite, repetition) qu'on recree en un clic depuis le menu ⋯ d'une colonne
# ---------------------------------------------------------------------------
function New-TemplateObject([string]$name, $src) {
    [pscustomobject]@{
        id = $(if ($src.id -and $src.name) { Get-SafeId $src.id } else { New-Id }); name = $name
        text = [string]$src.text; desc = [string]$src.desc; prio = Limit-Prio $src.prio
        checks = (ConvertTo-Checks $src.checks -Reset); repeat = [string]$src.repeat
    }
}

function Save-CardAsTemplate([string]$id) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $name = Show-Prompt 'Nouveau modèle' 'Nom du modèle :' $t.text
    if (-not $name) { return }
    foreach ($m in @($NB.Templates)) { if ($m.name -eq $name) { $NB.Templates.Remove($m) } }
    [void]$NB.Templates.Add((New-TemplateObject $name $t))
    Save-Todos
    Show-Bubble "📋 Modèle « $name » enregistré. Menu ⋯ d'une colonne > Nouvelle carte depuis un modèle." -Force -Seconds 5
}

function New-CardFromTemplate([string]$tplId, [string]$colId) {
    $m = $NB.Templates | Where-Object { $_.id -eq $tplId } | Select-Object -First 1
    if (-not $m) { return }
    $NB.LastAddedId = ''
    Add-Todo $m.text $m.prio $colId
    $t = Find-Todo $NB.LastAddedId
    if (-not $t) { return }
    $t.desc = $m.desc; $t.repeat = $m.repeat; $t.checks = ConvertTo-Checks $m.checks -Reset
    Save-Todos
    Start-EditTodo $t.id
}

function Remove-Template([string]$tplId) {
    foreach ($m in @($NB.Templates)) { if ($m.id -eq $tplId) { $NB.Templates.Remove($m) } }
    Save-Todos
}

# ---------------------------------------------------------------------------
#  Lien cartes <-> focus : on lie une ou plusieurs cartes au focus (en cours ou
#  prochain). A la fin de chaque focus, chacune gagne une 🍅 et les minutes ;
#  celles qui ne sont pas finies restent liees pour le focus suivant.
# ---------------------------------------------------------------------------
function Format-FocusTime([int]$min) {
    if ($min -lt 60) { return "$min min" }
    $h = [math]::Floor($min / 60); $m = $min % 60
    if ($m) { return "$h h $('{0:00}' -f $m)" } else { return "$h h" }
}

function Test-CardInFocus([string]$id) { return $NB.FocusCards.Contains($id) }

# cartes liees qui existent encore (-Open : seulement celles pas terminees)
function Get-FocusCards([switch]$Open) {
    $r = @()
    foreach ($id in @($NB.FocusCards)) {
        $t = Find-Todo $id
        if ($t -and (-not $Open -or -not $t.done)) { $r += $t }
    }
    return $r
}

# retire les cartes supprimees ou terminees
function Clear-FocusCardsDone {
    foreach ($id in @($NB.FocusCards)) {
        $t = Find-Todo $id
        if (-not $t -or $t.done) { $NB.FocusCards.Remove($id) }
    }
}

# Au debut d'un focus : une carte encore dans la 1re colonne passe dans « En cours » (si le tableau en a une)
function Move-CardToDoing($t) {
    $b = Get-Board $t.board
    if (-not $b -or $t.done -or $t.col -ne (Get-OpenColumn $b).id) { return }
    $doing = $b.columns | Where-Object { -not $_.done -and $_.name -match '^\s*en\s*cours' } | Select-Object -First 1
    if ($doing -and $doing.id -ne $t.col) { Move-Card $t.id $doing.id -Quiet }
}

function Set-FocusCards([string[]]$ids) {
    $NB.FocusCards.Clear()
    foreach ($id in $ids) { if ($id -and (Find-Todo $id) -and -not $NB.FocusCards.Contains($id)) { [void]$NB.FocusCards.Add($id) } }
    if ($O.State -eq 'Focus') { foreach ($t in (Get-FocusCards -Open)) { Move-CardToDoing $t } }
    Save-Todos
    Render-Todos
}

function Set-CardFocus([string]$id, [bool]$on) {
    $t = Find-Todo $id
    if (-not $t) { return }
    if ($on) {
        if ($t.done) { Show-Bubble "Cette carte est déjà terminée ✅" -Force -Seconds 3; return }
        if (-not $NB.FocusCards.Contains($id)) { [void]$NB.FocusCards.Add($id) }
        if ($O.State -eq 'Focus') { Move-CardToDoing $t }
    } else {
        $NB.FocusCards.Remove($id)
    }
    Save-Todos
    Render-Todos -Cols $t.col
    $n = @(Get-FocusCards -Open).Count
    $when = if ($O.State -eq 'Focus') { 'ce focus' } else { 'ton prochain focus' }
    if ($on) { Show-Bubble "🎯 « $(Short-Text $t.text 40) » est liée à $when ($n carte(s) en tout)." -Force -Seconds 4 }
    else { Show-Bubble "Ok, « $(Short-Text $t.text 40) » n'est plus liée au focus." -Force -Seconds 3 }
}

function Toggle-CardFocus([string]$id) { Set-CardFocus $id (-not $NB.FocusCards.Contains($id)) }

# fin d'un focus termine : une 🍅 et les minutes pour chaque carte liee (meme celles finies pendant le focus)
function Add-FocusToCards([int]$minutes) {
    $cards = @(Get-FocusCards)
    foreach ($t in $cards) {
        $t.pomos = [int]$t.pomos + 1
        $t.focusMin = [int]$t.focusMin + $minutes
        $t.lastFocus = (Get-Date).ToString('s')
    }
    Clear-FocusCardsDone
    if ($cards.Count) { Save-Todos; Render-Todos -Cols @($cards | ForEach-Object { $_.col }) }
    return $cards.Count
}

# Fenetre a cases a cocher : renvoie les id choisis, ou $null si on annule
function Show-CardPicker([string]$title, [string]$intro, $cards, [string[]]$checked, [string]$okLabel, [switch]$AllowNew) {
    $cards = @($cards)
    $w = New-Object Windows.Window
    $w.Title = $title; $w.Width = 440; $w.SizeToContent = 'Height'; $w.ResizeMode = 'NoResize'
    $w.WindowStartupLocation = 'CenterScreen'; $w.Topmost = $true; $w.ShowInTaskbar = $false
    $w.Background = '#FAFAFE'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '16'
    $lb = New-Object Windows.Controls.TextBlock; $lb.Text = $intro; $lb.TextWrapping = 'Wrap'; $lb.Margin = '0,0,0,10'; $lb.FontSize = 13
    [void]$sp.Children.Add($lb)
    $list = New-Object Windows.Controls.StackPanel
    $boxes = @()
    $lastBoard = ''
    foreach ($t in $cards) {
        if ($NB.Boards.Count -gt 1 -and $t.board -ne $lastBoard) {
            $lastBoard = $t.board
            $h = New-Object Windows.Controls.TextBlock
            $h.Text = "🗂 $((Get-Board $t.board).name)"; $h.FontWeight = 'Bold'; $h.Foreground = '#6C5CE7'; $h.Margin = '0,6,0,3'
            [void]$list.Children.Add($h)
        }
        $cb = New-Object Windows.Controls.CheckBox
        $label = "P$($t.prio) · $($t.text)"
        if ($t.pomos) { $label += "   🍅 $($t.pomos)" }
        $col = Get-Column (Get-Board $t.board) $t.col
        if ($col) { $label += "   ($($col.name))" }
        $cb.Content = $label; $cb.Tag = $t.id; $cb.Margin = '4,3,0,3'; $cb.IsChecked = $checked -contains $t.id
        $cb.ToolTip = if ($t.desc) { $t.desc } else { $null }
        [void]$list.Children.Add($cb)
        $boxes += $cb
    }
    if (-not $cards.Count) {
        $e = New-Object Windows.Controls.TextBlock; $e.Text = 'Aucune carte à faire pour le moment.'; $e.FontStyle = 'Italic'; $e.Foreground = '#8A87A3'
        [void]$list.Children.Add($e)
    }
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.MaxHeight = 360; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $list
    [void]$sp.Children.Add($sv)
    $new = $null
    if ($AllowNew) {
        $g = New-Object Windows.Controls.Grid; $g.Margin = '0,10,0,0'
        $new = New-Object Windows.Controls.TextBox; $new.Padding = '6,4'
        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = '＋ ou une nouvelle carte (ajoutée au tableau affiché)'; $hint.Margin = '8,0,0,0'; $hint.VerticalAlignment = 'Center'
        $hint.Foreground = '#9A98B0'; $hint.IsHitTestVisible = $false
        $new.Tag = $hint
        $new.Add_TextChanged({ param($s, $e) $s.Tag.Visibility = if ($s.Text) { 'Collapsed' } else { 'Visible' } })
        [void]$g.Children.Add($new); [void]$g.Children.Add($hint)
        [void]$sp.Children.Add($g)
    }
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,14,0,0'
    $ok = New-Object Windows.Controls.Button; $ok.Content = $okLabel; $ok.Padding = '14,5'; $ok.IsDefault = $true; $ok.Margin = '0,0,8,0'
    $ok.Background = '#6C5CE7'; $ok.Foreground = 'White'; $ok.BorderThickness = '0'
    $ko = New-Object Windows.Controls.Button; $ko.Content = 'Annuler'; $ko.Padding = '14,5'; $ko.IsCancel = $true
    $ok.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($ko)
    [void]$sp.Children.Add($btns)
    $w.Content = $sp
    if (-not $w.ShowDialog()) { return $null }
    $ids = @($boxes | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
    if ($new -and $new.Text.Trim()) {
        $NB.LastAddedId = ''
        Add-Todo $new.Text
        if ($NB.LastAddedId) { $ids += $NB.LastAddedId }
    }
    return , $ids
}

# tri pour l'affichage : par tableau (dans l'ordre des tableaux), puis par priorite
function Sort-CardsByBoard($cards) {
    $order = @($NB.Boards | ForEach-Object { $_.id })
    return @($cards | Sort-Object -Property @{ e = { [array]::IndexOf($order, $_.board) } }, @{ e = { [int]$_.prio } })
}

# Choisir les cartes du focus. -Start : lance le focus juste apres
function Choose-FocusCards([switch]$Start, [string[]]$Preselect) {
    $open = @(Sort-CardsByBoard (Get-OpenTodos))
    $intro = if ($O.State -eq 'Focus') { "Sur quelles cartes tu travailles pendant ce focus ? (plusieurs possibles)" }
             else { "Sur quelles cartes tu vas travailler ? (plusieurs possibles ; elles restent liées d'un focus à l'autre tant qu'elles ne sont pas finies)" }
    $ok = if ($Start) { '🚀 Lancer le focus' } else { '🎯 Valider' }
    $checked = if ($Preselect) { $Preselect } else { @($NB.FocusCards) }
    $ids = Show-CardPicker '🎯 Cartes du focus' $intro $open $checked $ok -AllowNew
    if ($null -eq $ids) {
        if ($O.State -eq 'AwaitFocus') { Ask-Focus }
        return
    }
    Set-FocusCards $ids
    if ($Start) { Start-Focus }
    elseif ($ids.Count) { Show-Bubble "🎯 $($ids.Count) carte(s) liée(s) au focus." -Force -Seconds 3 }
    else { Show-Bubble "Plus aucune carte liée au focus." -Force -Seconds 3 }
}

# Fin de focus avec plusieurs cartes : lesquelles sont finies ?
function Choose-DoneFocusCards {
    $cards = @(Sort-CardsByBoard (Get-FocusCards -Open))
    $ids = Show-CardPicker '✅ Cartes terminées' "Coche les cartes que tu as finies. Les autres restent liées au prochain focus." $cards @() '✅ Valider'
    if ($null -eq $ids) { Ask-Break; return }
    foreach ($id in $ids) { Set-TodoDone $id $true -Quiet }
    Clear-FocusCardsDone
    Save-Todos
    Complete-FocusMessage $ids.Count
}

# ---------------------------------------------------------------------------
#  Sauvegardes : chaque jour, avant la premiere modification, une copie de
#  kanban.json part dans %APPDATA%\Orbit\sauvegardes (7 derniers jours gardes).
#  Bouton 🕘 des tableaux pour revenir a l'une d'elles.
# ---------------------------------------------------------------------------
function Get-BackupFiles {
    if (-not (Test-Path -LiteralPath $BackupDir)) { return @() }
    return @(Get-ChildItem -Path $BackupDir -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'kanban-*' -or $_.Name -like 'avant-restauration-*' } |
        Sort-Object LastWriteTime -Descending)
}

function Limit-Backups([string]$pattern, [int]$keep) {
    Get-ChildItem -Path $BackupDir -Filter $pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
        Select-Object -Skip $keep | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Backup-Kanban {
    $day = (Get-Date).ToString('yyyy-MM-dd')
    if ($NB.BackupDay -eq $day -or -not (Test-Path -LiteralPath $KanbanFile)) { return }
    try {
        if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
        $dest = Join-Path $BackupDir "kanban-$day.json"
        if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $KanbanFile -Destination $dest -Force }
        $NB.BackupDay = $day
        Limit-Backups 'kanban-*.json' $BackupKeep
    } catch { Write-Log "Sauvegarde des tableaux : $($_.Exception.Message)" }
}

# kanban.json illisible au demarrage : on le met de cote et on repart de la sauvegarde la plus recente
function Recover-Kanban {
    $bad = Join-Path $DataDir ("kanban-illisible-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
    try { Move-Item -LiteralPath $KanbanFile -Destination $bad -Force } catch { Write-Log "Mise de cote : $($_.Exception.Message)" }
    foreach ($f in (Get-BackupFiles)) {
        try {
            Import-KanbanData (ConvertFrom-Json ([IO.File]::ReadAllText($f.FullName)))
            if ($NB.Boards.Count) {
                Copy-Item -LiteralPath $f.FullName -Destination $KanbanFile -Force
                $NB.LoadNotice = "Ton fichier de tableaux était abîmé 😬 J'ai repris ta sauvegarde « $(Get-BackupLabel $f) »."
                Write-Log "Tableaux repris de $($f.Name)"
                return
            }
        } catch { Write-Log "Sauvegarde $($f.Name) illisible : $($_.Exception.Message)" }
    }
    $NB.Todos.Clear(); $NB.Boards.Clear()
    $NB.LoadNotice = "Ton fichier de tableaux était abîmé 😬 et je n'ai pas trouvé de sauvegarde. Il est gardé dans $bad."
}

function Get-BackupLabel($f) {
    $fr = try { [Globalization.CultureInfo]::GetCultureInfo('fr-FR') } catch { [Globalization.CultureInfo]::InvariantCulture }
    if ($f.Name -match '^kanban-(\d{4}-\d{2}-\d{2})\.json$') {
        $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
        $when = if ($d.Date -eq (Get-Date).Date) { "aujourd'hui" } elseif ($d.Date -eq (Get-Date).Date.AddDays(-1)) { 'hier' } else { $d.ToString('dddd dd/MM', $fr) }
        return "début de journée, $when"
    }
    if ($f.Name -match '^avant-restauration-(\d{4}-\d{2}-\d{2}_\d{6})\.json$') {
        $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd_HHmmss', $null)
        return "juste avant la restauration du $($d.ToString('dd/MM à HH:mm'))"
    }
    return $f.BaseName
}

function Show-BackupMenu($btn) {
    $m = New-Object Windows.Controls.ContextMenu
    $files = @(Get-BackupFiles)
    if (-not $files.Count) {
        $it = New-Object Windows.Controls.MenuItem
        $it.Header = "Pas encore de sauvegarde (une copie est faite chaque jour)"; $it.IsEnabled = $false
        [void]$m.Items.Add($it)
    }
    foreach ($f in $files) {
        $info = ''
        try {
            $d = ConvertFrom-Json ([IO.File]::ReadAllText($f.FullName))
            $info = " — $(@($d.boards).Count) tableau(x), $(@($d.cards).Count) carte(s)"
        } catch { $info = ' — illisible' }
        $it = New-Object Windows.Controls.MenuItem
        $it.Header = "↩  $(Get-BackupLabel $f)$info"; $it.Tag = $f.FullName
        $it.IsEnabled = $info -ne ' — illisible'
        $it.Add_Click({ param($s, $e) Invoke-Safe { Restore-Kanban ([string]$s.Tag) } })
        [void]$m.Items.Add($it)
    }
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    $open = New-Object Windows.Controls.MenuItem
    $open.Header = "📂  Ouvrir le dossier des sauvegardes"
    $open.Add_Click({
        Invoke-Safe {
            if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
            Start-Process explorer.exe $BackupDir
        }
    })
    [void]$m.Items.Add($open)
    $m.PlacementTarget = $btn
    $m.IsOpen = $true
}

function Restore-Kanban([string]$path) {
    try {
        $content = [IO.File]::ReadAllText($path)
        $data = ConvertFrom-Json $content
        if (-not @($data.boards).Count) { throw 'aucun tableau dedans' }
    } catch { [void][Windows.MessageBox]::Show($panel, "Cette sauvegarde est illisible : $($_.Exception.Message)", 'Orbit'); return }
    $label = Get-BackupLabel (Get-Item -LiteralPath $path)
    if (-not (Confirm-Action "Remplacer tous tes tableaux par la sauvegarde « $label » ?`n(L'état actuel est gardé : tu pourras revenir en arrière avec 🕘.)")) { return }
    if ($NB.EditId) { End-EditTodo -NoRender }
    Save-Todos
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    $undo = Join-Path $BackupDir ("avant-restauration-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
    if ($undo -eq $path) { $undo = $undo -replace '\.json$', '-2.json' }
    Copy-Item -LiteralPath $KanbanFile -Destination $undo -Force
    Write-FileSafe $KanbanFile $content
    Limit-Backups 'avant-restauration-*.json' $UndoKeep
    Load-Todos
    Save-Todos
    Render-Todos; Fit-Notebook
    Show-Bubble "Tableaux restaurés ↩ ($label)" -Force -Seconds 4
}

# Sauvegarde a chaque modification dans kanban.json. La copie lisible todo.md
# est regeneree au plus tard 10 s apres (et a la fermeture d'Orbit).
function Save-Todos {
    Backup-Kanban
    try {
        $data = [ordered]@{ current = $NB.BoardId; boards = @($NB.Boards); cards = @($NB.Todos); focus = @($NB.FocusCards)
                   upcoming = @($NB.Upcoming); templates = @($NB.Templates) }
        Write-FileSafe $KanbanFile (ConvertTo-Json -InputObject $data -Depth 6)
    } catch { Write-Log "Ecriture tableaux : $($_.Exception.Message)" }
    if ($NB.MdTimer) {
        $NB.MdPending = $true
        if (-not $NB.MdTimer.IsEnabled) { $NB.MdTimer.Start() }
    } else { Write-TodoMd }
}

function Write-TodoMd {
    $NB.MdPending = $false
    if ($NB.MdTimer) { $NB.MdTimer.Stop() }
    try {
        $lines = @("# Tableaux Orbit", "", "_Mis à jour le $((Get-Date).ToString('dd/MM/yyyy HH:mm'))_")
        foreach ($b in $NB.Boards) {
            $lines += ''; $lines += "## $($b.name)"
            foreach ($c in $b.columns) {
                $lines += ''; $lines += "### $($c.name)"
                foreach ($t in (Get-ColumnCards $c.id)) {
                    $extra = ''
                    if ($t.due) { $extra += " 📅 $(([datetime]$t.due).ToString('dd/MM'))" }
                    if ($t.remindAt -and -not $t.done) { $extra += " ⏰ $(([datetime]$t.remindAt).ToString('dd/MM HH:mm'))" }
                    if ($t.pomos) { $extra += " 🍅 $($t.pomos) focus ($(Format-FocusTime $t.focusMin))" }
                    if ($NB.FocusCards.Contains($t.id)) { $extra += ' 🎯' }
                    $lines += "- [$(if ($t.done) { 'x' } else { ' ' })] (P$($t.prio)) $($t.text)$extra"
                    if ($t.desc) { foreach ($d in ($t.desc -split "`r?`n")) { $lines += "    > $d" } }
                }
            }
        }
        Write-FileSafe $TodoMd ($lines -join "`r`n")
    } catch { Write-Log "Ecriture todo.md : $($_.Exception.Message)" }
}

# Deplace une carte dans une colonne (eventuellement d'un autre tableau), a la position voulue
function Move-Card([string]$id, [string]$colId, [int]$index = -1, [switch]$Quiet) {
    $t = Find-Todo $id
    $board = Find-ColumnBoard $colId
    if (-not $t -or -not $board) { return }
    $col = Get-Column $board $colId
    $wasDone = $t.done
    $oldCol = $t.col
    $list = New-Object System.Collections.ArrayList
    foreach ($o in (Get-ColumnCards $colId)) { if ($o.id -ne $id) { [void]$list.Add($o) } }
    if ($index -lt 0 -or $index -gt $list.Count) { $index = $list.Count }
    $list.Insert($index, $t)
    for ($i = 0; $i -lt $list.Count; $i++) { $list[$i].order = $i }
    $t.board = $board.id; $t.col = $col.id
    $t.done = [bool]$col.done
    if ($t.done -and -not $wasDone) { $t.doneAt = (Get-Date).ToString('s') } elseif (-not $t.done) { $t.doneAt = '' }
    $next = if ($t.done -and -not $wasDone) { Add-NextOccurrence $t } else { $null }
    Save-Todos
    Render-Todos -Cols @($oldCol, $col.id)
    if ($t.done -and -not $wasDone -and -not $Quiet) {
        $left = @($NB.Todos | Where-Object { -not $_.done -and $_.board -eq $board.id }).Count
        $again = if ($next) { "`n🔁 Elle reviendra $(Format-Due $next.showAt)." } else { '' }
        if ($left -eq 0) { Show-Bubble "Tout le tableau « $($board.name) » est terminé ! 🎉$again" -Force -Seconds 5 }
        else { Show-Bubble ((Pick @("Bien joué ✅", "Une de moins ! 💪", "Terminé, ça fait du bien hein 😌")) + $again) -Force -Seconds 4 }
    }
}

function Add-Todo([string]$text, $prio = $DefaultPrio, [string]$colId = '') {
    $text = $text.Trim()
    # raccourci : "!2 Appeler Paul" ou "Appeler Paul !2" donne la priorite 2
    if ($text -match '(^|\s)!(10|[1-9])(?=\s|$)') {
        $prio = [int]$Matches[2]
        $text = (($text -replace '(^|\s)!(10|[1-9])(?=\s|$)', ' ') -replace '\s{2,}', ' ').Trim()
    }
    # raccourci : "@14h", "@14h30" ou "@14:30" programme un rappel (aujourd'hui, ou demain si l'heure est passee)
    $remindAt = ''
    $rx = '(^|\s)@([01]?\d|2[0-3])(?:h|:)([0-5]\d)?(?=\s|$)'
    if ($text -match $rx) {
        $at = (Get-Date).Date.AddHours([int]$Matches[2]).AddMinutes($(if ($Matches[3]) { [int]$Matches[3] } else { 0 }))
        if ($at -le (Get-Date)) { $at = $at.AddDays(1) }
        $remindAt = $at.ToString('s')
        $text = (($text -replace $rx, ' ') -replace '\s{2,}', ' ').Trim()
    }
    if (-not $text) { return }
    $prio = Limit-Prio $prio
    # par defaut : premiere colonne "a faire" du tableau affiche
    $board = if ($colId) { Find-ColumnBoard $colId } else { $null }
    if (-not $board) { $board = Get-CurrentBoard; $colId = (Get-OpenColumn $board).id }
    $col = Get-Column $board $colId
    [void]$NB.Todos.Add([pscustomobject]@{
        id      = [guid]::NewGuid().ToString('N')
        text    = $text
        desc    = ''
        prio    = $prio
        due     = ''
        remindAt = $remindAt
        reminded = $false
        done    = [bool]$col.done
        created = (Get-Date).ToString('s')
        doneAt  = $(if ($col.done) { (Get-Date).ToString('s') } else { '' })
        board   = $board.id
        col     = $colId
        order   = @(Get-ColumnCards $colId).Count
        pomos   = 0
        focusMin = 0
        lastFocus = ''
        checks  = (New-Object System.Collections.ArrayList)
        repeat  = ''
        spawned = $false
    })
    $NB.LastAddedId = $NB.Todos[$NB.Todos.Count - 1].id
    Save-Todos
    Render-Todos -Cols $colId
    $msg = Pick @("Noté ! ✍", "C'est dans la liste 📝", "Hop, enregistré 💾", "Je m'en souviendrai pour toi 🧠")
    if ($prio -le 2) { $msg += " Priorité $prio, je la mets en haut de la pile 🔥" }
    if ($remindAt) { $msg += " Rappel prévu $(Format-When $remindAt) ⏰" }
    Show-Bubble $msg -Force -Seconds 3
}

function Set-TodoPrio([string]$id, $prio) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $t.prio = Limit-Prio $prio
    Save-Todos
    Render-Todos -Cols $t.col
}

function Find-Todo([string]$id) { foreach ($t in $NB.Todos) { if ($t.id -eq $id) { return $t } } }

# "Terminer" une carte = la deplacer dans la colonne terminee de son tableau (et inversement)
function Set-TodoDone([string]$id, [bool]$done, [switch]$Quiet) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $b = Get-Board $t.board
    if (-not $b) { return }
    $target = if ($done) { Get-DoneColumn $b } else { Get-OpenColumn $b }
    Move-Card $id $target.id -Quiet:$Quiet
}

function Remove-Todo([string]$id) {
    $t = Find-Todo $id
    if ($t) {
        if ($NB.EditId -eq $id) { $NB.EditId = ''; if ($NB.SaveTimer) { $NB.SaveTimer.Stop() } }
        $NB.Todos.Remove($t); Save-Todos; Render-Todos -Cols $t.col
    }
}

# Archive les cartes terminees du tableau affiche (ou d'une seule colonne)
function Clear-DoneTodos([string]$colId = '') {
    $board = Get-CurrentBoard
    $done = @(if ($colId) { Get-ColumnCards $colId } else { $NB.Todos | Where-Object { $_.done -and $_.board -eq $board.id } })
    if (-not $done.Count) { return }
    $md = "`r`n## $((Get-Date).ToString('yyyy-MM-dd')) — $($board.name)`r`n" + (($done | ForEach-Object { "- [x] $($_.text)" }) -join "`r`n")
    Add-Content -Path $TodoArchive -Value $md -Encoding UTF8
    foreach ($t in $done) { $NB.Todos.Remove($t) }
    Save-Todos
    Render-Todos -Cols @($done | ForEach-Object { $_.col } | Select-Object -Unique)
}

# Tri : a faire d'abord, par priorite (1 en premier) puis par date d'ajout ; terminees a la fin
function Get-SortedTodos {
    $open = @($NB.Todos | Where-Object { -not $_.done } |
        Sort-Object -Property @{ e = { [int]$_.prio } }, @{ e = { if ($_.due) { $_.due } else { '9999' } } }, created)
    $done = @($NB.Todos | Where-Object { $_.done } | Sort-Object -Property doneAt -Descending)
    return @($open + $done)
}
function Get-OpenTodos { @(Get-SortedTodos | Where-Object { -not $_.done }) }
function Get-NextTodo { $open = @(Get-OpenTodos); if ($open.Count) { return $open[0] } }

function Get-PrioColor([int]$p) {
    if ($p -le 3) { return '#E03131' }      # urgent
    if ($p -le 6) { return '#F08C00' }      # normal
    return '#7A869A'                        # quand j'ai le temps
}

# ---------------------------------------------------------------------------
#  Echeances et rappels
# ---------------------------------------------------------------------------
$DayNames = @('dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.')
$DayFull = @('dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi')

function Format-Due([string]$due) {
    if (-not $due) { return '' }
    $d = [datetime]::ParseExact($due, 'yyyy-MM-dd', $null)
    $diff = ($d - (Get-Date).Date).Days
    if ($diff -lt 0) { return "en retard ($($d.ToString('dd/MM')))" }
    if ($diff -eq 0) { return "aujourd'hui" }
    if ($diff -eq 1) { return 'demain' }
    if ($diff -lt 7) { return "$($DayNames[[int]$d.DayOfWeek]) $($d.ToString('dd/MM'))" }
    return $d.ToString('dd/MM/yyyy')
}

function Get-DueColor([string]$due) {
    $diff = ([datetime]::ParseExact($due, 'yyyy-MM-dd', $null) - (Get-Date).Date).Days
    if ($diff -le 0) { return '#E03131' }
    if ($diff -eq 1) { return '#F08C00' }
    return '#5C6B85'
}

function Format-When([string]$iso) {
    if (-not $iso) { return '' }
    $d = [datetime]$iso
    $day = ($d.Date - (Get-Date).Date).Days
    if ($day -eq 0) { return "à $($d.ToString('HH:mm'))" }
    if ($day -eq 1) { return "demain à $($d.ToString('HH:mm'))" }
    return "le $($d.ToString('dd/MM')) à $($d.ToString('HH:mm'))"
}

function Set-TodoDue([string]$id, $date) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $t.due = if ($date) { ([datetime]$date).ToString('yyyy-MM-dd') } else { '' }
    Save-Todos
}

function Set-TodoReminder([string]$id, $when) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $t.remindAt = if ($when) { ([datetime]$when).ToString('s') } else { '' }
    $t.reminded = $false
    Save-Todos
}

# Resume des echeances pour la bulle d'accueil
function Get-DeadlineSummary {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $open = @(Get-OpenTodos)
    $late = @($open | Where-Object { $_.due -and $_.due -lt $today })
    $now = @($open | Where-Object { $_.due -eq $today })
    if (-not $late.Count -and -not $now.Count) { return '' }
    $parts = @()
    if ($now.Count) { $parts += "📅 À rendre aujourd'hui : " + (($now | Select-Object -First 3 | ForEach-Object { "« $(Short-Text $_.text 35) »" }) -join ', ') }
    if ($late.Count) { $parts += "⚠ En retard : " + (($late | Select-Object -First 3 | ForEach-Object { "« $(Short-Text $_.text 35) »" }) -join ', ') }
    return $parts -join "`n"
}

# Verifie toutes les 10 secondes si un rappel doit sonner
function Check-TaskReminders {
    $now = Get-Date
    $back = @(Release-Upcoming)
    if ($back.Count) {
        $msg = "🔁 De retour : « $(Short-Text $back[0].text 50) »"
        if ($back.Count -gt 1) { $msg += " et $($back.Count - 1) autre(s) carte(s) récurrente(s)" }
        Show-Bubble $msg -Seconds 6
    }
    foreach ($t in @($NB.Todos)) {
        if ($t.done -or $t.reminded -or -not $t.remindAt) { continue }
        if ([datetime]$t.remindAt -gt $now) { continue }
        $t.reminded = $true
        Save-Todos
        Render-Todos -Cols $t.col
        Ensure-Visible
        Play-Sound
        $msg = "⏰ Rappel : « $(Short-Text $t.text 80) »"
        if ($t.desc) { $msg += "`n📄 $(Short-Text $t.desc 120)" }
        if ($t.due) { $msg += "`n📅 Échéance : $(Format-Due $t.due)" }
        # (securite : l'identifiant passe par une variable, jamais dans du code genere)
        $script:BubbleCardId = $t.id
        Show-Bubble $msg -Force -AutoHide -Seconds 300 -Buttons @(
            @{ Label = "✅ C'est fait"; Action = { Set-TodoDone $script:BubbleCardId $true }; Primary = $true },
            @{ Label = '⏰ Dans 15 min'; Action = { Set-TodoReminder $script:BubbleCardId ((Get-Date).AddMinutes(15)); Render-Todos; Show-Bubble 'Ok, je te le rappelle dans 15 minutes ⏰' -Force -Seconds 3 } },
            @{ Label = '👍 OK'; Action = { } })
        Show-Tray "⏰ Rappel Orbit" (Short-Text $t.text 60)
        return   # un rappel a la fois ; le suivant sonnera au prochain passage
    }
    # une fois par jour : le point sur les echeances (au demarrage, c'est la bulle d'accueil qui s'en charge)
    $today = $now.ToString('yyyy-MM-dd')
    if ($NB.DeadlineDay -ne $today) {
        $first = -not $NB.DeadlineDay
        $NB.DeadlineDay = $today
        # avec le plan du matin, les echeances du jour y sont deja
        if (-not $first -and -not $Config.MorningPlan) {
            $sum = Get-DeadlineSummary
            if ($sum) { Show-Bubble $sum -Force -Seconds 12 }
        }
    }
}

# Texte court pour les bulles
function Short-Text([string]$text, [int]$max = 60) {
    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt $max) { return (Get-TextStart $text ($max - 1)) + '…' }
    return $text
}

# ---------------------------------------------------------------------------
#  Historique des copier-coller (de la journee uniquement)
# ---------------------------------------------------------------------------
function Get-ClipFile { Join-Path $ClipDir ($NB.ClipDay + '.json') }

function Load-Clips {
    $NB.Clips.Clear()
    # on ne garde que la journee en cours : les fichiers des jours precedents sont supprimes
    Get-ChildItem -Path $ClipDir -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -ne $NB.ClipDay } | Remove-Item -Force -ErrorAction SilentlyContinue
    $f = Get-ClipFile
    if (-not (Test-Path $f)) { return }
    try {
        foreach ($c in (ConvertFrom-Json ([IO.File]::ReadAllText($f)))) {
            [void]$NB.Clips.Add([pscustomobject]@{
                time  = [string]$c.time
                kind  = [string]$c.kind
                text  = [string]$c.text
                files = @($c.files | Where-Object { $_ })
            })
        }
        if ($NB.Clips.Count) { $NB.LastClip = $NB.Clips[0].text }
    } catch { Write-Log "Lecture presse-papiers : $($_.Exception.Message)" }
}

function Load-Favs {
    $NB.Favs.Clear()
    if (-not (Test-Path $FavFile)) { return }
    try {
        foreach ($c in (ConvertFrom-Json ([IO.File]::ReadAllText($FavFile)))) {
            [void]$NB.Favs.Add([pscustomobject]@{
                time  = [string]$c.time
                kind  = [string]$c.kind
                text  = [string]$c.text
                files = @($c.files | Where-Object { $_ })
            })
        }
    } catch { Write-Log "Lecture favoris : $($_.Exception.Message)" }
}

function Save-Favs {
    try { Write-FileSafe $FavFile (ConvertTo-JsonArray $NB.Favs) }
    catch { Write-Log "Ecriture favoris : $($_.Exception.Message)" }
}

function Find-Fav([string]$text) { foreach ($f in $NB.Favs) { if ($f.text -eq $text) { return $f } } }

# Les favoris sont gardes d'un jour a l'autre (contrairement a l'historique du jour)
function Toggle-Fav($c) {
    $f = Find-Fav $c.text
    if ($f) {
        $NB.Favs.Remove($f)
        Show-Bubble "Retiré des favoris." -Force -Seconds 2
    } else {
        [void]$NB.Favs.Insert(0, [pscustomobject]@{
            time  = (Get-Date).ToString('dd/MM/yyyy')
            kind  = $c.kind
            text  = $c.text
            files = @($c.files)
        })
        Show-Bubble "⭐ Ajouté aux favoris : je le garde même après aujourd'hui." -Force -Seconds 3
    }
    Save-Favs
    Render-Clips
}

# L'historique peut peser plus d'1 Mo : au lieu de le reecrire a chaque Ctrl+C,
# on l'enregistre au plus tard 2,5 s apres (et tout de suite a la fermeture). -Now : immediatement.
function Save-Clips([switch]$Now) {
    if (-not $Now -and $NB.ClipSaveTimer) {
        $NB.ClipPending = $true
        if (-not $NB.ClipSaveTimer.IsEnabled) { $NB.ClipSaveTimer.Start() }
        return
    }
    $NB.ClipPending = $false
    if ($NB.ClipSaveTimer) { $NB.ClipSaveTimer.Stop() }
    try { Write-FileSafe (Get-ClipFile) (ConvertTo-JsonArray $NB.Clips) }
    catch { Write-Log "Ecriture presse-papiers : $($_.Exception.Message)" }
}

# Tout ce qui attend encore d'etre ecrit (appele a la fermeture d'Orbit)
function Flush-Notebook {
    if ($NB.ClipPending) { Save-Clips -Now }
    if ($NB.MdPending) { Write-TodoMd }
}

function Add-Clip([string]$kind, [string]$text, [string[]]$files) {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($today -ne $NB.ClipDay) {
        # nouveau jour : l'historique d'hier est jete, inutile de finir de l'ecrire
        $NB.ClipPending = $false
        if ($NB.ClipSaveTimer) { $NB.ClipSaveTimer.Stop() }
        $NB.ClipDay = $today; Load-Clips
    }

    if ($text.Length -gt $NB.MaxClipLen) { $text = (Get-TextStart $text $NB.MaxClipLen) + ' […]' }
    # deja dans l'historique : on le remonte en haut
    foreach ($c in @($NB.Clips)) { if ($c.text -eq $text) { $NB.Clips.Remove($c) } }
    $NB.Clips.Insert(0, [pscustomobject]@{
        time  = (Get-Date).ToString('HH:mm:ss')
        kind  = $kind
        text  = $text
        files = @($files)
    })
    while ($NB.Clips.Count -gt $NB.MaxClips) { $NB.Clips.RemoveAt($NB.Clips.Count - 1) }
    $NB.LastClip = $text
    Save-Clips
    $NB.ClipDirty = $true
    if ($panel.Visibility -eq 'Visible' -and $NB.Tab -eq 'Clip') { Render-Clips }
    else { Update-Tabs }
}

function Check-Clipboard {
    if ($NB.ClipPaused) { return }
    if ($Native) {
        $seq = [OrbitNative]::GetClipboardSequenceNumber()
        if ($seq -eq $NB.ClipSeq) { return }
        $NB.ClipSeq = $seq
    }
    $data = $null
    try { $data = [Windows.Clipboard]::GetDataObject() } catch { $NB.ClipSeq = 0; return }   # occupe : on reessaie
    if (-not $data) { return }
    try {
        # respecte les gestionnaires de mots de passe qui demandent a ne pas etre enregistres
        if ($data.GetDataPresent('ExcludeClipboardContentFromMonitorProcessing') -or
            $data.GetDataPresent('Clipboard Viewer Ignore')) { return }
        if ($data.GetDataPresent('CanIncludeInClipboardHistory')) {
            $ms = $data.GetData('CanIncludeInClipboardHistory')
            if ($ms -is [IO.MemoryStream] -and $ms.Length -ge 4) {
                $buf = New-Object byte[] 4
                $ms.Position = 0; [void]$ms.Read($buf, 0, 4)
                if ([BitConverter]::ToInt32($buf, 0) -eq 0) { return }
            }
        }
        if ($data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
            $files = @($data.GetData([Windows.DataFormats]::FileDrop))
            $text = ($files -join "`n")
            if ($text -and $text -ne $NB.LastClip) { Add-Clip 'files' $text $files }
        } elseif ($data.GetDataPresent([Windows.DataFormats]::UnicodeText)) {
            $text = [string]$data.GetData([Windows.DataFormats]::UnicodeText)
            if ($text.Trim() -and $text -ne $NB.LastClip) { Add-Clip 'text' $text @() }
        }
    } catch { Write-Log "Presse-papiers : $($_.Exception.Message)" }
}

function Copy-Clip($c) {
    try {
        if ($c.kind -eq 'files' -and $c.files.Count) {
            $sc = New-Object System.Collections.Specialized.StringCollection
            foreach ($f in $c.files) { [void]$sc.Add($f) }
            [Windows.Clipboard]::SetFileDropList($sc)
        } else {
            [Windows.Clipboard]::SetText($c.text)
        }
        Show-Bubble "Recopié ! Tu n'as plus qu'à coller (Ctrl+V) 📋" -Force -Seconds 3
    } catch { Show-Bubble "Oups, le presse-papiers est occupé, réessaie 😅" -Force -Seconds 3 }
}

# ---------------------------------------------------------------------------
#  Recherche globale : cartes (titre, description, sous-taches) de tous les
#  tableaux, cartes recurrentes a venir, copier-coller et favoris, archives.
#  Tous les mots doivent y etre ; accents et majuscules ignores.
# ---------------------------------------------------------------------------
$SearchFold = @{
    'à' = 'a'; 'â' = 'a'; 'ä' = 'a'; 'á' = 'a'; 'ã' = 'a'; 'å' = 'a'; 'é' = 'e'; 'è' = 'e'; 'ê' = 'e'; 'ë' = 'e'
    'î' = 'i'; 'ï' = 'i'; 'í' = 'i'; 'ì' = 'i'; 'ô' = 'o'; 'ö' = 'o'; 'ó' = 'o'; 'ò' = 'o'; 'õ' = 'o'; 'ù' = 'u'
    'û' = 'u'; 'ü' = 'u'; 'ú' = 'u'; 'ç' = 'c'; 'ÿ' = 'y'; 'ñ' = 'n'; 'œ' = 'oe'; 'æ' = 'ae'
}
$SearchFold[[string][char]0x2019] = "'"   # apostrophe typographique

# texte en minuscules sans accents, pour comparer « Réunion » et « reunion »
function Get-SearchKey([string]$text) {
    if (-not $text) { return '' }
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $text.ToLowerInvariant().ToCharArray()) {
        $k = [string]$ch
        if ($SearchFold.ContainsKey($k)) { [void]$sb.Append($SearchFold[$k]) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Test-SearchMatch([string]$haystack, [string[]]$words) {
    $h = Get-SearchKey $haystack
    foreach ($w in $words) { if (-not $h.Contains($w)) { return $false } }
    return $true
}

function Find-Everything([string]$query) {
    $words = @((Get-SearchKey $query) -split '\s+' | Where-Object { $_ })
    $r = @{ Cards = @(); Upcoming = @(); Clips = @(); Archives = @(); Notes = @() }
    if (-not $words.Count) { return $r }
    $r.Cards = @($NB.Todos | Where-Object {
            Test-SearchMatch ("$($_.text) $($_.desc) " + (($_.checks | ForEach-Object { $_.text }) -join ' ')) $words } |
        Sort-Object -Property @{ e = { [int][bool]$_.done } }, @{ e = { [int]$_.prio } })
    $r.Upcoming = @($NB.Upcoming | Where-Object { Test-SearchMatch "$($_.text) $($_.desc)" $words })
    $r.Notes = @($NB.Notes | Where-Object { $_ -and (Test-SearchMatch $_.text $words) })
    $seen = @{}
    $r.Clips = @(@($NB.Favs) + @($NB.Clips) | Where-Object {
            $_ -and -not $seen.ContainsKey($_.text) -and ($seen[$_.text] = $true) -and (Test-SearchMatch $_.text $words) } |
        Select-Object -First 40)
    if (Test-Path -LiteralPath $TodoArchive) {
        $section = ''
        $found = foreach ($line in [IO.File]::ReadAllLines($TodoArchive)) {
            if ($line -match '^##\s+(.*)$') { $section = $Matches[1]; continue }
            if ($line -match '^- \[.\]\s*(.+)$' -and (Test-SearchMatch $Matches[1] $words)) {
                [pscustomobject]@{ text = $Matches[1]; section = $section }
            }
        }
        $r.Archives = @(@($found) | Select-Object -Last 30)
        [array]::Reverse($r.Archives)
    }
    return $r
}

function New-SearchResult([string]$title, [string]$sub, [string]$tip, $tag, [scriptblock]$onClick, [bool]$dim = $false) {
    $b = New-Object Windows.Controls.Border
    $b.Margin = '0,0,0,5'; $b.Padding = '10,5,8,6'; $b.CornerRadius = '9'
    $b.Background = '#F6F5FD'; $b.BorderBrush = '#E2DFF5'; $b.BorderThickness = '1'
    $sp = New-Object Windows.Controls.StackPanel
    $t1 = New-Object Windows.Controls.TextBlock
    $t1.Text = $title; $t1.TextWrapping = 'Wrap'; $t1.FontWeight = 'SemiBold'
    $t1.Foreground = if ($dim) { '#9A98B0' } else { '#1E1B3A' }
    if ($dim) { $t1.TextDecorations = [Windows.TextDecorations]::Strikethrough }
    [void]$sp.Children.Add($t1)
    if ($sub) {
        $t2 = New-Object Windows.Controls.TextBlock
        $t2.Text = $sub; $t2.FontSize = 11.5; $t2.Foreground = '#7A7794'; $t2.TextWrapping = 'Wrap'; $t2.MaxHeight = 34
        $t2.TextTrimming = 'CharacterEllipsis'
        [void]$sp.Children.Add($t2)
    }
    $b.Child = $sp
    if ($tip) { $b.ToolTip = $tip }
    if ($onClick) { $b.Cursor = 'Hand'; $b.Tag = $tag; $b.Add_MouseLeftButtonUp($onClick) }
    return $b
}

# extrait de la description autour du premier mot cherche
function Get-Snippet([string]$text, [string]$word, [int]$len = 90) {
    $flat = ($text -replace '\s+', ' ').Trim()
    if (-not $flat) { return '' }
    $i = (Get-SearchKey $flat).IndexOf($word)
    if ($i -lt 0 -or $flat.Length -le $len) { return (Short-Text $flat $len) }
    $start = [math]::Max(0, $i - 25)
    if ([char]::IsLowSurrogate($flat[$start])) { $start++ }   # ne pas commencer au milieu d'un emoji
    $out = Get-TextStart $flat.Substring($start) $len
    if ($start -gt 0) { $out = '…' + $out }
    if ($start + $len -lt $flat.Length) { $out += '…' }
    return $out
}

function Render-Search {
    if (-not $pn.SearchList) { return }
    $pn.SearchList.Children.Clear()
    $q = $pn.SearchBox.Text.Trim()
    if ($q.Length -lt 2) {
        $pn.SearchCount.Text = 'Plusieurs mots : ils doivent tous y être. Les accents et majuscules ne comptent pas.'
        return
    }
    $r = Find-Everything $q
    $first = @((Get-SearchKey $q) -split '\s+' | Where-Object { $_ })[0]
    if ($r.Cards.Count) {
        [void]$pn.SearchList.Children.Add((New-SectionTitle "🗂 Cartes ($($r.Cards.Count))"))
        foreach ($t in ($r.Cards | Select-Object -First 60)) {
            $b = Get-Board $t.board
            $col = if ($b) { Get-Column $b $t.col }
            $sub = "$(if ($b) { $b.name }) › $(if ($col) { $col.name })"
            if ($t.due -and -not $t.done) { $sub += " · 📅 $(Format-Due $t.due)" }
            if ($t.checks.Count) { $sub += " · ☑ $(@($t.checks | Where-Object { $_.done }).Count)/$($t.checks.Count)" }
            $snip = Get-Snippet $t.desc $first
            if ($snip) { $sub += "`n📄 $snip" }
            [void]$pn.SearchList.Children.Add((New-SearchResult "P$($t.prio)  $($t.text)" $sub 'Clic : ouvrir la carte' $t.id {
                        param($s, $e) Invoke-Safe { Reveal-Card $s.Tag } } ([bool]$t.done)))
        }
    }
    if ($r.Notes.Count) {
        [void]$pn.SearchList.Children.Add((New-SectionTitle "📝 Notes ($($r.Notes.Count))"))
        foreach ($nt in $r.Notes) {
            [void]$pn.SearchList.Children.Add((New-SearchResult (Get-NoteTitle $nt 90) "$(([datetime]$nt.updated).ToString('dd/MM à HH:mm'))`n$(Get-Snippet $nt.text $first)" 'Clic : ouvrir la note' $nt.id {
                        param($s, $e) Invoke-Safe { Show-QuickNote $s.Tag } }))
        }
    }
    if ($r.Upcoming.Count) {
        [void]$pn.SearchList.Children.Add((New-SectionTitle "🔁 Cartes récurrentes à venir ($($r.Upcoming.Count))"))
        foreach ($u in $r.Upcoming) {
            $b = Get-Board $u.board
            [void]$pn.SearchList.Children.Add((New-SearchResult $u.text "Revient $(Format-Due $u.showAt)$(if ($b) { " dans « $($b.name) »" })" $null $null $null))
        }
    }
    if ($r.Clips.Count) {
        [void]$pn.SearchList.Children.Add((New-SectionTitle "📋 Copier-coller ($($r.Clips.Count))"))
        foreach ($c in $r.Clips) {
            $fav = $NB.Favs -contains $c
            $title = "$(if ($fav) { '⭐ ' })$(Short-Text (($c.text -replace '\s+', ' ').Trim()) 120)"
            [void]$pn.SearchList.Children.Add((New-SearchResult $title $(if ($c.time) { "à $($c.time)" }) 'Clic : recopier' $c {
                        param($s, $e) Invoke-Safe { Copy-Clip $s.Tag } }))
        }
    }
    if ($r.Archives.Count) {
        [void]$pn.SearchList.Children.Add((New-SectionTitle "📦 Archives ($($r.Archives.Count))"))
        foreach ($a in $r.Archives) {
            [void]$pn.SearchList.Children.Add((New-SearchResult $a.text "archivée : $($a.section)" 'Clic : recopier le texte' ([pscustomobject]@{ kind = 'text'; text = $a.text; files = @() }) {
                        param($s, $e) Invoke-Safe { Copy-Clip $s.Tag } } $true))
        }
    }
    $n = $r.Cards.Count + $r.Notes.Count + $r.Upcoming.Count + $r.Clips.Count + $r.Archives.Count
    if (-not $n) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = "Rien trouvé pour « $q »"; $empty.Foreground = '#9A98B0'; $empty.Margin = '4,10,4,0'; $empty.TextAlignment = 'Center'
        [void]$pn.SearchList.Children.Add($empty)
    }
    $pn.SearchCount.Text = "$n résultat(s) · clic sur une carte pour l'ouvrir, sur un copier-coller pour le recopier"
}

# Ouvre une carte trouvee : bon tableau, editeur ouvert, et on la fait defiler a l'ecran
function Reveal-Card([string]$id) {
    $t = Find-Todo $id
    if (-not $t) { return }
    if ($NB.EditId) { End-EditTodo -NoRender }
    $NB.BoardId = $t.board
    Select-Tab 'Todo'
    Start-EditTodo $id
    $NB.RevealId = $id
    [void]$panel.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Loaded, [Action]{ Invoke-Safe { Show-RevealedCard } })
}

function Show-RevealedCard {
    foreach ($colBox in $pn.TodoList.Children) {
        if ($colBox.Tag -isnot [hashtable]) { continue }
        foreach ($el in $colBox.Tag.Stack.Children) {
            if ($el.Tag -eq $NB.RevealId) { $el.BringIntoView(); return }
        }
    }
}

# ---------------------------------------------------------------------------
#  Fenetre du carnet
# ---------------------------------------------------------------------------
[xml]$panelXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Carnet d'Orbit" Width="380" Height="600" MinWidth="380" MinHeight="420"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="CanResizeWithGrip" UseLayoutRounding="True"
        FontFamily="Segoe UI" FontSize="13">
  <Border Margin="6" CornerRadius="18" Background="#FFFDFBFF" BorderBrush="#1E1B3A" BorderThickness="2.5">
    <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="-45" Opacity="0.25"/></Border.Effect>
    <DockPanel LastChildFill="True">
      <!-- en-tete (on peut deplacer la fenetre en le tirant) -->
      <Grid x:Name="Header" DockPanel.Dock="Top" Background="Transparent" Margin="16,12,10,4">
        <TextBlock Text="🛰 Carnet d'Orbit" FontFamily="Comic Sans MS, Segoe UI" FontSize="17"
                   FontWeight="Bold" Foreground="#1E1B3A" VerticalAlignment="Center"/>
        <Button x:Name="CloseBtn" Content="✕" HorizontalAlignment="Right" Width="30" Height="30"
                Background="Transparent" BorderThickness="0" FontSize="14" Cursor="Hand"
                ToolTip="Fermer (Échap)"/>
      </Grid>

      <!-- onglets -->
      <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="14,4,14,8">
        <Button x:Name="TabTodo" Padding="12,5" Margin="0,0,6,0" Cursor="Hand" BorderThickness="2"
                BorderBrush="#1E1B3A" FontWeight="SemiBold"/>
        <Button x:Name="TabClip" Padding="12,5" Cursor="Hand" BorderThickness="2"
                BorderBrush="#1E1B3A" FontWeight="SemiBold"/>
        <Button x:Name="TabNotes" Padding="12,5" Margin="6,0,0,0" Cursor="Hand" BorderThickness="2"
                BorderBrush="#1E1B3A" FontWeight="SemiBold"/>
        <Button x:Name="TabSearch" Content="🔍" Padding="10,5" Margin="6,0,0,0" Cursor="Hand" BorderThickness="2"
                BorderBrush="#1E1B3A" FontWeight="SemiBold" ToolTip="Rechercher partout (Ctrl+F)"/>
      </StackPanel>

      <Grid>
        <!-- ===== Tableaux Kanban ===== -->
        <DockPanel x:Name="TodoPanel" Margin="14,0,14,12">
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <ComboBox x:Name="BoardPick" Width="230" VerticalContentAlignment="Center" FontWeight="SemiBold"
                      ToolTip="Choisir le tableau à afficher"/>
            <Button x:Name="BoardAdd" Grid.Column="1" Content="＋ Tableau" Padding="10,4" Margin="6,0,0,0"
                    Background="#6C5CE7" Foreground="White" BorderThickness="0" Cursor="Hand" ToolTip="Créer un nouveau tableau"/>
            <Button x:Name="BoardRename" Grid.Column="2" Content="✏" Width="32" Margin="6,0,0,0"
                    Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Renommer ce tableau"/>
            <Button x:Name="BoardDel" Grid.Column="3" Content="🗑" Width="32" Margin="6,0,0,0"
                    Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Supprimer ce tableau"/>
            <Button x:Name="BoardHistory" Grid.Column="4" Content="🕘" Width="32" Margin="6,0,0,0"
                    Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Revenir à une sauvegarde (une par jour, 7 jours)"/>
          </Grid>
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TodoInput" Padding="8,6" BorderBrush="#1E1B3A" BorderThickness="2"
                     VerticalContentAlignment="Center"/>
            <TextBlock x:Name="TodoHint" Text="Ajout rapide dans la 1re colonne… (Entrée)" Margin="12,0,0,0"
                       VerticalAlignment="Center" Foreground="#9A98B0" IsHitTestVisible="False"/>
            <ComboBox x:Name="TodoPrio" Grid.Column="1" Width="58" Margin="6,0,0,0" VerticalContentAlignment="Center"
                      ToolTip="Priorité : 1 = la plus urgente, 10 = la moins urgente. Astuce : tape « !2 » dans le texte."/>
            <Button x:Name="TodoAdd" Grid.Column="2" Content="＋" Width="38" Margin="6,0,0,0"
                    FontSize="16" FontWeight="Bold" Cursor="Hand" Foreground="White"
                    Background="#6C5CE7" BorderBrush="#1E1B3A" BorderThickness="2"/>
          </Grid>
          <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <TextBlock x:Name="TodoCount" VerticalAlignment="Center" Foreground="#6B6880" TextTrimming="CharacterEllipsis" Margin="0,0,190,0"/>
            <Button x:Name="TodoClear" Content="🧹 Archiver les terminées" HorizontalAlignment="Right"
                    Padding="10,4" Cursor="Hand" Background="#EEEEF5" BorderThickness="0"/>
          </Grid>
          <ScrollViewer x:Name="KanbanScroll" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
            <StackPanel x:Name="TodoList" Orientation="Horizontal"/>
          </ScrollViewer>
        </DockPanel>

        <!-- ===== Copier-coller ===== -->
        <DockPanel x:Name="ClipPanel" Margin="14,0,14,12" Visibility="Collapsed">
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <TextBox x:Name="ClipSearch" Padding="8,6" BorderBrush="#1E1B3A" BorderThickness="2"
                     VerticalContentAlignment="Center"/>
            <TextBlock x:Name="ClipHint" Text="🔎 Rechercher dans mes copier-coller…" Margin="12,0,0,0"
                       VerticalAlignment="Center" Foreground="#9A98B0" IsHitTestVisible="False"/>
          </Grid>
          <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="ClipCount" VerticalAlignment="Center" Foreground="#6B6880" Margin="0,0,10,0"/>
              <CheckBox x:Name="ClipPause" Content="Pause" VerticalAlignment="Center"
                        ToolTip="Ne plus enregistrer les copier-coller pour l'instant"/>
            </StackPanel>
            <Button x:Name="ClipClear" Content="🗑 Tout effacer" HorizontalAlignment="Right"
                    Padding="10,4" Cursor="Hand" Background="#EEEEF5" BorderThickness="0"/>
          </Grid>
          <TextBlock DockPanel.Dock="Top" Text="Clique sur un élément pour le recopier." FontSize="11.5"
                     Foreground="#9A98B0" Margin="2,0,0,6"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="ClipList"/>
          </ScrollViewer>
        </DockPanel>

        <!-- ===== Notes rapides ===== -->
        <DockPanel x:Name="NotesPanel" Margin="14,0,14,12" Visibility="Collapsed">
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <Button x:Name="NotesAdd" Content="＋ Nouvelle note" HorizontalAlignment="Left" Padding="12,5" Cursor="Hand"
                    Background="#FFE066" BorderBrush="#1E1B3A" BorderThickness="2" FontWeight="SemiBold"/>
            <Button x:Name="NotesBackup" Content="🕘 Sauvegardes" HorizontalAlignment="Right" Padding="10,5" Cursor="Hand"
                    Background="#EEEEF5" BorderThickness="0" ToolTip="Restaurer, corbeille, copie automatique, enregistrer une copie"/>
          </Grid>
          <TextBlock x:Name="NotesCount" DockPanel.Dock="Bottom" Margin="0,8,0,0" Foreground="#6B6880"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="NotesList"/>
          </ScrollViewer>
        </DockPanel>

        <!-- ===== Recherche globale ===== -->
        <DockPanel x:Name="SearchPanel" Margin="14,0,14,12" Visibility="Collapsed">
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <TextBox x:Name="SearchBox" Padding="8,6" BorderBrush="#1E1B3A" BorderThickness="2"
                     VerticalContentAlignment="Center"/>
            <TextBlock x:Name="SearchHint" Text="🔍 Chercher dans les cartes, notes, copier-coller, archives…" Margin="12,0,0,0"
                       VerticalAlignment="Center" Foreground="#9A98B0" IsHitTestVisible="False"/>
          </Grid>
          <TextBlock x:Name="SearchCount" DockPanel.Dock="Bottom" Margin="0,8,0,0" Foreground="#6B6880"
                     Text="Plusieurs mots : ils doivent tous y être. Les accents et majuscules ne comptent pas."/>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="SearchList"/>
          </ScrollViewer>
        </DockPanel>
      </Grid>
    </DockPanel>
  </Border>
</Window>
'@

# La fenetre du carnet est construite a la demande (Initialize-Notebook) :
# a la premiere ouverture, ou quelques secondes apres le demarrage d'Orbit.
$panel = $null
$pn = @{}

function Update-Tabs {
    if (-not $panel) { return }
    $open = @($NB.Todos | Where-Object { -not $_.done }).Count
    $pn.TabTodo.Content = "🗂 Tableaux ($open)"
    $pn.TabClip.Content = "📋 Copier-coller ($($NB.Clips.Count))"
    $on = '#FFD166'; $off = '#FFFFFF'
    $pn.TabTodo.Background = if ($NB.Tab -eq 'Todo') { $on } else { $off }
    $pn.TabClip.Background = if ($NB.Tab -eq 'Clip') { $on } else { $off }
    $pn.TabSearch.Background = if ($NB.Tab -eq 'Search') { $on } else { $off }
    $pn.TabNotes.Background = if ($NB.Tab -eq 'Notes') { $on } else { $off }
    $pn.TabNotes.Content = "📝 Notes ($(@($NB.Notes).Count))"
}

function Format-Day([string]$iso) {
    try {
        $d = [datetime]::Parse($iso)
        if ($d.Date -eq (Get-Date).Date) { return $d.ToString('HH:mm') }
        if ($d.Date -eq (Get-Date).Date.AddDays(-1)) { return 'hier' }
        return $d.ToString('dd/MM')
    } catch { return '' }
}

# ---------------------------------------------------------------------------
#  Affichage des tableaux : une colonne = une liste de cartes. On glisse les
#  cartes d'une colonne a l'autre (ou clic droit > Deplacer vers).
# ---------------------------------------------------------------------------
$KanbanColW = 244

function Get-BoardLabel($b) {
    $n = 0
    foreach ($t in $NB.Todos) { if ($t.board -eq $b.id -and -not $t.done) { $n++ } }
    return "🗂 $($b.name)  ($n)"
}

# -Cols : ne redessine que ces colonnes (ajout, deplacement, modification d'une carte...).
# Sans -Cols, ou si le tableau affiche a change, tout est redessine. Fenetre fermee :
# rien n'est dessine, ce sera fait a la prochaine ouverture.
function Render-Todos([string[]]$Cols) {
    if (-not $panel.IsVisible -or $NB.Tab -ne 'Todo') { $NB.TodoDirty = $true; Update-Tabs; return }
    $board = Get-CurrentBoard
    if ($Cols -and -not $NB.TodoDirty -and $NB.RenderedBoard -eq $board.id) {
        $want = @($Cols | Where-Object { $_ -and (Get-Column $board $_) } | Select-Object -Unique)
        $found = 0
        for ($i = 0; $i -lt $pn.TodoList.Children.Count; $i++) {
            $el = $pn.TodoList.Children[$i]
            if ($el.Tag -is [hashtable] -and $want -contains $el.Tag.Col) {
                $pn.TodoList.Children.RemoveAt($i)
                $pn.TodoList.Children.Insert($i, (New-KanbanColumn $board (Get-Column $board $el.Tag.Col)))
                $found++
            }
        }
        if ($found -eq $want.Count) {
            $NB.Rendering = $true
            foreach ($it in $pn.BoardPick.Items) { $b = Get-Board ([string]$it.Tag); if ($b) { $it.Content = Get-BoardLabel $b } }
            $NB.Rendering = $false
            Update-KanbanFooter $board
            return
        }
    }
    $NB.TodoDirty = $false
    $NB.RenderedBoard = $board.id
    $NB.Rendering = $true
    $pn.BoardPick.Items.Clear()
    foreach ($b in $NB.Boards) {
        $it = New-Object Windows.Controls.ComboBoxItem
        $it.Content = Get-BoardLabel $b; $it.Tag = $b.id
        [void]$pn.BoardPick.Items.Add($it)
        if ($b.id -eq $board.id) { $pn.BoardPick.SelectedItem = $it }
    }
    $NB.Rendering = $false
    $pn.BoardDel.IsEnabled = $NB.Boards.Count -gt 1

    $pn.TodoList.Children.Clear()
    foreach ($col in $board.columns) { [void]$pn.TodoList.Children.Add((New-KanbanColumn $board $col)) }
    $add = New-Object Windows.Controls.Button
    $add.Content = "＋ Ajouter une colonne"; $add.Width = 170; $add.Height = 38; $add.VerticalAlignment = 'Top'
    $add.Background = '#F3F1FF'; $add.BorderBrush = '#C9C3F5'; $add.BorderThickness = '1.5'; $add.Cursor = 'Hand'
    $add.Add_Click({ Invoke-Safe { Add-BoardColumn } })
    [void]$pn.TodoList.Children.Add($add)
    Update-KanbanFooter $board
}

function Update-KanbanFooter($board) {
    $cards = @($NB.Todos | Where-Object { $_.board -eq $board.id })
    $done = @($cards | Where-Object { $_.done }).Count
    $txt = "$($cards.Count) carte(s), $done terminée(s) · glisse les cartes d'une colonne à l'autre, clic droit pour plus d'options"
    $up = Get-BoardUpcoming $board.id
    if ($up.Count) {
        $txt = "🔁 $($up.Count) à venir · $txt"
        $pn.TodoCount.Cursor = 'Hand'
        $pn.TodoCount.ToolTip = (($up | ForEach-Object { "🔁 $($_.text) — $(Format-Due $_.showAt)" }) -join "`n") + "`n(clic pour gérer)"
    } else { $pn.TodoCount.Cursor = $null; $pn.TodoCount.ToolTip = $null }
    $pn.TodoCount.Text = $txt
    $pn.TodoClear.IsEnabled = $done -gt 0
    Update-Tabs
}

function New-KanbanColumn($board, $col) {
    $cards = @(Get-ColumnCards $col.id)
    $box = New-Object Windows.Controls.Border
    $box.Width = $KanbanColW; $box.Margin = '0,0,10,0'; $box.Padding = '8'; $box.CornerRadius = '12'
    $bg = if ($col.done) { '#E8F6EE' } else { '#EEF0F6' }
    $box.Background = $bg; $box.BorderBrush = '#D5D9E6'; $box.BorderThickness = '1'
    $box.AllowDrop = $true
    $dock = New-Object Windows.Controls.DockPanel

    # en-tete : nom (double-clic pour renommer), nombre de cartes, menu
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = '2,0,0,6'
    $menu = New-Object Windows.Controls.Button
    $menu.Content = '⋯'; $menu.Width = 26; $menu.Background = 'Transparent'; $menu.BorderThickness = '0'
    $menu.FontWeight = 'Bold'; $menu.Cursor = 'Hand'; $menu.Tag = $col.id; $menu.ToolTip = 'Options de la colonne'
    $menu.Add_Click({ param($s, $e) Invoke-Safe { Show-ColumnMenu $s } })
    [Windows.Controls.DockPanel]::SetDock($menu, 'Right')
    [void]$head.Children.Add($menu)
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = "$(if ($col.done) { '✅ ' })$($col.name)  "
    $title.FontWeight = 'Bold'; $title.FontSize = 13.5; $title.Foreground = '#1E1B3A'; $title.VerticalAlignment = 'Center'
    $title.Tag = $col.id; $title.ToolTip = 'Double-clic pour renommer'
    $title.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -eq 2) { Invoke-Safe { Rename-BoardColumn $s.Tag } } })
    $count = New-Object Windows.Documents.Run
    $count.Text = "$($cards.Count)"; $count.FontWeight = 'Normal'; $count.Foreground = '#8A87A3'; $count.FontSize = 12
    $title.Inlines.Add($count)
    [void]$head.Children.Add($title)
    [Windows.Controls.DockPanel]::SetDock($head, 'Top')
    [void]$dock.Children.Add($head)

    # pied : ajout d'une carte dans cette colonne
    $foot = New-Object Windows.Controls.Grid
    $foot.Margin = '0,6,0,0'
    $addBox = New-Object Windows.Controls.TextBox
    $addBox.Padding = '6,4'; $addBox.BorderBrush = '#C9C3F5'; $addBox.BorderThickness = '1.2'
    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = '＋ Ajouter une carte…'; $hint.Margin = '8,0,0,0'; $hint.VerticalAlignment = 'Center'
    $hint.Foreground = '#9A98B0'; $hint.IsHitTestVisible = $false
    $addBox.Tag = @{ Col = $col.id; Hint = $hint }
    $addBox.Add_TextChanged({ param($s, $e) $s.Tag.Hint.Visibility = if ($s.Text) { 'Collapsed' } else { 'Visible' } })
    $addBox.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') { $e.Handled = $true; $NB.FocusCol = $s.Tag.Col; Invoke-Safe { Add-Todo $s.Text $DefaultPrio $s.Tag.Col } }
    })
    # apres un ajout, le curseur reste dans cette colonne pour enchainer les cartes
    if ($NB.FocusCol -eq $col.id) { $NB.FocusCol = ''; $addBox.Add_Loaded({ param($s, $e) $s.Focus() | Out-Null }) }
    [void]$foot.Children.Add($addBox); [void]$foot.Children.Add($hint)
    [Windows.Controls.DockPanel]::SetDock($foot, 'Bottom')
    [void]$dock.Children.Add($foot)

    # cartes
    $stack = New-Object Windows.Controls.StackPanel
    $stack.MinHeight = 40
    foreach ($t in $cards) { [void]$stack.Children.Add((New-KanbanCard $t)) }
    if (-not $cards.Count) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = 'Glisse une carte ici'; $empty.FontStyle = 'Italic'; $empty.Foreground = '#A9A6BD'
        $empty.HorizontalAlignment = 'Center'; $empty.Margin = '0,10,0,0'
        [void]$stack.Children.Add($empty)
    }
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $stack
    [void]$dock.Children.Add($sv)
    $box.Child = $dock

    # glisser-deposer
    $box.Tag = @{ Col = $col.id; Stack = $stack; Bg = $bg }
    $box.Add_DragOver({ param($s, $e) $e.Effects = if ($e.Data.GetDataPresent('OrbitCard')) { 'Move' } else { 'None' }; $e.Handled = $true })
    $box.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent('OrbitCard')) { $s.Background = '#DCE3FF' } })
    $box.Add_DragLeave({ param($s, $e) $s.Background = $s.Tag.Bg })
    $box.Add_Drop({
        param($s, $e)
        Invoke-Safe {
            $s.Background = $s.Tag.Bg
            $id = [string]$e.Data.GetData('OrbitCard')
            if (-not $id) { return }
            # position : nombre de cartes (autres que celle deplacee) au-dessus du point de depot
            $stack = $s.Tag.Stack
            $y = $e.GetPosition($stack).Y
            $idx = 0
            foreach ($ch in $stack.Children) {
                if ($ch -is [Windows.Controls.Border] -and $ch.Tag -and $ch.Tag -ne $id) {
                    $top = $ch.TranslatePoint((New-Object Windows.Point 0, 0), $stack).Y
                    if ($y -gt $top + $ch.ActualHeight / 2) { $idx++ }
                }
            }
            # le deplacement est fait une fois le glisser termine (voir New-KanbanCard)
            $NB.PendingMove = @{ Id = $id; Col = $s.Tag.Col; Index = $idx }
        }
    })
    return $box
}

function New-KanbanCard($t) {
    $card = New-Object Windows.Controls.Border
    $card.Background = 'White'; $card.CornerRadius = '8'; $card.Padding = '8,6,4,7'; $card.Margin = '0,0,0,6'
    $card.BorderBrush = '#DADDE8'; $card.BorderThickness = '1'; $card.Tag = $t.id
    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 4; $shadow.ShadowDepth = 1; $shadow.Opacity = 0.12
    $card.Effect = $shadow
    if ($NB.EditId -eq $t.id) {
        $card.Child = New-TodoEditor $t
        $card.BorderBrush = '#6C5CE7'; $card.BorderThickness = '1.5'
        return $card
    }
    $card.Cursor = 'Hand'
    $card.ToolTip = 'Clic : modifier · Glisser : déplacer · Clic droit : plus d''options'

    $g = New-Object Windows.Controls.Grid
    foreach ($w in 'Auto', '*', 'Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; $g.ColumnDefinitions.Add($cd) }

    # pastille de priorite : un clic ouvre le choix de 1 a 10
    $pb = New-Object Windows.Controls.Button
    $pb.Content = "P$($t.prio)"; $pb.Tag = $t.id
    $pb.Width = 30; $pb.Height = 19; $pb.Margin = '0,0,6,0'; $pb.VerticalAlignment = 'Top'
    $pb.FontSize = 10.5; $pb.FontWeight = 'Bold'; $pb.Foreground = 'White'; $pb.BorderThickness = '0'
    $pb.Background = if ($t.done) { '#C9C7D6' } else { Get-PrioColor $t.prio }
    $pb.Cursor = 'Hand'; $pb.ToolTip = 'Priorité (1 = la plus urgente). Clic pour changer.'
    $pb.Add_Click({ param($s, $e) Invoke-Safe { Show-PrioMenu $s } })
    [void]$g.Children.Add($pb)

    $content = New-Object Windows.Controls.StackPanel
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $t.text; $tb.TextWrapping = 'Wrap'
    if ($t.done) { $tb.TextDecorations = [Windows.TextDecorations]::Strikethrough; $tb.Foreground = '#9A98B0' }
    else { $tb.Foreground = '#1E1B3A' }
    [void]$content.Children.Add($tb)
    if ($t.desc) {
        $dp = New-Object Windows.Controls.TextBlock
        $dp.Text = '📄 ' + (($t.desc -replace '\s+', ' ').Trim())
        $dp.FontSize = 11.5; $dp.Foreground = '#7A7794'; $dp.Margin = '0,2,0,0'
        $dp.TextWrapping = 'Wrap'; $dp.MaxHeight = 32; $dp.TextTrimming = 'CharacterEllipsis'
        [void]$content.Children.Add($dp)
    }
    $inFocus = $NB.FocusCards.Contains($t.id) -and -not $t.done
    if ($t.pomos -or $inFocus -or $t.checks.Count -or $t.repeat) {
        $fm = New-Object Windows.Controls.WrapPanel
        $fm.Margin = '0,3,0,0'
        if ($inFocus) {
            $b = New-Object Windows.Controls.Border
            $b.Background = '#FFE8D6'; $b.CornerRadius = '6'; $b.Padding = '5,0'; $b.Margin = '0,0,8,0'
            $bt = New-Object Windows.Controls.TextBlock
            $bt.Text = if ($O.State -eq 'Focus') { '🎯 en focus' } else { '🎯 prochain focus' }
            $bt.FontSize = 11; $bt.FontWeight = 'SemiBold'; $bt.Foreground = '#C2410C'
            $b.Child = $bt
            [void]$fm.Children.Add($b)
        }
        if ($t.pomos) {
            $b = New-Object Windows.Controls.TextBlock
            $b.Text = "🍅 $($t.pomos) · $(Format-FocusTime $t.focusMin)"
            $b.FontSize = 11; $b.Foreground = '#B4532A'
            $b.ToolTip = "$($t.pomos) session(s) de focus sur cette carte$(if ($t.lastFocus) { ", la dernière le $(([datetime]$t.lastFocus).ToString('dd/MM à HH:mm'))" })"
            [void]$fm.Children.Add($b)
        }
        if ($t.checks.Count) {
            $n = @($t.checks | Where-Object { $_.done }).Count
            $b = New-Object Windows.Controls.TextBlock
            $b.Text = "☑ $n/$($t.checks.Count)"; $b.FontSize = 11; $b.Margin = '0,0,8,0'
            $b.Foreground = if ($n -eq $t.checks.Count) { '#2F9E44' } else { '#5C6B85' }
            $b.ToolTip = ($t.checks | ForEach-Object { "$(if ($_.done) { '☑' } else { '☐' }) $($_.text)" }) -join "`n"
            [void]$fm.Children.Add($b)
        }
        if ($t.repeat) {
            $b = New-Object Windows.Controls.TextBlock
            $b.Text = '🔁'; $b.FontSize = 11; $b.Margin = '0,0,8,0'; $b.Foreground = '#5C6B85'
            $b.ToolTip = "Revient $(Get-RepeatLabel $t)"
            [void]$fm.Children.Add($b)
        }
        [void]$content.Children.Add($fm)
    }
    if (($t.due -or $t.remindAt) -and -not $t.done) {
        $meta = New-Object Windows.Controls.WrapPanel
        $meta.Margin = '0,3,0,0'
        if ($t.due) {
            $b = New-Object Windows.Controls.TextBlock
            $b.Text = "📅 $(Format-Due $t.due)"
            $b.FontSize = 11; $b.FontWeight = 'SemiBold'; $b.Foreground = Get-DueColor $t.due; $b.Margin = '0,0,10,0'
            [void]$meta.Children.Add($b)
        }
        if ($t.remindAt) {
            $b = New-Object Windows.Controls.TextBlock
            $b.Text = "⏰ $(Format-When $t.remindAt)"
            $b.FontSize = 11; $b.Foreground = if ($t.reminded) { '#B0AEC4' } else { '#5C6B85' }
            [void]$meta.Children.Add($b)
        }
        [void]$content.Children.Add($meta)
    }
    [Windows.Controls.Grid]::SetColumn($content, 1)
    [void]$g.Children.Add($content)

    $del = New-Object Windows.Controls.Button
    $del.Content = '✕'; $del.Tag = $t.id; $del.Width = 20; $del.Height = 19; $del.VerticalAlignment = 'Top'
    $del.Background = 'Transparent'; $del.BorderThickness = '0'; $del.Foreground = '#B0AEC4'
    $del.Cursor = 'Hand'; $del.ToolTip = 'Supprimer la carte'
    $del.Add_Click({ param($s, $e) Invoke-Safe { Remove-Todo $s.Tag } })
    $side = New-Object Windows.Controls.StackPanel
    [void]$side.Children.Add($del)
    if (-not $t.done) {
        # bouton cible : lier / delier la carte au focus
        $fb = New-Object Windows.Controls.Button
        $fb.Content = '🎯'; $fb.Tag = $t.id; $fb.Width = 20; $fb.Height = 19; $fb.Margin = '0,2,0,0'
        $fb.BorderThickness = '0'; $fb.Cursor = 'Hand'; $fb.FontSize = 11
        $fb.Background = if ($inFocus) { '#FFE8D6' } else { 'Transparent' }
        $fb.Opacity = if ($inFocus) { 1 } else { 0.35 }
        $fb.ToolTip = if ($inFocus) { 'Retirer cette carte du focus' } else { 'Lier cette carte à mon focus' }
        $fb.Add_Click({ param($s, $e) Invoke-Safe { Toggle-CardFocus $s.Tag } })
        [void]$side.Children.Add($fb)
    }
    [Windows.Controls.Grid]::SetColumn($side, 2)
    [void]$g.Children.Add($side)
    $card.Child = $g
    if ($inFocus) { $card.BorderBrush = '#FF9F43'; $card.BorderThickness = '1.8' }

    # clic = modifier, glisser = deplacer, clic droit = menu
    $card.Add_PreviewMouseLeftButtonDown({ param($s, $e) $NB.DragId = $s.Tag; $NB.DragStart = $e.GetPosition($panel) })
    $card.Add_MouseMove({
        param($s, $e)
        if ($e.LeftButton -ne 'Pressed' -or $NB.DragId -ne $s.Tag -or -not $NB.DragStart) { return }
        $p = $e.GetPosition($panel)
        if ([math]::Abs($p.X - $NB.DragStart.X) + [math]::Abs($p.Y - $NB.DragStart.Y) -lt 6) { return }
        $NB.DragId = ''; $NB.PendingMove = $null
        $s.Opacity = 0.5
        [void][Windows.DragDrop]::DoDragDrop($s, (New-Object Windows.DataObject('OrbitCard', [string]$s.Tag)), 'Move')
        $s.Opacity = 1
        $m = $NB.PendingMove; $NB.PendingMove = $null
        if ($m) { Invoke-Safe { Move-Card $m.Id $m.Col $m.Index } }
    })
    $card.Add_MouseLeftButtonUp({ param($s, $e) if ($NB.DragId -eq $s.Tag) { $NB.DragId = ''; Invoke-Safe { Start-EditTodo $s.Tag } } })
    $card.Add_MouseRightButtonUp({ param($s, $e) $e.Handled = $true; Invoke-Safe { Show-CardMenu $s } })
    return $card
}

# --- menus ---
function New-TaggedItem([string]$header, $tag, [scriptblock]$onClick) {
    $mi = New-Object Windows.Controls.MenuItem
    $mi.Header = $header; $mi.Tag = $tag
    if ($onClick) { $mi.Add_Click($onClick) }
    return $mi
}

function Show-CardMenu($card) {
    $t = Find-Todo $card.Tag
    if (-not $t) { return }
    $board = Get-Board $t.board
    $m = New-Object Windows.Controls.ContextMenu
    [void]$m.Items.Add((New-TaggedItem '✏  Modifier' $t.id { param($s, $e) Invoke-Safe { Start-EditTodo $s.Tag } }))
    if (-not $t.done) {
        $fl = if ($NB.FocusCards.Contains($t.id)) { '🎯  Retirer du focus' } else { '🎯  Lier à mon focus' }
        [void]$m.Items.Add((New-TaggedItem $fl $t.id { param($s, $e) Invoke-Safe { Toggle-CardFocus $s.Tag } }))
    }
    $mv = New-Object Windows.Controls.MenuItem; $mv.Header = '➡  Déplacer vers'
    foreach ($c in $board.columns) {
        if ($c.id -eq $t.col) { continue }
        [void]$mv.Items.Add((New-TaggedItem "$(if ($c.done) { '✅ ' })$($c.name)" "$($t.id)|$($c.id)" { param($s, $e) Invoke-Safe { $p = $s.Tag.Split('|'); Move-Card $p[0] $p[1] } }))
    }
    [void]$m.Items.Add($mv)
    if ($NB.Boards.Count -gt 1) {
        $sb = New-Object Windows.Controls.MenuItem; $sb.Header = '🗂  Envoyer vers le tableau'
        foreach ($b in $NB.Boards) {
            if ($b.id -eq $board.id) { continue }
            [void]$sb.Items.Add((New-TaggedItem $b.name "$($t.id)|$((Get-OpenColumn $b).id)" { param($s, $e) Invoke-Safe { $p = $s.Tag.Split('|'); Move-Card $p[0] $p[1] } }))
        }
        [void]$m.Items.Add($sb)
    }
    [void]$m.Items.Add((New-TaggedItem '📋  Enregistrer comme modèle' $t.id { param($s, $e) Invoke-Safe { Save-CardAsTemplate $s.Tag } }))
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    [void]$m.Items.Add((New-TaggedItem '🗑  Supprimer la carte' $t.id { param($s, $e) Invoke-Safe { Remove-Todo $s.Tag } }))
    $m.PlacementTarget = $card
    $m.IsOpen = $true
}

function Show-ColumnMenu($button) {
    $board = Get-CurrentBoard
    $col = Get-Column $board $button.Tag
    if (-not $col) { return }
    $i = $board.columns.IndexOf($col)
    $m = New-Object Windows.Controls.ContextMenu
    [void]$m.Items.Add((New-TaggedItem '✏  Renommer' $col.id { param($s, $e) Invoke-Safe { Rename-BoardColumn $s.Tag } }))
    $l = New-TaggedItem '◀  Déplacer à gauche' $col.id { param($s, $e) Invoke-Safe { Move-BoardColumn $s.Tag -1 } }; $l.IsEnabled = $i -gt 0
    $r = New-TaggedItem '▶  Déplacer à droite' $col.id { param($s, $e) Invoke-Safe { Move-BoardColumn $s.Tag 1 } }; $r.IsEnabled = $i -lt $board.columns.Count - 1
    [void]$m.Items.Add($l); [void]$m.Items.Add($r)
    $d = New-TaggedItem '✅  Colonne « terminé »' $col.id { param($s, $e) Invoke-Safe { Toggle-ColumnDone $s.Tag } }
    $d.IsCheckable = $true; $d.IsChecked = [bool]$col.done
    $d.ToolTip = 'Les cartes de cette colonne comptent comme terminées (rappels, statistiques, bulles)'
    [void]$m.Items.Add($d)
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    $a = New-TaggedItem '🧹  Archiver les cartes de la colonne' $col.id { param($s, $e) Invoke-Safe { Clear-DoneTodos $s.Tag } }
    $a.IsEnabled = @(Get-ColumnCards $col.id).Count -gt 0
    [void]$m.Items.Add($a)
    $x = New-TaggedItem '🗑  Supprimer la colonne' $col.id { param($s, $e) Invoke-Safe { Remove-BoardColumn $s.Tag } }
    $x.IsEnabled = $board.columns.Count -gt 1
    [void]$m.Items.Add($x)
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    $tp = New-Object Windows.Controls.MenuItem; $tp.Header = '📋  Nouvelle carte depuis un modèle'
    if ($NB.Templates.Count) {
        foreach ($tpl in $NB.Templates) {
            $label = $tpl.name
            if ($tpl.checks.Count) { $label += "  (☑ $($tpl.checks.Count))" }
            [void]$tp.Items.Add((New-TaggedItem $label "$($tpl.id)|$($col.id)" { param($s, $e) Invoke-Safe { $p = $s.Tag.Split('|'); New-CardFromTemplate $p[0] $p[1] } }))
        }
        [void]$tp.Items.Add((New-Object Windows.Controls.Separator))
        $del = New-Object Windows.Controls.MenuItem; $del.Header = '🗑  Supprimer un modèle'
        foreach ($tpl in $NB.Templates) { [void]$del.Items.Add((New-TaggedItem $tpl.name $tpl.id { param($s, $e) Invoke-Safe { Remove-Template $s.Tag } })) }
        [void]$tp.Items.Add($del)
    } else {
        $none = New-Object Windows.Controls.MenuItem
        $none.Header = 'Aucun modèle : clic droit sur une carte > Enregistrer comme modèle'; $none.IsEnabled = $false
        [void]$tp.Items.Add($none)
    }
    [void]$m.Items.Add($tp)
    $m.PlacementTarget = $button
    $m.IsOpen = $true
}

# --- petite fenetre de saisie (nom de tableau, de colonne...) ---
function Show-Prompt([string]$title, [string]$label, [string]$default = '') {
    $w = New-Object Windows.Window
    $w.Title = $title; $w.Width = 360; $w.SizeToContent = 'Height'; $w.ResizeMode = 'NoResize'
    $w.WindowStartupLocation = 'CenterOwner'; $w.Topmost = $true; $w.ShowInTaskbar = $false
    try { $w.Owner = $panel } catch {}
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '16'
    $lb = New-Object Windows.Controls.TextBlock; $lb.Text = $label; $lb.Margin = '0,0,0,6'
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = $default; $tb.Padding = '6,4'
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,12,0,0'
    $ok = New-Object Windows.Controls.Button; $ok.Content = 'OK'; $ok.Width = 80; $ok.IsDefault = $true; $ok.Margin = '0,0,8,0'
    $ko = New-Object Windows.Controls.Button; $ko.Content = 'Annuler'; $ko.Width = 80; $ko.IsCancel = $true
    $ok.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
    $tb.Add_Loaded({ param($s, $e) $s.Focus() | Out-Null; $s.SelectAll() })
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($ko)
    [void]$sp.Children.Add($lb); [void]$sp.Children.Add($tb); [void]$sp.Children.Add($btns)
    $w.Content = $sp
    if ($w.ShowDialog()) { $v = $tb.Text.Trim(); if ($v) { return $v } }
    return $null
}

function Confirm-Action([string]$text) {
    $r = if ($panel -and $panel.IsVisible) { [Windows.MessageBox]::Show($panel, $text, 'Orbit', 'YesNo', 'Question') }
         else { [Windows.MessageBox]::Show($text, 'Orbit', 'YesNo', 'Question') }
    $r -eq 'Yes'
}

# --- tableaux ---
function Add-Board {
    $n = Show-Prompt 'Nouveau tableau' 'Nom du nouveau tableau :' ''
    if (-not $n) { return }
    if ($NB.EditId) { End-EditTodo -NoRender }
    $b = New-BoardObject $n
    [void]$NB.Boards.Add($b); $NB.BoardId = $b.id
    Save-Todos; Render-Todos; Fit-Notebook
    Show-Bubble "Nouveau tableau « $n » prêt 🗂" -Force -Seconds 3
}

function Rename-Board {
    $b = Get-CurrentBoard
    $n = Show-Prompt 'Renommer le tableau' 'Nouveau nom :' $b.name
    if ($n) { $b.name = $n; Save-Todos; Render-Todos }
}

function Remove-Board {
    if ($NB.Boards.Count -le 1) { return }
    $b = Get-CurrentBoard
    $cards = @($NB.Todos | Where-Object { $_.board -eq $b.id })
    $msg = "Supprimer le tableau « $($b.name) »"
    if ($cards.Count) { $msg += " et ses $($cards.Count) carte(s) ?`n(Elles seront copiées dans todo-archive.md.)" } else { $msg += ' ?' }
    if (-not (Confirm-Action $msg)) { return }
    if ($NB.EditId) { End-EditTodo -NoRender }
    if ($cards.Count) {
        $md = "`r`n## $((Get-Date).ToString('yyyy-MM-dd')) — tableau supprimé : $($b.name)`r`n" + (($cards | ForEach-Object { "- [$(if ($_.done) { 'x' } else { ' ' })] $($_.text)" }) -join "`r`n")
        Add-Content -Path $TodoArchive -Value $md -Encoding UTF8
        foreach ($c in $cards) { $NB.Todos.Remove($c) }
    }
    $NB.Boards.Remove($b)
    $NB.BoardId = $NB.Boards[0].id
    Save-Todos; Render-Todos; Fit-Notebook
}

# --- colonnes ---
function Add-BoardColumn {
    $b = Get-CurrentBoard
    $n = Show-Prompt 'Nouvelle colonne' 'Nom de la colonne :' ''
    if (-not $n) { return }
    # avant la premiere colonne "terminee", comme sur Trello on range le "fini" a droite
    $i = $b.columns.Count
    for ($k = 0; $k -lt $b.columns.Count; $k++) { if ($b.columns[$k].done) { $i = $k; break } }
    $b.columns.Insert($i, (New-Column $n))
    Save-Todos; Render-Todos; Fit-Notebook
}

function Rename-BoardColumn([string]$colId) {
    $c = Get-Column (Get-CurrentBoard) $colId
    if (-not $c) { return }
    $n = Show-Prompt 'Renommer la colonne' 'Nouveau nom :' $c.name
    if ($n) { $c.name = $n; Save-Todos; Render-Todos }
}

function Move-BoardColumn([string]$colId, [int]$dir) {
    $b = Get-CurrentBoard
    $c = Get-Column $b $colId
    $i = $b.columns.IndexOf($c); $j = $i + $dir
    if ($i -lt 0 -or $j -lt 0 -or $j -ge $b.columns.Count) { return }
    $b.columns.RemoveAt($i); $b.columns.Insert($j, $c)
    Save-Todos; Render-Todos
}

function Toggle-ColumnDone([string]$colId) {
    $c = Get-Column (Get-CurrentBoard) $colId
    if (-not $c) { return }
    $c.done = -not $c.done
    foreach ($t in (Get-ColumnCards $colId)) {
        $t.done = $c.done
        $t.doneAt = if ($c.done) { (Get-Date).ToString('s') } else { '' }
    }
    Save-Todos; Render-Todos
}

function Remove-BoardColumn([string]$colId) {
    $b = Get-CurrentBoard
    if ($b.columns.Count -le 1) { return }
    $c = Get-Column $b $colId
    $cards = @(Get-ColumnCards $colId)
    $other = $null
    foreach ($o in $b.columns) { if ($o.id -ne $colId) { $other = $o; break } }
    $msg = "Supprimer la colonne « $($c.name) » ?"
    if ($cards.Count) { $msg += "`nSes $($cards.Count) carte(s) iront dans « $($other.name) »." }
    if (-not (Confirm-Action $msg)) { return }
    $b.columns.Remove($c)
    $n = @(Get-ColumnCards $other.id).Count
    foreach ($t in $cards) { $t.col = $other.id; $t.order = $n++; $t.done = [bool]$other.done }
    Save-Todos; Render-Todos; Fit-Notebook
}

# ---------------------------------------------------------------------------
#  Modification d'une tache (titre + description), enregistree en continu
# ---------------------------------------------------------------------------
$NB.MdTimer = New-Object Windows.Threading.DispatcherTimer
$NB.MdTimer.Interval = [timespan]::FromSeconds(10)
$NB.MdTimer.Add_Tick({ $NB.MdTimer.Stop(); Invoke-Safe { if ($NB.MdPending) { Write-TodoMd } } })
$NB.ClipSaveTimer = New-Object Windows.Threading.DispatcherTimer
$NB.ClipSaveTimer.Interval = [timespan]::FromMilliseconds(2500)
$NB.ClipSaveTimer.Add_Tick({ $NB.ClipSaveTimer.Stop(); Invoke-Safe { if ($NB.ClipPending) { Save-Clips -Now } } })

$NB.SaveTimer = New-Object Windows.Threading.DispatcherTimer
$NB.SaveTimer.Interval = [timespan]::FromMilliseconds(700)
$NB.SaveTimer.Add_Tick({ if ($NB.SaveTimer) { $NB.SaveTimer.Stop() }; Invoke-Safe { Save-Todos } })

function Queue-SaveTodos { if ($NB.SaveTimer) { $NB.SaveTimer.Stop() }; $NB.SaveTimer.Start() }

function Start-EditTodo([string]$id) {
    $cols = @()
    if ($NB.EditId -and $NB.EditId -ne $id) {
        $prev = Find-Todo $NB.EditId
        if ($prev) { $cols += $prev.col }
        End-EditTodo -NoRender
    }
    $t = Find-Todo $id
    if (-not $t) { return }
    $NB.EditId = $id
    $NB.EditOrig = $t.text
    Render-Todos -Cols ($cols + $t.col)
}

function End-EditTodo([switch]$NoRender) {
    if (-not $NB.EditId) { return }
    $t = Find-Todo $NB.EditId
    if ($t) {
        # un titre vide n'a pas de sens : on remet l'ancien
        if (-not $t.text.Trim()) { $t.text = $NB.EditOrig } else { $t.text = $t.text.Trim() }
        $t.desc = $t.desc.TrimEnd()
    }
    $NB.EditId = ''
    if ($NB.SaveTimer) { $NB.SaveTimer.Stop() }
    Save-Todos
    if (-not $NoRender) { if ($t) { Render-Todos -Cols $t.col } else { Render-Todos } }
}

function New-TodoEditor($t) {
    $box = New-Object Windows.Controls.StackPanel

    $title = New-Object Windows.Controls.TextBox
    $title.Text = $t.text
    $title.Tag = $t.id
    $title.FontWeight = 'SemiBold'; $title.Padding = '6,4'; $title.BorderBrush = '#6C5CE7'; $title.BorderThickness = '1.5'
    $title.TextWrapping = 'Wrap'
    $title.Add_TextChanged({ param($s, $e) $x = Find-Todo $s.Tag; if ($x) { $x.text = $s.Text; Queue-SaveTodos } })
    [void]$box.Children.Add($title)

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = 'Description'
    $lbl.FontSize = 11; $lbl.Foreground = '#8A87A3'; $lbl.Margin = '2,6,0,2'
    [void]$box.Children.Add($lbl)

    $desc = New-Object Windows.Controls.TextBox
    $desc.Text = $t.desc
    $desc.Tag = $t.id
    $desc.AcceptsReturn = $true; $desc.TextWrapping = 'Wrap'
    $desc.MinHeight = 70; $desc.MaxHeight = 180; $desc.VerticalScrollBarVisibility = 'Auto'
    $desc.Padding = '6,4'; $desc.BorderBrush = '#C9C3F5'; $desc.BorderThickness = '1.5'
    $desc.ToolTip = 'Détails, liens, étapes… (Ctrl+Entrée pour terminer)'
    $desc.Add_TextChanged({ param($s, $e) $x = Find-Todo $s.Tag; if ($x) { $x.desc = $s.Text; Queue-SaveTodos } })
    $desc.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            $e.Handled = $true; Invoke-Safe { End-EditTodo }
        }
    })
    [void]$box.Children.Add($desc)

    # sous-taches : on coche directement, Entree pour en ajouter une
    $focusChecks = $NB.FocusChecklist -eq $t.id
    if ($focusChecks) { $NB.FocusChecklist = '' }
    $l3 = New-Object Windows.Controls.TextBlock
    $nDone = @($t.checks | Where-Object { $_.done }).Count
    $l3.Text = if ($t.checks.Count) { "☑ Sous-tâches ($nDone/$($t.checks.Count))" } else { '☑ Sous-tâches' }
    $l3.Margin = '2,8,0,2'; $l3.FontSize = 12
    [void]$box.Children.Add($l3)
    for ($i = 0; $i -lt $t.checks.Count; $i++) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '2,1,0,1'
        $cx = New-Object Windows.Controls.Button
        $cx.Content = '✕'; $cx.Width = 20; $cx.Background = 'Transparent'; $cx.BorderThickness = '0'; $cx.Foreground = '#B0AEC4'
        $cx.Cursor = 'Hand'; $cx.ToolTip = 'Supprimer cette sous-tâche'; $cx.Tag = "$($t.id)|$i"
        $cx.Add_Click({ param($s, $e) $p = $s.Tag.Split('|'); Invoke-Safe { Remove-CardCheck $p[0] ([int]$p[1]) } })
        [Windows.Controls.DockPanel]::SetDock($cx, 'Right')
        [void]$row.Children.Add($cx)
        $cb = New-Object Windows.Controls.CheckBox
        $lab = New-Object Windows.Controls.TextBlock
        $lab.Text = $t.checks[$i].text; $lab.TextWrapping = 'Wrap'
        $cb.Content = $lab; $cb.IsChecked = [bool]$t.checks[$i].done; $cb.Tag = @{ Key = "$($t.id)|$i"; Label = $l3; Card = $t.id }
        $cb.Add_Click({
            param($s, $e)
            $p = $s.Tag.Key.Split('|')
            Invoke-Safe {
                Set-CardCheck $p[0] ([int]$p[1]) ([bool]$s.IsChecked)
                $x = Find-Todo $s.Tag.Card
                if ($x) { $s.Tag.Label.Text = "☑ Sous-tâches ($(@($x.checks | Where-Object { $_.done }).Count)/$($x.checks.Count))" }
            }
        })
        [void]$row.Children.Add($cb)
        [void]$box.Children.Add($row)
    }
    $addG = New-Object Windows.Controls.Grid
    $addG.Margin = '0,2,0,0'
    $addT = New-Object Windows.Controls.TextBox
    $addT.Padding = '5,3'; $addT.BorderBrush = '#C9C3F5'; $addT.BorderThickness = '1.2'
    $addH = New-Object Windows.Controls.TextBlock
    $addH.Text = '＋ Ajouter une sous-tâche (Entrée)'; $addH.Margin = '7,0,0,0'; $addH.VerticalAlignment = 'Center'
    $addH.Foreground = '#9A98B0'; $addH.IsHitTestVisible = $false; $addH.FontSize = 11.5
    $addT.Tag = @{ Id = $t.id; Hint = $addH }
    $addT.Add_TextChanged({ param($s, $e) $s.Tag.Hint.Visibility = if ($s.Text) { 'Collapsed' } else { 'Visible' } })
    $addT.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') { $e.Handled = $true; Invoke-Safe { Add-CardCheck $s.Tag.Id $s.Text } }
    })
    if ($focusChecks) { $addT.Add_Loaded({ param($s, $e) $s.Focus() | Out-Null }) }
    [void]$addG.Children.Add($addT); [void]$addG.Children.Add($addH)
    [void]$box.Children.Add($addG)

    # echeance et rappel, l'un sous l'autre (pour tenir dans une carte)
    $l1 = New-Object Windows.Controls.TextBlock
    $l1.Text = '📅 Échéance'; $l1.Margin = '2,8,0,2'; $l1.FontSize = 12
    [void]$box.Children.Add($l1)
    $dueRow = New-Object Windows.Controls.DockPanel
    $dueP = New-Object Windows.Controls.DatePicker
    $dueP.Tag = $t.id
    if ($t.due) { $dueP.SelectedDate = [datetime]::ParseExact($t.due, 'yyyy-MM-dd', $null) }
    $dueP.Add_SelectedDateChanged({ param($s, $e) Invoke-Safe { Set-TodoDue $s.Tag $s.SelectedDate } })
    $dueX = New-Object Windows.Controls.Button
    $dueX.Content = '✕'; $dueX.Width = 24; $dueX.Margin = '4,0,0,0'; $dueX.Background = 'Transparent'; $dueX.BorderThickness = '0'
    $dueX.ToolTip = "Retirer l'échéance"; $dueX.Cursor = 'Hand'
    $dueX.Tag = $dueP
    $dueX.Add_Click({ param($s, $e) $s.Tag.SelectedDate = $null })
    [Windows.Controls.DockPanel]::SetDock($dueX, 'Right')
    [void]$dueRow.Children.Add($dueX); [void]$dueRow.Children.Add($dueP)
    [void]$box.Children.Add($dueRow)

    $l2 = New-Object Windows.Controls.TextBlock
    $l2.Text = '⏰ Rappel (date et heure)'; $l2.Margin = '2,6,0,2'; $l2.FontSize = 12
    [void]$box.Children.Add($l2)
    $remRow = New-Object Windows.Controls.DockPanel
    $remP = New-Object Windows.Controls.DatePicker
    $remT = New-Object Windows.Controls.TextBox
    $remT.Width = 50; $remT.Margin = '4,0,0,0'; $remT.Padding = '3,3'; $remT.VerticalContentAlignment = 'Center'
    $remT.ToolTip = 'Heure du rappel, par ex. 14:30'
    if ($t.remindAt) {
        $remP.SelectedDate = ([datetime]$t.remindAt).Date
        $remT.Text = ([datetime]$t.remindAt).ToString('HH:mm')
    }
    $remX = New-Object Windows.Controls.Button
    $remX.Content = '✕'; $remX.Width = 24; $remX.Margin = '4,0,0,0'; $remX.Background = 'Transparent'; $remX.BorderThickness = '0'
    $remX.ToolTip = 'Retirer le rappel'; $remX.Cursor = 'Hand'

    # les trois controles partagent le meme Tag : l'id de la tache et les champs a relire
    $ctx = @{ Id = $t.id; Date = $remP; Time = $remT }
    $remP.Tag = $ctx; $remT.Tag = $ctx; $remX.Tag = $ctx
    $remP.Add_SelectedDateChanged({ param($s, $e) Invoke-Safe { Apply-ReminderFields $s.Tag } })
    $remT.Add_TextChanged({ param($s, $e) Invoke-Safe { Apply-ReminderFields $s.Tag } })
    $remX.Add_Click({ param($s, $e) $s.Tag.Time.Text = ''; $s.Tag.Date.SelectedDate = $null; Invoke-Safe { Apply-ReminderFields $s.Tag } })
    [Windows.Controls.DockPanel]::SetDock($remX, 'Right'); [Windows.Controls.DockPanel]::SetDock($remT, 'Right')
    [void]$remRow.Children.Add($remX); [void]$remRow.Children.Add($remT); [void]$remRow.Children.Add($remP)
    [void]$box.Children.Add($remRow)

    # repetition
    $l4 = New-Object Windows.Controls.TextBlock
    $l4.Text = '🔁 Répéter'; $l4.Margin = '2,6,0,2'; $l4.FontSize = 12
    [void]$box.Children.Add($l4)
    $rc = New-Object Windows.Controls.ComboBox
    foreach ($k in $RepeatChoices.Keys) {
        $it = New-Object Windows.Controls.ComboBoxItem
        $it.Content = $RepeatChoices[$k]; $it.Tag = $k
        [void]$rc.Items.Add($it)
        if ($k -eq [string]$t.repeat) { $rc.SelectedItem = $it }
    }
    $rc.Tag = $t.id
    $rc.ToolTip = "Une fois terminée, la carte revient toute seule dans la 1re colonne à la date suivante (calculée depuis son échéance, sinon depuis son jour de création), sous-tâches décochées."
    $rc.Add_SelectionChanged({ param($s, $e) if ($s.SelectedItem) { Invoke-Safe { Set-CardRepeat $s.Tag ([string]$s.SelectedItem.Tag) } } })
    [void]$box.Children.Add($rc)

    # Entree dans le titre : on passe a la description
    $title.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $e.Handled = $true; $desc.Focus() | Out-Null } }.GetNewClosure())

    $foot = New-Object Windows.Controls.DockPanel
    $foot.Margin = '0,6,0,0'
    $ok = New-Object Windows.Controls.Button
    $ok.Content = '✓ Terminé'; $ok.Padding = '10,3'; $ok.Cursor = 'Hand'
    $ok.Background = '#6C5CE7'; $ok.Foreground = 'White'; $ok.BorderThickness = '0'
    $ok.Add_Click({ Invoke-Safe { End-EditTodo } })
    [Windows.Controls.DockPanel]::SetDock($ok, 'Right')
    [void]$foot.Children.Add($ok)
    $info = New-Object Windows.Controls.TextBlock
    $info.Text = '💾 Enregistré automatiquement'
    $info.FontSize = 11; $info.Foreground = '#8A87A3'; $info.VerticalAlignment = 'Center'
    [void]$foot.Children.Add($info)
    [void]$box.Children.Add($foot)

    # le curseur se place directement dans le titre (ou dans les sous-taches si on vient d'en ajouter une)
    if (-not $focusChecks) { $title.Add_Loaded({ param($s, $e) $s.Focus() | Out-Null; $s.CaretIndex = $s.Text.Length }) }
    return $box
}

# Le rappel est enregistre des que l'heure est valide (date du jour si aucune date choisie)
function Apply-ReminderFields($ctx) {
    $raw = $ctx.Time.Text.Trim()
    if (-not $raw -and -not $ctx.Date.SelectedDate) {
        Set-TodoReminder $ctx.Id $null
        $ctx.Time.ClearValue([Windows.Controls.Control]::BorderBrushProperty)
        return
    }
    if (-not $raw) { return }   # une date sans heure : on attend l'heure
    if (($raw -replace 'h', ':') -match '^([01]?\d|2[0-3])(?::([0-5]\d)?)?$') {
        $ts = New-Object TimeSpan([int]$Matches[1], $(if ($Matches[2]) { [int]$Matches[2] } else { 0 }), 0)
        $day = if ($ctx.Date.SelectedDate) { $ctx.Date.SelectedDate.Value.Date } else { (Get-Date).Date }
        Set-TodoReminder $ctx.Id ($day + $ts)
        $ctx.Time.ClearValue([Windows.Controls.Control]::BorderBrushProperty)
    } else {
        $ctx.Time.BorderBrush = '#E03131'
    }
}

function Show-PrioMenu($button) {
    $m = New-Object Windows.Controls.ContextMenu
    foreach ($p in 1..10) {
        $label = switch ($p) { 1 { "P1  · la plus urgente" } 10 { "P10 · quand j'ai le temps" } default { "P$p" } }
        $mi = New-Object Windows.Controls.MenuItem
        $mi.Header = $label
        $mi.Tag = "$($button.Tag)|$p"
        $mi.Foreground = Get-PrioColor $p
        $mi.Add_Click({ param($s, $e) Invoke-Safe { $parts = $s.Tag.Split('|'); Set-TodoPrio $parts[0] $parts[1] } })
        [void]$m.Items.Add($mi)
    }
    $m.PlacementTarget = $button
    $m.IsOpen = $true
}

function New-ClipCard($c, [bool]$isFav) {
    $card = New-Object Windows.Controls.Border
    $card.Margin = '0,0,0,6'; $card.Padding = '10,6,6,6'; $card.CornerRadius = '10'
    if ($isFav) { $card.Background = '#FFF8E1'; $card.BorderBrush = '#FFD166' }
    else { $card.Background = '#F3F1FF'; $card.BorderBrush = '#DDD8FF' }
    $card.BorderThickness = '1'
    $card.Cursor = 'Hand'; $card.Tag = $c
    $tip = if ($c.text.Length -gt 800) { (Get-TextStart $c.text 800) + '…' } else { $c.text }
    $card.ToolTip = $tip

    $g = New-Object Windows.Controls.Grid
    foreach ($w in '*', 'Auto', 'Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; $g.ColumnDefinitions.Add($cd) }

    $sp = New-Object Windows.Controls.StackPanel
    $head = New-Object Windows.Controls.TextBlock
    $icon = if ($c.kind -eq 'files') { '📁 Fichier(s)' } else { '📝 Texte' }
    $head.Text = if ($isFav) { "⭐ Favori depuis le $($c.time)  ·  $icon" } else { "$($c.time)  ·  $icon" }
    $head.FontSize = 11; $head.Foreground = '#8A87A3'
    $body = New-Object Windows.Controls.TextBlock
    $preview = ($c.text -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 220) { $preview = (Get-TextStart $preview 220) + '…' }
    $body.Text = $preview
    $body.TextWrapping = 'Wrap'; $body.MaxHeight = 38; $body.TextTrimming = 'CharacterEllipsis'
    $body.Foreground = '#1E1B3A'
    [void]$sp.Children.Add($head); [void]$sp.Children.Add($body)
    [void]$g.Children.Add($sp)

    $star = New-Object Windows.Controls.Button
    $on = $isFav -or [bool](Find-Fav $c.text)
    $star.Content = if ($on) { '★' } else { '☆' }
    $star.Foreground = if ($on) { '#F5A400' } else { '#B0AEC4' }
    $star.FontSize = 15; $star.Tag = $c; $star.Width = 24; $star.Height = 22; $star.VerticalAlignment = 'Top'
    $star.Background = 'Transparent'; $star.BorderThickness = '0'; $star.Cursor = 'Hand'
    $star.ToolTip = if ($on) { 'Retirer des favoris' } else { 'Garder en favori (même après aujourd''hui)' }
    $star.Add_Click({ param($s, $e) Invoke-Safe { Toggle-Fav $s.Tag } })
    [Windows.Controls.Grid]::SetColumn($star, 1)
    [void]$g.Children.Add($star)

    if (-not $isFav) {
        $del = New-Object Windows.Controls.Button
        $del.Content = '✕'; $del.Tag = $c; $del.Width = 22; $del.Height = 20; $del.VerticalAlignment = 'Top'
        $del.Background = 'Transparent'; $del.BorderThickness = '0'; $del.Foreground = '#B0AEC4'
        $del.Cursor = 'Hand'; $del.ToolTip = "Retirer de l'historique"
        $del.Add_Click({ param($s, $e) Invoke-Safe { $NB.Clips.Remove($s.Tag); Save-Clips; Render-Clips } })
        [Windows.Controls.Grid]::SetColumn($del, 2)
        [void]$g.Children.Add($del)
    }

    $card.Child = $g
    $card.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Copy-Clip $s.Tag } })
    return $card
}

function New-SectionTitle([string]$text) {
    $h = New-Object Windows.Controls.TextBlock
    $h.Text = $text; $h.FontWeight = 'Bold'; $h.FontSize = 12; $h.Foreground = '#4A4766'; $h.Margin = '2,4,0,6'
    return $h
}

function Render-Clips {
    $NB.ClipDirty = $false
    $pn.ClipList.Children.Clear()
    $q = $pn.ClipSearch.Text.Trim().ToLowerInvariant()

    # favoris en premier
    $favs = @($NB.Favs | Where-Object { -not $q -or $_.text.ToLowerInvariant().Contains($q) })
    if ($favs.Count) {
        [void]$pn.ClipList.Children.Add((New-SectionTitle "⭐ Favoris ($($favs.Count))"))
        foreach ($f in $favs) { [void]$pn.ClipList.Children.Add((New-ClipCard $f $true)) }
        [void]$pn.ClipList.Children.Add((New-SectionTitle "📋 Aujourd'hui"))
    }

    $shown = 0
    foreach ($c in $NB.Clips) {
        if ($q -and -not $c.text.ToLowerInvariant().Contains($q)) { continue }
        if (++$shown -gt 80) { break }   # au-dela, la recherche aide a retrouver
        [void]$pn.ClipList.Children.Add((New-ClipCard $c $false))
    }
    if ($shown -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = if ($q) { "Rien ne correspond à « $q »" } else { "Aucun copier-coller aujourd'hui.`nFais un Ctrl+C quelque part, je m'en souviendrai 📋`nClique sur ☆ pour garder un élément en favori." }
        $empty.Foreground = '#9A98B0'; $empty.TextWrapping = 'Wrap'; $empty.Margin = '4,10,4,0'
        $empty.TextAlignment = 'Center'
        [void]$pn.ClipList.Children.Add($empty)
    }
    $pn.ClipCount.Text = "$($NB.Clips.Count) aujourd'hui · ⭐ $($NB.Favs.Count)"
    Update-Tabs
}

# Largeur de la fenetre : large pour les tableaux, etroite pour les copier-coller
function Fit-Notebook {
    $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int]$panel.Left + 20, [int]$panel.Top + 20)))
    if ($NB.Tab -eq 'Todo') {
        $cols = (Get-CurrentBoard).columns.Count
        $want = if ($NB.KanbanW -gt 0) { $NB.KanbanW } else { 60 + ($KanbanColW + 10) * $cols + 180 }
        $panel.Width = [math]::Max(560, [math]::Min($want, $wa.R - $wa.L - 20))
    } elseif ($NB.Tab -eq 'Search' -or $NB.Tab -eq 'Notes') {
        $panel.Width = 470
    } else {
        $panel.Width = 380
    }
    if ($panel.Left + $panel.Width -gt $wa.R) { $panel.Left = [math]::Max($wa.L, $wa.R - $panel.Width - 8) }
    if ($panel.Top + $panel.Height -gt $wa.B) { $panel.Top = [math]::Max($wa.T, $wa.B - $panel.Height - 8) }
}

function Select-Tab([string]$tab) {
    if ($NB.Tab -eq 'Todo' -and $tab -ne 'Todo' -and $panel.Visibility -eq 'Visible') { $NB.KanbanW = $panel.Width }
    $NB.Tab = $tab
    Fit-Notebook
    $pn.TodoPanel.Visibility = if ($tab -eq 'Todo') { 'Visible' } else { 'Collapsed' }
    $pn.ClipPanel.Visibility = if ($tab -eq 'Clip') { 'Visible' } else { 'Collapsed' }
    $pn.SearchPanel.Visibility = if ($tab -eq 'Search') { 'Visible' } else { 'Collapsed' }
    $pn.NotesPanel.Visibility = if ($tab -eq 'Notes') { 'Visible' } else { 'Collapsed' }
    if ($tab -eq 'Clip') { Render-Clips; $pn.ClipSearch.Focus() | Out-Null }
    elseif ($tab -eq 'Notes') { Render-Notes }
    elseif ($tab -eq 'Search') { Render-Search; $pn.SearchBox.Focus() | Out-Null; $pn.SearchBox.SelectAll() }
    else { Render-Todos; $pn.TodoInput.Focus() | Out-Null }
    Update-Tabs
}

function Open-Notebook([string]$tab = 'Todo') {
    Initialize-Notebook
    if ($panel.Visibility -ne 'Visible') {
        # au-dessus d'Orbit, dans le coin de l'ecran ou se trouve la souris
        $p = [System.Windows.Forms.Cursor]::Position
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint($p))
        $panel.Left = [math]::Max($wa.L, $wa.R - $panel.Width - 8)
        $panel.Top = [math]::Max($wa.T, $wa.B - $panel.Height - 150)
        $NB.Tab = ''
        $panel.Show()
    }
    $panel.Activate() | Out-Null
    Select-Tab $tab
}

function Close-Notebook {
    if ($NB.EditId) { End-EditTodo -NoRender }
    $panel.Hide()
}

# --- evenements du carnet ---

Load-Todos
Load-Clips
Load-Favs
Update-Tabs

# ---------------------------------------------------------------------------
#  Construction de la fenetre du carnet et de ses evenements
# ---------------------------------------------------------------------------
function Initialize-Notebook {
    if ($script:panel) { return }
    $script:panel = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $panelXaml))
    $script:pn = @{}
    foreach ($n in 'Header','CloseBtn','TabTodo','TabClip','TodoPanel','TodoInput','TodoHint','TodoPrio','TodoAdd','TodoCount',
                   'BoardPick','BoardAdd','BoardRename','BoardDel','BoardHistory','KanbanScroll',
                   'TodoClear','TodoList','ClipPanel','ClipSearch','ClipHint','ClipCount','ClipPause','ClipClear','ClipList',
                   'TabSearch','SearchPanel','SearchBox','SearchHint','SearchCount','SearchList',
                   'TabNotes','NotesPanel','NotesAdd','NotesBackup','NotesCount','NotesList') {
        $pn[$n] = $panel.FindName($n)
    }

    $pn.Header.Add_MouseLeftButtonDown({ try { $panel.DragMove() } catch {} })
    $pn.CloseBtn.Add_Click({ Close-Notebook })
    $panel.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Close-Notebook } })
    $panel.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Escape') {
            $e.Handled = $true
            if ($NB.EditId) { Invoke-Safe { End-EditTodo } } else { Close-Notebook }
        } elseif ($e.Key -eq 'F' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            $e.Handled = $true
            Invoke-Safe { Select-Tab 'Search' }
        }
    })
    $pn.TabTodo.Add_Click({ Invoke-Safe { Select-Tab 'Todo' } })
    $pn.TabClip.Add_Click({ Invoke-Safe { Select-Tab 'Clip' } })
    $pn.TabSearch.Add_Click({ Invoke-Safe { Select-Tab 'Search' } })
    $pn.TabNotes.Add_Click({ Invoke-Safe { Select-Tab 'Notes' } })
    $pn.NotesAdd.Add_Click({ Invoke-Safe { Show-QuickNote } })
    $pn.NotesBackup.Add_Click({ param($s, $e) Invoke-Safe { Show-NotesBackupMenu $s } })
    $NB.SearchTimer = New-Object Windows.Threading.DispatcherTimer
    $NB.SearchTimer.Interval = [timespan]::FromMilliseconds(250)
    $NB.SearchTimer.Add_Tick({ $NB.SearchTimer.Stop(); Invoke-Safe { Render-Search } })
    $pn.SearchBox.Add_TextChanged({
        $pn.SearchHint.Visibility = if ($pn.SearchBox.Text) { 'Collapsed' } else { 'Visible' }
        $NB.SearchTimer.Stop(); $NB.SearchTimer.Start()
    })

    $pn.TodoInput.Add_TextChanged({ $pn.TodoHint.Visibility = if ($pn.TodoInput.Text) { 'Collapsed' } else { 'Visible' } })
    $pn.TodoInput.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') {
            $e.Handled = $true
            Invoke-Safe { Add-Todo $pn.TodoInput.Text ($pn.TodoPrio.SelectedIndex + 1); $pn.TodoInput.Clear() }
        }
    })
    $pn.TodoAdd.Add_Click({ Invoke-Safe { Add-Todo $pn.TodoInput.Text ($pn.TodoPrio.SelectedIndex + 1); $pn.TodoInput.Clear(); $pn.TodoInput.Focus() | Out-Null } })
    foreach ($p in 1..10) { [void]$pn.TodoPrio.Items.Add("P$p") }
    $pn.TodoPrio.SelectedIndex = $DefaultPrio - 1
    $pn.TodoClear.Add_Click({ Invoke-Safe { if (Confirm-Action "Archiver les cartes terminées de ce tableau ?`n(Elles seront copiées dans todo-archive.md.)") { Clear-DoneTodos } } })
    $pn.BoardPick.Add_SelectionChanged({
        if ($NB.Rendering -or -not $pn.BoardPick.SelectedItem) { return }
        Invoke-Safe {
            if ($NB.EditId) { End-EditTodo -NoRender }
            $NB.BoardId = [string]$pn.BoardPick.SelectedItem.Tag
            Save-Todos; Render-Todos
        }
    })
    $pn.BoardAdd.Add_Click({ Invoke-Safe { Add-Board } })
    $pn.BoardRename.Add_Click({ Invoke-Safe { Rename-Board } })
    $pn.BoardDel.Add_Click({ Invoke-Safe { Remove-Board } })
    $pn.BoardHistory.Add_Click({ param($s, $e) Invoke-Safe { Show-BackupMenu $s } })
    $pn.TodoCount.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Show-UpcomingMenu $s } })

    $pn.ClipSearch.Add_TextChanged({
        $pn.ClipHint.Visibility = if ($pn.ClipSearch.Text) { 'Collapsed' } else { 'Visible' }
        Invoke-Safe { Render-Clips }
    })
    $pn.ClipPause.Add_Click({
        $NB.ClipPaused = [bool]$pn.ClipPause.IsChecked
        Show-Bubble $(if ($NB.ClipPaused) { "Ok, je ne regarde plus tes copier-coller 🙈" } else { "Je reprends l'historique des copier-coller 📋" }) -Force -Seconds 3
    })
    $pn.ClipClear.Add_Click({
        Invoke-Safe {
            $r = [Windows.MessageBox]::Show($panel, "Effacer tout l'historique des copier-coller d'aujourd'hui ?`n(Les favoris ⭐ sont conservés.)", 'Orbit', 'YesNo', 'Question')
            if ($r -eq 'Yes') { $NB.Clips.Clear(); $NB.LastClip = ''; Save-Clips -Now; Render-Clips }
        }
    })

    # les tableaux modifies pendant que la fenetre etait fermee sont redessines a l'ouverture
    $panel.Add_IsVisibleChanged({ Invoke-Safe { if ($panel.IsVisible -and $NB.TodoDirty -and $NB.Tab -eq 'Todo') { Render-Todos } } })
}
