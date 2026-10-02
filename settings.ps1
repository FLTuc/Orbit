<#
    Fenetre de reglages d'Orbit (clic droit > Reglages).
    Ce fichier est charge par orbit.ps1 (il ne se lance pas tout seul).
#>

[xml]$settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Réglages d'Orbit" Width="420" Height="640"
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
        <TextBlock Text="⚙️ Réglages d'Orbit" FontSize="17" FontWeight="Bold" Foreground="#1E1B3A" VerticalAlignment="Center"/>
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
            <RadioButton x:Name="SSkinSatellite" Content="🛰️ Satellite" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinDroid" Content="🤖 Droïde" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinRobot" Content="🦾 Robot" GroupName="Skin" Margin="0,2,14,2" VerticalContentAlignment="Center"/>
            <RadioButton x:Name="SSkinButler" Content="🎩 Majordome" GroupName="Skin" Margin="0,2,0,2" VerticalContentAlignment="Center"/>
          </WrapPanel>

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

          <TextBlock Style="{StaticResource Section}" Text="🔔 Rappels"/>
          <CheckBox x:Name="STasks" Content="Rappeler mes tâches au début et à la fin du focus"/>
          <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
            <TextBlock Text="Me relancer toutes les" VerticalAlignment="Center"/>
            <TextBox x:Name="SNudge"/>
            <TextBlock Text="min quand Orbit attend ma réponse" VerticalAlignment="Center"/>
          </StackPanel>

          <TextBlock Style="{StaticResource Section}" Text="😄 Blagues et commentaires"/>
          <CheckBox x:Name="SJokes">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Blagues pendant la pause, environ toutes les" VerticalAlignment="Center"/>
              <TextBox x:Name="SJokeMin"/>
              <TextBlock Text="min" VerticalAlignment="Center"/>
            </StackPanel>
          </CheckBox>
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
          <CheckBox x:Name="SSounds" Content="Petit son à la fin des sessions et pour les rappels"/>
          <CheckBox x:Name="SDroid" Content="Bips de droïde à chaque bulle 🤖"/>
          <StackPanel Orientation="Horizontal" Margin="22,2,0,0">
            <TextBlock Text="Volume des bips" VerticalAlignment="Center"/>
            <Slider x:Name="SDroidVol" Minimum="5" Maximum="100" Width="150" Margin="10,0,8,0"
                    VerticalAlignment="Center" IsSnapToTickEnabled="True" TickFrequency="5"/>
            <Button x:Name="SDroidTest" Content="▶ Écouter" Padding="8,2" Background="#EEEEF5" BorderThickness="0" Cursor="Hand"/>
          </StackPanel>
          <CheckBox x:Name="SAuto" Content="Lancer Orbit au démarrage de Windows"/>
          <TextBlock Text=" " Margin="0,6,0,0"/>
        </StackPanel>
      </ScrollViewer>
    </DockPanel>
  </Border>
</Window>
'@

$settingsWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $settingsXaml))
$sw = @{}
foreach ($n in 'SHeader','SClose','SDefaults','SCancel','SSave','SError','SR50','SR25','SRPerso','SPersoFocus','SPersoBreak',
               'SIdle','SIdleMin','STasks','SNudge','SJokes','SJokeMin','SMotiv','SApps','SQuiet','SWander','SWanderMin',
               'SWanderMax','SSounds','SDroid','SDroidVol','SDroidTest','SAuto','SSkinSatellite','SSkinDroid','SSkinRobot','SSkinButler') {
    $sw[$n] = $settingsWin.FindName($n)
}

# Valeurs d'usine, pour le bouton "Valeurs par defaut"
$DefaultSettings = Get-SettingsSnapshot
$DefaultSettings.rhythm = '50/10'; $DefaultSettings.customFocus = 40; $DefaultSettings.customBreak = 8
$DefaultSettings.quiet = $false; $DefaultSettings.wander = $true; $DefaultSettings.wanderMin = 4; $DefaultSettings.wanderMax = 9
$DefaultSettings.taskReminders = $true; $DefaultSettings.reminderEveryMin = 4; $DefaultSettings.motivationEveryMin = 9
$DefaultSettings.jokes = $true; $DefaultSettings.jokeEveryMin = 2; $DefaultSettings.appComments = $true
$DefaultSettings.skin = 'Satellite'; $DefaultSettings.sounds = $true; $DefaultSettings.droidSounds = $true; $DefaultSettings.droidVolume = 40; $DefaultSettings.idlePause = $true; $DefaultSettings.idleMinutes = 5

function Fill-SettingsForm($d) {
    $sw.SR50.IsChecked = $d.rhythm -eq '50/10'
    $sw.SR25.IsChecked = $d.rhythm -eq '25/5'
    $sw.SRPerso.IsChecked = $d.rhythm -eq 'Perso'
    $sw.SPersoFocus.Text = $d.customFocus
    $sw.SPersoBreak.Text = $d.customBreak
    $sw.SIdle.IsChecked = $d.idlePause
    $sw.SIdleMin.Text = $d.idleMinutes
    $sw.STasks.IsChecked = $d.taskReminders
    $sw.SNudge.Text = $d.reminderEveryMin
    $sw.SJokes.IsChecked = $d.jokes
    $sw.SJokeMin.Text = $d.jokeEveryMin
    $sw.SMotiv.Text = $d.motivationEveryMin
    $sw.SApps.IsChecked = $d.appComments
    $sw.SQuiet.IsChecked = $d.quiet
    $sw.SWander.IsChecked = $d.wander
    $sw.SWanderMin.Text = $d.wanderMin
    $sw.SWanderMax.Text = $d.wanderMax
    $sw.SSounds.IsChecked = $d.sounds
    $sw.SDroid.IsChecked = $d.droidSounds
    $sw.SDroidVol.Value = [math]::Max(5, [double]$d.droidVolume)
    foreach ($k in 'Satellite', 'Droid', 'Robot', 'Butler') { $sw["SSkin$k"].IsChecked = ($d.skin -eq $k) }
    $sw.SError.Visibility = 'Collapsed'
    foreach ($tb in 'SPersoFocus','SPersoBreak','SIdleMin','SNudge','SJokeMin','SMotiv','SWanderMin','SWanderMax') {
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
        taskReminders = [bool]$sw.STasks.IsChecked; reminderEveryMin = [int]$nudge
        jokes = [bool]$sw.SJokes.IsChecked; jokeEveryMin = $joke; motivationEveryMin = [int]$motiv
        appComments = [bool]$sw.SApps.IsChecked; quiet = [bool]$sw.SQuiet.IsChecked
        wander = [bool]$sw.SWander.IsChecked; wanderMin = [int]$wmin; wanderMax = [int]$wmax
        sounds = [bool]$sw.SSounds.IsChecked; droidSounds = [bool]$sw.SDroid.IsChecked
        droidVolume = [int]$sw.SDroidVol.Value
    })
    Apply-Rhythm
    $skin = 'Satellite'
    foreach ($k in 'Droid', 'Robot', 'Butler') { if ($sw["SSkin$k"].IsChecked) { $skin = $k } }
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
    Fill-SettingsForm (Get-SettingsSnapshot)
    $sw.SAuto.IsChecked = Test-Path $StartupLink
    if ($CustomDurations) { $sw.SR50.ToolTip = 'Durées imposées au lancement (mode démo) : le rythme choisi servira au prochain démarrage normal.' }
    if (-not $Native) {
        $sw.SIdle.IsEnabled = $false
        $sw.SIdle.ToolTip = "Indisponible : les fonctions système d'Orbit n'ont pas pu être chargées sur ce PC."
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

$sw.SHeader.Add_MouseLeftButtonDown({ try { $settingsWin.DragMove() } catch {} })
$sw.SClose.Add_Click({ $settingsWin.Hide() })
$sw.SCancel.Add_Click({ $settingsWin.Hide() })
$sw.SDefaults.Add_Click({ Invoke-Safe { Fill-SettingsForm $DefaultSettings } })
$sw.SSave.Add_Click({ Invoke-Safe { Save-SettingsForm } })
# ecoute immediate du volume choisi, sans enregistrer
$sw.SDroidTest.Add_Click({
    Invoke-Safe {
        $old = $Config.DroidVolume; $wasOn = $Config.DroidSounds
        $Config.DroidVolume = [int]$sw.SDroidVol.Value; $Config.DroidSounds = $true
        $script:LastChirp = [datetime]::MinValue
        Play-Chirp
        $Config.DroidVolume = $old; $Config.DroidSounds = $wasOn
    }
})
$settingsWin.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; $settingsWin.Hide() } })
$settingsWin.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $e.Handled = $true; $settingsWin.Hide() } })
