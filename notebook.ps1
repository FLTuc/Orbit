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
    EditId     = ''
    EditOrig   = ''
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

# Priorite : 1 = la plus urgente ... 10 = la moins urgente (5 par defaut)
$DefaultPrio = 5
function Limit-Prio($p) {
    $n = 0
    if (-not [int]::TryParse([string]$p, [ref]$n)) { return $DefaultPrio }
    return [math]::Min(10, [math]::Max(1, $n))
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
                desc    = [string]$t.desc
                prio    = Limit-Prio $t.prio
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
        foreach ($t in (Get-SortedTodos)) {
            $lines += $(if ($t.done) { "- [x] (P$($t.prio)) $($t.text)" } else { "- [ ] (P$($t.prio)) $($t.text)" })
            if ($t.desc) { foreach ($d in ($t.desc -split "`r?`n")) { $lines += "    > $d" } }
        }
        Write-FileSafe $TodoMd ($lines -join "`r`n")
    } catch { Write-Log "Ecriture to-do : $($_.Exception.Message)" }
}

function Add-Todo([string]$text, $prio = $DefaultPrio) {
    $text = $text.Trim()
    # raccourci : "!2 Appeler Paul" ou "Appeler Paul !2" donne la priorite 2
    if ($text -match '(^|\s)!(10|[1-9])(?=\s|$)') {
        $prio = [int]$Matches[2]
        $text = (($text -replace '(^|\s)!(10|[1-9])(?=\s|$)', ' ') -replace '\s{2,}', ' ').Trim()
    }
    if (-not $text) { return }
    $prio = Limit-Prio $prio
    [void]$NB.Todos.Add([pscustomobject]@{
        id      = [guid]::NewGuid().ToString('N')
        text    = $text
        desc    = ''
        prio    = $prio
        done    = $false
        created = (Get-Date).ToString('s')
        doneAt  = ''
    })
    Save-Todos
    Render-Todos
    $msg = Pick @("Noté ! ✍️", "C'est dans la liste 📝", "Hop, enregistré 💾", "Je m'en souviendrai pour toi 🧠")
    if ($prio -le 2) { $msg += " Priorité $prio, je la mets en haut de la pile 🔥" }
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
    if ($t) {
        if ($NB.EditId -eq $id) { $NB.EditId = ''; $NB.SaveTimer.Stop() }
        $NB.Todos.Remove($t); Save-Todos; Render-Todos
    }
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

# Tri : a faire d'abord, par priorite (1 en premier) puis par date d'ajout ; terminees a la fin
function Get-SortedTodos {
    $open = @($NB.Todos | Where-Object { -not $_.done } | Sort-Object -Property @{ e = { [int]$_.prio } }, created)
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
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TodoInput" Padding="8,6" BorderBrush="#1E1B3A" BorderThickness="2"
                     VerticalContentAlignment="Center"/>
            <TextBlock x:Name="TodoHint" Text="Note une tâche… (Entrée)" Margin="12,0,0,0"
                       VerticalAlignment="Center" Foreground="#9A98B0" IsHitTestVisible="False"/>
            <ComboBox x:Name="TodoPrio" Grid.Column="1" Width="58" Margin="6,0,0,0" VerticalContentAlignment="Center"
                      ToolTip="Priorité : 1 = la plus urgente, 10 = la moins urgente. Astuce : tape « !2 » dans le texte."/>
            <Button x:Name="TodoAdd" Grid.Column="2" Content="＋" Width="38" Margin="6,0,0,0"
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
foreach ($n in 'Header','CloseBtn','TabTodo','TabClip','TodoPanel','TodoInput','TodoHint','TodoPrio','TodoAdd','TodoCount',
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
    foreach ($t in (Get-SortedTodos)) {
        $row = New-Object Windows.Controls.Grid
        $row.Margin = '0,0,0,6'
        foreach ($w in 'Auto', 'Auto', '*', 'Auto', 'Auto', 'Auto') {
            $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w
            $row.ColumnDefinitions.Add($cd)
        }

        # pastille de priorite : un clic ouvre le choix de 1 a 10
        $pb = New-Object Windows.Controls.Button
        $pb.Content = "P$($t.prio)"
        $pb.Tag = $t.id
        $pb.Width = 32; $pb.Height = 20; $pb.Margin = '0,0,6,0'; $pb.VerticalAlignment = 'Top'
        $pb.FontSize = 11; $pb.FontWeight = 'Bold'; $pb.Foreground = 'White'; $pb.BorderThickness = '0'
        $pb.Background = if ($t.done) { '#C9C7D6' } else { Get-PrioColor $t.prio }
        $pb.Cursor = 'Hand'; $pb.ToolTip = 'Priorité (1 = la plus urgente). Clic pour changer.'
        $pb.Add_Click({ param($s, $e) Invoke-Safe { Show-PrioMenu $s } })
        [void]$row.Children.Add($pb)

        $cb = New-Object Windows.Controls.CheckBox
        $cb.IsChecked = $t.done
        $cb.Tag = $t.id
        $cb.VerticalAlignment = 'Top'; $cb.Margin = '0,2,6,0'
        $cb.Cursor = 'Hand'; $cb.ToolTip = 'Cocher comme terminée'
        $cb.Add_Click({ param($s, $e) Invoke-Safe { Set-TodoDone $s.Tag ([bool]$s.IsChecked) } })
        [Windows.Controls.Grid]::SetColumn($cb, 1)
        [void]$row.Children.Add($cb)

        if ($NB.EditId -eq $t.id) {
            $content = New-TodoEditor $t
        } else {
            # titre + apercu de la description ; un clic ouvre la modification
            $content = New-Object Windows.Controls.StackPanel
            $content.Background = 'Transparent'; $content.Cursor = 'Hand'; $content.Tag = $t.id
            $content.ToolTip = 'Clic pour modifier la tâche et sa description'
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = $t.text
            $tb.TextWrapping = 'Wrap'
            if ($t.done) { $tb.TextDecorations = [Windows.TextDecorations]::Strikethrough; $tb.Foreground = '#9A98B0' }
            else { $tb.Foreground = '#1E1B3A' }
            [void]$content.Children.Add($tb)
            if ($t.desc) {
                $dp = New-Object Windows.Controls.TextBlock
                $dp.Text = '📄 ' + (($t.desc -replace '\s+', ' ').Trim())
                $dp.FontSize = 11.5; $dp.Foreground = '#7A7794'; $dp.Margin = '0,1,0,0'
                $dp.TextWrapping = 'Wrap'; $dp.MaxHeight = 32; $dp.TextTrimming = 'CharacterEllipsis'
                [void]$content.Children.Add($dp)
            }
            $content.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Start-EditTodo $s.Tag } })
        }
        [Windows.Controls.Grid]::SetColumn($content, 2)
        [void]$row.Children.Add($content)

        $when = New-Object Windows.Controls.TextBlock
        $when.Text = Format-Day $t.created
        $when.FontSize = 11; $when.Foreground = '#B0AEC4'; $when.Margin = '6,1,4,0'
        [Windows.Controls.Grid]::SetColumn($when, 3)
        [void]$row.Children.Add($when)

        $ed = New-Object Windows.Controls.Button
        $ed.Content = '✏️'; $ed.Tag = $t.id; $ed.Width = 24; $ed.Height = 20; $ed.VerticalAlignment = 'Top'
        $ed.Background = 'Transparent'; $ed.BorderThickness = '0'; $ed.Cursor = 'Hand'
        $ed.ToolTip = 'Modifier la tâche et sa description'
        $ed.Add_Click({ param($s, $e) Invoke-Safe { if ($NB.EditId -eq $s.Tag) { End-EditTodo } else { Start-EditTodo $s.Tag } } })
        [Windows.Controls.Grid]::SetColumn($ed, 4)
        [void]$row.Children.Add($ed)

        $del = New-Object Windows.Controls.Button
        $del.Content = '✕'; $del.Tag = $t.id; $del.Width = 22; $del.Height = 20
        $del.Background = 'Transparent'; $del.BorderThickness = '0'; $del.Foreground = '#B0AEC4'
        $del.Cursor = 'Hand'; $del.ToolTip = 'Supprimer'; $del.VerticalAlignment = 'Top'
        $del.Add_Click({ param($s, $e) Invoke-Safe { Remove-Todo $s.Tag } })
        [Windows.Controls.Grid]::SetColumn($del, 5)
        [void]$row.Children.Add($del)

        [void]$pn.TodoList.Children.Add($row)
    }
    $done = @($NB.Todos | Where-Object { $_.done }).Count
    $pn.TodoCount.Text = "$done / $($NB.Todos.Count) terminée(s)"
    $pn.TodoClear.IsEnabled = $done -gt 0
    Update-Tabs
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
