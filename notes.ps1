# ---------------------------------------------------------------------------
#  Notes rapides : un petit post-it qu'on ouvre d'un clic (clic droit sur
#  Orbit > Note rapide, ou l'icone pres de l'horloge), on ecrit, et c'est
#  garde. On les retrouve dans l'onglet « 📝 Notes » du carnet, on peut les
#  transformer en carte, les epingler, les copier. Sauvegarde : notes.json
#  (+ une copie lisible notes.md, et une copie par jour dans sauvegardes\).
# ---------------------------------------------------------------------------
$NotesFile = Join-Path $DataDir 'notes.json'
$NotesMd = Join-Path $DataDir 'notes.md'
$NB.Notes = New-Object System.Collections.ArrayList
$NB.NotesBackupDay = ''

function Load-Notes {
    $NB.Notes.Clear()
    if (-not (Test-Path -LiteralPath $NotesFile)) { return }
    try {
        foreach ($n in @(ConvertFrom-Json ([IO.File]::ReadAllText($NotesFile)))) {
            if (-not $n -or -not [string]$n.text) { continue }
            [void]$NB.Notes.Add([pscustomobject]@{
                id = $(if ($n.id) { [string]$n.id } else { New-Id }); text = [string]$n.text
                created = To-IsoString $n.created; updated = To-IsoString $n.updated; pinned = [bool]$n.pinned
            })
        }
    } catch { Write-Log "Lecture notes : $($_.Exception.Message)" }
}

function Save-Notes {
    try {
        # une copie par jour, avant la premiere modification (7 jours gardes)
        $day = (Get-Date).ToString('yyyy-MM-dd')
        if ($NB.NotesBackupDay -ne $day -and (Test-Path -LiteralPath $NotesFile)) {
            if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
            $dest = Join-Path $BackupDir "notes-$day.json"
            if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $NotesFile -Destination $dest -Force }
            Limit-Backups 'notes-*.json' $BackupKeep
            $NB.NotesBackupDay = $day
        }
        Write-FileSafe $NotesFile (ConvertTo-JsonArray $NB.Notes)
        $lines = @('# Notes rapides d''Orbit', '')
        foreach ($n in (Get-SortedNotes)) {
            $lines += "## $(([datetime]$n.updated).ToString('dd/MM/yyyy HH:mm'))$(if ($n.pinned) { ' 📌' })"
            $lines += ''; $lines += $n.text; $lines += ''
        }
        Write-FileSafe $NotesMd ($lines -join "`r`n")
    } catch { Write-Log "Ecriture notes : $($_.Exception.Message)" }
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

function Remove-Note([string]$id) {
    $n = Find-Note $id
    if ($n) { $NB.Notes.Remove($n); Save-Notes }
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
    Remove-Note $id
    $b = Get-Board $t.board
    Show-Bubble "🗂️ Note transformée en carte dans « $($b.name) »." -Force -Seconds 4
    Render-Notes
    return $t
}

function Copy-NoteText([string]$id) {
    $n = Find-Note $id
    if ($n) { Copy-Clip ([pscustomobject]@{ kind = 'text'; text = $n.text; files = @() }) }
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
    $pn.NotesCount.Text = "$($list.Count) note(s) · clic sur une note pour la modifier"
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
    [void]$btns.Children.Add((New-NoteButton '🗑️' 'Supprimer' $n.id {
                param($s, $e) $e.Handled = $true; Invoke-Safe { if (Confirm-Action 'Supprimer cette note ?') { Remove-Note $s.Tag; Render-Notes; Update-Tabs } } }))
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
