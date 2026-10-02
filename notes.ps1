# ---------------------------------------------------------------------------
#  Notes rapides : un petit post-it qu'on ouvre d'un clic (clic droit sur
#  Orbit > Note rapide, ou l'icone pres de l'horloge), on ecrit, et c'est
#  garde. On les retrouve dans l'onglet « 📝 Notes » du carnet, on peut les
#  transformer en carte, les epingler, les copier.
#
#  Sauvegardes des notes :
#   - notes.json (ecriture sure) + une copie lisible notes.md ;
#   - une copie par jour dans sauvegardes\notes-AAAA-MM-JJ.json (14 jours),
#     restaurable avec le bouton 🕘 de l'onglet Notes (et annulable) ;
#   - une corbeille : une note supprimee reste recuperable 30 jours ;
#   - notes.json abime au demarrage : repris depuis la derniere sauvegarde ;
#   - en option, une copie automatique dans un dossier de ton choix
#     (OneDrive, reseau, cle USB...) : Orbit-notes.md + Orbit-notes.json ;
#   - « Enregistrer une copie… » ou tu veux, en .txt ou .md.
# ---------------------------------------------------------------------------
$NotesFile = Join-Path $DataDir 'notes.json'
$NotesMd = Join-Path $DataDir 'notes.md'
$NotesTrashFile = Join-Path $DataDir 'notes-corbeille.json'
$NotesKeepDays = 14       # copies quotidiennes gardees
$NotesTrashDays = 30      # duree de vie dans la corbeille
$NB.Notes = New-Object System.Collections.ArrayList
$NB.NotesTrash = New-Object System.Collections.ArrayList
$NB.NotesBackupDay = ''

function ConvertTo-Note($n) {
    $c = [pscustomobject]@{
        id = $(if ($n.id) { [string]$n.id } else { New-Id }); text = [string]$n.text
        created = To-IsoString $n.created; updated = To-IsoString $n.updated; pinned = [bool]$n.pinned
    }
    if (-not $c.updated) { $c.updated = $(if ($c.created) { $c.created } else { (Get-Date).ToString('s') }) }
    if (-not $c.created) { $c.created = $c.updated }
    return $c
}

# Lit une liste de notes depuis un fichier (leve une erreur si le fichier est abime)
function Read-NotesFile([string]$path) {
    # (PowerShell 5.1 renvoie la liste d'un bloc : on la parcourt avec foreach, sans @())
    $data = ConvertFrom-Json ([IO.File]::ReadAllText($path))
    $list = New-Object System.Collections.ArrayList
    foreach ($n in $data) { if ($n -and [string]$n.text) { [void]$list.Add((ConvertTo-Note $n)) } }
    return , $list
}

function Load-Notes {
    $NB.Notes.Clear()
    if (Test-Path -LiteralPath $NotesFile) {
        try { foreach ($n in (Read-NotesFile $NotesFile)) { [void]$NB.Notes.Add($n) } }
        catch {
            Write-Log "Lecture notes : $($_.Exception.Message)"
            Recover-Notes
        }
    }
    Load-NotesTrash
}

# notes.json illisible : on le met de cote et on repart de la sauvegarde la plus recente
function Recover-Notes {
    $bad = Join-Path $DataDir ("notes-illisible-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
    try { Move-Item -LiteralPath $NotesFile -Destination $bad -Force } catch {}
    foreach ($f in (Get-NoteBackupFiles)) {
        try {
            $list = Read-NotesFile $f.Path
            foreach ($n in $list) { [void]$NB.Notes.Add($n) }
            Copy-Item -LiteralPath $f.Path -Destination $NotesFile -Force
            $NB.LoadNotice = (@($NB.LoadNotice, "Ton fichier de notes était abîmé 😬 J'ai repris la sauvegarde « $($f.Label) ».") | Where-Object { $_ }) -join "`n"
            Write-Log "Notes reprises de $($f.Path)"
            return
        } catch { Write-Log "Sauvegarde de notes illisible ($($f.Path)) : $($_.Exception.Message)" }
    }
    $NB.LoadNotice = (@($NB.LoadNotice, "Ton fichier de notes était abîmé 😬 et je n'ai pas trouvé de sauvegarde. Il est gardé dans $bad.") | Where-Object { $_ }) -join "`n"
}

function Load-NotesTrash {
    $NB.NotesTrash.Clear()
    if (-not (Test-Path -LiteralPath $NotesTrashFile)) { return }
    try {
        $limit = (Get-Date).AddDays(-$NotesTrashDays).ToString('s')
        $data = ConvertFrom-Json ([IO.File]::ReadAllText($NotesTrashFile))
        foreach ($n in $data) {
            if (-not $n -or -not [string]$n.text) { continue }
            $del = To-IsoString $n.deletedAt
            if ($del -and $del -lt $limit) { continue }   # plus de 30 jours : on oublie
            $c = ConvertTo-Note $n
            $c | Add-Member -NotePropertyName deletedAt -NotePropertyValue $(if ($del) { $del } else { (Get-Date).ToString('s') })
            [void]$NB.NotesTrash.Add($c)
        }
    } catch { Write-Log "Lecture corbeille des notes : $($_.Exception.Message)" }
}

function Save-NotesTrash {
    try { Write-FileSafe $NotesTrashFile (ConvertTo-JsonArray $NB.NotesTrash) }
    catch { Write-Log "Ecriture corbeille des notes : $($_.Exception.Message)" }
}

function Save-Notes {
    try {
        # une copie par jour, avant la premiere modification (7 jours gardes)
        $day = (Get-Date).ToString('yyyy-MM-dd')
        if ($NB.NotesBackupDay -ne $day -and (Test-Path -LiteralPath $NotesFile)) {
            if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
            $dest = Join-Path $BackupDir "notes-$day.json"
            if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $NotesFile -Destination $dest -Force }
            Limit-Backups 'notes-????-??-??.json' $NotesKeepDays
            $NB.NotesBackupDay = $day
        }
        $json = ConvertTo-JsonArray $NB.Notes
        Write-FileSafe $NotesFile $json
        $md = Get-NotesText
        Write-FileSafe $NotesMd $md
        Write-NotesMirror $json $md
    } catch { Write-Log "Ecriture notes : $($_.Exception.Message)" }
}

# Toutes les notes en texte lisible (pour notes.md, la copie automatique et « Enregistrer une copie »)
function Get-NotesText {
    $lines = @('# Notes rapides d''Orbit', '', "_Mis à jour le $((Get-Date).ToString('dd/MM/yyyy HH:mm'))_", '')
    foreach ($n in (Get-SortedNotes)) {
        $lines += "## $(([datetime]$n.updated).ToString('dd/MM/yyyy HH:mm'))$(if ($n.pinned) { ' 📌' })"
        $lines += ''; $lines += $n.text; $lines += ''
    }
    return ($lines -join "`r`n")
}

# Copie automatique dans le dossier choisi (si il est la : cle USB debranchee = on attend)
function Write-NotesMirror([string]$json, [string]$md) {
    $dir = [string]$Config.NotesMirror
    if (-not $dir) { return }
    if (-not (Test-Path -LiteralPath $dir)) {
        if (-not $script:MirrorMissingLogged) { Write-Log "Copie des notes : dossier introuvable ($dir)"; $script:MirrorMissingLogged = $true }
        return
    }
    $script:MirrorMissingLogged = $false
    try {
        Write-FileSafe (Join-Path $dir 'Orbit-notes.json') $json
        Write-FileSafe (Join-Path $dir 'Orbit-notes.md') $md
    } catch { Write-Log "Copie des notes dans $dir : $($_.Exception.Message)" }
}

# epinglees d'abord, puis la plus recemment modifiee
function Get-SortedNotes {
    @($NB.Notes | Sort-Object -Property @{ e = { [int](-not $_.pinned) } }, @{ e = { [string]$_.updated }; Descending = $true })
}

function Find-Note([string]$id) { foreach ($n in $NB.Notes) { if ($n.id -eq $id) { return $n } } }

function Add-Note([string]$text) {
    $text = $text.Trim()
    if (-not $text) { return $null }
    $now = (Get-Date).ToString('s')
    $n = [pscustomobject]@{ id = (New-Id); text = $text; created = $now; updated = $now; pinned = $false }
    $NB.Notes.Insert(0, $n)
    Save-Notes
    return $n
}

function Update-Note([string]$id, [string]$text) {
    $n = Find-Note $id
    if (-not $n) { return }
    $text = $text.Trim()
    if (-not $text) { Remove-Note $id; return }
    if ($n.text -ne $text) { $n.text = $text; $n.updated = (Get-Date).ToString('s'); Save-Notes }
}

# Supprimer = mettre a la corbeille (sauf -NoTrash, par ex. quand la note devient une carte)
function Remove-Note([string]$id, [switch]$NoTrash) {
    $n = Find-Note $id
    if (-not $n) { return }
    $NB.Notes.Remove($n)
    if (-not $NoTrash) {
        $t = ConvertTo-Note $n
        $t | Add-Member -NotePropertyName deletedAt -NotePropertyValue (Get-Date).ToString('s')
        $NB.NotesTrash.Insert(0, $t)
        while ($NB.NotesTrash.Count -gt 200) { $NB.NotesTrash.RemoveAt($NB.NotesTrash.Count - 1) }
        Save-NotesTrash
    }
    Save-Notes
}

function Restore-TrashedNote([string]$id) {
    $t = $NB.NotesTrash | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $t) { return }
    $NB.NotesTrash.Remove($t)
    $n = ConvertTo-Note $t
    if (Find-Note $n.id) { $n.id = New-Id }
    $NB.Notes.Insert(0, $n)
    Save-NotesTrash
    Save-Notes
    Render-Notes; Update-Tabs
    Show-Bubble "♻️ Note « $(Get-NoteTitle $n 40) » récupérée." -Force -Seconds 3
}

function Clear-NotesTrash {
    $NB.NotesTrash.Clear()
    Save-NotesTrash
}

function Set-NotePinned([string]$id, [bool]$on) {
    $n = Find-Note $id
    if ($n) { $n.pinned = $on; Save-Notes }
}

function Get-NoteTitle($n, [int]$max = 60) {
    $first = @($n.text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $first.Count) { return '' }
    return (Short-Text $first[0].Trim() $max)
}

# 1re ligne = titre de la carte, le reste = description (les raccourcis !2 et @14h marchent)
function Convert-NoteToCard([string]$id) {
    $n = Find-Note $id
    if (-not $n) { return $null }
    $lines = @($n.text -split "`r?`n")
    $i = 0
    while ($i -lt $lines.Count -and -not $lines[$i].Trim()) { $i++ }
    $title = $lines[$i].Trim()
    if ($title.Length -gt 150) { $title = $title.Substring(0, 147) + '…' }
    $desc = (@($lines | Select-Object -Skip ($i + 1)) -join "`r`n").Trim()
    $NB.LastAddedId = ''
    Add-Todo $title
    $t = Find-Todo $NB.LastAddedId
    if (-not $t) { return $null }
    if ($desc) { $t.desc = $desc; Save-Todos }
    Remove-Note $id -NoTrash
    $b = Get-Board $t.board
    Show-Bubble "🗂️ Note transformée en carte dans « $($b.name) »." -Force -Seconds 4
    Render-Notes
    return $t
}

function Copy-NoteText([string]$id) {
    $n = Find-Note $id
    if ($n) { Copy-Clip ([pscustomobject]@{ kind = 'text'; text = $n.text; files = @() }) }
}

# --- sauvegardes des notes ------------------------------------------------------
# Copies du jour + copies « avant restauration », la plus recente d'abord : @{ Path ; Label ; Count }
function Get-NoteBackupFiles {
    $out = @()
    if (Test-Path -LiteralPath $BackupDir) {
        $files = @(Get-ChildItem -Path $BackupDir -Filter 'notes-*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^notes-(\d{4}-\d{2}-\d{2}|undo-\d{4}-\d{2}-\d{2}_\d{6})\.json$' } |
            Sort-Object LastWriteTime -Descending)
        foreach ($f in $files) {
            $label = $f.BaseName
            if ($f.Name -match '^notes-(\d{4}-\d{2}-\d{2})\.json$') {
                $d = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
                $when = if ($d.Date -eq (Get-Date).Date) { "aujourd'hui" } elseif ($d.Date -eq (Get-Date).Date.AddDays(-1)) { 'hier' } else { $d.ToString('dd/MM') }
                $label = "début de journée, $when"
            } elseif ($f.Name -match '^notes-undo-(\d{4}-\d{2}-\d{2}_\d{6})\.json$') {
                $label = "juste avant la restauration du $(([datetime]::ParseExact($Matches[1], 'yyyy-MM-dd_HHmmss', $null)).ToString('dd/MM à HH:mm'))"
            }
            $out += [pscustomobject]@{ Path = $f.FullName; Label = $label }
        }
    }
    # la copie automatique (OneDrive, cle USB...) : utile apres un changement de PC
    if ($Config.NotesMirror) {
        $m = Join-Path ([string]$Config.NotesMirror) 'Orbit-notes.json'
        if (Test-Path -LiteralPath $m) {
            $out += [pscustomobject]@{ Path = $m; Label = "copie automatique du $((Get-Item -LiteralPath $m).LastWriteTime.ToString('dd/MM à HH:mm')) ($($Config.NotesMirror))" }
        }
    }
    return $out
}

# Remplace toutes les notes par celles d'une sauvegarde ; l'etat actuel est garde (annulable)
function Restore-Notes([string]$path, [string]$label = '', [switch]$NoConfirm) {
    try { $list = Read-NotesFile $path } catch { [void][Windows.MessageBox]::Show("Cette sauvegarde est illisible : $($_.Exception.Message)", 'Orbit'); return $false }
    if (-not $NoConfirm -and -not (Confirm-Action "Remplacer tes $($NB.Notes.Count) note(s) par les $($list.Count) de la sauvegarde « $label » ?`n(L'état actuel est gardé : tu pourras revenir en arrière avec 🕘.)")) { return $false }
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    if (Test-Path -LiteralPath $NotesFile) {
        $undo = Join-Path $BackupDir ("notes-undo-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
        Copy-Item -LiteralPath $NotesFile -Destination $undo -Force
        Limit-Backups 'notes-undo-*.json' 5
    }
    $NB.Notes.Clear()
    foreach ($n in $list) { [void]$NB.Notes.Add($n) }
    Save-Notes
    Render-Notes; Update-Tabs
    Show-Bubble "📝 Notes restaurées ($($list.Count)) ↩️" -Force -Seconds 4
    return $true
}

function Export-NotesCopy([string]$path) {
    if (-not $path) {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'Enregistrer une copie de mes notes'
        $dlg.Filter = 'Texte (*.txt)|*.txt|Markdown (*.md)|*.md'
        $dlg.FileName = "Mes notes Orbit $((Get-Date).ToString('yyyy-MM-dd')).txt"
        $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if (-not $dlg.ShowDialog()) { return $null }
        $path = $dlg.FileName
    }
    [IO.File]::WriteAllText($path, (Get-NotesText), (New-Object Text.UTF8Encoding($true)))
    Show-Bubble "💾 Copie de tes $($NB.Notes.Count) note(s) enregistrée : $([IO.Path]::GetFileName($path))" -Force -Seconds 5
    return $path
}

function Set-NotesMirror([string]$dir) {
    $Config.NotesMirror = $dir
    Save-Settings
    if ($dir) {
        Save-Notes
        Show-Bubble "☁️ Tes notes sont maintenant copiées automatiquement dans :`n$dir`n(Orbit-notes.md à lire, Orbit-notes.json pour restaurer)" -Force -Seconds 7
    } else {
        Show-Bubble "Ok, plus de copie automatique des notes." -Force -Seconds 3
    }
    Render-Notes
}

function Choose-NotesMirror {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Dossier où copier automatiquement tes notes (OneDrive, dossier réseau, clé USB…)'
    $od = $env:OneDrive
    $dlg.SelectedPath = if ($Config.NotesMirror) { $Config.NotesMirror } elseif ($od -and (Test-Path -LiteralPath $od)) { $od } else { [Environment]::GetFolderPath('MyDocuments') }
    if ($dlg.ShowDialog() -eq 'OK' -and $dlg.SelectedPath) { Set-NotesMirror $dlg.SelectedPath }
}

function Show-NotesBackupMenu($btn) {
    $m = New-Object Windows.Controls.ContextMenu
    $title = New-Object Windows.Controls.MenuItem
    $title.Header = '↩️ Revenir à une sauvegarde'; $title.IsEnabled = $false; $title.FontWeight = 'Bold'
    [void]$m.Items.Add($title)
    $backs = @(Get-NoteBackupFiles)
    if (-not $backs.Count) {
        $none = New-Object Windows.Controls.MenuItem
        $none.Header = '    Pas encore de sauvegarde (une copie est faite chaque jour)'; $none.IsEnabled = $false
        [void]$m.Items.Add($none)
    }
    foreach ($b in $backs) {
        $count = try { "$(@(Read-NotesFile $b.Path).Count) note(s)" } catch { 'illisible' }
        $it = New-TaggedItem "    $($b.Label) — $count" "$($b.Path)|$($b.Label)" { param($s, $e) Invoke-Safe { $p = $s.Tag.Split('|', 2); [void](Restore-Notes $p[0] $p[1]) } }
        $it.IsEnabled = $count -ne 'illisible'
        [void]$m.Items.Add($it)
    }
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    $trash = New-Object Windows.Controls.MenuItem
    $trash.Header = "🗑️  Corbeille ($($NB.NotesTrash.Count))"
    if ($NB.NotesTrash.Count) {
        foreach ($t in ($NB.NotesTrash | Select-Object -First 25)) {
            $when = try { ([datetime]$t.deletedAt).ToString('dd/MM HH:mm') } catch { '' }
            [void]$trash.Items.Add((New-TaggedItem "♻️  $(Get-NoteTitle $t 45)  (supprimée le $when)" $t.id { param($s, $e) Invoke-Safe { Restore-TrashedNote $s.Tag } }))
        }
        [void]$trash.Items.Add((New-Object Windows.Controls.Separator))
        [void]$trash.Items.Add((New-TaggedItem '🧹  Vider la corbeille' $null { param($s, $e) Invoke-Safe { if (Confirm-Action 'Vider la corbeille des notes ? (Elles seront perdues.)') { Clear-NotesTrash } } }))
    } else {
        $none = New-Object Windows.Controls.MenuItem
        $none.Header = "Vide (une note supprimée y reste $NotesTrashDays jours)"; $none.IsEnabled = $false
        [void]$trash.Items.Add($none)
    }
    [void]$m.Items.Add($trash)
    [void]$m.Items.Add((New-Object Windows.Controls.Separator))
    [void]$m.Items.Add((New-TaggedItem '💾  Enregistrer une copie de mes notes…' $null { param($s, $e) Invoke-Safe { [void](Export-NotesCopy) } }))
    $mir = if ($Config.NotesMirror) { "☁️  Copie automatique : $(Short-Text $Config.NotesMirror 40) (changer…)" } else { '☁️  Copie automatique dans un dossier (OneDrive, clé USB…)…' }
    [void]$m.Items.Add((New-TaggedItem $mir $null { param($s, $e) Invoke-Safe { Choose-NotesMirror } }))
    if ($Config.NotesMirror) { [void]$m.Items.Add((New-TaggedItem '✖  Arrêter la copie automatique' $null { param($s, $e) Invoke-Safe { Set-NotesMirror '' } })) }
    [void]$m.Items.Add((New-TaggedItem '📂  Ouvrir le dossier des sauvegardes' $null {
                param($s, $e) Invoke-Safe { if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }; Start-Process explorer.exe $BackupDir } }))
    $m.PlacementTarget = $btn
    $m.IsOpen = $true
}

# --- le post-it ------------------------------------------------------------
[xml]$QuickNoteXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Note rapide" Width="360" SizeToContent="Height" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" FontFamily="Segoe UI" FontSize="13.5">
  <Border Margin="8" CornerRadius="14" Background="#FFF4B8" BorderBrush="#1E1B3A" BorderThickness="2.5">
    <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="-45" Opacity="0.25"/></Border.Effect>
    <DockPanel Margin="12,8,12,10">
      <Grid x:Name="QnHeader" DockPanel.Dock="Top" Background="Transparent" Margin="0,0,0,6" Cursor="SizeAll">
        <TextBlock Text="📝 Note rapide" FontWeight="Bold" FontSize="14" Foreground="#1E1B3A" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="QnWhen" Foreground="#8A7A3A" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,8,0"/>
          <Button x:Name="QnClose" Content="✕" Width="24" Height="22" Background="Transparent" BorderThickness="0"
                  Cursor="Hand" ToolTip="Fermer (la note est gardée)"/>
        </StackPanel>
      </Grid>
      <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0">
        <TextBlock x:Name="QnHint" Text="Gardée automatiquement" Foreground="#8A7A3A" FontSize="11" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="QnCard" Content="🗂️ En carte" Padding="8,3" Margin="0,0,6,0" Cursor="Hand"
                  Background="#FFFDF0" BorderBrush="#D9C66A" ToolTip="Transformer en carte : 1re ligne = titre, le reste = description"/>
          <Button x:Name="QnCopy" Content="📋" Width="30" Margin="0,0,6,0" Cursor="Hand" Background="#FFFDF0" BorderBrush="#D9C66A" ToolTip="Copier le texte"/>
          <Button x:Name="QnDelete" Content="🗑️" Width="30" Margin="0,0,6,0" Cursor="Hand" Background="#FFFDF0" BorderBrush="#D9C66A" ToolTip="Jeter cette note"/>
          <Button x:Name="QnSave" Content="✓ OK" Padding="12,3" Cursor="Hand" Background="#1E1B3A" Foreground="White" BorderThickness="0"/>
        </StackPanel>
      </Grid>
      <TextBox x:Name="QnText" AcceptsReturn="True" AcceptsTab="False" TextWrapping="Wrap" MinHeight="120" MaxHeight="340"
               VerticalScrollBarVisibility="Auto" Background="#FFFBDD" BorderBrush="#E6D57A" BorderThickness="1" Padding="6,4"/>
    </DockPanel>
  </Border>
</Window>
'@
$script:qnWin = $null
$script:qnId = ''
$script:qnClosing = $false

function Initialize-QuickNote {
    if ($script:qnWin) { return }
    $script:qnWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $QuickNoteXaml))
    $script:qn = @{}
    foreach ($n in 'QnHeader', 'QnWhen', 'QnClose', 'QnHint', 'QnCard', 'QnCopy', 'QnDelete', 'QnSave', 'QnText') { $qn[$n] = $qnWin.FindName($n) }
    $qn.QnHeader.Add_MouseLeftButtonDown({ try { $qnWin.DragMove() } catch {} })
    $qn.QnClose.Add_Click({ Invoke-Safe { Close-QuickNote } })
    $qn.QnSave.Add_Click({ Invoke-Safe { Close-QuickNote } })
    $qn.QnCard.Add_Click({ Invoke-Safe { Close-QuickNote -ToCard } })
    $qn.QnCopy.Add_Click({ Invoke-Safe { if ($qn.QnText.Text.Trim()) { Copy-Clip ([pscustomobject]@{ kind = 'text'; text = $qn.QnText.Text; files = @() }) } } })
    $qn.QnDelete.Add_Click({ Invoke-Safe { $qn.QnText.Text = ''; Close-QuickNote } })
    $qn.QnText.Add_TextChanged({ $qn.QnHint.Text = if ($qn.QnText.Text.Trim()) { "$(@($qn.QnText.Text -split '\s+' | Where-Object { $_ }).Count) mot(s) · gardée automatiquement" } else { 'Gardée automatiquement' } })
    # on clique ailleurs : la note est gardee et le post-it se range
    $qnWin.Add_Deactivated({ Invoke-Safe { Close-QuickNote } })
    $qnWin.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $e.Handled = $true; Invoke-Safe { Close-QuickNote } } })
    $qnWin.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Invoke-Safe { Close-QuickNote } } })
}

# Ouvre le post-it : vide pour une nouvelle note, ou avec une note existante ($id)
function Show-QuickNote([string]$id = '') {
    Initialize-QuickNote
    if ($qnWin.IsVisible) { Close-QuickNote }   # une autre note etait ouverte : on la garde d'abord
    $n = if ($id) { Find-Note $id }
    $script:qnId = if ($n) { $n.id } else { '' }
    $qn.QnText.Text = if ($n) { $n.text } else { '' }
    $qn.QnWhen.Text = if ($n) { "du $(([datetime]$n.updated).ToString('dd/MM à HH:mm'))" } else { (Get-Date).ToString('dd/MM à HH:mm') }
    $qn.QnDelete.Visibility = if ($n) { 'Visible' } else { 'Collapsed' }
    if (-not $qnWin.IsVisible) {
        # au milieu de l'ecran ou se trouve la souris
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position))
        $qnWin.Left = ($wa.L + $wa.R) / 2 - 180
        $qnWin.Top = [math]::Max($wa.T, ($wa.T + $wa.B) / 2 - 170)
        $qnWin.Show()
    }
    $qnWin.Activate() | Out-Null
    $qn.QnText.Focus() | Out-Null
    $qn.QnText.CaretIndex = $qn.QnText.Text.Length
}

function Close-QuickNote([switch]$ToCard) {
    if (-not $script:qnWin -or $script:qnClosing -or -not $qnWin.IsVisible) { return }
    $script:qnClosing = $true
    try {
        $text = $qn.QnText.Text.Trim()
        $isNew = -not $script:qnId
        $qnWin.Hide()
        if ($script:qnId) { Update-Note $script:qnId $text }
        elseif ($text) { $script:qnId = (Add-Note $text).id }
        if ($ToCard -and $script:qnId -and $text) { [void](Convert-NoteToCard $script:qnId) }
        elseif ($isNew -and $text) { Show-Bubble "📝 Noté ! Tu la retrouves dans clic droit > 📝 Mes notes." -Force -Seconds 3 }
        $script:qnId = ''
        Render-Notes
        Update-Tabs
    } finally { $script:qnClosing = $false }
}

# --- l'onglet « Notes » du carnet --------------------------------------------
function Render-Notes {
    if (-not $pn.NotesList -or $NB.Tab -ne 'Notes') { return }
    $pn.NotesList.Children.Clear()
    $list = Get-SortedNotes
    foreach ($n in $list) { [void]$pn.NotesList.Children.Add((New-NoteCard $n)) }
    if (-not $list.Count) {
        $e = New-Object Windows.Controls.TextBlock
        $e.Text = "Aucune note pour l'instant.`nClique sur « ＋ Nouvelle note », ou clic droit sur Orbit > 📝 Note rapide."
        $e.Foreground = '#9A98B0'; $e.TextWrapping = 'Wrap'; $e.TextAlignment = 'Center'; $e.Margin = '4,14,4,0'
        [void]$pn.NotesList.Children.Add($e)
    }
    $txt = "$($list.Count) note(s) · sauvegarde chaque jour"
    if ($Config.NotesMirror) { $txt += " · ☁️ copie auto dans $(Split-Path -Leaf $Config.NotesMirror)" }
    if ($NB.NotesTrash.Count) { $txt += " · 🗑️ $($NB.NotesTrash.Count) dans la corbeille" }
    $pn.NotesCount.Text = $txt
}

function New-NoteButton([string]$label, [string]$tip, [string]$id, [scriptblock]$onClick) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $label; $b.ToolTip = $tip; $b.Tag = $id
    $b.Padding = '6,1'; $b.Margin = '0,0,4,0'; $b.Background = 'Transparent'; $b.BorderThickness = '0'; $b.Cursor = 'Hand'
    $b.Add_Click($onClick)
    return $b
}

function New-NoteCard($n) {
    $card = New-Object Windows.Controls.Border
    $card.Margin = '0,0,0,8'; $card.Padding = '10,6,6,6'; $card.CornerRadius = '10'
    $card.Background = if ($n.pinned) { '#FFEFA0' } else { '#FFF7CC' }
    $card.BorderBrush = '#E6D57A'; $card.BorderThickness = '1'; $card.Cursor = 'Hand'; $card.Tag = $n.id
    $card.ToolTip = 'Clic : modifier'
    $sp = New-Object Windows.Controls.StackPanel
    $head = New-Object Windows.Controls.DockPanel
    $btns = New-Object Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    [void]$btns.Children.Add((New-NoteButton $(if ($n.pinned) { '📌' } else { '📍' }) $(if ($n.pinned) { 'Désépingler' } else { 'Épingler en haut' }) $n.id {
                param($s, $e) $e.Handled = $true; Invoke-Safe { $x = Find-Note $s.Tag; if ($x) { Set-NotePinned $s.Tag (-not $x.pinned); Render-Notes } } }))
    [void]$btns.Children.Add((New-NoteButton '🗂️' 'Transformer en carte (1re ligne = titre)' $n.id { param($s, $e) $e.Handled = $true; Invoke-Safe { [void](Convert-NoteToCard $s.Tag) } }))
    [void]$btns.Children.Add((New-NoteButton '📋' 'Copier le texte' $n.id { param($s, $e) $e.Handled = $true; Invoke-Safe { Copy-NoteText $s.Tag } }))
    [void]$btns.Children.Add((New-NoteButton '🗑️' 'Mettre à la corbeille' $n.id {
                param($s, $e) $e.Handled = $true; Invoke-Safe {
                    Remove-Note $s.Tag; Render-Notes; Update-Tabs
                    Show-Bubble "🗑️ Note mise à la corbeille. Tu peux la récupérer pendant $NotesTrashDays jours : 🕘 Sauvegardes > Corbeille." -Force -Seconds 5
                } }))
    [Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    [void]$head.Children.Add($btns)
    $when = New-Object Windows.Controls.TextBlock
    $when.Text = "$(if ($n.pinned) { '📌 ' })$(([datetime]$n.updated).ToString('dd/MM à HH:mm'))"
    $when.FontSize = 11; $when.Foreground = '#8A7A3A'; $when.VerticalAlignment = 'Center'
    [void]$head.Children.Add($when)
    [void]$sp.Children.Add($head)
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $n.text; $tb.TextWrapping = 'Wrap'; $tb.MaxHeight = 110; $tb.TextTrimming = 'CharacterEllipsis'
    $tb.Foreground = '#1E1B3A'; $tb.Margin = '0,2,0,0'
    [void]$sp.Children.Add($tb)
    $card.Child = $sp
    $card.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Show-QuickNote $s.Tag } })
    return $card
}

Load-Notes
