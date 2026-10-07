# ---------------------------------------------------------------------------
#  🚨 S.O.S / ⚡ Unstick Me et le journal des victoires (les memes que sur le telephone) :
#   - une tache qui bloque est decoupee en 3 a 5 micro-etapes ridiculement
#     petites ; on n'en voit qu'une a la fois, avec un minuteur doux de 2 min 30
#     qui ne sonne jamais ;
#   - le journal des victoires note tout seul ce qui a ete fait (focus termines,
#     cartes finies, reprises, deblocages), jamais ce qui est « en retard ».
#  Le decoupage est fait sur le PC, avec les regles de unstick\rules.json (les memes
#  que sur le telephone) : aucun service d'IA, rien ne sort du PC.
#  Donnees : lifeanchor.json (meme format que le telephone, voyage avec l'export).
#  (Le Brain Dump et la DopaList ont ete retires : leurs donnees deviennent des notes
#  rapides et des cartes, une seule fois, au premier lancement.)
# ---------------------------------------------------------------------------
$AnchorFile = Join-Path $DataDir 'lifeanchor.json'
$AnchorRulesFile = Join-Path $PSScriptRoot 'unstick\rules.json'
$AnchorRepeats = [ordered]@{ daily = 'chaque jour'; weekdays = 'en semaine'; weekly = 'chaque semaine' }
$AnchorWinIcons = @{ task = '✅'; routine = '🔁'; unstick = '⚡'; focus = '🍅'; card = '🗂'; reprise = '↩' }
$Anchor = @{
    Dump = New-Object System.Collections.ArrayList
    Tasks = New-Object System.Collections.ArrayList
    Wins = New-Object System.Collections.ArrayList
    Unstick = $null
    BackupDay = ''
    Rules = $null
}

# ---------------------------------------------------------------------------
#  Petites fonctions et lecture verifiee du fichier
# ---------------------------------------------------------------------------
# texte stocke : sans caracteres de controle, longueur bornee
function Get-AnchorText($v, [int]$max = 300) {
    $s = ([string]$v) -replace "`r`n?", "`n" -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\uFEFF\uFFFD]', ''
    $s = $s -replace $script:TextLone, ''
    if ($s.Length -gt $max) { $s = (Get-TextStart $s ($max - 1)) + '…' }
    return $s
}
function Get-AnchorDate($v) { $s = To-IsoString $v; if ($s -match '^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?') { return $s.Substring(0, [math]::Min(19, $s.Length)) }; return '' }
function Get-AnchorDay($v) { $s = Get-AnchorDate $v; if ($s) { return $s.Substring(0, 10) }; return '' }
function Get-NowMs { [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }

function ConvertTo-AnchorSteps($list) {
    $r = New-Object System.Collections.ArrayList
    foreach ($x in @($list)) {
        if ($null -eq $x -or $r.Count -ge 12) { continue }
        $c = Get-AnchorText $x.content 300
        if (-not $c) { continue }
        $sec = 150; [void][int]::TryParse([string]$x.sec, [ref]$sec)
        [void]$r.Add([pscustomobject]@{ content = $c; sec = [math]::Min(900, [math]::Max(30, $sec)); done = [bool]$x.done })
    }
    return , $r
}

function ConvertTo-AnchorTask($x) {
    $status = if ([string]$x.status -in 'todo', 'completed', 'archived') { [string]$x.status } else { 'todo' }
    $repeat = if ($AnchorRepeats.Contains([string]$x.repeat)) { [string]$x.repeat } elseif ([bool]$x.isRoutine) { 'daily' } else { '' }
    $t = Get-AnchorText $x.title 300
    [pscustomobject]@{
        id = (Get-SafeId $x.id); title = $(if ($t) { $t } else { 'Sans titre' }); status = $status
        isRoutine = [bool]$repeat; repeat = $repeat
        created = $(if (Get-AnchorDate $x.created) { Get-AnchorDate $x.created } else { (Get-Date).ToString('s') })
        completedAt = Get-AnchorDate $x.completedAt; lastDone = Get-AnchorDay $x.lastDone
        steps = ConvertTo-AnchorSteps $x.steps
    }
}

# lifeanchor.json (PC ou telephone) : tout est reverifie
function Import-AnchorData($d) {
    $Anchor.Dump.Clear(); $Anchor.Tasks.Clear(); $Anchor.Wins.Clear(); $Anchor.Unstick = $null
    if (-not $d) { return }
    $ids = @{}
    $uid = { param($v) $id = Get-SafeId $v; if ($ids.ContainsKey($id)) { $id = New-Id }; $ids[$id] = $true; $id }
    foreach ($x in @($d.dump)) {
        if ($null -eq $x -or $Anchor.Dump.Count -ge 1000) { continue }
        $t = Get-AnchorText $x.text 2000
        if (-not $t.Trim()) { continue }
        [void]$Anchor.Dump.Add([pscustomobject]@{ id = (& $uid $x.id); text = $t; created = $(if (Get-AnchorDate $x.created) { Get-AnchorDate $x.created } else { (Get-Date).ToString('s') }) })
    }
    foreach ($x in @($d.tasks)) {
        if ($null -eq $x -or $Anchor.Tasks.Count -ge 2000) { continue }
        $t = ConvertTo-AnchorTask $x
        $t.id = & $uid $t.id
        [void]$Anchor.Tasks.Add($t)
    }
    foreach ($x in @(@($d.wins) | Select-Object -Last 3000)) {
        if ($null -eq $x) { continue }
        $t = Get-AnchorText $x.title 200
        if (-not $t) { continue }
        $kind = ([string]$x.kind) -replace '[^a-z]', ''
        [void]$Anchor.Wins.Add([pscustomobject]@{ id = (& $uid $x.id); title = $t; kind = $(if ($kind) { $kind } else { 'task' })
                at = $(if (Get-AnchorDate $x.at) { Get-AnchorDate $x.at } else { (Get-Date).ToString('s') }) })
    }
    $u = $d.unstick
    if ($u) {
        $steps = ConvertTo-AnchorSteps $u.steps
        if ($steps.Count) {
            $i = 0; [void][int]::TryParse([string]$u.index, [ref]$i)
            [double]$ends = 0; [void][double]::TryParse([string]$u.timerEndsAt, [ref]$ends)
            $Anchor.Unstick = [pscustomobject]@{ title = (Get-AnchorText $u.title 300); taskId = $(if (Test-SafeId $u.taskId) { [string]$u.taskId } else { '' })
                steps = $steps; index = [math]::Min($steps.Count - 1, [math]::Max(0, $i)); timerEndsAt = $ends }
        }
    }
}

function Load-Anchor {
    if (-not (Test-Path -LiteralPath $AnchorFile)) { Import-AnchorData $null; return }
    try { Import-AnchorData (ConvertFrom-Json ([IO.File]::ReadAllText($AnchorFile))) }
    catch {
        Write-Log "Lecture lifeanchor.json : $($_.Exception.Message)"
        $bad = Join-Path $DataDir ("lifeanchor-illisible-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
        try { Move-Item -LiteralPath $AnchorFile -Destination $bad -Force } catch {}
        Import-AnchorData $null
        foreach ($f in @(Get-ChildItem -Path $BackupDir -Filter 'lifeanchor-????-??-??.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
            try {
                Import-AnchorData (ConvertFrom-Json ([IO.File]::ReadAllText($f.FullName)))
                $NB.LoadNotice = (@($NB.LoadNotice, "Ton fichier de victoires était abîmé 😬 J'ai repris la copie du $($f.BaseName.Substring(11)).") | Where-Object { $_ }) -join "`n"
                break
            } catch {}
        }
    }
}

function Save-Anchor {
    try {
        $day = (Get-Date).ToString('yyyy-MM-dd')
        if ($Anchor.BackupDay -ne $day -and (Test-Path -LiteralPath $AnchorFile)) {
            if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
            $dest = Join-Path $BackupDir "lifeanchor-$day.json"
            if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $AnchorFile -Destination $dest -Force }
            Limit-Backups 'lifeanchor-????-??-??.json' 7
            $Anchor.BackupDay = $day
        }
        $data = [ordered]@{ dump = @($Anchor.Dump); tasks = @($Anchor.Tasks); wins = @($Anchor.Wins); unstick = $Anchor.Unstick }   # (dump et tasks : vides, anciens modules)
        Write-FileSafe $AnchorFile (ConvertTo-Json -InputObject $data -Depth 6)
    } catch { Write-Log "Ecriture lifeanchor.json : $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
#  Journal des victoires
# ---------------------------------------------------------------------------
function Add-Win([string]$title, [string]$kind = 'task', [datetime]$now = (Get-Date)) {
    $w = [pscustomobject]@{ id = (New-Id); title = $(if ($title) { Get-AnchorText $title 200 } else { 'Une victoire' }); kind = $kind; at = $now.ToString('s') }
    [void]$Anchor.Wins.Add($w)
    $limit = $now.AddDays(-60).ToString('s')
    while ($Anchor.Wins.Count -and ($Anchor.Wins[0].at -lt $limit -or $Anchor.Wins.Count -gt 3000)) { $Anchor.Wins.RemoveAt(0) }
    Save-Anchor
    return $w
}
function Get-WinsOfDay([datetime]$day = (Get-Date)) {
    $d = $day.ToString('yyyy-MM-dd')
    return @($Anchor.Wins | Where-Object { $_.at.StartsWith($d) } | Sort-Object -Property at -Descending)
}
# jours d'affilee avec au moins une victoire (aujourd'hui pas encore commence : la serie tient)
function Get-WinStreak([datetime]$now = (Get-Date)) {
    $days = @{}
    foreach ($w in $Anchor.Wins) { $days[$w.at.Substring(0, 10)] = $true }
    $d = $now.Date
    if (-not $days.ContainsKey($d.ToString('yyyy-MM-dd'))) { $d = $d.AddDays(-1) }
    $n = 0
    while ($days.ContainsKey($d.ToString('yyyy-MM-dd'))) { $n++; $d = $d.AddDays(-1) }
    return $n
}

# ---------------------------------------------------------------------------
#  Anciennes donnees (Brain Dump, DopaList) : converties une seule fois
#  idees du Brain Dump -> notes rapides ; actions -> cartes ; routines -> cartes recurrentes
# ---------------------------------------------------------------------------
function Convert-AnchorLegacy {
    $notes = 0; $cards = 0
    foreach ($d in @($Anchor.Dump)) {
        if ($d -and $d.text -and (Add-Note $d.text)) { $notes++ }
    }
    foreach ($t in @($Anchor.Tasks | Where-Object { $_.status -eq 'todo' })) {
        $NB.LastAddedId = ''
        Add-Todo $t.title -Quiet
        $c = Find-Todo $NB.LastAddedId
        if (-not $c) { continue }
        if ($t.isRoutine) {
            $c.repeat = switch ($t.repeat) { 'weekdays' { 'workdays' } 'weekly' { 'weekly' } default { 'daily' } }
            $c.desc = 'Ancienne routine de la DopaList'
        }
        $cards++
    }
    if (-not ($Anchor.Dump.Count + $Anchor.Tasks.Count)) { return }
    $Anchor.Dump.Clear(); $Anchor.Tasks.Clear()
    if ($cards) { Save-Todos }
    Save-Anchor
    Write-Log "Brain Dump et DopaList retires : $notes note(s) et $cards carte(s) creees"
    if ($notes -or $cards) {
        $NB.LoadNotice = (@($NB.LoadNotice, "Le Brain Dump et la DopaList ont été retirés. Rien n'est perdu : $notes idée(s) sont devenues des notes rapides 📝 et $cards action(s) ou routine(s) sont devenues des cartes 🗂 (les routines se répètent).") | Where-Object { $_ }) -join "`n"
    }
}

# ---------------------------------------------------------------------------
#  Unstick Me : decoupage local en micro-etapes (memes regles que le telephone)
# ---------------------------------------------------------------------------
function Get-UnstickRules {
    if ($null -eq $Anchor.Rules) {
        try { $Anchor.Rules = ConvertFrom-Json ([IO.File]::ReadAllText($AnchorRulesFile)) }
        catch { Write-Log "Regles de decoupage illisibles : $($_.Exception.Message)"; $Anchor.Rules = [pscustomobject]@{ rules = @(); verbs = @(); generic = @() } }
    }
    return $Anchor.Rules
}

function Split-Task([string]$text) {
    $task = (Get-AnchorText $text 300).Trim()
    if (-not $task) { return @() }
    $rules = Get-UnstickRules
    $key = Get-SearchKey $task
    $norm = ' ' + (($key -replace "[^a-z0-9' -]", ' ') -replace '\s+', ' ') + ' '
    $obj = $task
    foreach ($v in @($rules.verbs)) {
        if ($key.StartsWith("$v ")) { $obj = $task.Substring($v.Length).Trim(); break }
    }
    $obj = ($obj -replace "^(le|la|les|l'|un|une|des|du|de|d'|mon|ma|mes|ton|ta|tes)\s*", '').Trim()
    if (-not $obj) { $obj = $task }
    $steps = @($rules.generic)
    if (-not $steps.Count) { $steps = @("Commence « {x} » : la toute première action", 'Continue 2 minutes', 'Note où tu en es') }
    foreach ($r in @($rules.rules)) {
        $hit = $false
        foreach ($k in @($r.keys)) { if ($norm.Contains(' ' + (Get-SearchKey $k))) { $hit = $true; break } }
        if ($hit) { $steps = @($r.steps); break }
    }
    return @($steps | Select-Object -First 5 | ForEach-Object { ([string]$_).Replace('{x}', $task).Replace('{o}', $obj) })
}

function Start-Unstick([string]$title, [string]$taskId = '') {
    $steps = New-Object System.Collections.ArrayList
    foreach ($s in (Split-Task $title)) { [void]$steps.Add([pscustomobject]@{ content = $s; sec = 150; done = $false }) }
    if (-not $steps.Count) { return $null }
    $Anchor.Unstick = [pscustomobject]@{ title = (Get-AnchorText $title 300); taskId = $(if (Test-SafeId $taskId) { $taskId } else { '' }); steps = $steps; index = 0; timerEndsAt = [double]0 }
    Save-Anchor
    return $Anchor.Unstick
}

# etape faite : la suivante ('next'), ou tout est fait ('finished')
function Complete-UnstickStep([datetime]$now = (Get-Date)) {
    $u = $Anchor.Unstick
    if (-not $u) { return '' }
    $u.steps[$u.index].done = $true
    $u.timerEndsAt = [double]0
    if ($u.index -lt $u.steps.Count - 1) { $u.index++; Save-Anchor; return 'next' }
    $Anchor.Unstick = $null
    [void](Add-Win "Débloqué : $($u.title)" 'unstick' $now)
    return 'finished'
}

# « Encore plus petit » : une etape de preparation avant l'etape actuelle
function Split-UnstickStep {
    $u = $Anchor.Unstick
    if (-not $u -or $u.steps.Count -ge 12) { return }
    $s = $u.steps[$u.index]
    $u.steps.Insert($u.index, [pscustomobject]@{ content = "Prépare-toi juste pour : « $(Short-Text $s.content 80) » (pose ce qu'il faut devant toi)"; sec = 90; done = $false })
    $u.timerEndsAt = [double]0
    Save-Anchor
}

# ---------------------------------------------------------------------------
#  Bruit brun (ambiance) : genere par Orbit, joue en boucle
# ---------------------------------------------------------------------------
$script:NoisePlayer = $null
function Set-BrownNoise([bool]$on) {
    if (-not $on) {
        if ($script:NoisePlayer) { $script:NoisePlayer.Stop(); $script:NoisePlayer.Close(); $script:NoisePlayer = $null }
        return $false
    }
    if ($script:NoisePlayer) { return $true }
    if (-not $Native) { return $false }
    $file = Join-Path ([IO.Path]::GetTempPath()) 'orbit-bruit-brun.wav'
    if (-not (Test-Path -LiteralPath $file)) { [IO.File]::WriteAllBytes($file, [OrbitNative]::BrownNoise(0.5, 8)) }
    $p = New-Object Windows.Media.MediaPlayer
    $p.Volume = [math]::Min(1, [math]::Max(0.05, $Config.DroidVolume / 100))
    $p.Add_MediaEnded({ param($s, $e) $s.Position = [timespan]::Zero; $s.Play() })
    $p.Open((New-Object Uri $file))
    $p.Play()
    $script:NoisePlayer = $p
    return $true
}

# ---------------------------------------------------------------------------
#  Fenetre plein ecran doux : Unstick Me (une seule chose a la fois)
# ---------------------------------------------------------------------------
[xml]$AnchorFocusXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Orbit - une seule chose" Width="560" Height="600" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" FontFamily="Segoe UI, Segoe UI Emoji, Segoe UI Symbol" FontSize="14">
  <Border Margin="8" CornerRadius="22" Background="#F4F2FF" BorderBrush="#1E1B3A" BorderThickness="2.5">
    <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="-45" Opacity="0.25"/></Border.Effect>
    <DockPanel Margin="18,12,18,16">
      <Grid x:Name="AfHeader" DockPanel.Dock="Top" Background="Transparent" Cursor="SizeAll">
        <TextBlock x:Name="AfTitle" FontWeight="Bold" FontSize="15" Foreground="#1E1B3A" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="AfNoise" Content="🟤 Bruit brun" Padding="8,3" Margin="0,0,6,0" Background="Transparent" BorderThickness="0" Cursor="Hand"
                  ToolTip="Un fond sonore doux qui aide à se concentrer"/>
          <Button x:Name="AfClose" Content="✖ Plus tard" Padding="8,3" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
        </StackPanel>
      </Grid>
      <StackPanel x:Name="AfBody" VerticalAlignment="Center" HorizontalAlignment="Stretch"/>
    </DockPanel>
  </Border>
</Window>
'@
$script:afWin = $null
$script:afMode = ''        # 'sos' | 'unstick' | 'done'
$script:afTimer = $null

function Initialize-AnchorFocus {
    if ($script:afWin) { return }
    $script:afWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $AnchorFocusXaml))
    $script:af = @{}
    foreach ($n in 'AfHeader', 'AfTitle', 'AfNoise', 'AfClose', 'AfBody') { $af[$n] = $afWin.FindName($n) }
    $af.AfHeader.Add_MouseLeftButtonDown({ try { $afWin.DragMove() } catch {} })
    $af.AfClose.Add_Click({ Invoke-Safe { Close-AnchorFocus } })
    $af.AfNoise.Add_Click({ Invoke-Safe { [void](Set-BrownNoise (-not $script:NoisePlayer)); Update-NoiseButton } })
    $afWin.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Invoke-Safe { Close-AnchorFocus } } })
    $afWin.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $e.Handled = $true; Invoke-Safe { Close-AnchorFocus } } })
    $script:afTimer = New-Object Windows.Threading.DispatcherTimer
    $script:afTimer.Interval = [timespan]::FromMilliseconds(500)
    $script:afTimer.Add_Tick({ Invoke-Safe { Update-UnstickTimer } 'deblocage' })
}

function Update-NoiseButton { if ($script:afWin) { $af.AfNoise.Content = if ($script:NoisePlayer) { '🟤 Bruit brun : oui' } else { '🟤 Bruit brun' } } }

function Show-AnchorFocus {
    Initialize-AnchorFocus
    Update-NoiseButton
    if (-not $afWin.IsVisible) {
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position))
        $afWin.Left = ($wa.L + $wa.R) / 2 - 280
        $afWin.Top = [math]::Max($wa.T, ($wa.T + $wa.B) / 2 - 300)
        $afWin.Show()
    }
    $afWin.Activate() | Out-Null
}
function Close-AnchorFocus {
    if (-not $script:afWin) { return }
    if ($script:afTimer) { $script:afTimer.Stop() }
    $afWin.Hide()
    $script:afMode = ''
}

# petits outils pour construire le contenu (toujours du texte, jamais du code)
function New-AfText([string]$text, [double]$size = 14, [string]$color = '#1E1B3A', [string]$weight = 'Normal') {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = ConvertTo-DisplayText $text; $tb.TextWrapping = 'Wrap'; $tb.TextAlignment = 'Center'; $tb.FontSize = $size
    $tb.Foreground = $color; $tb.FontWeight = $weight; $tb.Margin = '0,4,0,4'; $tb.HorizontalAlignment = 'Center'
    return $tb
}
function New-AfButton([string]$label, [scriptblock]$onClick, [string]$kind = '', $tag = $null) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $label; $b.Tag = $tag; $b.Padding = '12,7'; $b.Margin = '4'; $b.Cursor = 'Hand'; $b.FontWeight = 'SemiBold'
    $b.BorderThickness = '2'; $b.BorderBrush = '#1E1B3A'
    switch ($kind) {
        'primary' { $b.Background = '#6C5CE7'; $b.Foreground = 'White' }
        'ok' { $b.Background = '#2F9E44'; $b.Foreground = 'White'; $b.FontSize = 17; $b.Padding = '12,10' }
        default { $b.Background = '#FFFFFF'; $b.BorderBrush = '#D9D5F2' }
    }
    $b.Add_Click($onClick)
    return $b
}
function New-AfRow([object[]]$items) {
    $w = New-Object Windows.Controls.WrapPanel
    $w.HorizontalAlignment = 'Center'; $w.Margin = '0,4,0,0'
    foreach ($i in $items) { if ($i) { [void]$w.Children.Add($i) } }
    return $w
}

# --- 🚨 S.O.S et Unstick Me -------------------------------------------------------------
function Show-Sos {
    if ($Anchor.Unstick) { Show-Unstick; return }
    $script:afMode = 'sos'
    Show-AnchorFocus
    $af.AfTitle.Text = '🚨 S.O.S déblocage'
    $af.AfBody.Children.Clear()
    [void]$af.AfBody.Children.Add((New-AfText "Qu'est-ce que tu n'arrives pas à commencer ?" 22 '#1E1B3A' 'Bold'))
    [void]$af.AfBody.Children.Add((New-AfText "Je le découpe en micro-étapes ridiculement petites. Tu ne verras que la première. (Win+H pour dicter)" 13 '#6B6880'))
    $tb = New-Object Windows.Controls.TextBox
    $tb.FontSize = 16; $tb.Padding = '8,6'; $tb.Margin = '0,10,0,6'; $tb.BorderBrush = '#9F95E8'; $tb.MaxLength = 300
    $tb.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $e.Handled = $true; Invoke-Safe { if ($s.Text.Trim()) { Start-UnstickFor $s.Text } } } })
    [void]$af.AfBody.Children.Add($tb)
    $script:afSosBox = $tb
    [void]$af.AfBody.Children.Add((New-AfRow @((New-AfButton '⚡ Découper' { Invoke-Safe { if ($script:afSosBox.Text.Trim()) { Start-UnstickFor $script:afSosBox.Text } } } 'primary'))))
    # idees : les cartes du focus, puis les plus urgentes des tableaux
    $ideas = @()
    $seen = @{}
    foreach ($t in @(@(Get-FocusCards -Open) + @(Get-PlanCards 3 | ForEach-Object { $_.Card }))) {
        if (-not $t -or $seen.ContainsKey($t.id) -or $ideas.Count -ge 4) { continue }
        $seen[$t.id] = $true
        $ideas += New-AfButton (Short-Text $t.text 28) { param($s, $e) Invoke-Safe { $x = Find-Todo $s.Tag; if ($x) { Start-UnstickFor $x.text } } } '' $t.id
    }
    if ($ideas.Count) {
        [void]$af.AfBody.Children.Add((New-AfText 'Ou bien :' 12 '#6B6880'))
        [void]$af.AfBody.Children.Add((New-AfRow $ideas))
    }
    $tb.Focus() | Out-Null
}

function Start-UnstickFor([string]$title, [string]$taskId = '') {
    if (Start-Unstick $title $taskId) { Show-Unstick }
}

function Show-Unstick {
    if (-not $Anchor.Unstick) { Show-Sos; return }
    $script:afMode = 'unstick'
    Show-AnchorFocus
    Render-Unstick
}

function Render-Unstick {
    $u = $Anchor.Unstick
    if (-not $u) { return }
    $step = $u.steps[$u.index]
    $af.AfTitle.Text = "⚡ $(Short-Text $u.title 50)"
    $af.AfBody.Children.Clear()
    $dots = (@(for ($i = 0; $i -lt $u.steps.Count; $i++) { if ($u.steps[$i].done) { '●' } elseif ($i -eq $u.index) { '◉' } else { '○' } }) -join ' ')
    [void]$af.AfBody.Children.Add((New-AfText $dots 16 '#6C5CE7'))
    [void]$af.AfBody.Children.Add((New-AfText "Étape $($u.index + 1) sur $($u.steps.Count) · une seule chose" 13 '#6B6880'))
    [void]$af.AfBody.Children.Add((New-AfText $step.content 24 '#1E1B3A' 'Bold'))
    # minuteur visuel doux : une barre qui se vide, sans sonnerie
    $track = New-Object Windows.Controls.Border
    $track.Height = 16; $track.CornerRadius = '8'; $track.Background = '#E2DFF5'; $track.Margin = '30,14,30,4'
    $fill = New-Object Windows.Controls.Border
    $fill.CornerRadius = '8'; $fill.Background = '#6C5CE7'; $fill.HorizontalAlignment = 'Left'
    $track.Child = $fill
    $script:afFill = $fill; $script:afTrack = $track
    [void]$af.AfBody.Children.Add($track)
    $script:afClock = New-AfText '' 22 '#1E1B3A' 'Bold'
    [void]$af.AfBody.Children.Add($script:afClock)
    $script:afHint = New-AfText $(if ($u.timerEndsAt) { 'Juste pour amorcer : pas besoin de finir.' } else { 'Le minuteur est doux : il ne sonne pas.' }) 12 '#6B6880'
    [void]$af.AfBody.Children.Add($script:afHint)
    [void]$af.AfBody.Children.Add((New-AfRow @((New-AfButton "✅ C'est fait !" { Invoke-Safe { Complete-UnstickUi } } 'ok'))))
    $row = @()
    if (-not $u.timerEndsAt) { $row += New-AfButton "▶ Je commence ($(Format-Clock ($step.sec * 1000)))" { Invoke-Safe { $Anchor.Unstick.timerEndsAt = [double](Get-NowMs) + $Anchor.Unstick.steps[$Anchor.Unstick.index].sec * 1000; Save-Anchor; Render-Unstick } } 'primary' }
    $row += New-AfButton '🔪 Encore plus petit' { Invoke-Safe { Split-UnstickStep; Render-Unstick } }
    $row += New-AfButton '✏ Modifier' { Invoke-Safe {
            $v = Show-Prompt "Modifier l'étape" 'Cette étape :' $Anchor.Unstick.steps[$Anchor.Unstick.index].content
            if ($v) { $Anchor.Unstick.steps[$Anchor.Unstick.index].content = Get-AnchorText $v 300; Save-Anchor }
            Render-Unstick } }
    $row += New-AfButton '⏭ Passer' { Invoke-Safe { $x = $Anchor.Unstick; if ($x.index -lt $x.steps.Count - 1) { $x.index++; $x.timerEndsAt = [double]0; Save-Anchor; Render-Unstick } else { Complete-UnstickUi } } }
    [void]$af.AfBody.Children.Add((New-AfRow $row))
    $script:afBuzzed = $false
    Update-UnstickTimer
    if ($u.timerEndsAt) { $script:afTimer.Start() } else { $script:afTimer.Stop() }
}

function Format-Clock([double]$ms) { $s = [math]::Ceiling($ms / 1000); return ('{0:00}:{1:00}' -f [math]::Floor($s / 60), ($s % 60)) }

function Update-UnstickTimer {
    $u = $Anchor.Unstick
    if (-not $u -or $script:afMode -ne 'unstick' -or -not $script:afFill) { if ($script:afTimer) { $script:afTimer.Stop() }; return }
    $total = $u.steps[$u.index].sec * 1000
    $left = if ($u.timerEndsAt) { [math]::Max(0, $u.timerEndsAt - (Get-NowMs)) } else { $total }
    $w = $script:afTrack.ActualWidth
    if ($w -le 0) { $w = 440 }
    $script:afFill.Width = [math]::Max(0, $w * $left / $total)
    $script:afClock.Text = Format-Clock $left
    if ($u.timerEndsAt -and $left -le 0) {
        $script:afFill.Width = $w; $script:afFill.Background = '#2F9E44'
        $script:afClock.Text = '✓'
        $script:afHint.Text = 'Le temps est passé : continue sur ta lancée, ou passe à la suite 🙂'
        $script:afTimer.Stop()
    }
}

function Complete-UnstickUi {
    $r = Complete-UnstickStep
    if ($r -eq 'next') { Play-Win; Render-Unstick; return }
    if ($r -ne 'finished') { return }
    $script:afTimer.Stop()
    $script:afMode = 'done'
    $af.AfBody.Children.Clear()
    [void]$af.AfBody.Children.Add((New-AfText '🎉 Tu es lancé(e) !' 28 '#1E1B3A' 'Bold'))
    [void]$af.AfBody.Children.Add((New-AfText "Le plus dur, c'était de commencer. C'est fait, et c'est noté dans tes victoires." 14 '#6B6880'))
    [void]$af.AfBody.Children.Add((New-AfRow @(
                (New-AfButton '🚀 Enchaîner avec un focus' { Invoke-Safe { Close-AnchorFocus; Ensure-Visible; Start-Focus } } 'primary'),
                (New-AfButton '🏆 Mes victoires' { Invoke-Safe { Close-AnchorFocus; Show-Wins } }),
                (New-AfButton 'Fermer' { Invoke-Safe { Close-AnchorFocus } }))))
    Play-Win -Big
}

# petite fete : son (si active) et Orbit content
function Play-Win([switch]$Big) {
    try { Play-Chirp } catch {}
    if ($Big) { Show-Bubble (Pick @('Bravo ! 🎉', 'Une victoire de plus 🏆', 'Yes ! ✨', 'Bien joué 💪')) -Force -Seconds 3 }
}

# ---------------------------------------------------------------------------
#  🏆 Mes victoires du jour (clic droit sur Orbit, ou a la fin d'un deblocage)
# ---------------------------------------------------------------------------
function Get-WinsText {
    $wins = @(Get-WinsOfDay)
    if (-not $wins.Count) { return "🏆 La journée commence : chaque petite chose faite (focus, carte finie, déblocage…) sera notée ici 🌱" }
    $streak = Get-WinStreak
    $text = "🏆 Aujourd'hui : $($wins.Count) victoire$(if ($wins.Count -gt 1) { 's' }) 🎉$(if ($streak -ge 2) { "  ·  🔥 $streak jours d'affilée" })"
    foreach ($w in ($wins | Select-Object -First 12)) {
        $ico = if ($AnchorWinIcons.ContainsKey($w.kind)) { $AnchorWinIcons[$w.kind] } else { '✅' }
        $text += "`n$ico $(Short-Text $w.title 50)"
    }
    if ($wins.Count -gt 12) { $text += "`n… et $($wins.Count - 12) autre(s)" }
    return $text
}
function Show-Wins {
    Ensure-Visible
    Show-Bubble (Get-WinsText) -Force -Seconds 15
}

Load-Anchor
Convert-AnchorLegacy
