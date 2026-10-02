<#
    Carnet d'Orbit : to-do en vrac + historique des copier-coller de la journee.
    Ce fichier est charge par orbit.ps1 (il ne se lance pas tout seul).
#>

$TodoFile = Join-Path $DataDir 'todo.json'
$TodoMd = Join-Path $DataDir 'todo.md'
$TodoArchive = Join-Path $DataDir 'todo-archive.md'
$ClipDir = Join-Path $DataDir 'clipboard'
if (-not (Test-Path $ClipDir)) { New-Item -ItemType Directory -Path $ClipDir | Out-Null }

$NB = @{
    Todos      = New-Object System.Collections.ArrayList
    Clips      = New-Object System.Collections.ArrayList
    ClipDay    = (Get-Date).ToString('yyyy-MM-dd')
    ClipSeq    = [uint32]0
    ClipPaused = $false
    LastClip   = ''
    Tab        = 'Todo'
    ClipDirty  = $true
    MaxClips   = 150
    MaxClipLen = 10000
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

function Load-Todos {
    $NB.Todos.Clear()
    if (-not (Test-Path $TodoFile)) { return }
    try {
        $raw = [IO.File]::ReadAllText($TodoFile)
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $archived = @()
        foreach ($t in (ConvertFrom-Json $raw)) {
            $item = [pscustomobject]@{
                id      = [string]$t.id
                text    = [string]$t.text
                done    = [bool]$t.done
                created = To-IsoString $t.created
                doneAt  = To-IsoString $t.doneAt
            }
            # les taches terminees les jours precedents partent dans l'archive
            if ($item.done -and $item.doneAt -and $item.doneAt.Substring(0, 10) -ne $today) {
                $archived += $item
            } else {
                [void]$NB.Todos.Add($item)
            }
        }
        if ($archived.Count) {
            $md = ($archived | Group-Object { $_.doneAt.Substring(0, 10) } | ForEach-Object {
                "`r`n## $($_.Name)`r`n" + (($_.Group | ForEach-Object { "- [x] $($_.text)" }) -join "`r`n")
            }) -join "`r`n"
            Add-Content -Path $TodoArchive -Value $md -Encoding UTF8
            Save-Todos
        }
    } catch { Write-Log "Lecture to-do : $($_.Exception.Message)" }
}

# Sauvegarde a chaque modification (ajout, coche, suppression)
function Save-Todos {
    try {
        Write-FileSafe $TodoFile (ConvertTo-JsonArray $NB.Todos)
        $lines = @("# To-do Orbit", "", "_Mis à jour le $((Get-Date).ToString('dd/MM/yyyy HH:mm'))_", "")
        foreach ($t in $NB.Todos) { $lines += $(if ($t.done) { "- [x] $($t.text)" } else { "- [ ] $($t.text)" }) }
        Write-FileSafe $TodoMd ($lines -join "`r`n")
    } catch { Write-Log "Ecriture to-do : $($_.Exception.Message)" }
}

function Add-Todo([string]$text) {
    $text = $text.Trim()
    if (-not $text) { return }
    [void]$NB.Todos.Add([pscustomobject]@{
        id      = [guid]::NewGuid().ToString('N')
        text    = $text
        done    = $false
        created = (Get-Date).ToString('s')
        doneAt  = ''
    })
    Save-Todos
    Render-Todos
    Show-Bubble (Pick @("Noté ! ✍️", "C'est dans la liste 📝", "Hop, enregistré 💾", "Je m'en souviendrai pour toi 🧠")) -Force -Seconds 3
}

function Find-Todo([string]$id) { foreach ($t in $NB.Todos) { if ($t.id -eq $id) { return $t } } }

function Set-TodoDone([string]$id, [bool]$done, [switch]$Quiet) {
    $t = Find-Todo $id
    if (-not $t) { return }
    $t.done = $done
    $t.doneAt = if ($done) { (Get-Date).ToString('s') } else { '' }
    Save-Todos
    Render-Todos
    if ($done -and -not $Quiet) {
        $left = @($NB.Todos | Where-Object { -not $_.done }).Count
        if ($left -eq 0) { Show-Bubble "Tout est coché ! Tu es une machine 🎉" -Force -Seconds 5 }
        else { Show-Bubble (Pick @("Bien joué ✅", "Une de moins ! 💪", "Coché, ça fait du bien hein 😌")) -Force -Seconds 3 }
    }
}

function Remove-Todo([string]$id) {
    $t = Find-Todo $id
    if ($t) { $NB.Todos.Remove($t); Save-Todos; Render-Todos }
}

function Clear-DoneTodos {
    $done = @($NB.Todos | Where-Object { $_.done })
    if (-not $done.Count) { return }
    $md = "`r`n## $((Get-Date).ToString('yyyy-MM-dd'))`r`n" + (($done | ForEach-Object { "- [x] $($_.text)" }) -join "`r`n")
    Add-Content -Path $TodoArchive -Value $md -Encoding UTF8
    foreach ($t in $done) { $NB.Todos.Remove($t) }
    Save-Todos
    Render-Todos
}

function Get-NextTodo { foreach ($t in $NB.Todos) { if (-not $t.done) { return $t } } }
function Get-OpenTodos { @($NB.Todos | Where-Object { -not $_.done }) }

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
        Title="Carnet d'Orbit" Width="380" Height="540"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="NoResize" UseLayoutRounding="True"
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
        <!-- ===== To-do ===== -->
        <DockPanel x:Name="TodoPanel" Margin="14,0,14,12">
          <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TodoInput" Padding="8,6" BorderBrush="#1E1B3A" BorderThickness="2"
                     VerticalContentAlignment="Center"/>
            <TextBlock x:Name="TodoHint" Text="Note une tâche en vrac… (Entrée)" Margin="12,0,0,0"
                       VerticalAlignment="Center" Foreground="#9A98B0" IsHitTestVisible="False"/>
            <Button x:Name="TodoAdd" Grid.Column="1" Content="＋" Width="38" Margin="6,0,0,0"
                    FontSize="16" FontWeight="Bold" Cursor="Hand" Foreground="White"
                    Background="#6C5CE7" BorderBrush="#1E1B3A" BorderThickness="2"/>
          </Grid>
          <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <TextBlock x:Name="TodoCount" VerticalAlignment="Center" Foreground="#6B6880"/>
            <Button x:Name="TodoClear" Content="🧹 Archiver les terminées" HorizontalAlignment="Right"
                    Padding="10,4" Cursor="Hand" Background="#EEEEF5" BorderThickness="0"/>
          </Grid>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="TodoList"/>
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
foreach ($n in 'Header','CloseBtn','TabTodo','TabClip','TodoPanel','TodoInput','TodoHint','TodoAdd','TodoCount',
               'TodoClear','TodoList','ClipPanel','ClipSearch','ClipHint','ClipCount','ClipPause','ClipClear','ClipList') {
    $pn[$n] = $panel.FindName($n)
}

function Update-Tabs {
    $open = @($NB.Todos | Where-Object { -not $_.done }).Count
    $pn.TabTodo.Content = "📝 To-do ($open)"
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

function Render-Todos {
    $pn.TodoList.Children.Clear()
    if ($NB.Todos.Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = "Rien pour l'instant.`nNote tout ce qui te passe par la tête, je garde tout au chaud 🧠"
        $empty.Foreground = '#9A98B0'; $empty.TextWrapping = 'Wrap'; $empty.Margin = '4,10,4,0'
        $empty.TextAlignment = 'Center'
        [void]$pn.TodoList.Children.Add($empty)
    }
    # les taches a faire d'abord, les terminees ensuite
    $ordered = @($NB.Todos | Where-Object { -not $_.done }) + @($NB.Todos | Where-Object { $_.done })
    foreach ($t in $ordered) {
        $row = New-Object Windows.Controls.Grid
        $row.Margin = '0,0,0,4'
        $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = '*'
        $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
        $c3 = New-Object Windows.Controls.ColumnDefinition; $c3.Width = 'Auto'
        $row.ColumnDefinitions.Add($c1); $row.ColumnDefinitions.Add($c2); $row.ColumnDefinitions.Add($c3)

        $cb = New-Object Windows.Controls.CheckBox
        $cb.IsChecked = $t.done
        $cb.Tag = $t.id
        $cb.VerticalContentAlignment = 'Top'
        $cb.Padding = '6,0,0,0'
        $cb.Cursor = 'Hand'
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = $t.text
        $tb.TextWrapping = 'Wrap'
        if ($t.done) { $tb.TextDecorations = [Windows.TextDecorations]::Strikethrough; $tb.Foreground = '#9A98B0' }
        else { $tb.Foreground = '#1E1B3A' }
        $cb.Content = $tb
        $cb.Add_Click({ param($s, $e) Invoke-Safe { Set-TodoDone $s.Tag ([bool]$s.IsChecked) } })
        [void]$row.Children.Add($cb)

        $when = New-Object Windows.Controls.TextBlock
        $when.Text = Format-Day $t.created
        $when.FontSize = 11; $when.Foreground = '#B0AEC4'; $when.Margin = '6,1,4,0'
        [Windows.Controls.Grid]::SetColumn($when, 1)
        [void]$row.Children.Add($when)

        $del = New-Object Windows.Controls.Button
        $del.Content = '✕'; $del.Tag = $t.id; $del.Width = 22; $del.Height = 20
        $del.Background = 'Transparent'; $del.BorderThickness = '0'; $del.Foreground = '#B0AEC4'
        $del.Cursor = 'Hand'; $del.ToolTip = 'Supprimer'; $del.VerticalAlignment = 'Top'
        $del.Add_Click({ param($s, $e) Invoke-Safe { Remove-Todo $s.Tag } })
        [Windows.Controls.Grid]::SetColumn($del, 2)
        [void]$row.Children.Add($del)

        [void]$pn.TodoList.Children.Add($row)
    }
    $done = @($NB.Todos | Where-Object { $_.done }).Count
    $pn.TodoCount.Text = "$done / $($NB.Todos.Count) terminée(s)"
    $pn.TodoClear.IsEnabled = $done -gt 0
    Update-Tabs
}

function Render-Clips {
    $NB.ClipDirty = $false
    $pn.ClipList.Children.Clear()
    $q = $pn.ClipSearch.Text.Trim().ToLowerInvariant()
    $shown = 0
    foreach ($c in $NB.Clips) {
        if ($q -and -not $c.text.ToLowerInvariant().Contains($q)) { continue }
        if (++$shown -gt 80) { break }   # au-dela, la recherche aide a retrouver

        $card = New-Object Windows.Controls.Border
        $card.Margin = '0,0,0,6'; $card.Padding = '10,6,6,6'; $card.CornerRadius = '10'
        $card.Background = '#F3F1FF'; $card.BorderBrush = '#DDD8FF'; $card.BorderThickness = '1'
        $card.Cursor = 'Hand'; $card.Tag = $c
        $tip = if ($c.text.Length -gt 800) { $c.text.Substring(0, 800) + '…' } else { $c.text }
        $card.ToolTip = $tip

        $g = New-Object Windows.Controls.Grid
        $gc1 = New-Object Windows.Controls.ColumnDefinition; $gc1.Width = '*'
        $gc2 = New-Object Windows.Controls.ColumnDefinition; $gc2.Width = 'Auto'
        $g.ColumnDefinitions.Add($gc1); $g.ColumnDefinitions.Add($gc2)

        $sp = New-Object Windows.Controls.StackPanel
        $head = New-Object Windows.Controls.TextBlock
        $icon = if ($c.kind -eq 'files') { '📁 Fichier(s)' } else { '📝 Texte' }
        $head.Text = "$($c.time)  ·  $icon"
        $head.FontSize = 11; $head.Foreground = '#8A87A3'
        $body = New-Object Windows.Controls.TextBlock
        $preview = ($c.text -replace '\s+', ' ').Trim()
        if ($preview.Length -gt 220) { $preview = $preview.Substring(0, 220) + '…' }
        $body.Text = $preview
        $body.TextWrapping = 'Wrap'; $body.MaxHeight = 38; $body.TextTrimming = 'CharacterEllipsis'
        $body.Foreground = '#1E1B3A'
        [void]$sp.Children.Add($head); [void]$sp.Children.Add($body)
        [void]$g.Children.Add($sp)

        $del = New-Object Windows.Controls.Button
        $del.Content = '✕'; $del.Tag = $c; $del.Width = 22; $del.Height = 20; $del.VerticalAlignment = 'Top'
        $del.Background = 'Transparent'; $del.BorderThickness = '0'; $del.Foreground = '#B0AEC4'
        $del.Cursor = 'Hand'; $del.ToolTip = "Retirer de l'historique"
        $del.Add_Click({ param($s, $e) Invoke-Safe { $NB.Clips.Remove($s.Tag); Save-Clips; Render-Clips } })
        [Windows.Controls.Grid]::SetColumn($del, 1)
        [void]$g.Children.Add($del)

        $card.Child = $g
        $card.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Copy-Clip $s.Tag } })
        [void]$pn.ClipList.Children.Add($card)
    }
    if ($shown -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = if ($q) { "Rien ne correspond à « $q »" } else { "Aucun copier-coller aujourd'hui.`nFais un Ctrl+C quelque part, je m'en souviendrai 📋" }
        $empty.Foreground = '#9A98B0'; $empty.TextWrapping = 'Wrap'; $empty.Margin = '4,10,4,0'
        $empty.TextAlignment = 'Center'
        [void]$pn.ClipList.Children.Add($empty)
    }
    $pn.ClipCount.Text = "$($NB.Clips.Count) aujourd'hui"
    Update-Tabs
}

function Select-Tab([string]$tab) {
    $NB.Tab = $tab
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
    }
    $panel.Activate() | Out-Null
    Select-Tab $tab
}

function Close-Notebook { $panel.Hide() }

# --- evenements du carnet ---
$pn.Header.Add_MouseLeftButtonDown({ try { $panel.DragMove() } catch {} })
$pn.CloseBtn.Add_Click({ Close-Notebook })
$panel.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Close-Notebook } })
$panel.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { Close-Notebook } })
$pn.TabTodo.Add_Click({ Invoke-Safe { Select-Tab 'Todo' } })
$pn.TabClip.Add_Click({ Invoke-Safe { Select-Tab 'Clip' } })

$pn.TodoInput.Add_TextChanged({ $pn.TodoHint.Visibility = if ($pn.TodoInput.Text) { 'Collapsed' } else { 'Visible' } })
$pn.TodoInput.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') {
        $e.Handled = $true
        Invoke-Safe { Add-Todo $pn.TodoInput.Text; $pn.TodoInput.Clear() }
    }
})
$pn.TodoAdd.Add_Click({ Invoke-Safe { Add-Todo $pn.TodoInput.Text; $pn.TodoInput.Clear(); $pn.TodoInput.Focus() | Out-Null } })
$pn.TodoClear.Add_Click({ Invoke-Safe { Clear-DoneTodos } })

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
        $r = [Windows.MessageBox]::Show($panel, "Effacer tout l'historique des copier-coller d'aujourd'hui ?", 'Orbit', 'YesNo', 'Question')
        if ($r -eq 'Yes') { $NB.Clips.Clear(); $NB.LastClip = ''; Save-Clips; Render-Clips }
    }
})

Load-Todos
Load-Clips
Update-Tabs
