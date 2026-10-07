# ---------------------------------------------------------------------------
#  Les 3 modules anti-paralysie (les memes que sur le telephone) :
#   - 📥 Brain Dump : vider sa tete sans rien trier (bouton 📥 a cote d'Orbit),
#     puis trier « a froid », une idee a la fois ;
#   - 📋 DopaList : actions et routines en grandes cartes, et le journal des
#     victoires (ce qui a ete fait aujourd'hui, jamais ce qui est « en retard ») ;
#   - ⚡ Unstick Me / 🚨 S.O.S : une tache qui bloque est decoupee en 3 a 5
#     micro-etapes ridiculement petites ; on n'en voit qu'une a la fois, avec un
#     minuteur doux de 2 min 30 qui ne sonne jamais.
#  Le decoupage est fait sur le PC, avec les regles de unstick\rules.json (les memes
#  que sur le telephone) : aucun service d'IA, rien ne sort du PC.
#  Donnees : lifeanchor.json (meme format que le telephone, voyage avec l'export).
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
    $s = ([string]$v) -replace "`r`n?", "`n" -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F﻿�]', ''
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
                $NB.LoadNotice = (@($NB.LoadNotice, "Ton fichier DopaList / Brain Dump était abîmé 😬 J'ai repris la copie du $($f.BaseName.Substring(11)).") | Where-Object { $_ }) -join "`n"
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
        $data = [ordered]@{ dump = @($Anchor.Dump); tasks = @($Anchor.Tasks); wins = @($Anchor.Wins); unstick = $Anchor.Unstick }
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
#  Brain Dump
# ---------------------------------------------------------------------------
function Add-DumpItem([string]$text) {
    $t = (Get-AnchorText $text 2000).Trim()
    if (-not $t -or $Anchor.Dump.Count -ge 1000) { return $null }
    $x = [pscustomobject]@{ id = (New-Id); text = $t; created = (Get-Date).ToString('s') }
    [void]$Anchor.Dump.Add($x)
    Save-Anchor
    return $x
}

# tri a froid : 'dopa' | 'unstick' | 'card' | 'archive' | 'delete'
function Invoke-DumpSort([string]$id, [string]$action) {
    $x = $Anchor.Dump | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $x) { return $null }
    $Anchor.Dump.Remove($x)
    $r = $null
    if ($action -eq 'card') {
        $NB.LastAddedId = ''
        Add-Todo (Get-TextStart $x.text 300)
        $r = Find-Todo $NB.LastAddedId
    } elseif ($action -ne 'delete') {
        $t = ConvertTo-AnchorTask ([pscustomobject]@{ id = (New-Id); title = $x.text; status = $(if ($action -eq 'archive') { 'archived' } else { 'todo' }); created = $x.created })
        [void]$Anchor.Tasks.Add($t)
        if ($action -eq 'unstick') { [void](Start-Unstick $t.title $t.id) }
        $r = $t
    }
    Save-Anchor
    return $r
}

# ---------------------------------------------------------------------------
#  DopaList
# ---------------------------------------------------------------------------
function Add-DopaTask([string]$title, [string]$repeat = '') {
    $t = (Get-AnchorText $title 300).Trim()
    if (-not $t) { return $null }
    $x = ConvertTo-AnchorTask ([pscustomobject]@{ id = (New-Id); title = $t; status = 'todo'; repeat = $repeat; isRoutine = [bool]$AnchorRepeats.Contains($repeat) })
    [void]$Anchor.Tasks.Add($x)
    Save-Anchor
    return $x
}
function Find-DopaTask([string]$id) { foreach ($t in $Anchor.Tasks) { if ($t.id -eq $id) { return $t } } }

function Test-RoutineDue($t, [datetime]$now = (Get-Date)) {
    if (-not $t.isRoutine -or $t.status -eq 'archived') { return $false }
    if ($t.repeat -eq 'weekdays' -and $now.DayOfWeek -in 'Saturday', 'Sunday') { return $false }
    if ($t.repeat -eq 'weekly') {
        if (-not $t.lastDone) { return $true }
        return (($now.Date - [datetime]::ParseExact($t.lastDone, 'yyyy-MM-dd', $null)).TotalDays -ge 7)
    }
    return $t.lastDone -ne $now.ToString('yyyy-MM-dd')
}

function Get-DopaView([datetime]$now = (Get-Date)) {
    $today = $now.ToString('yyyy-MM-dd')
    $routines = @($Anchor.Tasks | Where-Object { $_.isRoutine -and $_.status -ne 'archived' } | ForEach-Object {
            [pscustomobject]@{ Task = $_; DoneToday = ($_.lastDone -eq $today); Due = (Test-RoutineDue $_ $now) } } | Where-Object { $_.Due -or $_.DoneToday })
    $actions = @($Anchor.Tasks | Where-Object { -not $_.isRoutine -and $_.status -eq 'todo' })
    return [pscustomobject]@{ Routines = $routines; Actions = $actions }
}

function Complete-DopaTask([string]$id, [datetime]$now = (Get-Date)) {
    $t = Find-DopaTask $id
    if (-not $t) { return $null }
    if ($t.isRoutine) {
        if ($t.lastDone -eq $now.ToString('yyyy-MM-dd')) { return $null }
        $t.lastDone = $now.ToString('yyyy-MM-dd')
        return (Add-Win $t.title 'routine' $now)
    }
    if ($t.status -ne 'todo') { return $null }
    $t.status = 'completed'; $t.completedAt = $now.ToString('s')
    return (Add-Win $t.title 'task' $now)
}
function Undo-DopaTask([string]$id, [datetime]$now = (Get-Date)) {
    $t = Find-DopaTask $id
    if (-not $t) { return }
    if ($t.isRoutine) { if ($t.lastDone -eq $now.ToString('yyyy-MM-dd')) { $t.lastDone = '' } }
    elseif ($t.status -eq 'completed') { $t.status = 'todo'; $t.completedAt = '' }
    for ($i = $Anchor.Wins.Count - 1; $i -ge 0; $i--) {
        if ($Anchor.Wins[$i].title -eq $t.title -and $Anchor.Wins[$i].at.StartsWith($now.ToString('yyyy-MM-dd'))) { $Anchor.Wins.RemoveAt($i); break }
    }
    Save-Anchor
}
function Remove-DopaTask([string]$id) {
    $t = Find-DopaTask $id
    if ($t) { $Anchor.Tasks.Remove($t); Save-Anchor }
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
    if ($u.taskId) {
        $t = Find-DopaTask $u.taskId
        if ($t -and -not $t.isRoutine -and $t.status -eq 'todo') { $t.status = 'completed'; $t.completedAt = $now.ToString('s') }
        elseif ($t -and $t.isRoutine) { $t.lastDone = $now.ToString('yyyy-MM-dd') }
    }
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
#  Fenetre « capture rapide » (bouton 📥 a cote d'Orbit, menu, icone)
# ---------------------------------------------------------------------------
[xml]$AnchorDumpXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Brain Dump" Width="380" SizeToContent="Height" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" FontFamily="Segoe UI, Segoe UI Emoji, Segoe UI Symbol" FontSize="14">
  <Border Margin="8" CornerRadius="14" Background="#EEEBFF" BorderBrush="#1E1B3A" BorderThickness="2.5">
    <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="-45" Opacity="0.25"/></Border.Effect>
    <StackPanel Margin="14,10,14,12">
      <Grid x:Name="BdHeader" Background="Transparent" Cursor="SizeAll" Margin="0,0,0,6">
        <TextBlock Text="📥 Vide ta tête" FontWeight="Bold" FontSize="15" Foreground="#1E1B3A"/>
        <Button x:Name="BdClose" Content="✕" HorizontalAlignment="Right" Width="24" Height="22" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
      </Grid>
      <TextBox x:Name="BdText" AcceptsReturn="False" TextWrapping="Wrap" MinHeight="64" MaxHeight="200" VerticalScrollBarVisibility="Auto"
               Padding="6,4" BorderBrush="#9F95E8"/>
      <Grid Margin="0,8,0,0">
        <TextBlock x:Name="BdHint" Foreground="#6B6880" FontSize="11.5" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,110,0"
                   Text="Rien à trier maintenant · Entrée = déposer · Win+H pour dicter"/>
        <Button x:Name="BdSave" Content="📥 Déposer" HorizontalAlignment="Right" Padding="12,4" Cursor="Hand" Background="#6C5CE7" Foreground="White" BorderThickness="0"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@
$script:bdWin = $null
$script:bdClosing = $false
function Initialize-QuickDump {
    if ($script:bdWin) { return }
    $script:bdWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $AnchorDumpXaml))
    $script:bd = @{}
    foreach ($n in 'BdHeader', 'BdClose', 'BdText', 'BdHint', 'BdSave') { $bd[$n] = $bdWin.FindName($n) }
    $bd.BdHeader.Add_MouseLeftButtonDown({ try { $bdWin.DragMove() } catch {} })
    $bd.BdClose.Add_Click({ Invoke-Safe { Close-QuickDump } })
    $bd.BdSave.Add_Click({ Invoke-Safe { Close-QuickDump } })
    $bd.BdText.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $e.Handled = $true; Invoke-Safe { Close-QuickDump } } })
    $bdWin.Add_Deactivated({ Invoke-Safe { Close-QuickDump } })
    $bdWin.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $e.Handled = $true; Invoke-Safe { Close-QuickDump } } })
    $bdWin.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Invoke-Safe { Close-QuickDump } } })
}
function Show-QuickDump {
    Initialize-QuickDump
    $bd.BdText.Text = ''
    if (-not $bdWin.IsVisible) {
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position))
        $bdWin.Left = ($wa.L + $wa.R) / 2 - 190
        $bdWin.Top = [math]::Max($wa.T, ($wa.T + $wa.B) / 2 - 120)
        $bdWin.Show()
    }
    $bdWin.Activate() | Out-Null
    $bd.BdText.Focus() | Out-Null
}
function Close-QuickDump {
    if (-not $script:bdWin -or $script:bdClosing -or -not $bdWin.IsVisible) { return }
    $script:bdClosing = $true
    try {
        $t = $bd.BdText.Text
        $bdWin.Hide()
        if (Add-DumpItem $t) {
            Show-Bubble "📥 Déposé ($($Anchor.Dump.Count) dans le bac). Tu trieras plus tard, à froid." -Force -Seconds 3
            Render-AnchorTabs
        }
    } finally { $script:bdClosing = $false }
}

# ---------------------------------------------------------------------------
#  Fenetre plein ecran doux : tri a froid et Unstick Me (une seule chose a la fois)
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
$script:afMode = ''        # 'sort' | 'sos' | 'unstick' | 'done' | 'sorted'
$script:afQueue = New-Object System.Collections.ArrayList
$script:afSortUnstick = $false
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
    # fleches du clavier pendant le tri : → action, ← archiver, ↑ debloquer
    $afWin.Add_PreviewKeyDown({
            param($s, $e)
            if ($e.Key -eq 'Escape') { $e.Handled = $true; Invoke-Safe { Close-AnchorFocus }; return }
            if ($script:afMode -ne 'sort') { return }
            $a = switch ($e.Key) { 'Right' { 'dopa' } 'Left' { 'archive' } 'Up' { 'unstick' } default { '' } }
            if ($a -and -not ($e.OriginalSource -is [Windows.Controls.TextBox])) { $e.Handled = $true; Invoke-Safe { Invoke-SortAction $a } }
        })
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
    Render-AnchorTabs
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

# --- tri a froid ------------------------------------------------------------------
function Start-DumpSort {
    if (-not $Anchor.Dump.Count) { Show-Bubble "✨ Bac vide : rien à trier." -Force -Seconds 3; return }
    $script:afQueue.Clear()
    foreach ($x in $Anchor.Dump) { [void]$script:afQueue.Add($x.id) }
    $script:afSortUnstick = $false
    $script:afMode = 'sort'
    Show-AnchorFocus
    Render-DumpSort
}
function Invoke-SortAction([string]$action) {
    if (-not $script:afQueue.Count) { return }
    $id = $script:afQueue[0]
    $script:afQueue.RemoveAt(0)
    if ($action -ne 'later') {
        [void](Invoke-DumpSort $id $action)
        if ($action -eq 'unstick') { $script:afSortUnstick = $true }
    }
    Render-DumpSort
}
function Render-DumpSort {
    $af.AfTitle.Text = '🧊 Tri à froid'
    $af.AfBody.Children.Clear()
    $id = if ($script:afQueue.Count) { $script:afQueue[0] } else { '' }
    $x = if ($id) { $Anchor.Dump | Where-Object { $_.id -eq $id } | Select-Object -First 1 }
    if (-not $x) {
        $script:afMode = 'sorted'
        [void]$af.AfBody.Children.Add((New-AfText '✨ Bac trié !' 26 '#1E1B3A' 'Bold'))
        [void]$af.AfBody.Children.Add((New-AfText 'Ta tête est plus légère. Bravo.' 14 '#6B6880'))
        $row = @()
        if ($script:afSortUnstick -and $Anchor.Unstick) { $row += New-AfButton "⚡ Me débloquer sur « $(Short-Text $Anchor.Unstick.title 30) »" { Invoke-Safe { Show-Unstick } } 'primary' }
        $row += New-AfButton '📋 Voir ma DopaList' { Invoke-Safe { Close-AnchorFocus; Open-Notebook 'Dopa' } }
        [void]$af.AfBody.Children.Add((New-AfRow $row))
        Play-Win -Big
        Render-AnchorTabs
        return
    }
    [void]$af.AfBody.Children.Add((New-AfText "Encore $($script:afQueue.Count) · une idée à la fois" 13 '#6B6880'))
    $card = New-Object Windows.Controls.Border
    $card.Background = 'White'; $card.BorderBrush = '#1E1B3A'; $card.BorderThickness = '2.5'; $card.CornerRadius = '18'
    $card.Padding = '18'; $card.Margin = '0,10,0,10'; $card.MinHeight = 150; $card.Cursor = 'SizeAll'
    $card.ToolTip = 'Fais-la glisser : → action, ← archiver, ↑ débloquer (ou les flèches du clavier)'
    $tt = New-Object Windows.Media.TranslateTransform
    $card.RenderTransform = $tt
    $tb = New-AfText $x.text 19 '#1E1B3A' 'Bold'
    $tb.VerticalAlignment = 'Center'
    $card.Child = $tb
    # glisser la carte a la souris
    $card.Add_MouseLeftButtonDown({ param($s, $e) $script:afDrag = $e.GetPosition($afWin); [void]$s.CaptureMouse() })
    $card.Add_MouseMove({ param($s, $e) if ($script:afDrag -and $s.IsMouseCaptured) { $p = $e.GetPosition($afWin); $s.RenderTransform.X = $p.X - $script:afDrag.X; $s.RenderTransform.Y = [math]::Min(0, $p.Y - $script:afDrag.Y) } })
    $card.Add_MouseLeftButtonUp({
            param($s, $e)
            if (-not $script:afDrag) { return }
            $p = $e.GetPosition($afWin); $dx = $p.X - $script:afDrag.X; $dy = $p.Y - $script:afDrag.Y
            $script:afDrag = $null; $s.ReleaseMouseCapture(); $s.RenderTransform.X = 0; $s.RenderTransform.Y = 0
            Invoke-Safe { if ($dx -gt 90) { Invoke-SortAction 'dopa' } elseif ($dx -lt -90) { Invoke-SortAction 'archive' } elseif ($dy -lt -90) { Invoke-SortAction 'unstick' } }
        })
    [void]$af.AfBody.Children.Add($card)
    [void]$af.AfBody.Children.Add((New-AfText '← 📦 archiver    ·    ↑ ⚡ débloquer    ·    action ✅ →' 12 '#6B6880'))
    [void]$af.AfBody.Children.Add((New-AfRow @(
                (New-AfButton '✅ En action (DopaList)' { Invoke-Safe { Invoke-SortAction 'dopa' } } 'primary'),
                (New-AfButton '⚡ À débloquer' { Invoke-Safe { Invoke-SortAction 'unstick' } }),
                (New-AfButton '🗂 Carte (tableau)' { Invoke-Safe { Invoke-SortAction 'card' } }))))
    [void]$af.AfBody.Children.Add((New-AfRow @(
                (New-AfButton '📦 Archiver' { Invoke-Safe { Invoke-SortAction 'archive' } }),
                (New-AfButton '🗑 Supprimer' { Invoke-Safe { Invoke-SortAction 'delete' } }),
                (New-AfButton '⏭ Plus tard' { Invoke-Safe { Invoke-SortAction 'later' } }))))
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
    # idees : actions de la DopaList et cartes du focus
    $ideas = @()
    foreach ($t in @((Get-DopaView).Actions | Select-Object -First 3)) { $ideas += New-AfButton (Short-Text $t.title 28) { param($s, $e) Invoke-Safe { $x = Find-DopaTask $s.Tag; if ($x) { Start-UnstickFor $x.title $x.id } } } '' $t.id }
    foreach ($t in @(Get-FocusCards -Open | Select-Object -First 2)) { $ideas += New-AfButton (Short-Text $t.text 28) { param($s, $e) Invoke-Safe { $x = Find-Todo $s.Tag; if ($x) { Start-UnstickFor $x.text } } } '' $t.id }
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
                (New-AfButton '🏆 Mes victoires' { Invoke-Safe { Close-AnchorFocus; Open-Notebook 'Dopa' } }),
                (New-AfButton 'Fermer' { Invoke-Safe { Close-AnchorFocus } }))))
    Play-Win -Big
    Render-AnchorTabs
}

# petite fete : son (si active) et Orbit content
function Play-Win([switch]$Big) {
    try { Play-Chirp } catch {}
    if ($Big) { Show-Bubble (Pick @('Bravo ! 🎉', 'Une victoire de plus 🏆', 'Yes ! ✨', 'Bien joué 💪')) -Force -Seconds 3 }
}

# ---------------------------------------------------------------------------
#  Onglets du carnet : 📋 DopaList (et victoires) et 📥 Dump
# ---------------------------------------------------------------------------
function New-DopaCard($t, [bool]$doneToday) {
    $b = New-Object Windows.Controls.Border
    $b.Margin = '0,0,0,8'; $b.Padding = '12,8,8,8'; $b.CornerRadius = '14'; $b.BorderThickness = '2'; $b.Cursor = 'Hand'; $b.Tag = $t.id
    $b.Background = if ($doneToday) { '#E3F6E7' } else { 'White' }
    $b.BorderBrush = if ($doneToday) { '#2F9E44' } else { '#1E1B3A' }
    $b.ToolTip = if ($doneToday) { 'Fait aujourd''hui ✓ (clic : annuler)' } else { 'Clic : fait ! ✅' }
    $dp = New-Object Windows.Controls.DockPanel
    $btns = New-Object Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    [Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    [void]$btns.Children.Add((New-NoteButton '⚡' 'Je bloque : découper en micro-étapes' $t.id { param($s, $e) $e.Handled = $true; Invoke-Safe { $x = Find-DopaTask $s.Tag; if ($x) { Start-UnstickFor $x.title $x.id } } }))
    [void]$btns.Children.Add((New-NoteButton '🗂' 'En carte (tableau)' $t.id { param($s, $e) $e.Handled = $true; Invoke-Safe { $x = Find-DopaTask $s.Tag; if ($x) { Add-Todo $x.title; Remove-DopaTask $x.id; Render-AnchorTabs } } }))
    [void]$btns.Children.Add((New-NoteButton '🗑' 'Supprimer' $t.id { param($s, $e) $e.Handled = $true; Invoke-Safe { Remove-DopaTask $s.Tag; Render-AnchorTabs } }))
    [void]$dp.Children.Add($btns)
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = "$(if ($doneToday) { '✓ ' })$($t.title)$(if ($t.isRoutine) { "   🔁 $($AnchorRepeats[$t.repeat])" })"
    $tb.TextWrapping = 'Wrap'; $tb.FontWeight = 'SemiBold'; $tb.VerticalAlignment = 'Center'
    $tb.Foreground = if ($doneToday) { '#2F7A3E' } else { '#1E1B3A' }
    [void]$dp.Children.Add($tb)
    $b.Child = $dp
    $b.Add_MouseLeftButtonUp({
            param($s, $e)
            Invoke-Safe {
                $x = Find-DopaTask $s.Tag
                if (-not $x) { return }
                if ($x.isRoutine -and $x.lastDone -eq (Get-Date).ToString('yyyy-MM-dd')) { Undo-DopaTask $x.id }
                elseif (Complete-DopaTask $x.id) { Play-Win -Big }
                Render-AnchorTabs
            }
        })
    return $b
}

function Render-AnchorTabs {
    Update-Tabs
    if (-not $script:panel -or -not $pn.DopaList) { return }
    if ($NB.Tab -eq 'Dopa') {
        $pn.DopaList.Children.Clear()
        $v = Get-DopaView
        [void]$pn.DopaList.Children.Add((New-SectionTitle '🔁 Routines du jour'))
        if (-not $v.Routines.Count) { [void]$pn.DopaList.Children.Add((New-CtxText 'Pas de routine pour aujourd''hui. Ajoute-en une (« chaque jour », « en semaine »…).' 12 '#9A98B0')) }
        foreach ($r in @($v.Routines | Sort-Object -Property DoneToday)) { [void]$pn.DopaList.Children.Add((New-DopaCard $r.Task $r.DoneToday)) }
        [void]$pn.DopaList.Children.Add((New-SectionTitle '⚡ Actions'))
        if (-not $v.Actions.Count) { [void]$pn.DopaList.Children.Add((New-CtxText 'Rien en attente 🌿 Ajoute une action, ou trie ton Brain Dump.' 12 '#9A98B0')) }
        foreach ($t in $v.Actions) { [void]$pn.DopaList.Children.Add((New-DopaCard $t $false)) }
        # journal des victoires : ce qui est fait, jamais ce qui est « en retard »
        $wins = Get-WinsOfDay
        $streak = Get-WinStreak
        $head = if ($wins.Count) { "🏆 Aujourd'hui : $($wins.Count) victoire$(if ($wins.Count -gt 1) { 's' }) 🎉$(if ($streak -ge 2) { "   🔥 $streak jours d'affilée" })" } else { "🏆 Mes victoires : la journée commence, chaque petite chose comptera ici 🌱" }
        [void]$pn.DopaList.Children.Add((New-SectionTitle $head))
        foreach ($w in ($wins | Select-Object -First 30)) {
            $ico = if ($AnchorWinIcons.ContainsKey($w.kind)) { $AnchorWinIcons[$w.kind] } else { '✅' }
            [void]$pn.DopaList.Children.Add((New-CtxText "$ico  $($w.title)   ·  $($w.at.Substring(11, 5))" 12.5 '#4A4766'))
        }
        $pn.DopaCount.Text = "$(@($v.Actions).Count) action(s) · $(@($v.Routines | Where-Object { -not $_.DoneToday }).Count) routine(s) à faire aujourd'hui"
    } elseif ($NB.Tab -eq 'Dump') {
        $pn.DumpList.Children.Clear()
        foreach ($d in @($Anchor.Dump | Sort-Object -Property created -Descending)) {
            $b = New-Object Windows.Controls.Border
            $b.Margin = '0,0,0,6'; $b.Padding = '10,6'; $b.CornerRadius = '10'; $b.Background = '#EEEBFF'
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = $d.text; $tb.TextWrapping = 'Wrap'; $tb.Foreground = '#1E1B3A'
            $b.Child = $tb
            [void]$pn.DumpList.Children.Add($b)
        }
        $n = $Anchor.Dump.Count
        $pn.DumpSort.Content = if ($n) { "🧊 Trier à froid ($n)" } else { '✨ Bac vide : rien à trier' }
        $pn.DumpSort.IsEnabled = $n -gt 0
    }
}

Load-Anchor
