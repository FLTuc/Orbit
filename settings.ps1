<#
    Fenetre de reglages d'Orbit (clic droit > Reglages).
    Ce fichier est charge par orbit.ps1 (il ne se lance pas tout seul).
#>

[xml]$settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Réglages d'Orbit" Width="440" Height="680"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="NoResize" UseLayoutRounding="True"
        FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="TextBlock" x:Key="Section">
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Foreground" Value="#1E1B3A"/>
      <Setter Property="Margin" Value="0,14,0,6"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Width" Value="52"/>
      <Setter Property="Padding" Value="4,2"/>
      <Setter Property="Margin" Value="6,0,6,0"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Margin" Value="0,3,0,3"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
  </Window.Resources>
  <Border Margin="6" CornerRadius="18" Background="#FFFDFBFF" BorderBrush="#1E1B3A" BorderThickness="2.5">
    <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="-45" Opacity="0.25"/></Border.Effect>
    <DockPanel>
      <Grid x:Name="SHeader" DockPanel.Dock="Top" Background="Transparent" Margin="18,12,10,0">
        <TextBlock Text="⚙ Réglages d'Orbit" FontSize="17" FontWeight="Bold" Foreground="#1E1B3A" VerticalAlignment="Center"/>
        <Button x:Name="SClose" Content="✕" HorizontalAlignment="Right" Width="30" Height="30"
                Background="Transparent" BorderThickness="0" FontSize="14" Cursor="Hand" ToolTip="Fermer sans enregistrer"/>
      </Grid>

      <Grid DockPanel.Dock="Bottom" Margin="18,8,18,14">
        <Button x:Name="SDefaults" Content="Valeurs par défaut" HorizontalAlignment="Left" Padding="10,5"
                Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="SCancel" Content="Annuler" Padding="12,5" Margin="0,0,8,0"
                  Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
          <Button x:Name="SSave" Content="💾 Enregistrer" Padding="12,5" Foreground="White"
                  Background="#6C5CE7" BorderBrush="#1E1B3A" BorderThickness="2" FontWeight="SemiBold" Cursor="Hand"/>
        </StackPanel>
      </Grid>
      <TextBlock x:Name="SError" DockPanel.Dock="Bottom" Foreground="#E03131" Margin="18,0,18,0"
                 TextWrapping="Wrap" Visibility="Collapsed"/>

      <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="18,0,10,0" Padding="0,0,8,0">
        <StackPanel>
          <TextBlock Style="{StaticResource Section}" Text="🎨 Apparence d'Orbit"/>
          <WrapPanel>
            <RadioButton x:Name="SSkinSatellite" Content="🛰 Satellite" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinDroid" Content="🤖 Droïde" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinRobot" Content="🦾 Robot" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinButler" Content="🎩 Majordome robot" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinHuman" Content="🤵 Majordome humain" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinBrain" Content="🧠 Cerveau" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinCustom" Content="🖼 Mon image" GroupName="Skin" Margin="0,2,0,2" VerticalContentAlignment="Center"/>
          </WrapPanel>
          <StackPanel Orientation="Horizontal" Margin="22,4,0,0">
            <Button x:Name="SImgPick" Content="🖼 Choisir une image…" Padding="8,2" Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
            <TextBlock x:Name="SImgName" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="#6B6880" FontSize="11.5"/>
          </StackPanel>

          <TextBlock Style="{StaticResource Section}" Text="⏱ Rythme Pomodoro"/>
          <StackPanel Orientation="Horizontal">
            <RadioButton x:Name="SR50" Content="50 / 10" GroupName="R" Margin="0,0,14,0" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SR25" Content="25 / 5" GroupName="R" Margin="0,0,14,0" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SRPerso" Content="Perso :" GroupName="R" VerticalContentAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="20,6,0,0">
            <TextBlock Text="focus" VerticalAlignment="Center"/>
            <TextBox x:Name="SPersoFocus"/>
            <TextBlock Text="min, pause" VerticalAlignment="Center"/>
            <TextBox x:Name="SPersoBreak"/>
            <TextBlock Text="min" VerticalAlignment="Center"/>
          </StackPanel>

          <TextBlock Style="{StaticResource Section}" Text="💤 Absence"/>
          <CheckBox x:Name="SIdle">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Mettre le focus en pause si je m'absente" VerticalAlignment="Center"/>
              <TextBox x:Name="SIdleMin"/>
              <TextBlock Text="min" VerticalAlignment="Center"/>
            </StackPanel>
          </CheckBox>

          <TextBlock Style="{StaticResource Section}" Text="✋ Je m'interromps (reprendre là où j'en étais)"/>
          <CheckBox x:Name="SCtxButton" Content="Bouton ✋ à côté d'Orbit pendant un focus"/>
          <CheckBox x:Name="SAnchorButton" Content="Bouton 📝 (note rapide) à côté d'Orbit"/>
          <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
            <TextBlock Text="Garder" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <ComboBox x:Name="SCtxWindows" Width="250">
              <ComboBoxItem Tag="0" Content="la fenêtre active seulement"/>
              <ComboBoxItem Tag="2" Content="la fenêtre active + les 2 précédentes"/>
              <ComboBoxItem Tag="3" Content="la fenêtre active + les 3 précédentes"/>
              <ComboBoxItem Tag="5" Content="la fenêtre active + les 5 précédentes"/>
            </ComboBox>
          </StackPanel>
          <CheckBox x:Name="SCtxShot" Margin="0,6,0,3">
            <TextBlock TextWrapping="Wrap" Width="370" Text="📷 Prendre aussi une petite capture d'écran (elle reste sur ce PC, n'est jamais exportée, et s'efface quand tu as repris)"/>
          </CheckBox>
          <CheckBox x:Name="SCtxRemind">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Me relancer si je n'ai pas repris après" VerticalAlignment="Center"/>
              <TextBox x:Name="SCtxRemindMin"/>
              <TextBlock Text="min (3 fois max)" VerticalAlignment="Center"/>
            </StackPanel>
          </CheckBox>

          <TextBlock Style="{StaticResource Section}" Text="🔔 Rappels"/>
          <CheckBox x:Name="STasks" Content="Rappeler mes tâches au début et à la fin du focus"/>
          <CheckBox x:Name="SMorning" Content="☀ Le matin, me proposer un plan (les 3 cartes les plus urgentes)" Margin="0,4,0,0"/>
          <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
            <TextBlock Text="Me relancer toutes les" VerticalAlignment="Center"/>
            <TextBox x:Name="SNudge"/>
            <TextBlock Text="min quand Orbit attend ma réponse" VerticalAlignment="Center"/>
          </StackPanel>

          <TextBlock Style="{StaticResource Section}" Text="😄 Blagues et commentaires"/>
          <CheckBox x:Name="SJokes">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Pendant la pause, environ toutes les" VerticalAlignment="Center"/>
              <TextBox x:Name="SJokeMin"/>
              <TextBlock Text="min :" VerticalAlignment="Center"/>
            </StackPanel>
          </CheckBox>
          <ComboBox x:Name="SBreakContent" Margin="22,4,0,0" Width="300" HorizontalAlignment="Left">
            <ComboBoxItem Tag="Both" Content="😄 + 🧠  Blagues et culture G, en alternance"/>
            <ComboBoxItem Tag="Jokes" Content="😄  Des blagues"/>
            <ComboBoxItem Tag="Culture" Content="🧠  De la culture G (anecdotes et quiz)"/>
          </ComboBox>
          <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
            <TextBlock Text="Une phrase de motivation toutes les" VerticalAlignment="Center"/>
            <TextBox x:Name="SMotiv"/>
            <TextBlock Text="min de focus" VerticalAlignment="Center"/>
          </StackPanel>
          <CheckBox x:Name="SApps" Content="Commentaires sur l'application sous ma souris"/>
          <CheckBox x:Name="SQuiet" Content="Mode silencieux (Orbit ne parle que pour l'essentiel)"/>

          <TextBlock Style="{StaticResource Section}" Text="🚶 Balades"/>
          <CheckBox x:Name="SWander">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Se balader toutes les" VerticalAlignment="Center"/>
              <TextBox x:Name="SWanderMin"/>
              <TextBlock Text="à" VerticalAlignment="Center"/>
              <TextBox x:Name="SWanderMax"/>
              <TextBlock Text="min" VerticalAlignment="Center"/>
            </StackPanel>
          </CheckBox>

          <TextBlock Style="{StaticResource Section}" Text="🔊 Sons et démarrage"/>
          <CheckBox x:Name="SDroid" Content="Un son à chaque bulle"/>
          <StackPanel Orientation="Horizontal" Margin="22,3,0,0">
            <ComboBox x:Name="SBubbleSound" Width="150">
              <ComboBoxItem Content="🤖 Droïde doux" Tag="Droide"/>
              <ComboBoxItem Content="🔔 Carillon" Tag="Carillon"/>
              <ComboBoxItem Content="🎵 Marimba" Tag="Marimba"/>
              <ComboBoxItem Content="🎈 Pop" Tag="Pop"/>
              <ComboBoxItem Content="📟 Bip" Tag="Bip"/>
              <ComboBoxItem Content="📁 Mes sons (au hasard)" Tag="Fichier"/>
              <ComboBoxItem Content="🎲 Aléatoire (tous les sons)" Tag="Aleatoire"/>
            </ComboBox>
            <Button x:Name="SBubbleTest" Content="▶" Padding="8,2" Margin="6,0,0,0" Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Écouter"/>
          </StackPanel>
          <TextBlock Margin="22,6,0,2" Text="Mes sons (.wav, .mp3…) — un est choisi au hasard à chaque bulle :" Foreground="#4A4766" FontSize="12"/>
          <Grid Margin="22,0,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <ListBox x:Name="SMySounds" Height="72" SelectionMode="Extended" FontSize="12"/>
            <StackPanel Grid.Column="1" Margin="6,0,0,0">
              <Button x:Name="SSoundAdd" Content="＋ Ajouter…" Padding="8,2" Margin="0,0,0,4" Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
              <Button x:Name="SSoundDel" Content="－ Retirer" Padding="8,2" Margin="0,0,0,4" Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
              <Button x:Name="SSoundPlay" Content="▶ Écouter" Padding="8,2" Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Écouter le son sélectionné"/>
            </StackPanel>
          </Grid>

          <CheckBox x:Name="SSounds" Margin="0,8,0,3" Content="Un son à la fin des sessions et pour les rappels"/>
          <StackPanel Orientation="Horizontal" Margin="22,3,0,0">
            <ComboBox x:Name="SEndSound" Width="150">
              <ComboBoxItem Content="🔔 Carillon (3 notes)" Tag="Carillon"/>
              <ComboBoxItem Content="💻 Son de Windows" Tag="Windows"/>
              <ComboBoxItem Content="📁 Mon fichier son" Tag="Fichier"/>
            </ComboBox>
            <Button x:Name="SEndFile" Content="Choisir…" Padding="8,2" Margin="6,0,0,0" Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
            <Button x:Name="SEndTest" Content="▶" Padding="8,2" Margin="6,0,0,0" Background="#EEEEF5" BorderThickness="0" Cursor="Hand" ToolTip="Écouter"/>
          </StackPanel>
          <TextBlock x:Name="SEndFileName" Margin="22,2,0,0" Foreground="#6B6880" FontSize="11.5"/>

          <StackPanel Orientation="Horizontal" Margin="0,8,0,4">
            <TextBlock Text="Volume des sons" VerticalAlignment="Center"/>
            <Slider x:Name="SDroidVol" Minimum="5" Maximum="100" Width="170" Margin="10,0,0,0"
                    VerticalAlignment="Center" IsSnapToTickEnabled="True" TickFrequency="5"/>
          </StackPanel>
          <CheckBox x:Name="SAuto" Content="Lancer Orbit au démarrage de Windows"/>
          <TextBlock Text=" " Margin="0,6,0,0"/>
        </StackPanel>
      </ScrollViewer>
    </DockPanel>
  </Border>
</Window>
'@

# La fenetre des reglages n'est construite qu'a sa premiere ouverture (Initialize-Settings)
$settingsWin = $null
$sw = @{}

# Valeurs d'usine, pour le bouton "Valeurs par defaut"
$DefaultSettings = Get-SettingsSnapshot
$DefaultSettings.rhythm = '50/10'; $DefaultSettings.customFocus = 40; $DefaultSettings.customBreak = 8
$DefaultSettings.quiet = $false; $DefaultSettings.wander = $true; $DefaultSettings.wanderMin = 4; $DefaultSettings.wanderMax = 9
$DefaultSettings.taskReminders = $true; $DefaultSettings.morningPlan = $true; $DefaultSettings.reminderEveryMin = 4; $DefaultSettings.motivationEveryMin = 9
$DefaultSettings.jokes = $true; $DefaultSettings.breakContent = 'Both'; $DefaultSettings.jokeEveryMin = 2; $DefaultSettings.appComments = $true
$DefaultSettings.skin = 'Satellite'; $DefaultSettings.sounds = $true; $DefaultSettings.droidSounds = $true; $DefaultSettings.droidVolume = 40; $DefaultSettings.bubbleSound = 'Droide'; $DefaultSettings.endSound = 'Carillon'; $DefaultSettings.idlePause = $true; $DefaultSettings.idleMinutes = 5
$DefaultSettings.anchorButton = $true; $DefaultSettings.contextButton = $true; $DefaultSettings.contextWindows = 3; $DefaultSettings.contextScreenshot = $false; $DefaultSettings.contextRemind = $true; $DefaultSettings.contextRemindMin = 30

function Fill-SettingsForm($d) {
    $sw.SR50.IsChecked = $d.rhythm -eq '50/10'
    $sw.SR25.IsChecked = $d.rhythm -eq '25/5'
    $sw.SRPerso.IsChecked = $d.rhythm -eq 'Perso'
    $sw.SPersoFocus.Text = $d.customFocus
    $sw.SPersoBreak.Text = $d.customBreak
    $sw.SIdle.IsChecked = $d.idlePause
    $sw.SIdleMin.Text = $d.idleMinutes
    $sw.STasks.IsChecked = $d.taskReminders
    $sw.SCtxButton.IsChecked = $d.contextButton
    $sw.SAnchorButton.IsChecked = $d.anchorButton
    Select-ComboTag $sw.SCtxWindows ([string]$d.contextWindows)
    $sw.SCtxShot.IsChecked = $d.contextScreenshot
    $sw.SCtxRemind.IsChecked = $d.contextRemind
    $sw.SCtxRemindMin.Text = $d.contextRemindMin
    $sw.SMorning.IsChecked = $d.morningPlan
    $sw.SNudge.Text = $d.reminderEveryMin
    $sw.SJokes.IsChecked = $d.jokes
    $sw.SJokeMin.Text = $d.jokeEveryMin
    Select-ComboTag $sw.SBreakContent $(if ($d.breakContent) { [string]$d.breakContent } else { 'Both' })
    $sw.SMotiv.Text = $d.motivationEveryMin
    $sw.SApps.IsChecked = $d.appComments
    $sw.SQuiet.IsChecked = $d.quiet
    $sw.SWander.IsChecked = $d.wander
    $sw.SWanderMin.Text = $d.wanderMin
    $sw.SWanderMax.Text = $d.wanderMax
    $sw.SSounds.IsChecked = $d.sounds
    $sw.SDroid.IsChecked = $d.droidSounds
    $sw.SDroidVol.Value = [math]::Max(5, [double]$d.droidVolume)
    foreach ($k in 'Satellite', 'Droid', 'Robot', 'Butler', 'Human', 'Brain', 'Custom') { $sw["SSkin$k"].IsChecked = ($d.skin -eq $k) }
    $SF.BubbleFiles = New-Object System.Collections.ArrayList
    foreach ($f in @($d.bubbleSoundFiles)) { if ($f) { [void]$SF.BubbleFiles.Add([string]$f) } }
    $SF.EndFile = [string]$d.endSoundFile
    Select-ComboTag $sw.SBubbleSound $d.bubbleSound
    Select-ComboTag $sw.SEndSound $d.endSound
    Update-FileLabels
    $sw.SError.Visibility = 'Collapsed'
    foreach ($tb in 'SPersoFocus','SPersoBreak','SIdleMin','SNudge','SJokeMin','SMotiv','SWanderMin','SWanderMax','SCtxRemindMin') {
        $sw[$tb].ClearValue([Windows.Controls.Control]::BorderBrushProperty)
    }
}

# Lit un nombre dans un champ ; le champ passe en rouge s'il est invalide
function Read-Number([string]$name, [double]$min, [double]$max, [ref]$errors) {
    $tb = $sw[$name]
    $v = 0.0
    $txt = $tb.Text.Trim().Replace(',', '.')
    if ([double]::TryParse($txt, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and
        $v -ge $min -and $v -le $max) {
        $tb.ClearValue([Windows.Controls.Control]::BorderBrushProperty)
        return $v
    }
    $tb.BorderBrush = '#E03131'
    $errors.Value += "entre $min et $max"
    return $null
}

function Save-SettingsForm {
    $errors = @()
    $pf = Read-Number 'SPersoFocus' 1 240 ([ref]$errors)
    $pb = Read-Number 'SPersoBreak' 1 120 ([ref]$errors)
    $idle = Read-Number 'SIdleMin' 1 120 ([ref]$errors)
    $nudge = Read-Number 'SNudge' 1 60 ([ref]$errors)
    $joke = Read-Number 'SJokeMin' 0.5 30 ([ref]$errors)
    $motiv = Read-Number 'SMotiv' 1 120 ([ref]$errors)
    $wmin = Read-Number 'SWanderMin' 1 120 ([ref]$errors)
    $wmax = Read-Number 'SWanderMax' 1 240 ([ref]$errors)
    $ctxMin = Read-Number 'SCtxRemindMin' 5 480 ([ref]$errors)
    if ($errors.Count) {
        $sw.SError.Text = "Certaines valeurs ne sont pas valides (en rouge). Corrige-les avant d'enregistrer."
        $sw.SError.Visibility = 'Visible'
        return
    }
    if ($wmax -le $wmin) { $wmax = $wmin + 1 }

    $rhythm = if ($sw.SR25.IsChecked) { '25/5' } elseif ($sw.SRPerso.IsChecked) { 'Perso' } else { '50/10' }
    Apply-SettingsData ([pscustomobject]@{
        rhythm = $rhythm; customFocus = $pf; customBreak = $pb
        idlePause = [bool]$sw.SIdle.IsChecked; idleMinutes = [int]$idle
        taskReminders = [bool]$sw.STasks.IsChecked; reminderEveryMin = [int]$nudge; morningPlan = [bool]$sw.SMorning.IsChecked
        jokes = [bool]$sw.SJokes.IsChecked; jokeEveryMin = $joke; breakContent = $(if ($sw.SBreakContent.SelectedItem) { [string]$sw.SBreakContent.SelectedItem.Tag } else { 'Both' }); motivationEveryMin = [int]$motiv
        appComments = [bool]$sw.SApps.IsChecked; quiet = [bool]$sw.SQuiet.IsChecked
        wander = [bool]$sw.SWander.IsChecked; wanderMin = [int]$wmin; wanderMax = [int]$wmax
        sounds = [bool]$sw.SSounds.IsChecked; droidSounds = [bool]$sw.SDroid.IsChecked
        droidVolume = [int]$sw.SDroidVol.Value
        bubbleSound = [string]$sw.SBubbleSound.SelectedItem.Tag; bubbleSoundFiles = @($SF.BubbleFiles)
        endSound = [string]$sw.SEndSound.SelectedItem.Tag; endSoundFile = $SF.EndFile
        anchorButton = [bool]$sw.SAnchorButton.IsChecked; contextButton = [bool]$sw.SCtxButton.IsChecked; contextWindows = $(if ($sw.SCtxWindows.SelectedItem) { [int]$sw.SCtxWindows.SelectedItem.Tag } else { 3 })
        contextScreenshot = [bool]$sw.SCtxShot.IsChecked; contextRemind = [bool]$sw.SCtxRemind.IsChecked; contextRemindMin = [int]$ctxMin
    })
    Update-Pill
    Apply-Rhythm
    $skin = 'Satellite'
    foreach ($k in 'Droid', 'Robot', 'Butler', 'Human', 'Brain', 'Custom') { if ($sw["SSkin$k"].IsChecked) { $skin = $k } }
    if ($skin -ne $O.Skin) { Set-Skin $skin -Quiet }
    if (-not $O.Wander) { $O.Walking = $false }
    if ($O.Quiet) { Hide-Bubble }
    Save-Settings

    $wantAuto = [bool]$sw.SAuto.IsChecked
    if ($wantAuto -ne (Test-Path $StartupLink)) {
        try { Set-Autostart $wantAuto -Silent } catch { Write-Log "Demarrage auto : $($_.Exception.Message)" }
    }

    $settingsWin.Hide()
    $msg = "Réglages enregistrés ✅"
    if ($O.State -in 'Focus', 'Break') { $msg += "`nLe nouveau rythme s'appliquera à la prochaine session." }
    Show-Bubble $msg -Force -Seconds 4
}

function Open-Settings {
    Initialize-Settings
    Fill-SettingsForm (Get-SettingsSnapshot)
    $sw.SAuto.IsChecked = Test-Path $StartupLink
    if ($CustomDurations) { $sw.SR50.ToolTip = 'Durées imposées au lancement (mode démo) : le rythme choisi servira au prochain démarrage normal.' }
    if (-not $Native) {
        $sw.SIdle.IsEnabled = $false
        $sw.SIdle.ToolTip = "Indisponible : les fonctions système d'Orbit n'ont pas pu être chargées sur ce PC."
        $sw.SCtxWindows.IsEnabled = $false
        $sw.SCtxWindows.ToolTip = "Indisponible : sans les fonctions système, Orbit garde seulement ta note."
    }
    if ($settingsWin.Visibility -ne 'Visible') {
        $p = [System.Windows.Forms.Cursor]::Position
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint($p))
        $settingsWin.Left = [math]::Max($wa.L, $wa.R - $settingsWin.Width - 8)
        $settingsWin.Top = [math]::Max($wa.T, $wa.B - $settingsWin.Height - 150)
        $settingsWin.Show()
    }
    $settingsWin.Activate() | Out-Null
}

# choix des fichiers en attente d'enregistrement
$SF = @{ BubbleFiles = (New-Object System.Collections.ArrayList); EndFile = '' }
$SoundsDir = Join-Path $DataDir 'sons'

function Select-ComboTag($combo, [string]$tag) {
    foreach ($it in $combo.Items) { if ($it.Tag -eq $tag) { $combo.SelectedItem = $it; return } }
    $combo.SelectedIndex = 0
}

function Update-FileLabels {
    $sw.SMySounds.Items.Clear()
    foreach ($f in $SF.BubbleFiles) {
        $it = New-Object Windows.Controls.ListBoxItem
        $it.Content = '🎵 ' + [IO.Path]::GetFileNameWithoutExtension($f) + $(if (Test-Path -LiteralPath $f) { '' } else { '  (introuvable)' })
        $it.Tag = $f
        [void]$sw.SMySounds.Items.Add($it)
    }
    if (-not $SF.BubbleFiles.Count) { [void]$sw.SMySounds.Items.Add('Aucun son pour l''instant : clique sur « Ajouter… »') }
    $sw.SEndFileName.Text = if ($SF.EndFile) { '📁 ' + [IO.Path]::GetFileName($SF.EndFile) } else { '' }
    $sw.SImgName.Text = if ($Config.CustomImage) { [IO.Path]::GetFileName($Config.CustomImage) } else { 'aucune image pour l''instant' }
}

function Pick-WavFile([switch]$Multi) {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = if ($Multi) { 'Choisis un ou plusieurs sons' } else { 'Choisis un son' }
    $dlg.Filter = 'Sons (*.wav;*.mp3;*.m4a;*.wma)|*.wav;*.mp3;*.m4a;*.wma'
    $dlg.Multiselect = [bool]$Multi
    if ($dlg.ShowDialog()) { if ($Multi) { return , $dlg.FileNames } else { return $dlg.FileName } }
    return $null
}

# ajoute des sons : copies dans le dossier d'Orbit pour rester disponibles
function Add-MySounds {
    $files = Pick-WavFile -Multi
    if (-not $files) { return }
    if (-not (Test-Path $SoundsDir)) { New-Item -ItemType Directory -Path $SoundsDir | Out-Null }
    foreach ($f in $files) {
        try {
            $name = [IO.Path]::GetFileName($f)
            $dest = Join-Path $SoundsDir $name
            $i = 2
            while ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -ne (Get-Item -LiteralPath $f).Length)) {
                $dest = Join-Path $SoundsDir ("{0} ({1}){2}" -f [IO.Path]::GetFileNameWithoutExtension($f), $i, [IO.Path]::GetExtension($f)); $i++
            }
            if ($f -ne $dest) { Copy-Item -LiteralPath $f -Destination $dest -Force }
            if ($SF.BubbleFiles -notcontains $dest) { [void]$SF.BubbleFiles.Add($dest) }
        } catch { Write-Log "Ajout son : $($_.Exception.Message)" }
    }
    if ([string]$sw.SBubbleSound.SelectedItem.Tag -notin 'Fichier', 'Aleatoire') { Select-ComboTag $sw.SBubbleSound 'Fichier' }
    Update-FileLabels
}

function Remove-MySounds {
    foreach ($it in @($sw.SMySounds.SelectedItems)) { if ($it.Tag) { $SF.BubbleFiles.Remove([string]$it.Tag) } }
    Update-FileLabels
}

# ecoute d'un son avec les choix de la fenetre, sans enregistrer
function Test-SoundChoice([switch]$End) {
    $keep = @{}
    foreach ($k in 'DroidVolume', 'DroidSounds', 'Sounds', 'BubbleSound', 'BubbleSoundFiles', 'EndSound', 'EndSoundFile') { $keep[$k] = $Config[$k] }
    $Config.DroidVolume = [int]$sw.SDroidVol.Value; $Config.DroidSounds = $true; $Config.Sounds = $true
    $Config.BubbleSound = [string]$sw.SBubbleSound.SelectedItem.Tag; $Config.BubbleSoundFiles = @($SF.BubbleFiles)
    $Config.EndSound = [string]$sw.SEndSound.SelectedItem.Tag; $Config.EndSoundFile = $SF.EndFile
    if ($End) { Play-Sound -Force } else { Play-Chirp -Force -Question:((Get-Random -Maximum 2) -eq 1) }
    foreach ($k in $keep.Keys) { $Config[$k] = $keep[$k] }
}

# ---------------------------------------------------------------------------
#  Construction de la fenetre (a la premiere ouverture seulement)
# ---------------------------------------------------------------------------
function Initialize-Settings {
    if ($script:settingsWin) { return }
    $script:settingsWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $settingsXaml))
    $script:sw = @{}
    foreach ($n in 'SHeader','SClose','SDefaults','SCancel','SSave','SError','SR50','SR25','SRPerso','SPersoFocus','SPersoBreak',
                   'SIdle','SIdleMin','STasks','SCtxButton','SAnchorButton','SCtxWindows','SCtxShot','SCtxRemind','SCtxRemindMin','SMorning','SNudge','SJokes','SJokeMin','SBreakContent','SMotiv','SApps','SQuiet','SWander','SWanderMin',
                   'SWanderMax','SSounds','SDroid','SDroidVol','SAuto','SBubbleSound','SBubbleTest','SMySounds','SSoundAdd','SSoundDel','SSoundPlay',
                   'SEndSound','SEndFile','SEndTest','SEndFileName','SSkinCustom','SImgPick','SImgName','SSkinSatellite','SSkinDroid','SSkinRobot','SSkinButler','SSkinBrain','SSkinHuman') {
        $sw[$n] = $settingsWin.FindName($n)
    }

    $sw.SHeader.Add_MouseLeftButtonDown({ try { $settingsWin.DragMove() } catch {} })
    $sw.SClose.Add_Click({ $settingsWin.Hide() })
    $sw.SCancel.Add_Click({ $settingsWin.Hide() })
    $sw.SDefaults.Add_Click({ Invoke-Safe { Fill-SettingsForm $DefaultSettings } })
    $sw.SSave.Add_Click({ Invoke-Safe { Save-SettingsForm } })
    $sw.SBubbleTest.Add_Click({ Invoke-Safe { Test-SoundChoice } })
    $sw.SEndTest.Add_Click({ Invoke-Safe { Test-SoundChoice -End } })
    $sw.SSoundAdd.Add_Click({ Invoke-Safe { Add-MySounds } })
    $sw.SSoundDel.Add_Click({ Invoke-Safe { Remove-MySounds } })
    $sw.SSoundPlay.Add_Click({
        Invoke-Safe {
            $it = $sw.SMySounds.SelectedItem
            $f = if ($it -and $it.Tag) { [string]$it.Tag } elseif ($SF.BubbleFiles.Count) { $SF.BubbleFiles[0] } else { $null }
            if ($f -and -not (Play-AudioFile $f)) { [Windows.MessageBox]::Show($settingsWin, "Impossible de lire ce fichier. Vérifie que c'est bien un fichier .wav, .mp3, .m4a ou .wma.", 'Orbit') | Out-Null }
        }
    })
    $sw.SEndFile.Add_Click({ Invoke-Safe { $f = Pick-WavFile; if ($f) { $SF.EndFile = $f; Select-ComboTag $sw.SEndSound 'Fichier'; Update-FileLabels } } })
    $sw.SImgPick.Add_Click({
        Invoke-Safe {
            if (Choose-CustomImage) { $sw.SSkinCustom.IsChecked = $true }
            Update-FileLabels
        }
    })
    $settingsWin.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; $settingsWin.Hide() } })
    $settingsWin.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $e.Handled = $true; $settingsWin.Hide() } })
}
