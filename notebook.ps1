<#
    Carnet d'Orbit : tableaux Kanban (facon Trello) + historique des copier-coller de la journee.
    Ce fichier est charge par orbit.ps1 (il ne se lance pas tout seul).
#>

$TodoFile = Join-Path $DataDir 'todo.json'          # ancienne to-do (reprise automatiquement)
$KanbanFile = Join-Path $DataDir 'kanban.json'
$TodoMd = Join-Path $DataDir 'todo.md'
$TodoArchive = Join-Path $DataDir 'todo-archive.md'
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
}

# ---------------------------------------------------------------------------
#  Ecriture "atomique" : on ecrit a cote puis on remplace, pour ne jamais
#  se retrouver avec un fichier a moitie ecrit
# ---------------------------------------------------------------------------
function Write-FileSafe([string]$path, [string]$content) {
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, $content, (New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
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
        id = [string]$t.id; text = [string]$t.text; desc = [string]$t.desc; prio = Limit-Prio $t.prio
        due = To-DayString $t.due; remindAt = To-IsoString $t.remindAt; reminded = [bool]$t.reminded
        done = [bool]$t.done; created = To-IsoString $t.created; doneAt = To-IsoString $t.doneAt
        board = $board; col = $col; order = $order
    }
}

function Load-Todos {
    $NB.Todos.Clear(); $NB.Boards.Clear()
    try {
        if (Test-Path $KanbanFile) {
            $data = ConvertFrom-Json ([IO.File]::ReadAllText($KanbanFile))
            foreach ($b in $data.boards) {
                $cols = New-Object System.Collections.ArrayList
                foreach ($c in $b.columns) { [void]$cols.Add([pscustomobject]@{ id = [string]$c.id; name = [string]$c.name; done = [bool]$c.done }) }
                if ($cols.Count) { [void]$NB.Boards.Add([pscustomobject]@{ id = [string]$b.id; name = [string]$b.name; columns = $cols }) }
            }
            $NB.BoardId = [string]$data.current
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
    } catch { Write-Log "Lecture tableaux : $($_.Exception.Message)" }
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

# Sauvegarde a chaque modification (kanban.json + une copie lisible todo.md)
function Save-Todos {
    try {
        $data = [ordered]@{ current = $NB.BoardId; boards = @($NB.Boards); cards = @($NB.Todos) }
        Write-FileSafe $KanbanFile (ConvertTo-Json -InputObject $data -Depth 6)
        $lines = @("# Tableaux Orbit", "", "_Mis à jour le $((Get-Date).ToString('dd/MM/yyyy HH:mm'))_")
        foreach ($b in $NB.Boards) {
            $lines += ''; $lines += "## $($b.name)"
            foreach ($c in $b.columns) {
                $lines += ''; $lines += "### $($c.name)"
                foreach ($t in (Get-ColumnCards $c.id)) {
                    $extra = ''
                    if ($t.due) { $extra += " 📅 $(([datetime]$t.due).ToString('dd/MM'))" }
                    if ($t.remindAt -and -not $t.done) { $extra += " ⏰ $(([datetime]$t.remindAt).ToString('dd/MM HH:mm'))" }
                    $lines += "- [$(if ($t.done) { 'x' } else { ' ' })] (P$($t.prio)) $($t.text)$extra"
                    if ($t.desc) { foreach ($d in ($t.desc -split "`r?`n")) { $lines += "    > $d" } }
                }
            }
        }
        Write-FileSafe $TodoMd ($lines -join "`r`n")
    } catch { Write-Log "Ecriture tableaux : $($_.Exception.Message)" }
}

# Deplace une carte dans une colonne (eventuellement d'un autre tableau), a la position voulue
function Move-Card([string]$id, [string]$colId, [int]$index = -1, [switch]$Quiet) {
    $t = Find-Todo $id
    $board = Find-ColumnBoard $colId
    if (-not $t -or -not $board) { return }
    $col = Get-Column $board $colId
    $wasDone = $t.done
    $list = New-Object System.Collections.ArrayList
    foreach ($o in (Get-ColumnCards $colId)) { if ($o.id -ne $id) { [void]$list.Add($o) } }
    if ($index -lt 0 -or $index -gt $list.Count) { $index = $list.Count }
    $list.Insert($index, $t)
    for ($i = 0; $i -lt $list.Count; $i++) { $list[$i].order = $i }
    $t.board = $board.id; $t.col = $col.id
    $t.done = [bool]$col.done
    if ($t.done -and -not $wasDone) { $t.doneAt = (Get-Date).ToString('s') } elseif (-not $t.done) { $t.doneAt = '' }
    Save-Todos
    Render-Todos
    if ($t.done -and -not $wasDone -and -not $Quiet) {
        $left = @($NB.Todos | Where-Object { -not $_.done -and $_.board -eq $board.id }).Count
        if ($left -eq 0) { Show-Bubble "Tout le tableau « $($board.name) » est terminé ! 🎉" -Force -Seconds 5 }
        else { Show-Bubble (Pick @("Bien joué ✅", "Une de moins ! 💪", "Terminé, ça fait du bien hein 😌")) -Force -Seconds 3 }
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
        order   = (Get-ColumnCards $colId).Count
    })
    Save-Todos
    Render-Todos
    $msg = Pick @("Noté ! ✍️", "C'est dans la liste 📝", "Hop, enregistré 💾", "Je m'en souviendrai pour toi 🧠")
    if ($prio -le 2) { $msg += " Priorité $prio, je la mets en haut de la pile 🔥" }
    if ($remindAt) { $msg += " Rappel prévu $(Format-When $remindAt) ⏰" }
    Show-Bubble $msg -Force -Seconds 3
}

function Set-TodoPrio([string]$id, $prio) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $t.prio = Limit-Prio $prio
    Save-Todos
    Render-Todos
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
        if ($NB.EditId -eq $id) { $NB.EditId = ''; $NB.SaveTimer.Stop() }
        $NB.Todos.Remove($t); Save-Todos; Render-Todos
    }
}

# Archive les cartes terminees du tableau affiche (ou d'une seule colonne)
function Clear-DoneTodos([string]$colId = '') {
    $board = Get-CurrentBoard
    $done = if ($colId) { @(Get-ColumnCards $colId) } else { @($NB.Todos | Where-Object { $_.done -and $_.board -eq $board.id }) }
    if (-not $done.Count) { return }
    $md = "`r`n## $((Get-Date).ToString('yyyy-MM-dd')) — $($board.name)`r`n" + (($done | ForEach-Object { "- [x] $($_.text)" }) -join "`r`n")
    Add-Content -Path $TodoArchive -Value $md -Encoding UTF8
    foreach ($t in $done) { $NB.Todos.Remove($t) }
    Save-Todos
    Render-Todos
}

# Tri : a faire d'abord, par priorite (1 en premier) puis par date d'ajout ; terminees a la fin
function Get-SortedTodos {
    $open = @($NB.Todos | Where-Object { -not $_.done } |
        Sort-Object -Property @{ e = { [int]$_.prio } }, @{ e = { if ($_.due) { $_.due } else { '9999' } } }, created)
    $done = @($NB.Todos | Where-Object { $_.done } | Sort-Object -Property doneAt -Descending)
    return @($open + $done)
}
function Get-OpenTodos { @(Get-SortedTodos | Where-Object { -not $_.done }) }
function Get-NextTodo { $open = Get-OpenTodos; if ($open.Count) { return $open[0] } }

function Get-PrioColor([int]$p) {
    if ($p -le 3) { return '#E03131' }      # urgent
    if ($p -le 6) { return '#F08C00' }      # normal
    return '#7A869A'                        # quand j'ai le temps
}

# ---------------------------------------------------------------------------
#  Echeances et rappels
# ---------------------------------------------------------------------------
$DayNames = @('dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.')

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
    $open = Get-OpenTodos
    $late = @($open | Where-Object { $_.due -and $_.due -lt $today })
    $now = @($open | Where-Object { $_.due -eq $today })
    if (-not $late.Count -and -not $now.Count) { return '' }
    $parts = @()
    if ($now.Count) { $parts += "📅 À rendre aujourd'hui : " + (($now | Select-Object -First 3 | ForEach-Object { "« $(Short-Text $_.text 35) »" }) -join ', ') }
    if ($late.Count) { $parts += "⚠️ En retard : " + (($late | Select-Object -First 3 | ForEach-Object { "« $(Short-Text $_.text 35) »" }) -join ', ') }
    return $parts -join "`n"
}

# Verifie toutes les 10 secondes si un rappel doit sonner
function Check-TaskReminders {
    $now = Get-Date
    foreach ($t in @($NB.Todos)) {
        if ($t.done -or $t.reminded -or -not $t.remindAt) { continue }
        if ([datetime]$t.remindAt -gt $now) { continue }
        $t.reminded = $true
        Save-Todos
        Render-Todos
        Ensure-Visible
        Play-Sound
        $msg = "⏰ Rappel : « $(Short-Text $t.text 80) »"
        if ($t.desc) { $msg += "`n📄 $(Short-Text $t.desc 120)" }
        if ($t.due) { $msg += "`n📅 Échéance : $(Format-Due $t.due)" }
        Show-Bubble $msg -Force -Buttons @(
            @{ Label = "✅ C'est fait"; Action = [scriptblock]::Create("Set-TodoDone '$($t.id)' `$true"); Primary = $true },
            @{ Label = '⏰ Dans 15 min'; Action = [scriptblock]::Create("Set-TodoReminder '$($t.id)' ((Get-Date).AddMinutes(15)); Render-Todos; Show-Bubble 'Ok, je te le rappelle dans 15 minutes ⏰' -Force -Seconds 3") },
            @{ Label = '👍 OK'; Action = { } })
        Show-Tray "⏰ Rappel Orbit" (Short-Text $t.text 60)
        return   # un rappel a la fois ; le suivant sonnera au prochain passage
    }
    # une fois par jour : le point sur les echeances (au demarrage, c'est la bulle d'accueil qui s'en charge)
    $today = $now.ToString('yyyy-MM-dd')
    if ($NB.DeadlineDay -ne $today) {
        $first = -not $NB.DeadlineDay
        $NB.DeadlineDay = $today
        if (-not $first) {
            $sum = Get-DeadlineSummary
            if ($sum) { Show-Bubble $sum -Force -Seconds 12 }
        }
    }
}

# Texte court pour les bulles
function Short-Text([string]$text, [int]$max = 60) {
    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt $max) { return $text.Substring(0, $max - 1) + '…' }
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

function Save-Clips {
    try { Write-FileSafe (Get-ClipFile) (ConvertTo-JsonArray $NB.Clips) }
    catch { Write-Log "Ecriture presse-papiers : $($_.Exception.Message)" }
}

function Add-Clip([string]$kind, [string]$text, [string[]]$files) {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($today -ne $NB.ClipDay) { $NB.ClipDay = $today; Load-Clips }

    if ($text.Length -gt $NB.MaxClipLen) { $text = $text.Substring(0, $NB.MaxClipLen) + ' […]' }
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
        <TextBlock Text="🛰️ Carnet d'Orbit" FontFamily="Comic Sans MS, Segoe UI" FontSize="17"
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
      </StackPanel>

      <Grid>
        <!-- ===== Tableaux Kanban ===== -->
        <DockPanel x:Name="TodoPanel" Margin="14,0,14,12">
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <ComboBox x:Name="BoardPick" Width="230" VerticalContentAlignment="Center" FontWeight="SemiBold"
                      ToolTip="Choisir le tableau à afficher"/>
            <Button x:Name="BoardAdd" Grid.Column="1" Content="＋ Tableau" Padding="10,4" Margin="6,0,0,0"
                    Background="#6C5CE7" Foreground="White" BorderThickness="0" Cursor="Hand" ToolTip="Créer un nouveau tableau"/>
            <Button x:Name="BoardRename" Grid.Column="2" Content="✏️" Width="32" Margin="6,0,0,0"
                    Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Renommer ce tableau"/>
            <Button x:Name="BoardDel" Grid.Column="3" Content="🗑️" Width="32" Margin="6,0,0,0"
                    Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Supprimer ce tableau"/>
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
            <Button x:Name="ClipClear" Content="🗑️ Tout effacer" HorizontalAlignment="Right"
                    Padding="10,4" Cursor="Hand" Background="#EEEEF5" BorderThickness="0"/>
          </Grid>
          <TextBlock DockPanel.Dock="Top" Text="Clique sur un élément pour le recopier." FontSize="11.5"
                     Foreground="#9A98B0" Margin="2,0,0,6"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="ClipList"/>
          </ScrollViewer>
        </DockPanel>
      </Grid>
    </DockPanel>
  </Border>
</Window>
'@

$panel = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $panelXaml))
$pn = @{}
foreach ($n in 'Header','CloseBtn','TabTodo','TabClip','TodoPanel','TodoInput','TodoHint','TodoPrio','TodoAdd','TodoCount',
               'BoardPick','BoardAdd','BoardRename','BoardDel','KanbanScroll',
               'TodoClear','TodoList','ClipPanel','ClipSearch','ClipHint','ClipCount','ClipPause','ClipClear','ClipList') {
    $pn[$n] = $panel.FindName($n)
}

function Update-Tabs {
    $open = @($NB.Todos | Where-Object { -not $_.done }).Count
    $pn.TabTodo.Content = "🗂️ Tableaux ($open)"
    $pn.TabClip.Content = "📋 Copier-coller ($($NB.Clips.Count))"
    $on = '#FFD166'; $off = '#FFFFFF'
    $pn.TabTodo.Background = if ($NB.Tab -eq 'Todo') { $on } else { $off }
    $pn.TabClip.Background = if ($NB.Tab -eq 'Clip') { $on } else { $off }
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

function Render-Todos {
    $board = Get-CurrentBoard
    $NB.Rendering = $true
    $pn.BoardPick.Items.Clear()
    foreach ($b in $NB.Boards) {
        $it = New-Object Windows.Controls.ComboBoxItem
        $n = @($NB.Todos | Where-Object { $_.board -eq $b.id -and -not $_.done }).Count
        $it.Content = "🗂️ $($b.name)  ($n)"; $it.Tag = $b.id
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

    $cards = @($NB.Todos | Where-Object { $_.board -eq $board.id })
    $done = @($cards | Where-Object { $_.done }).Count
    $pn.TodoCount.Text = "$($cards.Count) carte(s), $done terminée(s) · glisse les cartes d'une colonne à l'autre, clic droit pour plus d'options"
    $pn.TodoClear.IsEnabled = $done -gt 0
    Update-Tabs
}

function New-KanbanColumn($board, $col) {
    $cards = Get-ColumnCards $col.id
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
    $input = New-Object Windows.Controls.TextBox
    $input.Padding = '6,4'; $input.BorderBrush = '#C9C3F5'; $input.BorderThickness = '1.2'
    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = '＋ Ajouter une carte…'; $hint.Margin = '8,0,0,0'; $hint.VerticalAlignment = 'Center'
    $hint.Foreground = '#9A98B0'; $hint.IsHitTestVisible = $false
    $input.Tag = @{ Col = $col.id; Hint = $hint }
    $input.Add_TextChanged({ param($s, $e) $s.Tag.Hint.Visibility = if ($s.Text) { 'Collapsed' } else { 'Visible' } })
    $input.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') { $e.Handled = $true; $NB.FocusCol = $s.Tag.Col; Invoke-Safe { Add-Todo $s.Text $DefaultPrio $s.Tag.Col } }
    })
    # apres un ajout, le curseur reste dans cette colonne pour enchainer les cartes
    if ($NB.FocusCol -eq $col.id) { $NB.FocusCol = ''; $input.Add_Loaded({ param($s, $e) $s.Focus() | Out-Null }) }
    [void]$foot.Children.Add($input); [void]$foot.Children.Add($hint)
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
    [Windows.Controls.Grid]::SetColumn($del, 2)
    [void]$g.Children.Add($del)
    $card.Child = $g

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
    [void]$m.Items.Add((New-TaggedItem '✏️  Modifier' $t.id { param($s, $e) Invoke-Safe { Start-EditTodo $s.Tag } }))
    $mv = New-Object Windows.Controls.MenuItem; $mv.Header = '➡️  Déplacer vers'
    foreach ($c in $board.columns) {
        if ($c.id -eq $t.col) { continue }
        [void]$mv.Items.Add((New-TaggedItem "$(if ($c.done) { '✅ ' })$($c.name)" "$($t.id)|$($c.id)" { param($s, $e) Invoke-Safe { $p = $s.Tag.Split('|'); Move-Card $p[0] $p[1] } }))
    }
    [void]$m.Items.Add($mv)
    if ($NB.Boards.Count -gt 1) {
        $sb = New-Object Windows.Controls.MenuItem; $sb.Header = '🗂️  Envoyer vers le tableau'
        foreach ($b in $NB.Boards) {
            if ($b.id -eq $board.id) { continue }
            [void]$sb.Items.Add((New-TaggedItem $b.name "$($t.id)|$((Get-OpenColumn $b).id)" { param($s, $e) Invoke-Safe { $p = $s.Tag.Split('|'); Move-Card $p[0] $p[1] } }))
        }
        [void]$m.Items.Add($sb)
    }
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    [void]$m.Items.Add((New-TaggedItem '🗑️  Supprimer la carte' $t.id { param($s, $e) Invoke-Safe { Remove-Todo $s.Tag } }))
    $m.PlacementTarget = $card
    $m.IsOpen = $true
}

function Show-ColumnMenu($button) {
    $board = Get-CurrentBoard
    $col = Get-Column $board $button.Tag
    if (-not $col) { return }
    $i = $board.columns.IndexOf($col)
    $m = New-Object Windows.Controls.ContextMenu
    [void]$m.Items.Add((New-TaggedItem '✏️  Renommer' $col.id { param($s, $e) Invoke-Safe { Rename-BoardColumn $s.Tag } }))
    $l = New-TaggedItem '◀  Déplacer à gauche' $col.id { param($s, $e) Invoke-Safe { Move-BoardColumn $s.Tag -1 } }; $l.IsEnabled = $i -gt 0
    $r = New-TaggedItem '▶  Déplacer à droite' $col.id { param($s, $e) Invoke-Safe { Move-BoardColumn $s.Tag 1 } }; $r.IsEnabled = $i -lt $board.columns.Count - 1
    [void]$m.Items.Add($l); [void]$m.Items.Add($r)
    $d = New-TaggedItem '✅  Colonne « terminé »' $col.id { param($s, $e) Invoke-Safe { Toggle-ColumnDone $s.Tag } }
    $d.IsCheckable = $true; $d.IsChecked = [bool]$col.done
    $d.ToolTip = 'Les cartes de cette colonne comptent comme terminées (rappels, statistiques, bulles)'
    [void]$m.Items.Add($d)
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    $a = New-TaggedItem '🧹  Archiver les cartes de la colonne' $col.id { param($s, $e) Invoke-Safe { Clear-DoneTodos $s.Tag } }
    $a.IsEnabled = (Get-ColumnCards $col.id).Count -gt 0
    [void]$m.Items.Add($a)
    $x = New-TaggedItem '🗑️  Supprimer la colonne' $col.id { param($s, $e) Invoke-Safe { Remove-BoardColumn $s.Tag } }
    $x.IsEnabled = $board.columns.Count -gt 1
    [void]$m.Items.Add($x)
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
    ([Windows.MessageBox]::Show($panel, $text, 'Orbit', 'YesNo', 'Question')) -eq 'Yes'
}

# --- tableaux ---
function Add-Board {
    $n = Show-Prompt 'Nouveau tableau' 'Nom du nouveau tableau :' ''
    if (-not $n) { return }
    if ($NB.EditId) { End-EditTodo -NoRender }
    $b = New-BoardObject $n
    [void]$NB.Boards.Add($b); $NB.BoardId = $b.id
    Save-Todos; Render-Todos; Fit-Notebook
    Show-Bubble "Nouveau tableau « $n » prêt 🗂️" -Force -Seconds 3
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
    $cards = Get-ColumnCards $colId
    $other = $null
    foreach ($o in $b.columns) { if ($o.id -ne $colId) { $other = $o; break } }
    $msg = "Supprimer la colonne « $($c.name) » ?"
    if ($cards.Count) { $msg += "`nSes $($cards.Count) carte(s) iront dans « $($other.name) »." }
    if (-not (Confirm-Action $msg)) { return }
    $b.columns.Remove($c)
    $n = (Get-ColumnCards $other.id).Count
    foreach ($t in $cards) { $t.col = $other.id; $t.order = $n++; $t.done = [bool]$other.done }
    Save-Todos; Render-Todos; Fit-Notebook
}

# ---------------------------------------------------------------------------
#  Modification d'une tache (titre + description), enregistree en continu
# ---------------------------------------------------------------------------
$NB.SaveTimer = New-Object Windows.Threading.DispatcherTimer
$NB.SaveTimer.Interval = [timespan]::FromMilliseconds(700)
$NB.SaveTimer.Add_Tick({ $NB.SaveTimer.Stop(); Invoke-Safe { Save-Todos } })

function Queue-SaveTodos { $NB.SaveTimer.Stop(); $NB.SaveTimer.Start() }

function Start-EditTodo([string]$id) {
    if ($NB.EditId -and $NB.EditId -ne $id) { End-EditTodo -NoRender }
    $t = Find-Todo $id
    if (-not $t) { return }
    $NB.EditId = $id
    $NB.EditOrig = $t.text
    Render-Todos
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
    $NB.SaveTimer.Stop()
    Save-Todos
    if (-not $NoRender) { Render-Todos }
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

    # le curseur se place directement dans le titre
    $title.Add_Loaded({ param($s, $e) $s.Focus() | Out-Null; $s.CaretIndex = $s.Text.Length })
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
    $tip = if ($c.text.Length -gt 800) { $c.text.Substring(0, 800) + '…' } else { $c.text }
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
    if ($preview.Length -gt 220) { $preview = $preview.Substring(0, 220) + '…' }
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
    $p = [System.Windows.Forms.Cursor]::Position
    $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int]$panel.Left + 20, [int]$panel.Top + 20)))
    if ($NB.Tab -eq 'Todo') {
        $cols = (Get-CurrentBoard).columns.Count
        $want = if ($NB.KanbanW -gt 0) { $NB.KanbanW } else { 60 + ($KanbanColW + 10) * $cols + 180 }
        $panel.Width = [math]::Max(560, [math]::Min($want, $wa.R - $wa.L - 20))
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
    if ($tab -eq 'Clip') { Render-Clips; $pn.ClipSearch.Focus() | Out-Null }
    else { Render-Todos; $pn.TodoInput.Focus() | Out-Null }
    Update-Tabs
}

function Open-Notebook([string]$tab = 'Todo') {
    if ($panel.Visibility -ne 'Visible') {
        # au-dessus d'Orbit, dans le coin de l'ecran ou se trouve la souris
        $p = [System.Windows.Forms.Cursor]::Position
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint($p))
        $panel.Left = [math]::Max($wa.L, $wa.R - $panel.Width - 8)
        $panel.Top = [math]::Max($wa.T, $wa.B - $panel.Height - 150)
        $panel.Show()
        $NB.Tab = ''
    }
    $panel.Activate() | Out-Null
    Select-Tab $tab
}

function Close-Notebook {
    if ($NB.EditId) { End-EditTodo -NoRender }
    $panel.Hide()
}

# --- evenements du carnet ---
$pn.Header.Add_MouseLeftButtonDown({ try { $panel.DragMove() } catch {} })
$pn.CloseBtn.Add_Click({ Close-Notebook })
$panel.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Close-Notebook } })
$panel.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq 'Escape') {
        $e.Handled = $true
        if ($NB.EditId) { Invoke-Safe { End-EditTodo } } else { Close-Notebook }
    }
})
$pn.TabTodo.Add_Click({ Invoke-Safe { Select-Tab 'Todo' } })
$pn.TabClip.Add_Click({ Invoke-Safe { Select-Tab 'Clip' } })

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
        if ($r -eq 'Yes') { $NB.Clips.Clear(); $NB.LastClip = ''; Save-Clips; Render-Clips }
    }
})

Load-Todos
Load-Clips
Load-Favs
Update-Tabs
