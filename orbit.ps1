<#
    Orbit - petit compagnon de focus (Pomodoro 50/10 ou 25/5) pour Windows 10/11.

    Aucune installation, aucun droit administrateur :
    uniquement PowerShell 5.1 + WPF, deja presents dans Windows.

    Lancement : double-clic sur Orbit.cmd
    Test rapide : Orbit.cmd -Demo   (focus 1 min, pause 30 s)
    Le rythme 50/10 ou 25/5 se choisit ensuite dans le menu clic droit.
#>
param(
    [double]$FocusMinutes = 50,
    [double]$BreakMinutes = 10,
    [switch]$Demo
)

# Durees imposees en ligne de commande (ou mode demo) : elles priment sur le rythme choisi dans le menu
$CustomDurations = $Demo -or $PSBoundParameters.ContainsKey('FocusMinutes') -or $PSBoundParameters.ContainsKey('BreakMinutes')
if ($Demo) { $FocusMinutes = 1; $BreakMinutes = 0.5 }

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Reglages
# ---------------------------------------------------------------------------
$Config = @{
    FocusMinutes        = $FocusMinutes
    BreakMinutes        = $BreakMinutes
    MotivationEveryMin  = 9      # une petite phrase de motivation toutes les ~9 min
    AppCommentCooldownS = 150    # delai mini entre deux commentaires sur une appli
    AppDwellS           = 4      # temps passe sur une appli avant qu'Orbit la commente
    ReminderEveryMin    = 4      # relance quand Orbit attend ta reponse
    WanderMinMin        = 4      # balade toutes les 4 a 9 minutes
    WanderMaxMin        = 9
    BubbleSeconds       = 7
    CornerMargin        = 6
}

# Rythmes Pomodoro disponibles : focus / pause, en minutes
$Rhythms = [ordered]@{
    '50/10' = @{ Focus = 50; Break = 10; Icon = '🚀' }
    '25/5'  = @{ Focus = 25; Break = 5;  Icon = '⚡' }
}

$DataDir = Join-Path $env:APPDATA 'Orbit'
$StatsFile = Join-Path $DataDir 'stats.json'
$LogFile = Join-Path $DataDir 'orbit.log'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

function Write-Log([string]$msg) {
    try { Add-Content -Path $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8 } catch {}
}

# Une seule instance a la fois
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\OrbitFocusBot', [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ---------------------------------------------------------------------------
#  Fonctions natives (facultatives : si elles ne compilent pas, Orbit marche
#  quand meme, il perd juste les commentaires sur les applis)
# ---------------------------------------------------------------------------
$Native = $false
try {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class OrbitNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int idx, int v);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();

    public static uint UnderCursor(out string title) {
        title = "";
        POINT p;
        if (!GetCursorPos(out p)) return 0;
        IntPtr h = WindowFromPoint(p);
        if (h == IntPtr.Zero) return 0;
        IntPtr root = GetAncestor(h, 2);
        if (root != IntPtr.Zero) h = root;
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, 512);
        title = sb.ToString();
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        return pid;
    }

    // Masque la fenetre du Alt+Tab
    public static void MakeToolWindow(IntPtr h) {
        int ex = GetWindowLong(h, -20);
        SetWindowLong(h, -20, ex | 0x80);
    }

    // Repasse au premier plan sans voler le focus
    public static void KeepOnTop(IntPtr h) {
        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
    }

    public static void HideConsole() {
        IntPtr c = GetConsoleWindow();
        if (c != IntPtr.Zero) ShowWindow(c, 0);
    }
}
'@
    $Native = $true
    [OrbitNative]::HideConsole()
} catch {
    Write-Log "Fonctions natives indisponibles : $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
#  Repliques
# ---------------------------------------------------------------------------
$Lines = @{
    Hello = @(
        "Salut, moi c'est Orbit 👋 On lance une session de focus ?",
        "Coucou ! Prêt(e) à mettre le turbo ? 🚀"
    )
    FocusStart = @(
        "C'est parti pour {0} min de focus ! 🚀",
        "Mode concentration : ON. Je surveille les distractions 👀",
        "Décollage ! On se retrouve dans {0} minutes 🛰️"
    )
    Motivation = @(
        "Tu avances bien, continue comme ça 💪",
        "Une tâche à la fois. Tu gères.",
        "Les notifications peuvent attendre. Toi, tu avances.",
        "Petit rappel : le focus, c'est ton super-pouvoir ⚡",
        "Respire un coup… et on continue 🧘",
        "Chaque minute de focus compte. Celle-ci aussi.",
        "Si c'est difficile, c'est que ça vaut le coup.",
        "Tu fais du super boulot. Si si, je vois tout d'ici 🛰️",
        "Ferme un onglet inutile, juste pour le plaisir.",
        "Bois un peu d'eau, ton cerveau dit merci 💧",
        "Le futur toi te remercie déjà.",
        "Pas besoin d'être parfait, juste d'avancer."
    )
    HalfWay = @(
        "Mi-parcours ! Plus que {0} minutes 🏁",
        "La moitié est faite. La deuxième est toujours plus rapide 😉"
    )
    LastMinutes = @(
        "Plus que 5 minutes, dernier sprint ! 🏃",
        "5 minutes ! Termine ta phrase, ta cellule, ta ligne de code…"
    )
    FocusEnd = @(
        "Ding ! {0} minutes de focus bouclées 🎉 On fait la pause ?",
        "Bravo, session terminée ! 🏆 Je t'attends pour la pause."
    )
    BreakStart = @(
        "Pause méritée ! Lève-toi, étire-toi, bois de l'eau 💧",
        "Pause ! Regarde au loin 20 secondes, tes yeux te remercient 👀",
        "Va prendre l'air, je garde l'écran 🛡️"
    )
    BreakEnd = @(
        "La pause est finie ! On repart pour {0} minutes ? 🚀",
        "Rechargé(e) ? On y retourne ? 🔋"
    )
    AwaitBreak = @(
        "Psst… ta pause t'attend toujours ☕",
        "Tu as bien bossé, tu as le droit de souffler !",
        "Je ne veux pas insister, mais… pause ? 🥺"
    )
    AwaitFocus = @(
        "On relance une session quand tu veux 🚀",
        "Toujours là ? Je suis prêt à repartir 🛰️"
    )
    Stop = @(
        "Ok, on coupe. Bien joué : {0} session(s) de focus aujourd'hui 🏆",
        "Chrono coupé. {0} session(s) aujourd'hui, respect 🙌"
    )
    BreakJokes = @(
        "Pourquoi les astronautes ne se disputent jamais ? Parce qu'ils ont besoin d'espace 🚀",
        "Le comble pour un astronaute ? Être dans la lune 🌙",
        "Comment les planètes se coiffent-elles ? Avec des comètes ☄️",
        "Pourquoi les satellites ne mentent jamais ? Parce qu'on les a toujours à l'œil 🛰️",
        "Quel est le comble pour un électricien ? De ne pas être au courant ⚡",
        "Pourquoi les plongeurs plongent-ils en arrière ? Parce que sinon, ils tombent dans le bateau 🤿",
        "Qu'est-ce qui est jaune et qui attend ? Jonathan 🟡",
        "Que fait une fraise sur un cheval ? Tagada, tagada 🍓",
        "Quel est le sport le plus fruité ? La boxe : tu te prends des pêches et tu tombes dans les pommes 🥊",
        "Pourquoi le livre de maths est-il triste ? Parce qu'il a trop de problèmes 📘",
        "Qu'est-ce qu'un canif ? Un petit fien 🐶",
        "Qu'est-ce qui est vert et qui monte et descend ? Un petit pois dans un ascenseur 🟢",
        "Pourquoi Excel reste toujours calme ? Il a toutes ses cellules sous contrôle 📊",
        "Quel est le café préféré des développeurs ? Le Java ☕",
        "Comment appelle-t-on un boomerang qui ne revient pas ? Un bout de bois 🪃",
        "Deux grains de sable arrivent dans le désert : « Waouh, c'est blindé aujourd'hui ! » 🏜️",
        "Pourquoi les vaches ferment les yeux pendant la traite ? Pour faire du lait concentré 🐄",
        "Que dit une imprimante dans l'eau ? « J'ai papier ! » 🖨️",
        "Monsieur et Madame Térieur ont deux fils. Comment s'appellent-ils ? Alain et Alex 🏠",
        "Qu'est-ce qu'un crocodile qui surveille la pharmacie ? Un Lacoste-garde 🐊",
        "Que dit un oignon quand il se cogne ? « Aïe ! » 🧅",
        "Pourquoi les poissons détestent l'ordinateur ? À cause du Net 🐟",
        "Que dit un informaticien quand il s'ennuie ? « Je me fichier » 💾",
        "Pourquoi les fantômes sont-ils de mauvais menteurs ? Parce qu'on lit à travers eux 👻",
        "Quel est l'animal le plus heureux ? Le hibou, parce que sa femme est chouette 🦉",
        "Pourquoi les réunions du lundi sont-elles si longues ? Parce que le week-end a laissé des traces 😴",
        "Comment fait-on aboyer un chat ? On lui donne une tasse de lait, et il la boit 🐱",
        "Que dit le zéro au huit ? « Joli ta ceinture ! » 8️⃣",
        "Qu'est-ce qui a des dents mais ne mange jamais ? Un peigne 🪮",
        "Pourquoi le Wi-Fi est-il si sociable ? Parce qu'il a beaucoup de connexions 📶"
    )
    Wander = @(
        "Petite balade… 🚶",
        "Je vais voir ce qui se passe par là-bas 🔭",
        "Je me dégourdis les antennes 📡",
        "Tour d'orbite en cours… 🛰️"
    )
    Poke = @(
        "Hé ! Ça chatouille 😆",
        "Je suis là, je suis là 👋",
        "Bip boup 🤖"
    )
}

# Commentaires par application (nom du processus, en minuscules)
$AppLines = @{
    'chrome'  = @("Un onglet de plus et la RAM dépose plainte 🧠", "Chrome… combien d'onglets déjà ? Non, ne réponds pas.")
    'msedge'  = @("Edge ! Un choix audacieux, je respecte 😎", "Encore un onglet ? Je compte, hein 👀")
    'firefox' = @("Le renard est de sortie 🦊", "Firefox, le choix des connaisseurs.")
    'brave'   = @("Brave, comme toi face à cette to-do list 🦁")
    'outlook' = @("Inbox zéro, c'est un mythe… mais on y croit 📬", "Répondre à tous ? Réfléchis bien 😅", "Un mail = 2 minutes. Dix mails = la matinée.")
    'olk'     = @("Inbox zéro, c'est un mythe… mais on y croit 📬", "Répondre à tous ? Réfléchis bien 😅")
    'ms-teams'= @("Tu es en réunion ? Je fais semblant de prendre des notes 📝", "Pense à couper ton micro avant de soupirer 🎤", "Cette réunion aurait pu être un mail ? 🤫")
    'teams'   = @("Tu es en réunion ? Je fais semblant de prendre des notes 📝", "Pense à couper ton micro avant de soupirer 🎤")
    'excel'   = @("Tant que ça ne finit pas en #REF!, tout va bien 📊", "RECHERCHEV ou RECHERCHEX ? Le débat du siècle.", "Une macro et hop, tu deviens magicien 🪄", "Ctrl+Z est ton ami.")
    'winword' = @("Times New Roman ? Audacieux.", "Le document_final_v3_VRAIMENT_final.docx, c'est celui-là ? 📄", "Pense à sauvegarder ! Ctrl+S 💾")
    'powerpnt'= @("Encore une slide et c'est un roman graphique 🎞️", "Moins de texte, plus d'impact ✨", "Les transitions en 'tourbillon', c'est non 🌀")
    'onenote' = @("Prendre des notes, c'est déjà avancer 🗒️")
    'code'    = @("Ça compile ? Alors ça marche. (Presque.) 💻", "Un bug ? Explique-le à moi, je suis un excellent canard en caoutchouc 🦆", "Tabs ou espaces ? Je ne dirai rien.")
    'devenv'  = @("Visual Studio charge… on a le temps d'un café ☕", "Un breakpoint et tout s'éclaire 🔍")
    'idea64'  = @("IntelliJ réfléchit… toi aussi 🤔")
    'pycharm64' = @("Ça sent le Python 🐍")
    'notepad' = @("Le Bloc-notes, simple et efficace 📝")
    'notepad++' = @("Notepad++, l'outil des vrais 💪")
    'explorer'= @("Tu cherches un fichier ? Il est sûrement dans Téléchargements 🗂️", "Rangement de dossiers = procrastination déguisée ? 🤔")
    'windowsterminal' = @("Ah, l'écran noir des vrais pros 😎", "sudo fais-moi-un-café ☕")
    'powershell' = @("PowerShell ! On est entre collègues 😄")
    'pwsh'    = @("PowerShell ! On est entre collègues 😄")
    'cmd'     = @("L'invite de commandes, old school 👴")
    'slack'   = @("Slack… les fils de discussion n'ont jamais de fin 🧵")
    'spotify' = @("Mets-nous un bon son de concentration 🎧", "Lo-fi beats to focus to ? 🎶")
    'zoom'    = @("Caméra ON ? Vérifie ta coiffure 💇")
    'acrobat' = @("Un PDF de 200 pages ? Courage 📚")
    'acrord32'= @("Un PDF de 200 pages ? Courage 📚")
    'mstsc'   = @("Un bureau dans le bureau… inception 🌀")
    'calculatorapp' = @("2 + 2 = 4. Je vérifie pour toi 🧮")
    'saplogon'= @("SAP… bon courage, sincèrement 🫡")
}

# Mots-cles dans le titre de la fenetre (navigateurs surtout)
$TitleLines = @(
    @{ k = 'youtube';   d = $true;  l = @("YouTube pendant le focus ? Je n'ai rien vu… cette fois 👀", "Une petite vidéo et hop, 45 minutes envolées ⏳") }
    @{ k = 'netflix';   d = $true;  l = @("Netflix ?! Le focus pleure dans un coin 😢") }
    @{ k = 'twitch';    d = $true;  l = @("Twitch… le live peut attendre la pause 🎮") }
    @{ k = 'facebook';  d = $true;  l = @("Facebook… on dit qu'on y passe 'juste 2 minutes' 😏") }
    @{ k = 'instagram'; d = $true;  l = @("Insta peut attendre la pause 📸") }
    @{ k = 'tiktok';    d = $true;  l = @("TikTok ? Danger ! Zone de distraction maximale 🚨") }
    @{ k = 'reddit';    d = $true;  l = @("Reddit : le trou noir des pauses qui n'en sont pas 🕳️") }
    @{ k = 'amazon';    d = $true;  l = @("Ajouter au panier n'est pas un objectif de la journée 🛒") }
    @{ k = 'leboncoin'; d = $true;  l = @("Une bonne affaire sur Leboncoin ? Après le focus 😉") }
    @{ k = 'linkedin';  d = $false; l = @("LinkedIn… quelqu'un est 'ravi d'annoncer' quelque chose 🎉") }
    @{ k = 'gmail';     d = $false; l = @("Les mails, c'est mieux par paquets 📨") }
    @{ k = 'chatgpt';   d = $false; l = @("Tu parles à une autre IA ? Je suis un peu jaloux 🥺") }
    @{ k = 'claude';    d = $false; l = @("Ah, un cousin ! Passe-lui le bonjour 👋") }
    @{ k = 'wikipedia'; d = $false; l = @("Wikipédia : on commence par la photosynthèse, on finit sur les pharaons 🏺") }
    @{ k = 'stack overflow'; d = $false; l = @("Stack Overflow, le vrai collègue senior 🧑‍💻") }
    @{ k = 'github';    d = $false; l = @("Un petit commit ? 🐙") }
    @{ k = 'jira';      d = $false; l = @("Ticket en cours… ou ticket en souffrance ? 🎫") }
)

function Pick([object[]]$list) { $list[(Get-Random -Maximum $list.Count)] }

# ---------------------------------------------------------------------------
#  Interface (WPF)
# ---------------------------------------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Orbit" Width="320" Height="340"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize"
        UseLayoutRounding="True">
  <Grid x:Name="Root">
    <!-- bulle facon bande dessinee : contour epais + queue qui pointe vers Orbit -->
    <Grid x:Name="BubbleWrap" HorizontalAlignment="Right" VerticalAlignment="Bottom"
          Margin="0,0,10,126" MaxWidth="300" Visibility="Collapsed" RenderTransformOrigin="0.8,1">
      <Grid.RenderTransform>
        <ScaleTransform x:Name="BubblePop" ScaleX="1" ScaleY="1"/>
      </Grid.RenderTransform>
      <Grid.Effect>
        <DropShadowEffect BlurRadius="0" ShadowDepth="3" Direction="-45" Opacity="0.25"/>
      </Grid.Effect>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border x:Name="Bubble" Grid.Row="0" Padding="14,10,14,10" CornerRadius="20"
              Background="White" BorderBrush="#1E1B3A" BorderThickness="2.5">
        <StackPanel>
          <TextBlock x:Name="BubbleText" TextWrapping="Wrap" FontFamily="Segoe UI"
                     FontSize="13.5" Foreground="#1E1B3A" LineHeight="19"/>
          <WrapPanel x:Name="BubbleButtons" HorizontalAlignment="Right"/>
        </StackPanel>
      </Border>
      <!-- queue de bulle "parole" -->
      <Path x:Name="SpeechTail" Grid.Row="1" HorizontalAlignment="Right" Margin="0,-3.5,46,0"
            Fill="White" Stroke="#1E1B3A" StrokeThickness="2.5" StrokeLineJoin="Round"
            Data="M 0,0 Q 8,12 22,20 Q 14,9 16,0"/>
      <!-- queue de bulle "pensee" : petits ronds -->
      <Canvas x:Name="ThoughtTail" Grid.Row="1" HorizontalAlignment="Right" Width="26" Height="22"
              Margin="0,3,44,0" Visibility="Collapsed">
        <Ellipse Canvas.Left="0" Canvas.Top="0" Width="12" Height="10" Fill="White" Stroke="#1E1B3A" StrokeThickness="2.2"/>
        <Ellipse Canvas.Left="14" Canvas.Top="12" Width="7" Height="6" Fill="White" Stroke="#1E1B3A" StrokeThickness="2"/>
      </Canvas>
    </Grid>

    <Canvas x:Name="Bot" Width="120" Height="122" HorizontalAlignment="Right" VerticalAlignment="Bottom"
            Background="#01000000" Cursor="Hand" RenderTransformOrigin="1,1">
      <Canvas.RenderTransform>
        <ScaleTransform x:Name="BotScale" ScaleX="1" ScaleY="1"/>
      </Canvas.RenderTransform>

      <Canvas x:Name="Bobber" Width="120" Height="100" RenderTransformOrigin="0.5,0.5">
        <Canvas.RenderTransform>
          <TransformGroup>
            <RotateTransform x:Name="Tilt" Angle="0"/>
            <TranslateTransform x:Name="Bob" Y="0"/>
          </TransformGroup>
        </Canvas.RenderTransform>

        <!-- bras porteur des panneaux -->
        <Rectangle Canvas.Left="34" Canvas.Top="50" Width="52" Height="3" Fill="#6B7380"/>

        <!-- panneaux solaires -->
        <Border Canvas.Left="1" Canvas.Top="38" Width="35" Height="27" CornerRadius="1.5"
                BorderBrush="#9AA3B2" BorderThickness="1.2">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#34589E" Offset="0"/>
              <GradientStop Color="#14264F" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <Path Stroke="#667FA8E0" StrokeThickness="0.8"
                Data="M 8,0 V 25 M 16,0 V 25 M 24,0 V 25 M 0,8 H 33 M 0,16 H 33"/>
        </Border>
        <Border Canvas.Left="84" Canvas.Top="38" Width="35" Height="27" CornerRadius="1.5"
                BorderBrush="#9AA3B2" BorderThickness="1.2">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#34589E" Offset="0"/>
              <GradientStop Color="#14264F" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <Path Stroke="#667FA8E0" StrokeThickness="0.8"
                Data="M 8,0 V 25 M 16,0 V 25 M 24,0 V 25 M 0,8 H 33 M 0,16 H 33"/>
        </Border>

        <!-- antenne parabolique + balise -->
        <Line X1="60" Y1="31" X2="60" Y2="22" Stroke="#6B7380" StrokeThickness="2"/>
        <Path Stroke="#4A5260" StrokeThickness="1.2" Data="M 47,14 Q 60,30 73,14 Z">
          <Path.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#F4F6F9" Offset="0"/>
              <GradientStop Color="#A9B2BF" Offset="1"/>
            </LinearGradientBrush>
          </Path.Fill>
        </Path>
        <Line X1="60" Y1="20" X2="60" Y2="8" Stroke="#6B7380" StrokeThickness="1.2"/>
        <Ellipse x:Name="Beacon" Canvas.Left="57.5" Canvas.Top="3.5" Width="5" Height="5" Fill="#5FD3FF"/>

        <!-- module principal -->
        <Rectangle Canvas.Left="42" Canvas.Top="30" Width="36" Height="44" RadiusX="4" RadiusY="4"
                   Stroke="#4A5260" StrokeThickness="1.2">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
              <GradientStop Color="#F1F3F6" Offset="0"/>
              <GradientStop Color="#BAC2CD" Offset="0.55"/>
              <GradientStop Color="#8C95A4" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>
        <!-- isolation dorée -->
        <Rectangle Canvas.Left="42.6" Canvas.Top="60" Width="34.8" Height="10">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#EBCB6B" Offset="0"/>
              <GradientStop Color="#B48A1C" Offset="0.5"/>
              <GradientStop Color="#DDB84E" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>
        <!-- capteur optique : il suit la souris -->
        <Ellipse Canvas.Left="51" Canvas.Top="36" Width="18" Height="18" Fill="#1B2330"
                 Stroke="#4A5260" StrokeThickness="1.5"/>
        <Ellipse x:Name="Lens" Canvas.Left="56" Canvas.Top="41" Width="8" Height="8" Fill="#5FD3FF"/>
        <Ellipse x:Name="LensGlint" Canvas.Left="57" Canvas.Top="42" Width="2.6" Height="2.6" Fill="#D9FFFFFF"/>
        <!-- voyant d'etat -->
        <Ellipse x:Name="StatusLed" Canvas.Left="71.5" Canvas.Top="33" Width="4" Height="4" Fill="#5FD3FF"/>
        <!-- propulseur -->
        <Rectangle Canvas.Left="52" Canvas.Top="74" Width="16" Height="5" RadiusX="1" RadiusY="1" Fill="#5A6270"/>
      </Canvas>

      <!-- chrono -->
      <Border x:Name="Pill" Canvas.Left="23" Canvas.Top="94" Width="74" Height="22" CornerRadius="4"
              Background="#EE1B2330" BorderBrush="#5FD3FF" BorderThickness="1.2">
        <TextBlock x:Name="PillText" Text="▶" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI"
                   FontWeight="Bold" FontSize="12.5" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Canvas>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Root','BubbleWrap','BubblePop','SpeechTail','ThoughtTail','Bubble','BubbleText','BubbleButtons','Bot','BotScale','Bob','Tilt','Beacon','Lens','LensGlint','StatusLed','Pill','PillText') {
    $ui[$n] = $window.FindName($n)
}

# ---------------------------------------------------------------------------
#  Etat
# ---------------------------------------------------------------------------
$O = @{
    State        = 'Idle'      # Idle | Focus | AwaitBreak | Break | AwaitFocus
    EndsAt       = [datetime]::MinValue
    Paused       = $false
    Remaining    = [timespan]::Zero
    HalfSaid     = $false
    FiveSaid     = $false
    NextMotivation = [datetime]::MaxValue
    NextReminder = [datetime]::MaxValue
    BubbleUntil  = [datetime]::MinValue
    Quiet        = $false
    Mini         = $false
    Wander       = $true
    Pinned       = $false
    Dragging     = $false
    Walking      = $false
    WalkTarget   = $null
    WalkLingerUntil = [datetime]::MinValue
    NextWalk     = (Get-Date).AddMinutes((Get-Random -Minimum $Config.WanderMinMin -Maximum $Config.WanderMaxMin))
    Time         = 0.0
    LastFrame    = [datetime]::Now
    LastPid      = 0
    LastTitle    = ''
    AppSince     = [datetime]::Now
    AppCommented = $true
    NextAppComment = [datetime]::Now
    FromDevice   = $null
    Hwnd         = [IntPtr]::Zero
    Home         = $null
    MoodBrush    = $null
    Today        = (Get-Date).ToString('yyyy-MM-dd')
    FocusToday   = 0
    FocusMinToday = 0
    SessionMin   = 0
    Rhythm       = '50/10'
    TaskReminders = $true
    FocusTaskId  = ''
    NextJoke     = [datetime]::MaxValue
    JokeQueue    = New-Object System.Collections.ArrayList
    MyPid        = $PID
}

# Statistiques du jour
try {
    if (Test-Path $StatsFile) {
        $s = Get-Content $StatsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.date -eq $O.Today) {
            $O.FocusToday = [int]$s.focus
            $O.FocusMinToday = if ($null -ne $s.minutes) { [double]$s.minutes } else { $O.FocusToday * 50 }
        }
        if ($null -ne $s.quiet) { $O.Quiet = [bool]$s.quiet }
        if ($null -ne $s.wander) { $O.Wander = [bool]$s.wander }
        if ($s.rhythm -and $Rhythms.Contains([string]$s.rhythm)) { $O.Rhythm = [string]$s.rhythm }
        if ($null -ne $s.taskReminders) { $O.TaskReminders = [bool]$s.taskReminders }
    }
} catch { Write-Log "Lecture stats : $($_.Exception.Message)" }

function Save-Stats {
    try {
        $today = (Get-Date).ToString('yyyy-MM-dd')
        if ($today -ne $O.Today) { $O.Today = $today; $O.FocusToday = 0; $O.FocusMinToday = 0 }
        @{ date = $O.Today; focus = $O.FocusToday; minutes = $O.FocusMinToday; quiet = $O.Quiet; wander = $O.Wander
           rhythm = $O.Rhythm; taskReminders = $O.TaskReminders } |
            ConvertTo-Json | Set-Content -Path $StatsFile -Encoding UTF8
    } catch { Write-Log "Ecriture stats : $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
#  Apparence
# ---------------------------------------------------------------------------
function New-Color([string]$hex) { [Windows.Media.ColorConverter]::ConvertFromString($hex) }

# couleur du voyant / capteur, puis couleur des boutons
$Moods = @{
    Idle       = @('#5FD3FF', '#2B6CB0')
    Focus      = @('#4C8DFF', '#2747A8')
    Break      = @('#3DDC84', '#1E8E5A')
    Await      = @('#FF9F1C', '#D9480F')
}

function Set-Mood([string]$mood) {
    $c = $Moods[$mood]
    $accent = New-Object Windows.Media.SolidColorBrush((New-Color $c[0]))
    $ui.Lens.Fill = $accent
    $ui.Beacon.Fill = $accent
    $ui.StatusLed.Fill = $accent
    $ui.Pill.BorderBrush = $accent
    $O.MoodBrush = New-Object Windows.Media.SolidColorBrush((New-Color $c[1]))
}

# ---------------------------------------------------------------------------
#  Bulle de dialogue
# ---------------------------------------------------------------------------
function Show-Bubble {
    param([string]$Text, [object[]]$Buttons = @(), [double]$Seconds = $Config.BubbleSeconds,
          [switch]$Force, [switch]$Thought)

    if (-not $Force -and $Buttons.Count -eq 0 -and ($O.Quiet -or $O.Mini)) { return }
    if (-not $Force -and $Buttons.Count -eq 0 -and $ui.BubbleButtons.Children.Count -gt 0 -and
        $ui.BubbleWrap.Visibility -eq 'Visible') { return }   # ne pas ecraser une question en attente

    $wasVisible = $ui.BubbleWrap.Visibility -eq 'Visible'

    $ui.BubbleText.Text = $Text
    $ui.BubbleButtons.Children.Clear()
    $ui.BubbleButtons.Margin = if ($Buttons.Count) { '0,8,0,0' } else { '0' }
    foreach ($b in $Buttons) {
        $btn = New-Object Windows.Controls.Button
        $btn.Content = $b.Label
        $btn.Tag = $b.Action
        $btn.Margin = '4,2,0,2'
        $btn.Padding = '10,4,10,4'
        $btn.FontFamily = 'Segoe UI Semibold'
        $btn.FontSize = 12
        $btn.Cursor = 'Hand'
        $btn.BorderThickness = '1.5'
        $btn.BorderBrush = '#1E1B3A'
        if ($b.Primary) {
            $btn.Background = $O.MoodBrush
            $btn.Foreground = 'White'
        } else {
            $btn.Background = '#EEEEF5'
            $btn.Foreground = '#333344'
        }
        $btn.Add_Click({ param($s, $e) Hide-Bubble; Invoke-Safe $s.Tag })
        [void]$ui.BubbleButtons.Children.Add($btn)
    }
    # bulle de pensee (petits ronds) pour les blagues et reflexions, bulle de parole sinon
    $ui.SpeechTail.Visibility = if ($Thought) { 'Collapsed' } else { 'Visible' }
    $ui.ThoughtTail.Visibility = if ($Thought) { 'Visible' } else { 'Collapsed' }
    $ui.Bubble.CornerRadius = if ($Thought) { '26' } else { '20' }
    $ui.BubbleWrap.Visibility = 'Visible'
    if (-not $wasVisible) {
        # petit effet "pop" de dessin anime
        $anim = New-Object Windows.Media.Animation.DoubleAnimation(0.2, 1.0, [timespan]::FromMilliseconds(320))
        $ease = New-Object Windows.Media.Animation.BackEase
        $ease.EasingMode = 'EaseOut'
        $ease.Amplitude = 0.6
        $anim.EasingFunction = $ease
        $ui.BubblePop.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $anim)
        $ui.BubblePop.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $anim)
    }
    $O.BubbleUntil = if ($Buttons.Count) { [datetime]::MaxValue } else { (Get-Date).AddSeconds($Seconds) }
}

function Hide-Bubble {
    $ui.BubbleWrap.Visibility = 'Collapsed'
    $ui.BubbleButtons.Children.Clear()
    $O.BubbleUntil = [datetime]::MinValue
}

$script:lastErr = ''
$script:lastErrAt = [datetime]::MinValue
function Invoke-Safe([scriptblock]$sb) {
    try { & $sb } catch {
        $msg = "Erreur : $($_.Exception.Message) @ ligne $($_.InvocationInfo.ScriptLineNumber)"
        if ($msg -ne $script:lastErr -or ((Get-Date) - $script:lastErrAt).TotalSeconds -gt 60) {
            Write-Log $msg
            $script:lastErr = $msg
            $script:lastErrAt = Get-Date
        }
    }
}

# ---------------------------------------------------------------------------
#  Pomodoro
# ---------------------------------------------------------------------------
function Format-Min([double]$m) { if ($m -lt 1) { "{0} s" -f [int]($m * 60) } else { "{0}" -f [math]::Round($m, 1) } }

function Apply-Rhythm {
    if ($CustomDurations) { return }
    $Config.FocusMinutes = $Rhythms[$O.Rhythm].Focus
    $Config.BreakMinutes = $Rhythms[$O.Rhythm].Break
}

function Set-Rhythm([string]$name, [switch]$Quiet) {
    if (-not $Rhythms.Contains($name)) { return }
    $O.Rhythm = $name
    Apply-Rhythm
    Save-Stats
    if ($Quiet) { return }
    $r = $Rhythms[$name]
    $msg = "Rythme $name : $($r.Focus) min de focus, $($r.Break) min de pause $($r.Icon)"
    if ($CustomDurations) { $msg = "Durées imposées au lancement ($(Format-Min $Config.FocusMinutes)/$(Format-Min $Config.BreakMinutes)) : le rythme $name s'appliquera au prochain démarrage normal." }
    elseif ($O.State -in 'Focus', 'Break') { $msg += "`nÇa s'appliquera à la prochaine session." }
    Show-Bubble $msg -Force -Seconds 5
}
Apply-Rhythm

# un bouton par rythme dans la bulle d'accueil ; celui choisi en dernier est mis en avant
function Get-StartButtons {
    $list = @()
    foreach ($name in $Rhythms.Keys) {
        $r = $Rhythms[$name]
        $list += @{ Label = "$($r.Icon) Focus $name"; Action = [scriptblock]::Create("Set-Rhythm '$name' -Quiet; Start-Focus"); Primary = ($name -eq $O.Rhythm) }
    }
    return $list
}
$BtnAgain      = @{ Label = "🚀 On repart !"; Action = { Start-Focus }; Primary = $true }
$BtnBreak      = @{ Label = "☕ Je prends ma pause"; Action = { Start-Break }; Primary = $true }
$BtnStop       = @{ Label = "⏹ On arrête là"; Action = { Stop-Cycle } }
$BtnTodo       = @{ Label = "📝 Ma to-do"; Action = { Open-Notebook 'Todo' } }
$BtnLater      = @{ Label = "Plus tard"; Action = { Show-Bubble "Ok ! Clique sur moi quand tu veux te lancer 😉" -Force } }

function Start-Focus {
    $O.State = 'Focus'
    $O.Paused = $false
    $O.EndsAt = (Get-Date).AddMinutes($Config.FocusMinutes)
    $O.SessionMin = $Config.FocusMinutes
    $O.HalfSaid = $false
    $O.FiveSaid = $false
    $O.NextMotivation = (Get-Date).AddMinutes($Config.MotivationEveryMin)
    $O.NextReminder = [datetime]::MaxValue
    Set-Mood 'Focus'
    $msg = (Pick $Lines.FocusStart) -f (Format-Min $Config.FocusMinutes)
    $O.FocusTaskId = ''
    $secs = 6
    if ($O.TaskReminders) {
        # rappel des taches au debut du focus
        $open = Get-OpenTodos
        if ($open.Count) {
            $O.FocusTaskId = $open[0].id
            $msg += "`n`n🎯 Objectif : « $(Short-Text $open[0].text) »"
            if ($open.Count -gt 1) {
                $msg += "`n📝 Ensuite :"
                foreach ($t in ($open | Select-Object -Skip 1 -First 2)) { $msg += "`n   • $(Short-Text $t.text 45)" }
                if ($open.Count -gt 3) { $msg += "`n   … et $($open.Count - 3) autre(s)" }
            }
            $secs = 12
        } else {
            $msg += "`n`nTa to-do est vide : clic droit > 📝 Ma to-do pour noter tes tâches."
            $secs = 8
        }
    }
    Show-Bubble $msg -Force -Seconds $secs
    Update-Pill
}

function Start-Break {
    $O.State = 'Break'
    $O.Paused = $false
    $O.EndsAt = (Get-Date).AddMinutes($Config.BreakMinutes)
    $O.NextJoke = (Get-Date).AddSeconds(40)
    $O.NextMotivation = [datetime]::MaxValue
    $O.NextReminder = [datetime]::MaxValue
    Set-Mood 'Break'
    Show-Bubble (Pick $Lines.BreakStart) -Force -Seconds 8
    Update-Pill
}

# Blagues pendant la pause, sans repetition tant que toute la liste n'est pas passee
function Get-NextJoke {
    if ($O.JokeQueue.Count -eq 0) {
        $O.JokeQueue.AddRange(@($Lines.BreakJokes | Get-Random -Count $Lines.BreakJokes.Count))
    }
    $j = $O.JokeQueue[0]
    $O.JokeQueue.RemoveAt(0)
    return $j
}

function Stop-Cycle {
    $O.State = 'Idle'
    $O.Paused = $false
    $O.NextMotivation = [datetime]::MaxValue
    $O.NextReminder = [datetime]::MaxValue
    Set-Mood 'Idle'
    Show-Bubble ((Pick $Lines.Stop) -f $O.FocusToday) -Force -Seconds 8
    Update-Pill
}

function Toggle-Pause {
    if ($O.State -notin 'Focus', 'Break') { return }
    if ($O.Paused) {
        $O.EndsAt = (Get-Date) + $O.Remaining
        $O.Paused = $false
        Show-Bubble "Et c'est reparti ▶" -Force -Seconds 3
    } else {
        $O.Remaining = $O.EndsAt - (Get-Date)
        $O.Paused = $true
        Show-Bubble "Chrono en pause ⏸ Clic droit > Reprendre quand tu veux." -Force -Seconds 5
    }
    Update-Pill
}

# La tache "objectif" de la session, si elle est toujours a faire
function Get-FocusTask {
    if (-not $O.TaskReminders -or -not $O.FocusTaskId) { return $null }
    $t = Find-Todo $O.FocusTaskId
    if ($t -and -not $t.done) { return $t }
    return $null
}

$BtnTaskDone = @{ Label = "✅ C'est fait !"; Action = { Complete-FocusTask } }

function Get-AwaitBreakButtons {
    if (Get-FocusTask) { return @($BtnBreak, $BtnTaskDone, $BtnStop) }
    return @($BtnBreak, $BtnStop)
}

function Ask-Break([string]$Text, [switch]$NoTaskInfo) {
    if (-not $Text) { $Text = (Pick $Lines.FocusEnd) -f (Format-Min $O.SessionMin) }
    # rappel des taches a la fin du focus
    $task = Get-FocusTask
    if ($task) { $Text += "`n`n🎯 Et « $(Short-Text $task.text) », c'est bouclé ?" }
    elseif ($O.TaskReminders -and -not $NoTaskInfo) {
        $open = Get-OpenTodos
        if ($open.Count) { $Text += "`n`n📝 Il te reste $($open.Count) tâche(s), dont « $(Short-Text $open[0].text 45) »." }
    }
    Show-Bubble $Text -Buttons (Get-AwaitBreakButtons) -Force
}

function Complete-FocusTask {
    $task = Get-FocusTask
    if ($task) { Set-TodoDone $task.id $true -Quiet }
    $O.FocusTaskId = ''
    $left = (Get-OpenTodos).Count
    $msg = "Bravo, c'est coché ✅"
    if ($left -eq 0) { $msg += " Et ta to-do est vide, quelle journée ! 🎉" } else { $msg += " Plus que $left tâche(s)." }
    Ask-Break ($msg + "`nOn fait la pause ?") -NoTaskInfo
}

function Ask-Focus {
    $Text = (Pick $Lines.BreakEnd) -f (Format-Min $Config.FocusMinutes)
    if ($O.TaskReminders) {
        $next = Get-NextTodo
        if ($next) { $Text += "`n`n🎯 Au programme : « $(Short-Text $next.text) »" }
    }
    Show-Bubble $Text -Buttons @($BtnAgain, $BtnStop) -Force
}

function On-TimerEnded {
    Ensure-Visible
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    $O.NextReminder = (Get-Date).AddMinutes($Config.ReminderEveryMin)
    Set-Mood 'Await'
    if ($O.State -eq 'Focus') {
        $O.FocusToday++
        $O.FocusMinToday += $O.SessionMin
        Save-Stats
        $O.State = 'AwaitBreak'
        Ask-Break
        Show-Tray "Session de focus terminée 🎉" "Clique sur Orbit pour lancer ta pause."
    } else {
        $O.State = 'AwaitFocus'
        Ask-Focus
        Show-Tray "La pause est finie" "Orbit t'attend pour la prochaine session."
    }
    Update-Pill
}

function Update-Pill {
    $txt = switch ($O.State) {
        'Idle'       { '▶ Orbit' }
        'AwaitBreak' { '☕ ?' }
        'AwaitFocus' { '🚀 ?' }
        default {
            $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
            if ($left -lt [timespan]::Zero) { $left = [timespan]::Zero }
            $t = '{0:00}:{1:00}' -f [math]::Floor($left.TotalMinutes), $left.Seconds
            $prefix = if ($O.Paused) { '⏸ ' } elseif ($O.State -eq 'Break') { '☕ ' } else { '' }
            $prefix + $t
        }
    }
    $ui.PillText.Text = $txt
    if ($script:tray) {
        $tip = "Orbit - $txt - $($O.FocusToday) focus aujourd'hui"
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $script:tray.Text = $tip
    }
}

function Show-Status {
    switch ($O.State) {
        'Idle'       { Show-Bubble (Pick $Lines.Hello) -Buttons (@(Get-StartButtons) + @($BtnTodo, $BtnLater)) -Force }
        'AwaitBreak' { Ask-Break }
        'AwaitFocus' { Ask-Focus }
        'Focus' {
            $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
            $m = [math]::Ceiling($left.TotalMinutes)
            Show-Bubble ("Encore $m min de focus. " + (Pick $Lines.Motivation)) -Force
        }
        'Break' {
            $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
            $m = [math]::Ceiling($left.TotalMinutes)
            Show-Bubble "Encore $m min de pause, profite 😌" -Force
        }
    }
}

# ---------------------------------------------------------------------------
#  Commentaires sur l'appli survolee
# ---------------------------------------------------------------------------
function Check-App {
    if (-not $Native) { return }
    $title = ''
    $procId = [OrbitNative]::UnderCursor([ref]$title)
    if ($procId -eq 0 -or $procId -eq $O.MyPid) { return }

    if ($procId -ne $O.LastPid -or $title -ne $O.LastTitle) {
        $O.LastPid = $procId
        $O.LastTitle = $title
        $O.AppSince = Get-Date
        $O.AppCommented = $false
        return
    }
    if ($O.AppCommented) { return }
    if (((Get-Date) - $O.AppSince).TotalSeconds -lt $Config.AppDwellS) { return }
    $O.AppCommented = $true
    if ((Get-Date) -lt $O.NextAppComment) { return }

    $line = $null
    $lowTitle = $title.ToLowerInvariant()
    foreach ($t in $TitleLines) {
        if ($lowTitle.Contains($t.k)) {
            if ($t.d -and $O.State -eq 'Focus') { $line = Pick $t.l }
            elseif ($t.d -and $O.State -eq 'Break') { $line = "C'est la pause, profite 😌" }
            elseif (-not $t.d) { $line = Pick $t.l }
            break
        }
    }
    if (-not $line) {
        $name = ''
        try { $name = (Get-Process -Id $procId -ErrorAction Stop).ProcessName.ToLowerInvariant() } catch { return }
        if ($AppLines.ContainsKey($name) -and (Get-Random -Maximum 100) -lt 60) { $line = Pick $AppLines[$name] }
    }
    if ($line) {
        Show-Bubble $line -Thought
        $O.NextAppComment = (Get-Date).AddSeconds($Config.AppCommentCooldownS)
    }
}

function Get-TimeOfDayLine {
    $h = (Get-Date).Hour
    if ($h -lt 9)  { return "Tôt le matin et déjà au taquet ? Respect ☕" }
    if ($h -ge 12 -and $h -lt 14) { return "N'oublie pas de manger, hein 🥪" }
    if ($h -ge 18) { return "Il se fait tard… on termine proprement et on rentre ? 🌙" }
    return $null
}

# ---------------------------------------------------------------------------
#  Ecrans et deplacements (coordonnees WPF = pixels independants du DPI)
# ---------------------------------------------------------------------------
function To-Dip([double]$x, [double]$y) {
    if ($O.FromDevice) { return $O.FromDevice.Transform(([Windows.Point]::new($x, $y))) }
    return [Windows.Point]::new($x, $y)
}

function Get-WorkArea($screen) {
    $wa = $screen.WorkingArea
    $tl = To-Dip $wa.Left $wa.Top
    $br = To-Dip $wa.Right $wa.Bottom
    return @{ L = $tl.X; T = $tl.Y; R = $br.X; B = $br.Y }
}

function Get-CursorDip {
    $p = [System.Windows.Forms.Cursor]::Position
    return To-Dip $p.X $p.Y
}

function Get-HomePos {
    $p = [System.Windows.Forms.Cursor]::Position
    $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint($p))
    return [Windows.Point]::new(($wa.R - $window.Width - $Config.CornerMargin), ($wa.B - $window.Height - 2))
}

function Get-RandomSpot {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $p = [System.Windows.Forms.Cursor]::Position
    $scr = if ($screens.Count -gt 1 -and (Get-Random -Maximum 100) -lt 30) { Pick $screens } else { [System.Windows.Forms.Screen]::FromPoint($p) }
    $wa = Get-WorkArea $scr
    $maxX = [math]::Max($wa.L, $wa.R - $window.Width)
    $maxY = [math]::Max($wa.T, $wa.B - $window.Height)
    # le plus souvent le long du bas de l'ecran, parfois n'importe ou
    $y = if ((Get-Random -Maximum 100) -lt 70) { $maxY } else { $wa.T + (Get-Random -Maximum ([int][math]::Max(1, $maxY - $wa.T))) }
    $x = $wa.L + (Get-Random -Maximum ([int][math]::Max(1, $maxX - $wa.L)))
    return [Windows.Point]::new($x, $y)
}

function Start-Walk {
    $O.Walking = $true
    $O.WalkTarget = Get-RandomSpot
    $O.WalkLingerUntil = [datetime]::MinValue
    if ((Get-Random -Maximum 100) -lt 50) { Show-Bubble (Pick $Lines.Wander) -Seconds 4 -Thought }
}

function Ensure-Visible {
    if ($window.Visibility -ne 'Visible') {
        $window.Show()
        if ($Native -and $O.Hwnd -ne [IntPtr]::Zero) { [OrbitNative]::KeepOnTop($O.Hwnd) }
    }
}

# ---------------------------------------------------------------------------
#  Boucle d'animation (~25 images/s)
# ---------------------------------------------------------------------------
function On-Frame {
    $now = [datetime]::Now
    $dt = ($now - $O.LastFrame).TotalSeconds
    if ($dt -gt 0.2) { $dt = 0.2 }
    $O.LastFrame = $now
    $O.Time += $dt
    $t = $O.Time

    # derive lente dans l'espace
    $ui.Bob.Y = 2.5 * [math]::Sin($t * 1.6)
    $ui.Tilt.Angle = 3 * [math]::Sin($t * 0.7)

    # balise : un flash regulier, clignotement rapide quand Orbit attend une reponse
    if ($O.State -like 'Await*') {
        $ui.Beacon.Opacity = 0.3 + 0.7 * [math]::Abs([math]::Sin($t * 4))
        $ui.StatusLed.Opacity = $ui.Beacon.Opacity
    } else {
        $ui.Beacon.Opacity = if (($t % 2.0) -lt 0.18) { 1 } else { 0.35 }
        $ui.StatusLed.Opacity = 1
    }

    # le capteur optique suit la souris
    $c = Get-CursorDip
    $scale = $ui.BotScale.ScaleX
    $cx = $window.Left + $window.Width - 60 * $scale
    $cy = $window.Top + $window.Height - 77 * $scale
    $vx = $c.X - $cx; $vy = $c.Y - $cy
    $len = [math]::Sqrt($vx * $vx + $vy * $vy)
    if ($len -gt 1) { $vx = $vx / $len * 3.5; $vy = $vy / $len * 3.5 }
    [Windows.Controls.Canvas]::SetLeft($ui.Lens, 56 + $vx)
    [Windows.Controls.Canvas]::SetTop($ui.Lens, 41 + $vy)
    [Windows.Controls.Canvas]::SetLeft($ui.LensGlint, 57 + $vx)
    [Windows.Controls.Canvas]::SetTop($ui.LensGlint, 42 + $vy)

    # bulle temporaire
    if ($ui.BubbleWrap.Visibility -eq 'Visible' -and $now -ge $O.BubbleUntil) { Hide-Bubble }

    # deplacements
    if ($O.Dragging -or $window.Visibility -ne 'Visible') { return }
    if ($O.Pinned) { return }

    if (-not $O.Walking -and $O.Wander -and -not $O.Mini -and $now -ge $O.NextWalk -and
        $ui.BubbleButtons.Children.Count -eq 0) {
        Start-Walk
    }

    if ($O.Walking) {
        $target = $O.WalkTarget
        $wx = $target.X - $window.Left; $wy = $target.Y - $window.Top
        $d = [math]::Sqrt($wx * $wx + $wy * $wy)
        if ($d -lt 2) {
            if ($O.WalkLingerUntil -eq [datetime]::MinValue) {
                $O.WalkLingerUntil = $now.AddSeconds(6 + (Get-Random -Maximum 10))
            } elseif ($now -ge $O.WalkLingerUntil) {
                $O.Walking = $false
                $O.NextWalk = $now.AddMinutes((Get-Random -Minimum $Config.WanderMinMin -Maximum $Config.WanderMaxMin))
            }
            return
        }
        $step = [math]::Min($d, 140 * $dt)      # balade tranquille
        $window.Left += $wx / $d * $step
        $window.Top += $wy / $d * $step
        $ui.Tilt.Angle += 6 * $wx / $d   # s'incline dans le sens du deplacement
        return
    }

    $h = $O.Home
    if (-not $h) { return }
    $hx = $h.X - $window.Left; $hy = $h.Y - $window.Top
    $hd = [math]::Sqrt($hx * $hx + $hy * $hy)
    if ($hd -gt 0.5) {
        $k = [math]::Min(1, $dt * 4)
        $mv = [math]::Max($hd * $k, [math]::Min($hd, 300 * $dt))
        $window.Left += $hx / $hd * $mv
        $window.Top += $hy / $hd * $mv
    }
}

# ---------------------------------------------------------------------------
#  Boucle lente (1 fois / seconde) : chrono, commentaires, premier plan
# ---------------------------------------------------------------------------
$script:slowCount = 0
function On-Second {
    $now = Get-Date
    $script:slowCount++
    $O.Home = Get-HomePos

    if (($O.State -in 'Focus', 'Break') -and -not $O.Paused) {
        $left = $O.EndsAt - $now
        if ($left.TotalSeconds -le 0) { On-TimerEnded; return }
        if ($O.State -eq 'Break' -and $now -ge $O.NextJoke) {
            # une blague toutes les ~2 minutes pendant la pause (sauf dans les 15 dernieres secondes)
            $O.NextJoke = $now.AddSeconds((Get-Random -Minimum 80 -Maximum 131))
            if ($left.TotalSeconds -gt 15) { Show-Bubble (Get-NextJoke) -Seconds 10 }
        }
        if ($O.State -eq 'Focus') {
            $total = $Config.FocusMinutes
            if (-not $O.HalfSaid -and $total -ge 20 -and $left.TotalMinutes -le $total / 2) {
                $O.HalfSaid = $true
                Show-Bubble ((Pick $Lines.HalfWay) -f [math]::Ceiling($left.TotalMinutes))
            } elseif (-not $O.FiveSaid -and $total -ge 15 -and $left.TotalMinutes -le 5) {
                $O.FiveSaid = $true
                Show-Bubble (Pick $Lines.LastMinutes)
            } elseif ($now -ge $O.NextMotivation) {
                $O.NextMotivation = $now.AddMinutes($Config.MotivationEveryMin + (Get-Random -Minimum -2 -Maximum 3))
                $line = $null
                if ((Get-Random -Maximum 100) -lt 20) { $line = Get-TimeOfDayLine }
                if (-not $line) { $line = Pick $Lines.Motivation }
                Show-Bubble $line -Thought
            }
        }
    }

    if ($O.State -like 'Await*' -and $now -ge $O.NextReminder) {
        $O.NextReminder = $now.AddMinutes($Config.ReminderEveryMin)
        Ensure-Visible
        $pool = if ($O.State -eq 'AwaitBreak') { $Lines.AwaitBreak } else { $Lines.AwaitFocus }
        if ($O.State -eq 'AwaitBreak') { Ask-Break (Pick $pool) }
        else { Show-Bubble (Pick $pool) -Buttons @($BtnAgain, $BtnStop) -Force }
    }

    if ($Native -or $script:slowCount % 2 -eq 0) { Check-Clipboard }
    if ($script:slowCount % 2 -eq 0 -and $window.Visibility -eq 'Visible') { Check-App }
    if ($script:slowCount % 5 -eq 0 -and $Native -and $O.Hwnd -ne [IntPtr]::Zero -and $window.Visibility -eq 'Visible') {
        [OrbitNative]::KeepOnTop($O.Hwnd)
    }
    Update-Pill
}

# ---------------------------------------------------------------------------
#  Menu clic droit
# ---------------------------------------------------------------------------
function New-MenuItem([string]$header, [scriptblock]$action, [switch]$Checkable) {
    $mi = New-Object Windows.Controls.MenuItem
    $mi.Header = $header
    $mi.Tag = $action
    $mi.IsCheckable = [bool]$Checkable
    $mi.Add_Click({ param($s, $e) Invoke-Safe $s.Tag })
    return $mi
}

$StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Orbit.lnk'

function Toggle-Autostart {
    if (Test-Path $StartupLink) {
        Remove-Item $StartupLink -Force
        Show-Bubble "Ok, je ne me lancerai plus au démarrage." -Force
    } else {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($StartupLink)
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.WindowStyle = 7
        $lnk.Description = 'Orbit - compagnon de focus'
        $lnk.Save()
        Show-Bubble "C'est noté, je serai là à chaque démarrage de Windows 🚀 (sans droits admin)" -Force
    }
}

function Set-Mini([bool]$on) {
    $O.Mini = $on
    $s = if ($on) { 0.55 } else { 1 }
    $ui.BotScale.ScaleX = $s
    $ui.BotScale.ScaleY = $s
    $ui.BubbleWrap.Margin = if ($on) { '0,0,10,70' } else { '0,0,10,126' }
    $ui.SpeechTail.Margin = if ($on) { '0,-3.5,20,0' } else { '0,-3.5,46,0' }
    $ui.ThoughtTail.Margin = if ($on) { '0,3,18,0' } else { '0,3,44,0' }
    if ($on) { $O.Walking = $false }
}

function Hide-Orbit {
    $window.Hide()
    Show-Tray "Orbit est caché" "Je continue de chronométrer. Double-clic sur l'icône pour me faire revenir."
}

function Quit-Orbit {
    Save-Stats
    Save-Todos
    $NB.Quitting = $true
    $script:frameTimer.Stop()
    $script:secondTimer.Stop()
    $app.Shutdown()
}

# ---------------------------------------------------------------------------
#  Carnet : to-do + historique des copier-coller (voir notebook.ps1)
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'notebook.ps1')

$menu = New-Object Windows.Controls.ContextMenu
$miTodo   = New-MenuItem "📝  Ma to-do" { Open-Notebook 'Todo' }
$miClip   = New-MenuItem "📋  Mes copier-coller du jour" { Open-Notebook 'Clip' }
$miFocus  = New-MenuItem "🚀  Lancer un focus" { Start-Focus }
$miBreak  = New-MenuItem "☕  Prendre ma pause" { Start-Break }
$miPause  = New-MenuItem "⏸  Mettre le chrono en pause" { Toggle-Pause }
$miStop   = New-MenuItem "⏹  Couper le chrono" { Stop-Cycle }
$miQuiet  = New-MenuItem "🤫  Mode silencieux (pas de blagues)" { $O.Quiet = -not $O.Quiet; Save-Stats; if ($O.Quiet) { Hide-Bubble } } -Checkable
$miWander = New-MenuItem "🚶  Balades sur les écrans" { $O.Wander = -not $O.Wander; $O.Walking = $false; Save-Stats } -Checkable
$miHome   = New-MenuItem "🏠  Revenir en bas à droite" { $O.Pinned = $false; $O.Walking = $false }
$miMini   = New-MenuItem "🔽  Réduire" { Set-Mini (-not $O.Mini) } -Checkable
$miHide   = New-MenuItem "🙈  Masquer (icône près de l'horloge)" { Hide-Orbit }
$miAuto   = New-MenuItem "⚡  Lancer au démarrage de Windows" { Toggle-Autostart } -Checkable
$miStats  = New-MenuItem "🏆  Mes stats du jour" { Show-Bubble ("Aujourd'hui : {0} session(s) de focus, soit {1} min. 🔥" -f $O.FocusToday, [math]::Round($O.FocusMinToday)) -Force }
$miRhythm = New-Object Windows.Controls.MenuItem
$miRhythm.Header = "⏱  Rythme"
$rhythmItems = @{}
foreach ($name in $Rhythms.Keys) {
    $r = $Rhythms[$name]
    $it = New-MenuItem "$($r.Icon)  $name  ($($r.Focus) min focus / $($r.Break) min pause)" ([scriptblock]::Create("Set-Rhythm '$name'")) -Checkable
    $rhythmItems[$name] = $it
    [void]$miRhythm.Items.Add($it)
}
$miTasks  = New-MenuItem "🔔  Rappels de tâches (début / fin de focus)" {
    $O.TaskReminders = -not $O.TaskReminders; Save-Stats
    Show-Bubble $(if ($O.TaskReminders) { "Je te rappellerai tes tâches au début et à la fin de chaque focus 🔔" } else { "Ok, plus de rappels de tâches 🔕" }) -Force -Seconds 4
} -Checkable
$miQuit   = New-MenuItem "❌  Quitter Orbit" { Quit-Orbit }

foreach ($i in @($miTodo, $miClip, (New-Object Windows.Controls.Separator),
                 $miFocus, $miBreak, $miPause, $miStop, $miRhythm, $miTasks, (New-Object Windows.Controls.Separator),
                 $miQuiet, $miWander, $miMini, $miHome, $miHide, $miAuto, (New-Object Windows.Controls.Separator),
                 $miStats, $miQuit)) { [void]$menu.Items.Add($i) }

$menu.Add_Opened({
    $miPause.Header = if ($O.Paused) { "▶  Reprendre le chrono" } else { "⏸  Mettre le chrono en pause" }
    $miPause.IsEnabled = ($O.State -in 'Focus', 'Break')
    $miStop.IsEnabled = $O.State -ne 'Idle'
    $miQuiet.IsChecked = $O.Quiet
    $miWander.IsChecked = $O.Wander
    $miMini.IsChecked = $O.Mini
    $miHome.IsEnabled = $O.Pinned -or $O.Walking
    $miAuto.IsChecked = Test-Path $StartupLink
    $miTasks.IsChecked = $O.TaskReminders
    foreach ($name in $rhythmItems.Keys) { $rhythmItems[$name].IsChecked = ($name -eq $O.Rhythm) }
    $miFocus.Header = "🚀  Lancer un focus ($(Format-Min $Config.FocusMinutes) min)"
    $miBreak.Header = "☕  Prendre ma pause ($(Format-Min $Config.BreakMinutes) min)"
})
$ui.Bot.ContextMenu = $menu

# Clic gauche = statut / glisser = deplacer
$ui.Bot.Add_MouseLeftButtonDown({
    param($s, $e)
    Invoke-Safe {
        $x0 = $window.Left; $y0 = $window.Top
        $O.Dragging = $true
        try { $window.DragMove() } catch {}
        $O.Dragging = $false
        if ([math]::Abs($window.Left - $x0) + [math]::Abs($window.Top - $y0) -gt 6) {
            $O.Pinned = $true
            $O.Walking = $false
            Show-Bubble "Ok, je reste ici. Clic droit > « Revenir en bas à droite » pour me libérer." -Seconds 5
        } else {
            if ($ui.BubbleWrap.Visibility -eq 'Visible' -and $ui.BubbleButtons.Children.Count -eq 0 -and (Get-Random -Maximum 100) -lt 25) {
                Show-Bubble (Pick $Lines.Poke) -Force -Seconds 3
            } else { Show-Status }
        }
    }
})

# ---------------------------------------------------------------------------
#  Icone dans la zone de notification
# ---------------------------------------------------------------------------
function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(108, 92, 231))), 5, 5, 22, 22)
    $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200, 190, 255)), 2), 1, 12, 30, 9)
    $g.FillEllipse([System.Drawing.Brushes]::White, 10, 11, 5, 6)
    $g.FillEllipse([System.Drawing.Brushes]::White, 17, 11, 5, 6)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Show-Tray([string]$title, [string]$text) {
    if (-not $script:tray) { return }
    try { $script:tray.ShowBalloonTip(4000, $title, $text, 'Info') } catch {}
}

$script:tray = $null
try {
    $script:tray = New-Object System.Windows.Forms.NotifyIcon
    $script:tray.Icon = New-TrayIcon
    $script:tray.Text = 'Orbit'
    $cms = New-Object System.Windows.Forms.ContextMenuStrip
    [void]$cms.Items.Add('Afficher / masquer Orbit', $null, { Invoke-Safe { if ($window.Visibility -eq 'Visible') { $window.Hide() } else { Ensure-Visible } } })
    [void]$cms.Items.Add('Lancer un focus 50/10', $null, { Invoke-Safe { Ensure-Visible; Set-Rhythm '50/10' -Quiet; Start-Focus } })
    [void]$cms.Items.Add('Lancer un focus 25/5', $null, { Invoke-Safe { Ensure-Visible; Set-Rhythm '25/5' -Quiet; Start-Focus } })
    [void]$cms.Items.Add('Prendre ma pause', $null, { Invoke-Safe { Ensure-Visible; Start-Break } })
    [void]$cms.Items.Add('Couper le chrono', $null, { Invoke-Safe { Stop-Cycle } })
    [void]$cms.Items.Add('-')
    [void]$cms.Items.Add('Ma to-do', $null, { Invoke-Safe { Open-Notebook 'Todo' } })
    [void]$cms.Items.Add('Mes copier-coller du jour', $null, { Invoke-Safe { Open-Notebook 'Clip' } })
    [void]$cms.Items.Add('-')
    [void]$cms.Items.Add('Quitter Orbit', $null, { Invoke-Safe { Quit-Orbit } })
    $script:tray.ContextMenuStrip = $cms
    $script:tray.Add_DoubleClick({ Invoke-Safe { Ensure-Visible; Show-Status } })
    $script:tray.Visible = $true
} catch { Write-Log "Icone de notification : $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
#  Demarrage
# ---------------------------------------------------------------------------
$window.Add_SourceInitialized({
    Invoke-Safe {
        $src = [Windows.PresentationSource]::FromVisual($window)
        if ($src) { $O.FromDevice = $src.CompositionTarget.TransformFromDevice }
        $O.Hwnd = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
        if ($Native) { [OrbitNative]::MakeToolWindow($O.Hwnd) }
        $h = Get-HomePos
        $O.Home = $h
        $window.Left = $h.X
        $window.Top = $h.Y
    }
})

$window.Add_Loaded({
    Invoke-Safe {
        Set-Mood 'Idle'
        Update-Pill
        Show-Status
    }
})

$script:frameTimer = New-Object Windows.Threading.DispatcherTimer
$script:frameTimer.Interval = [timespan]::FromMilliseconds(40)
$script:frameTimer.Add_Tick({ Invoke-Safe { On-Frame } })

$script:secondTimer = New-Object Windows.Threading.DispatcherTimer
$script:secondTimer.Interval = [timespan]::FromSeconds(1)
$script:secondTimer.Add_Tick({ Invoke-Safe { On-Second } })

# placement initial hors ecran le temps de calculer la bonne position
$window.Left = -10000
$window.Top = -10000
Set-Mood 'Idle'

$app = New-Object Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$script:frameTimer.Start()
$script:secondTimer.Start()
Write-Log "Orbit demarre (focus $($Config.FocusMinutes) min, pause $($Config.BreakMinutes) min, natif=$Native)"
try {
    [void]$app.Run($window)
} catch {
    Write-Log "Arret inattendu : $($_.Exception.Message)"
} finally {
    if ($script:tray) { $script:tray.Visible = $false; $script:tray.Dispose() }
    $mutex.ReleaseMutex()
}
