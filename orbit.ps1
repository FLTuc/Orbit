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
$OrbitScript = $PSCommandPath

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
    Jokes               = $true  # blagues pendant la pause
    JokeEveryMin        = 2      # une blague toutes les ~2 minutes de pause
    AppComments         = $true  # commentaires selon l'appli sous la souris
    Sounds              = $true
    DroidSounds         = $true  # petits bips de droide a chaque bulle
    DroidVolume         = 40     # volume des bips, de 0 a 100
    IdlePause           = $true  # met le focus en pause si tu t'absentes
    IdleMinutes         = 5
}
# (tous ces reglages se modifient aussi depuis clic droit > Reglages)

# Rythmes Pomodoro disponibles : focus / pause, en minutes
$Rhythms = [ordered]@{
    '50/10' = @{ Focus = 50; Break = 10; Icon = '🚀' }
    '25/5'  = @{ Focus = 25; Break = 5;  Icon = '⚡' }
    'Perso' = @{ Focus = 40; Break = 8;  Icon = '🎛️' }   # modifiable dans les reglages
}

$DataDir = Join-Path $env:APPDATA 'Orbit'
$StatsFile = Join-Path $DataDir 'stats.json'
$SettingsFile = Join-Path $DataDir 'settings.json'
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

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

    // Temps ecoule depuis la derniere action clavier / souris, en millisecondes
    public static uint IdleMs() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.dwTime);
    }

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

    // Petits bips doux synthetises a la volee (fichier WAV en memoire) :
    // sons purs, notes medium-graves qui glissent doucement, attaque et fin progressives, leger echo.
    // question = true : la derniere note monte un peu, comme une question.
    public static byte[] DroidChirp(int seed, double volume, bool question) {
        Random rnd = new Random(seed);
        const int rate = 22050;
        System.Collections.Generic.List<double> buf = new System.Collections.Generic.List<double>();
        int notes = rnd.Next(2, 5);
        double phase = 0;
        // une petite gamme agreable (pentatonique) pour que les notes s'accordent entre elles
        double[] scale = { 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66 };
        for (int n = 0; n < notes; n++) {
            bool last = n == notes - 1;
            int len = rate * rnd.Next(70, 140) / 1000;
            double f0 = scale[rnd.Next(scale.Length)];
            double f1 = f0 * (0.9 + rnd.NextDouble() * 0.25);
            if (last && question) { f0 = scale[rnd.Next(2, 5)]; f1 = f0 * 1.33; len = rate * 170 / 1000; }
            bool vibrato = rnd.NextDouble() < 0.25;
            double vibHz = 7 + rnd.NextDouble() * 5;
            int attack = (int)(rate * 0.012), release = (int)(rate * 0.045);
            for (int i = 0; i < len; i++) {
                double p = (double)i / len;
                double t = (double)i / rate;
                double f = f0 * Math.Pow(f1 / f0, p * p * (3 - 2 * p));   // glissando adouci
                if (vibrato) f *= 1 + 0.035 * Math.Sin(2 * Math.PI * vibHz * t);
                phase += 2 * Math.PI * f / rate;
                double v = Math.Sin(phase) * 0.88 + Math.Sin(2 * phase) * 0.12;
                double env = 1;
                if (i < attack) env = 0.5 - 0.5 * Math.Cos(Math.PI * i / attack);
                else if (i > len - release) env = 0.5 - 0.5 * Math.Cos(Math.PI * (len - i) / release);
                buf.Add(v * env);
            }
            if (!last) {
                int gap = rate * rnd.Next(25, 55) / 1000;
                for (int i = 0; i < gap; i++) buf.Add(0);
            }
        }
        // leger echo pour arrondir le son
        int delay = rate * 85 / 1000;
        for (int i = 0; i < delay + rate / 20; i++) buf.Add(0);
        double[] outp = buf.ToArray();
        for (int i = outp.Length - 1; i >= delay; i--) outp[i] += buf[i - delay] * 0.22;
        System.Collections.Generic.List<short> data = new System.Collections.Generic.List<short>();
        foreach (double v in outp) data.Add((short)(Math.Max(-1, Math.Min(1, v * volume)) * 32767));
        System.IO.MemoryStream ms = new System.IO.MemoryStream();
        System.IO.BinaryWriter w = new System.IO.BinaryWriter(ms);
        int bytes = data.Count * 2;
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + bytes); w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(bytes);
        foreach (short sm in data) w.Write(sm);
        w.Flush();
        return ms.ToArray();
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
      <Canvas.Resources>
        <LinearGradientBrush x:Key="OMetal" StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#F2F4F7" Offset="0"/><GradientStop Color="#C9D0D9" Offset="0.45"/><GradientStop Color="#7F8A99" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="OMetalV" StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#F2F4F7" Offset="0"/><GradientStop Color="#8E98A6" Offset="1"/>
        </LinearGradientBrush>
        <RadialGradientBrush x:Key="ODome" GradientOrigin="0.35,0.3" Center="0.35,0.3" RadiusX="0.8" RadiusY="0.8">
          <GradientStop Color="#FFFFFF" Offset="0"/><GradientStop Color="#C9D0D9" Offset="0.5"/><GradientStop Color="#6E7988" Offset="1"/>
        </RadialGradientBrush>
        <LinearGradientBrush x:Key="OVisor" StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#22324A" Offset="0"/><GradientStop Color="#0A0F17" Offset="1"/>
        </LinearGradientBrush>
        <RadialGradientBrush x:Key="OGlow" GradientOrigin="0.5,0.2" Center="0.5,0.2" RadiusX="0.8" RadiusY="0.8">
          <GradientStop Color="#E67FD8FF" Offset="0"/><GradientStop Color="#004C8DFF" Offset="1"/>
        </RadialGradientBrush>
        <LinearGradientBrush x:Key="ODark" StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#4D5766" Offset="0"/><GradientStop Color="#2B323D" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="OStripe" StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#F08C00" Offset="0"/><GradientStop Color="#C96F00" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="OCoat" StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#2A3A5E" Offset="0"/><GradientStop Color="#1A2540" Offset="0.5"/><GradientStop Color="#0E1526" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="OTray" StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FAFBFC" Offset="0"/><GradientStop Color="#9AA3B0" Offset="1"/>
        </LinearGradientBrush>
      </Canvas.Resources>


      <Canvas x:Name="Bobber" Width="120" Height="100" RenderTransformOrigin="0.5,0.5">
        <Canvas.RenderTransform>
          <TransformGroup>
            <RotateTransform x:Name="Tilt" Angle="0"/>
            <TranslateTransform x:Name="Bob" Y="0"/>
          </TransformGroup>
        </Canvas.RenderTransform>

        <!-- ===== Apparence 1 : satellite ===== -->
        <Canvas x:Name="SkinSatellite">
        <!-- bras et charnieres des panneaux solaires -->
        <Rectangle Canvas.Left="35" Canvas.Top="49.6" Width="8" Height="2.4" Fill="#7D8796"/>
        <Rectangle Canvas.Left="77" Canvas.Top="49.6" Width="8" Height="2.4" Fill="#7D8796"/>
        <Rectangle Canvas.Left="34.5" Canvas.Top="47.5" Width="3" Height="6.5" RadiusX="0.6" RadiusY="0.6" Fill="#5E6878"/>
        <Rectangle Canvas.Left="82.5" Canvas.Top="47.5" Width="3" Height="6.5" RadiusX="0.6" RadiusY="0.6" Fill="#5E6878"/>

        <!-- panneaux solaires -->
        <Canvas Canvas.Left="2" Canvas.Top="38" Width="34" Height="26" ClipToBounds="True">
          <Rectangle Width="34" Height="26">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#2B5AA8" Offset="0"/>
                <GradientStop Color="#163A78" Offset="0.55"/>
                <GradientStop Color="#0B1F45" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
          </Rectangle>
          <Path Stroke="#4F7CC4" StrokeThickness="0.5" Opacity="0.8" Data="M 5.67,0 V 26 M 11.33,0 V 26 M 17,0 V 26 M 22.67,0 V 26 M 28.33,0 V 26 M 0,8.67 H 34 M 0,17.33 H 34"/>
          <!-- reflet du soleil qui balaie le panneau -->
          <Rectangle Canvas.Left="0" Canvas.Top="-18" Width="8" Height="62" Opacity="0.55">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#00FFFFFF" Offset="0"/>
                <GradientStop Color="#CCFFFFFF" Offset="0.5"/>
                <GradientStop Color="#00FFFFFF" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
            <Rectangle.RenderTransform>
              <TransformGroup>
                <RotateTransform Angle="25"/>
                <TranslateTransform x:Name="GlintL" X="-40"/>
              </TransformGroup>
            </Rectangle.RenderTransform>
          </Rectangle>
        </Canvas>
        <Rectangle Canvas.Left="2" Canvas.Top="38" Width="34" Height="26" RadiusX="1" RadiusY="1"
                   Stroke="#B4BCC8" StrokeThickness="1.1"/>
        <Canvas Canvas.Left="84" Canvas.Top="38" Width="34" Height="26" ClipToBounds="True">
          <Rectangle Width="34" Height="26">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#2B5AA8" Offset="0"/>
                <GradientStop Color="#163A78" Offset="0.55"/>
                <GradientStop Color="#0B1F45" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
          </Rectangle>
          <Path Stroke="#4F7CC4" StrokeThickness="0.5" Opacity="0.8" Data="M 5.67,0 V 26 M 11.33,0 V 26 M 17,0 V 26 M 22.67,0 V 26 M 28.33,0 V 26 M 0,8.67 H 34 M 0,17.33 H 34"/>
          <!-- reflet du soleil qui balaie le panneau -->
          <Rectangle Canvas.Left="0" Canvas.Top="-18" Width="8" Height="62" Opacity="0.55">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#00FFFFFF" Offset="0"/>
                <GradientStop Color="#CCFFFFFF" Offset="0.5"/>
                <GradientStop Color="#00FFFFFF" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
            <Rectangle.RenderTransform>
              <TransformGroup>
                <RotateTransform Angle="25"/>
                <TranslateTransform x:Name="GlintR" X="-40"/>
              </TransformGroup>
            </Rectangle.RenderTransform>
          </Rectangle>
        </Canvas>
        <Rectangle Canvas.Left="84" Canvas.Top="38" Width="34" Height="26" RadiusX="1" RadiusY="1"
                   Stroke="#B4BCC8" StrokeThickness="1.1"/>

        <!-- feux de navigation : rouge a babord, vert a tribord -->
        <Ellipse x:Name="NavL" Canvas.Left="0.2" Canvas.Top="49.4" Width="3.2" Height="3.2" Fill="#FF4D4D"/>
        <Ellipse x:Name="NavR" Canvas.Left="116.6" Canvas.Top="49.4" Width="3.2" Height="3.2" Fill="#3DDC84"/>

        <!-- antenne grand gain : mat, parabole, trepied et source, balise -->
        <Line X1="60" Y1="28" X2="60" Y2="19" Stroke="#7D8796" StrokeThickness="2"/>
        <Path Stroke="#4A5260" StrokeThickness="1" Data="M 45,11 Q 60,29 75,11 Z">
          <Path.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#FAFBFC" Offset="0"/>
              <GradientStop Color="#A3ACB9" Offset="1"/>
            </LinearGradientBrush>
          </Path.Fill>
        </Path>
        <Path Stroke="White" StrokeThickness="0.8" Opacity="0.8" Data="M 45.5,11.2 Q 60,14 74.5,11.2"/>
        <Path Stroke="#8A94A3" StrokeThickness="0.7" Data="M 47,12 L 60,5.5 L 73,12"/>
        <Rectangle Canvas.Left="58.6" Canvas.Top="4.5" Width="2.8" Height="3.5" RadiusX="0.5" RadiusY="0.5" Fill="#5E6878"/>
        <Ellipse x:Name="Beacon" Canvas.Left="58" Canvas.Top="0.6" Width="4" Height="4" Fill="#5FD3FF"/>

        <!-- viseur d'etoiles -->
        <Rectangle Canvas.Left="70" Canvas.Top="22.5" Width="6" Height="6" RadiusX="1" RadiusY="1"
                   Fill="#2A3240" Stroke="#4A5260" StrokeThickness="0.6"/>
        <Ellipse Canvas.Left="71.5" Canvas.Top="24" Width="3" Height="3" Fill="#0E141C" Stroke="#7D8796" StrokeThickness="0.5"/>

        <!-- module principal : plateforme argent + isolation doree (MLI) -->
        <Rectangle Canvas.Left="42" Canvas.Top="28" Width="36" Height="46" RadiusX="3" RadiusY="3">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
              <GradientStop Color="#EEF1F5" Offset="0"/>
              <GradientStop Color="#C3CAD4" Offset="0.5"/>
              <GradientStop Color="#8F99A8" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>
        <Rectangle Canvas.Left="42.6" Canvas.Top="52" Width="34.8" Height="21.4">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#F1D27A" Offset="0"/>
              <GradientStop Color="#C79A2A" Offset="0.35"/>
              <GradientStop Color="#E9C565" Offset="0.6"/>
              <GradientStop Color="#A9801A" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>
        <Path Stroke="White" StrokeThickness="0.45" Opacity="0.3"
              Data="M 44,56 L 49,54.8 L 53,57.6 L 58,55.4 L 63,58.4 L 69,56.2 L 76,57.8 M 44,64 L 50,62 L 55,64.6 L 61,62.4 L 66,65.4 L 72,63.2 L 76,64.6 M 46,70 L 52,68.4 L 58,70.6 L 64,69 L 71,71"/>
        <Path Stroke="#6B4E0E" StrokeThickness="0.4" Opacity="0.25"
              Data="M 44,59 L 50,58.2 L 56,60.4 L 62,58.8 L 70,60.6 L 76,60.2 M 45,67.5 L 51,66.4 L 57,68.2 L 64,66.4 L 75,68.2"/>
        <Rectangle Canvas.Left="42" Canvas.Top="28" Width="36" Height="46" RadiusX="3" RadiusY="3"
                   Stroke="#4A5260" StrokeThickness="1.1"/>
        <Line X1="42.6" Y1="52" X2="77.4" Y2="52" Stroke="#6B7380" StrokeThickness="0.7"/>
        <TextBlock Canvas.Left="42.6" Canvas.Top="53.3" Width="34.8" TextAlignment="Center" Text="ORBIT·1"
                   FontFamily="Consolas" FontWeight="Bold" FontSize="4.6" Foreground="#5A400C" Opacity="0.9"/>

        <!-- voyant d'etat -->
        <Ellipse x:Name="StatusLed" Canvas.Left="44.7" Canvas.Top="30.3" Width="3" Height="3" Fill="#5FD3FF"/>

        <!-- camera : elle suit la souris -->
        <Ellipse Canvas.Left="52.6" Canvas.Top="32.1" Width="14.8" Height="14.8" Fill="#1B2330"
                 Stroke="#4A5260" StrokeThickness="1.4"/>
        <Ellipse Canvas.Left="55" Canvas.Top="34.5" Width="10" Height="10" Stroke="#3A4556" StrokeThickness="0.8"/>
        <Ellipse x:Name="Lens" Canvas.Left="56.7" Canvas.Top="36.2" Width="6.6" Height="6.6" Fill="#5FD3FF"/>
        <Ellipse x:Name="LensGlint" Canvas.Left="57.9" Canvas.Top="37.4" Width="2.2" Height="2.2" Fill="#D9FFFFFF"/>

        <!-- afficheur binaire : les minutes restantes, en binaire (clin d'oeil geek) -->
        <Rectangle Canvas.Left="46" Canvas.Top="46.6" Width="28" Height="4.4" RadiusX="1" RadiusY="1" Fill="#141B24"
                   ToolTip="Minutes restantes, en binaire 🤓"/>
        <Rectangle x:Name="Bit0" Canvas.Left="69.5" Canvas.Top="47.6" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
        <Rectangle x:Name="Bit1" Canvas.Left="65.1" Canvas.Top="47.6" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
        <Rectangle x:Name="Bit2" Canvas.Left="60.7" Canvas.Top="47.6" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
        <Rectangle x:Name="Bit3" Canvas.Left="56.3" Canvas.Top="47.6" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
        <Rectangle x:Name="Bit4" Canvas.Left="51.9" Canvas.Top="47.6" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
        <Rectangle x:Name="Bit5" Canvas.Left="47.5" Canvas.Top="47.6" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>

        <!-- propulseurs et antennes fouet -->
        <Path Fill="#4D5664" Data="M 50,74 L 56,74 L 57.5,79 L 48.5,79 Z"/>
        <Path Fill="#4D5664" Data="M 64,74 L 70,74 L 71.5,79 L 62.5,79 Z"/>
        <Line X1="44" Y1="73" X2="37" Y2="84" Stroke="#8A94A3" StrokeThickness="0.8"/>
        <Ellipse Canvas.Left="36.1" Canvas.Top="83.1" Width="1.8" Height="1.8" Fill="#8A94A3"/>
        <Line X1="76" Y1="73" X2="83" Y2="84" Stroke="#8A94A3" StrokeThickness="0.8"/>
        <Ellipse Canvas.Left="82.1" Canvas.Top="83.1" Width="1.8" Height="1.8" Fill="#8A94A3"/>
        </Canvas>

        <!-- ===== Apparence 2 : droide de maintenance ===== -->
        <Canvas x:Name="SkinDroid" Visibility="Collapsed">
          <Ellipse x:Name="DGlow" Canvas.Left="44.00" Canvas.Top="79.00" Width="32.00" Height="18.00" Fill="{StaticResource OGlow}"/>
          <Path Data="M 37,52 L 27,58 L 25,68" Stroke="#7F8A99" StrokeThickness="3.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="24.60" Canvas.Top="55.60" Width="4.80" Height="4.80" Fill="#4D5766"/>
          <Ellipse Canvas.Left="34.00" Canvas.Top="49.00" Width="6.00" Height="6.00" Fill="#4D5766"/>
          <Path Data="M 22.5,68 L 25,73 M 27.5,68 L 26,73" Stroke="#4D5766" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Path Data="M 83,52 L 93,57 L 96,66" Stroke="#7F8A99" StrokeThickness="3.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="90.60" Canvas.Top="54.60" Width="4.80" Height="4.80" Fill="#4D5766"/>
          <Ellipse Canvas.Left="80.00" Canvas.Top="49.00" Width="6.00" Height="6.00" Fill="#4D5766"/>
          <Rectangle Canvas.Left="94.6" Canvas.Top="65" Width="3" Height="5" RadiusX="0.6" RadiusY="0.6" Fill="#F08C00"/>
          <Line X1="96.1" Y1="70" X2="96.1" Y2="76" Stroke="#AEB6C2" StrokeThickness="0.9"/>
          <Ellipse Canvas.Left="36.00" Canvas.Top="33.00" Width="48.00" Height="48.00" Fill="{StaticResource ODome}" Stroke="#4A5260" StrokeThickness="1.1"/>
          <Path Data="M 38,62 Q 60,70 82,62" Stroke="#6E7988" StrokeThickness="0.7"/>
          <Path Data="M 40,50 Q 60,44 80,50" Stroke="#6E7988" StrokeThickness="0.5" Opacity="0.6"/>
          <Path Data="M 37.5,64 Q 60,73 82.5,64 L 81.6,67.5 Q 60,76 38.4,67.5 Z" Fill="{StaticResource OStripe}"/>
          <Rectangle Canvas.Left="47" Canvas.Top="69" Width="26" Height="6" RadiusX="1.2" RadiusY="1.2" Fill="#141B24"/>
          <Rectangle x:Name="DBit0" Canvas.Left="70.0" Canvas.Top="70.8" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="DBit1" Canvas.Left="65.8" Canvas.Top="70.8" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="DBit2" Canvas.Left="61.6" Canvas.Top="70.8" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="DBit3" Canvas.Left="57.4" Canvas.Top="70.8" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="DBit4" Canvas.Left="53.2" Canvas.Top="70.8" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="DBit5" Canvas.Left="49.0" Canvas.Top="70.8" Width="2.6" Height="2.4" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Path Data="M 42,47 Q 60,36 78,47 L 76,58 Q 60,52 44,58 Z" Fill="{StaticResource OVisor}" Stroke="#3A4556" StrokeThickness="1"/>
          <Ellipse x:Name="DRing" Canvas.Left="56.60" Canvas.Top="44.10" Width="10.80" Height="10.80" Fill="#0B121C" Stroke="#4C8DFF" StrokeThickness="1"/>
          <Ellipse x:Name="DLens" Canvas.Left="59.00" Canvas.Top="46.50" Width="6.00" Height="6.00" Fill="#4C8DFF"/>
          <Ellipse x:Name="DGlint" Canvas.Left="60.00" Canvas.Top="47.30" Width="2.00" Height="2.00" Fill="#E6FFFFFF"/>
          <Ellipse Canvas.Left="49.60" Canvas.Top="49.60" Width="2.80" Height="2.80" Fill="#FF4D4D" Opacity="0.85"/>
          <Path Data="M 44,46.5 Q 60,38 76,46.5" Stroke="White" StrokeThickness="0.6" Opacity="0.35"/>
          <Line X1="70" Y1="35" X2="76" Y2="22" Stroke="#7F8A99" StrokeThickness="1"/>
          <Ellipse x:Name="DBeacon" Canvas.Left="74.20" Canvas.Top="19.70" Width="3.60" Height="3.60" Fill="#5FD3FF"/>
          <Line X1="66" Y1="34" X2="68" Y2="27" Stroke="#7F8A99" StrokeThickness="0.8"/>
          <Rectangle Canvas.Left="66.7" Canvas.Top="25.4" Width="2.6" Height="2" RadiusX="0.4" RadiusY="0.4" Fill="#4D5766"/>
          <TextBlock Canvas.Left="45.0" Canvas.Top="60.59" Width="30" TextAlignment="Center" Text="ORB-1" FontFamily="Consolas" FontSize="3.8" Foreground="#4A5260" FontWeight="Bold"/>
          <Path Data="M 50,79 L 56,79 L 55,84 L 51,84 Z" Fill="{StaticResource ODark}"/>
          <Path Data="M 64,79 L 70,79 L 69,84 L 65,84 Z" Fill="{StaticResource ODark}"/>
          <Ellipse x:Name="DJet1" Canvas.Left="51.00" Canvas.Top="84.30" Width="4.00" Height="2.40" Fill="#7FD8FF"/>
          <Ellipse x:Name="DJet2" Canvas.Left="65.00" Canvas.Top="84.30" Width="4.00" Height="2.40" Fill="#7FD8FF"/>
        </Canvas>

        <!-- ===== Apparence 3 : robot assistant ===== -->
        <Canvas x:Name="SkinRobot" Visibility="Collapsed">
          <Ellipse x:Name="RGlow" Canvas.Left="38.00" Canvas.Top="81.00" Width="44.00" Height="14.00" Fill="{StaticResource OGlow}" Opacity="0.8"/>
          <Rectangle Canvas.Left="30" Canvas.Top="58" Width="12" Height="9" RadiusX="4" RadiusY="4" Fill="{StaticResource OMetalV}" Stroke="#4A5260" StrokeThickness="0.9"/>
          <Rectangle Canvas.Left="78" Canvas.Top="58" Width="12" Height="9" RadiusX="4" RadiusY="4" Fill="{StaticResource OMetalV}" Stroke="#4A5260" StrokeThickness="0.9"/>
          <Path Data="M 33,67 L 31,79" Stroke="#7F8A99" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Path Data="M 87,67 L 89,79" Stroke="#7F8A99" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="28.40" Canvas.Top="78.40" Width="5.20" Height="5.20" Fill="#4D5766"/>
          <Ellipse Canvas.Left="86.40" Canvas.Top="78.40" Width="5.20" Height="5.20" Fill="#4D5766"/>
          <Path Data="M 40,56 L 80,56 L 77,84 L 43,84 Z" Fill="{StaticResource OMetal}" Stroke="#4A5260" StrokeThickness="1"/>
          <Path Data="M 45,60 L 75,60 L 73.5,72 L 46.5,72 Z" Fill="#1B2330" Stroke="#3A4556" StrokeThickness="0.7"/>
          <Rectangle x:Name="RBit0" Canvas.Left="70.0" Canvas.Top="63" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit1" Canvas.Left="65.7" Canvas.Top="63" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit2" Canvas.Left="61.4" Canvas.Top="63" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit3" Canvas.Left="57.1" Canvas.Top="63" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit4" Canvas.Left="52.8" Canvas.Top="63" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit5" Canvas.Left="48.5" Canvas.Top="63" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <TextBlock x:Name="RTerm" Canvas.Left="47.0" Canvas.Top="67.07" Width="26" TextAlignment="Center" Text="&gt; focus_" FontFamily="Consolas" FontSize="3.4" Foreground="#5FD3FF" Opacity="0.9"/>
          <Rectangle Canvas.Left="43.5" Canvas.Top="76" Width="33" Height="2.2" Fill="{StaticResource OStripe}"/>
          <TextBlock Canvas.Left="45.0" Canvas.Top="79.18" Width="30" TextAlignment="Center" Text="ORBIT·1" FontFamily="Consolas" FontSize="3.6" Foreground="#4A5260" FontWeight="Bold"/>
          <Rectangle Canvas.Left="55" Canvas.Top="50" Width="10" Height="7" Fill="{StaticResource ODark}"/>
          <Line X1="55" Y1="52.5" X2="65" Y2="52.5" Stroke="#6E7988" StrokeThickness="0.5"/>
          <Line X1="55" Y1="54.5" X2="65" Y2="54.5" Stroke="#6E7988" StrokeThickness="0.5"/>
          <Rectangle Canvas.Left="41" Canvas.Top="21" Width="38" Height="30" RadiusX="9" RadiusY="9" Fill="{StaticResource OMetal}" Stroke="#4A5260" StrokeThickness="1.1"/>
          <Rectangle Canvas.Left="37.5" Canvas.Top="30" Width="4" Height="11" RadiusX="1.5" RadiusY="1.5" Fill="{StaticResource ODark}"/>
          <Rectangle Canvas.Left="78.5" Canvas.Top="30" Width="4" Height="11" RadiusX="1.5" RadiusY="1.5" Fill="{StaticResource ODark}"/>
          <Ellipse x:Name="RStatus" Canvas.Left="38.40" Canvas.Top="34.40" Width="2.20" Height="2.20" Fill="#3DDC84"/>
          <Rectangle Canvas.Left="45" Canvas.Top="28" Width="30" Height="13" RadiusX="6.5" RadiusY="6.5" Fill="{StaticResource OVisor}" Stroke="#3A4556" StrokeThickness="0.8"/>
          <Ellipse x:Name="REyeL" Canvas.Left="50.20" Canvas.Top="31.20" Width="6.60" Height="6.60" Fill="#4C8DFF"/>
          <Ellipse x:Name="REyeR" Canvas.Left="63.20" Canvas.Top="31.20" Width="6.60" Height="6.60" Fill="#4C8DFF"/>
          <Ellipse x:Name="RGlintL" Canvas.Left="51.60" Canvas.Top="32.50" Width="2.00" Height="2.00" Fill="#E6FFFFFF"/>
          <Ellipse x:Name="RGlintR" Canvas.Left="64.60" Canvas.Top="32.50" Width="2.00" Height="2.00" Fill="#E6FFFFFF"/>
          <Path Data="M 47,30.5 Q 60,27.5 73,30.5" Stroke="White" StrokeThickness="0.5" Opacity="0.35"/>
          <Line X1="54" Y1="45" X2="66" Y2="45" Stroke="#6E7988" StrokeThickness="0.7"/>
          <Line X1="55" Y1="47" X2="65" Y2="47" Stroke="#6E7988" StrokeThickness="0.7"/>
          <Line X1="60" Y1="21" X2="60" Y2="12" Stroke="#7F8A99" StrokeThickness="1.4"/>
          <Ellipse x:Name="RBeacon" Canvas.Left="57.70" Canvas.Top="8.30" Width="4.60" Height="4.60" Fill="#5FD3FF"/>
          <Rectangle Canvas.Left="56.5" Canvas.Top="19" Width="7" Height="3" RadiusX="1" RadiusY="1" Fill="{StaticResource ODark}"/>
        </Canvas>

        <!-- ===== Apparence 4 : majordome (anneau holographique, plateau et cafe) ===== -->
        <Canvas x:Name="SkinButler" Visibility="Collapsed">
          <Canvas Opacity="0.55">
            <Canvas.RenderTransform><RotateTransform x:Name="MHud" CenterX="60" CenterY="27" Angle="20"/></Canvas.RenderTransform>
            <Ellipse x:Name="MHud1" Canvas.Left="36.00" Canvas.Top="3.00" Width="48.00" Height="48.00" Stroke="#5FD3FF" StrokeThickness="0.6" StrokeDashArray="2 3.6"/>
            <Path x:Name="MHud2" Data="M 39,19 A 22,22 0 0 1 60,5" Stroke="#5FD3FF" StrokeThickness="1.4"/>
            <Path x:Name="MHud3" Data="M 81,35 A 22,22 0 0 1 70,47" Stroke="#5FD3FF" StrokeThickness="1.4"/>
          </Canvas>
          <Ellipse x:Name="MGlow" Canvas.Left="45.00" Canvas.Top="81.00" Width="30.00" Height="10.00" Fill="{StaticResource OGlow}"/>
          <Path Data="M 41,49 L 36,62 L 44,68" Stroke="#1A2540" StrokeThickness="4.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Path Data="M 36.5,60 L 41.5,61 L 40.5,73 L 35,71 Z" Fill="#F4F6F9" Stroke="#C9D0D9" StrokeThickness="0.5"/>
          <Ellipse Canvas.Left="42.80" Canvas.Top="65.80" Width="4.40" Height="4.40" Fill="#E8ECF1"/>
          <Path Data="M 79,49 L 86,60 L 95,57" Stroke="#1A2540" StrokeThickness="4.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="93.80" Canvas.Top="54.30" Width="4.40" Height="4.40" Fill="#E8ECF1"/>
          <Ellipse Canvas.Left="85.00" Canvas.Top="51.60" Width="26.00" Height="4.80" Fill="{StaticResource OTray}" Stroke="#7F8A99" StrokeThickness="0.6"/>
          <Path Data="M 94,47 L 102,47 L 101,53 L 95,53 Z" Fill="White" Stroke="#AEB6C2" StrokeThickness="0.5"/>
          <Path Data="M 102,48.5 Q 105,49.5 101.6,51.6" Stroke="#AEB6C2" StrokeThickness="0.8"/>
          <Path x:Name="MSteam" Data="M 96.5,45 Q 95.5,42.5 97,40.5 M 99.5,45 Q 98.5,42 100,39.5" Stroke="#C9D0D9" StrokeThickness="0.6" Opacity="0.8"/>
          <Path Data="M 41,46 Q 60,42 79,46 L 80,72 L 74,82 L 66,72 L 54,72 L 46,82 L 40,72 Z" Fill="{StaticResource OCoat}" Stroke="#0A0F1A" StrokeThickness="0.8"/>
          <Path Data="M 52.5,45 L 67.5,45 L 60,71 Z" Fill="#F4F6F9" Stroke="#C9D0D9" StrokeThickness="0.5"/>
          <Path Data="M 52.5,45 L 60,71 L 49,56 Z" Fill="#26355A" Stroke="#0A0F1A" StrokeThickness="0.5"/>
          <Path Data="M 67.5,45 L 60,71 L 71,56 Z" Fill="#26355A" Stroke="#0A0F1A" StrokeThickness="0.5"/>
          <Path x:Name="MPocket" Data="M 70,57.5 L 75,57.5 L 73.5,60.5 L 72.5,59 L 71.5,60.5 Z" Fill="#4C8DFF"/>
          <Line X1="69.5" Y1="60.6" X2="75.5" Y2="60.6" Stroke="#0A0F1A" StrokeThickness="0.7"/>
          <Ellipse x:Name="MBit0" Canvas.Left="58.90" Canvas.Top="65.90" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="MBit1" Canvas.Left="58.90" Canvas.Top="62.70" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="MBit2" Canvas.Left="58.90" Canvas.Top="59.50" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="MBit3" Canvas.Left="58.90" Canvas.Top="56.30" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="MBit4" Canvas.Left="58.90" Canvas.Top="53.10" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="MBit5" Canvas.Left="58.90" Canvas.Top="49.90" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Path Data="M 54.5,44 L 59.2,46 L 54.5,48 Z" Fill="#111722"/>
          <Path Data="M 65.5,44 L 60.8,46 L 65.5,48 Z" Fill="#111722"/>
          <Rectangle Canvas.Left="58.6" Canvas.Top="44.9" Width="2.8" Height="2.2" RadiusX="0.6" RadiusY="0.6" Fill="#2B323D"/>
          <Rectangle Canvas.Left="56.5" Canvas.Top="39" Width="7" Height="5" Fill="{StaticResource ODark}"/>
          <Rectangle Canvas.Left="46" Canvas.Top="12" Width="28" Height="28" RadiusX="10" RadiusY="10" Fill="{StaticResource OMetal}" Stroke="#4A5260" StrokeThickness="1.1"/>
          <Path Data="M 47.5,20 Q 48,11.5 60,11.2 Q 72,11.5 72.5,20 Q 66,15.5 60,16 Q 53,15.6 47.5,20 Z" Fill="#3A4352"/>
          <Rectangle Canvas.Left="44" Canvas.Top="22" Width="3" Height="8" RadiusX="1.2" RadiusY="1.2" Fill="{StaticResource ODark}"/>
          <Rectangle Canvas.Left="73" Canvas.Top="22" Width="3" Height="8" RadiusX="1.2" RadiusY="1.2" Fill="{StaticResource ODark}"/>
          <Rectangle Canvas.Left="49" Canvas.Top="21.5" Width="22" Height="8.5" RadiusX="4.2" RadiusY="4.2" Fill="{StaticResource OVisor}" Stroke="#3A4556" StrokeThickness="0.7"/>
          <Ellipse x:Name="MEyeL" Canvas.Left="52.90" Canvas.Top="23.60" Width="4.20" Height="4.20" Fill="#4C8DFF"/>
          <Ellipse x:Name="MEyeR" Canvas.Left="62.90" Canvas.Top="23.60" Width="4.20" Height="4.20" Fill="#4C8DFF"/>
          <Ellipse x:Name="MGlintL" Canvas.Left="53.60" Canvas.Top="24.30" Width="1.40" Height="1.40" Fill="#E6FFFFFF"/>
          <Ellipse x:Name="MGlintR" Canvas.Left="63.60" Canvas.Top="24.30" Width="1.40" Height="1.40" Fill="#E6FFFFFF"/>
          <Ellipse Canvas.Left="61.00" Canvas.Top="21.70" Width="8.00" Height="8.00" Stroke="#C9A227" StrokeThickness="0.9"/>
          <Path Data="M 68.6,27.5 Q 72,36 70.5,44" Stroke="#C9A227" StrokeThickness="0.4"/>
          <Path Data="M 60,33 Q 56,32 53.5,34.5 Q 56.5,35.5 60,34.2 Q 63.5,35.5 66.5,34.5 Q 64,32 60,33 Z" Fill="#3A4352"/>
        </Canvas>
      </Canvas>

      <!-- chrono -->
      <Border x:Name="Pill" Canvas.Left="21" Canvas.Top="94" Width="78" Height="22" CornerRadius="3"
              Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="1.2">
        <TextBlock x:Name="PillText" Text="▶" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI"
                   FontWeight="Bold" FontSize="12.5" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Canvas>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
# tous les elements nommes (x:Name) du dessin, accessibles par $ui.Nom
$nsm = New-Object Xml.XmlNamespaceManager($xaml.NameTable)
$nsm.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
foreach ($node in $xaml.SelectNodes('//@x:Name', $nsm)) { $ui[$node.Value] = $window.FindName($node.Value) }

# ---------------------------------------------------------------------------
#  Etat
# ---------------------------------------------------------------------------
$O = @{
    State        = 'Idle'      # Idle | Focus | AwaitBreak | Break | AwaitFocus
    EndsAt       = [datetime]::MinValue
    Paused       = $false
    Remaining    = [timespan]::Zero
    AutoPaused   = $false
    AwaySince    = [datetime]::MinValue
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
    AccentBrush  = $null
    Skin         = 'Satellite'
    Mood         = ''
    Today        = (Get-Date).ToString('yyyy-MM-dd')
    FocusToday   = 0
    FocusMinToday = 0
    SessionMin   = 0
    Rhythm       = '50/10'
    TaskReminders = $true
    FocusTaskId  = ''
    NextJoke     = [datetime]::MaxValue
    JokeSeed     = (Get-Random)
    JokePos      = 0
    Punch        = $null
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
        if ($null -ne $s.jokeSeed) { $O.JokeSeed = [int]$s.jokeSeed; $O.JokePos = [int]$s.jokePos }
    }
} catch { Write-Log "Lecture stats : $($_.Exception.Message)" }

function Save-Stats {
    try {
        $today = (Get-Date).ToString('yyyy-MM-dd')
        if ($today -ne $O.Today) { $O.Today = $today; $O.FocusToday = 0; $O.FocusMinToday = 0 }
        @{ date = $O.Today; focus = $O.FocusToday; minutes = $O.FocusMinToday; jokeSeed = $O.JokeSeed; jokePos = $O.JokePos } |
            ConvertTo-Json | Set-Content -Path $StatsFile -Encoding UTF8
    } catch { Write-Log "Ecriture stats : $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
#  Preferences (settings.json) : tout ce qu'on regle dans la fenetre Reglages
# ---------------------------------------------------------------------------
function Get-SettingsSnapshot {
    [ordered]@{
        rhythm             = $O.Rhythm
        customFocus        = $Rhythms['Perso'].Focus
        customBreak        = $Rhythms['Perso'].Break
        quiet              = $O.Quiet
        wander             = $O.Wander
        wanderMin          = $Config.WanderMinMin
        wanderMax          = $Config.WanderMaxMin
        taskReminders      = $O.TaskReminders
        reminderEveryMin   = $Config.ReminderEveryMin
        motivationEveryMin = $Config.MotivationEveryMin
        jokes              = $Config.Jokes
        jokeEveryMin       = $Config.JokeEveryMin
        appComments        = $Config.AppComments
        sounds             = $Config.Sounds
        droidSounds        = $Config.DroidSounds
        droidVolume        = $Config.DroidVolume
        skin               = $O.Skin
        idlePause          = $Config.IdlePause
        idleMinutes        = $Config.IdleMinutes
    }
}

function Apply-SettingsData($d) {
    if ($null -eq $d) { return }
    function Has($n) { $null -ne $d.$n }
    if ((Has 'customFocus') -and [double]$d.customFocus -ge 1) { $Rhythms['Perso'].Focus = [double]$d.customFocus }
    if ((Has 'customBreak') -and [double]$d.customBreak -ge 1) { $Rhythms['Perso'].Break = [double]$d.customBreak }
    if ($d.rhythm -and $Rhythms.Contains([string]$d.rhythm)) { $O.Rhythm = [string]$d.rhythm }
    if (Has 'quiet') { $O.Quiet = [bool]$d.quiet }
    if (Has 'wander') { $O.Wander = [bool]$d.wander }
    if (Has 'wanderMin') { $Config.WanderMinMin = [int]$d.wanderMin }
    if (Has 'wanderMax') { $Config.WanderMaxMin = [int]$d.wanderMax }
    if (Has 'taskReminders') { $O.TaskReminders = [bool]$d.taskReminders }
    if (Has 'reminderEveryMin') { $Config.ReminderEveryMin = [int]$d.reminderEveryMin }
    if (Has 'motivationEveryMin') { $Config.MotivationEveryMin = [int]$d.motivationEveryMin }
    if (Has 'jokes') { $Config.Jokes = [bool]$d.jokes }
    if (Has 'jokeEveryMin') { $Config.JokeEveryMin = [double]$d.jokeEveryMin }
    if (Has 'appComments') { $Config.AppComments = [bool]$d.appComments }
    if (Has 'sounds') { $Config.Sounds = [bool]$d.sounds }
    if (Has 'droidSounds') { $Config.DroidSounds = [bool]$d.droidSounds }
    if (Has 'droidVolume') { $Config.DroidVolume = [math]::Min(100, [math]::Max(0, [int]$d.droidVolume)) }
    if ($d.skin) { $O.Skin = [string]$d.skin }   # verifie par Set-Skin
    if (Has 'idlePause') { $Config.IdlePause = [bool]$d.idlePause }
    if (Has 'idleMinutes') { $Config.IdleMinutes = [int]$d.idleMinutes }
    if ($Config.WanderMaxMin -le $Config.WanderMinMin) { $Config.WanderMaxMin = $Config.WanderMinMin + 1 }
}

function Save-Settings {
    try { Get-SettingsSnapshot | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8 }
    catch { Write-Log "Ecriture reglages : $($_.Exception.Message)" }
}

# les anciennes versions gardaient quelques preferences dans stats.json : elles sont lues
# plus haut, puis settings.json (s'il existe) a le dernier mot
try {
    if (Test-Path $SettingsFile) { Apply-SettingsData (Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
} catch { Write-Log "Lecture reglages : $($_.Exception.Message)" }

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

# ---------------------------------------------------------------------------
#  Apparences : ce que chaque dessin anime (yeux, balises, LED binaires...)
#  Eyes : elements qui suivent la souris (position de repos) ; EyeX/EyeY : centre du regard
# ---------------------------------------------------------------------------
$Skins = [ordered]@{
    Satellite = @{ Label = '🛰️ Satellite'; Root = 'SkinSatellite'; Bits = 'Bit'; EyeX = 60; EyeY = 39.5; EyeMax = 1.8
                   Eyes = @(@('Lens', 56.7, 36.2), @('LensGlint', 57.9, 37.4))
                   Fill = @('Lens', 'Beacon', 'StatusLed'); Stroke = @(); Beacons = @('Beacon'); Glows = @() }
    Droid     = @{ Label = '🤖 Droïde de maintenance'; Root = 'SkinDroid'; Bits = 'DBit'; EyeX = 62; EyeY = 49.5; EyeMax = 1.6
                   Eyes = @(@('DLens', 59, 46.5), @('DGlint', 60, 47.3))
                   Fill = @('DLens', 'DBeacon'); Stroke = @('DRing'); Beacons = @('DBeacon'); Glows = @('DGlow', 'DJet1', 'DJet2') }
    Robot     = @{ Label = '🦾 Robot assistant'; Root = 'SkinRobot'; Bits = 'RBit'; EyeX = 60; EyeY = 34.5; EyeMax = 1.3
                   Eyes = @(@('REyeL', 50.2, 31.2), @('REyeR', 63.2, 31.2), @('RGlintL', 51.6, 32.5), @('RGlintR', 64.6, 32.5))
                   Fill = @('REyeL', 'REyeR', 'RBeacon'); Stroke = @(); Beacons = @('RBeacon'); Glows = @('RGlow') }
    Butler    = @{ Label = '🎩 Majordome'; Root = 'SkinButler'; Bits = 'MBit'; EyeX = 60; EyeY = 25.7; EyeMax = 0.9
                   Eyes = @(@('MEyeL', 52.9, 23.6), @('MEyeR', 62.9, 23.6), @('MGlintL', 53.6, 24.3), @('MGlintR', 63.6, 24.3))
                   Fill = @('MEyeL', 'MEyeR', 'MPocket'); Stroke = @('MHud1', 'MHud2', 'MHud3'); Beacons = @(); Glows = @('MGlow') }
}

function Set-Skin([string]$name, [switch]$Quiet) {
    if (-not $Skins.Contains($name)) { $name = 'Satellite' }
    foreach ($k in $Skins.Keys) { $ui[$Skins[$k].Root].Visibility = if ($k -eq $name) { 'Visible' } else { 'Collapsed' } }
    $O.Skin = $name
    if ($O.Mood) { Set-Mood $O.Mood }
    if (-not $Quiet) {
        $hello = switch ($name) {
            'Satellite' { "Retour en orbite 🛰️" }
            'Droid'     { "Droïde de maintenance opérationnel. Je répare… surtout ta motivation 🔧" }
            'Robot'     { "Robot assistant en ligne. > focus_ 🦾" }
            'Butler'    { "Votre majordome est à votre service. Un café avec votre focus ? ☕🎩" }
        }
        Show-Bubble $hello -Force -Seconds 4
    }
}

function Set-Mood([string]$mood) {
    $O.Mood = $mood
    $c = $Moods[$mood]
    $accent = New-Object Windows.Media.SolidColorBrush((New-Color $c[0]))
    $sk = $Skins[$O.Skin]
    foreach ($n in $sk.Fill) { $ui[$n].Fill = $accent }
    foreach ($n in $sk.Stroke) { $ui[$n].Stroke = $accent }
    $ui.Pill.BorderBrush = $accent
    $O.AccentBrush = $accent
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
        Play-Chirp -Question:($Buttons.Count -gt 0 -or $Text.TrimEnd().EndsWith('?'))
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
    Save-Settings
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
        $label = if ($name -eq 'Perso') { "$($r.Icon) Focus $($r.Focus)/$($r.Break)" } else { "$($r.Icon) Focus $name" }
        $list += @{ Label = $label; Action = [scriptblock]::Create("Set-Rhythm '$name' -Quiet; Start-Focus"); Primary = ($name -eq $O.Rhythm) }
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
            $msg += "`n`n🎯 Objectif (P$($open[0].prio)) : « $(Short-Text $open[0].text) »"
            if ($open[0].desc) { $msg += "`n   📄 $(Short-Text $open[0].desc 90)" }
            if ($open.Count -gt 1) {
                $msg += "`n📝 Ensuite :"
                foreach ($t in ($open | Select-Object -Skip 1 -First 2)) { $msg += "`n   • P$($t.prio) $(Short-Text $t.text 45)" }
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

# ---------------------------------------------------------------------------
#  Blagues de pause : fichiers jokes\*.txt (une blague par ligne,
#  "question|reponse" pour garder la chute quelques secondes)
# ---------------------------------------------------------------------------
function Load-Jokes {
    $list = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $dir = Join-Path $PSScriptRoot 'jokes'
    if (Test-Path $dir) {
        foreach ($f in (Get-ChildItem -Path $dir -Filter '*.txt' | Sort-Object Name)) {
            try {
                foreach ($line in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
                    $l = $line.Trim()
                    if (-not $l -or $l.StartsWith('#')) { continue }
                    if ($seen.Add($l.ToLowerInvariant())) { $list.Add($l) }
                }
            } catch { Write-Log "Blagues ($($f.Name)) : $($_.Exception.Message)" }
        }
    }
    if ($list.Count -eq 0) { foreach ($j in $Lines.BreakJokes) { $list.Add($j) } }
    return , $list
}
$Jokes = Load-Jokes
$script:JokeOrder = $null

# Ordre melange mais memorise d'un lancement a l'autre : pas de repetition
# tant que toutes les blagues ne sont pas passees
function Get-NextJoke {
    if (-not $script:JokeOrder -or $O.JokePos -ge $Jokes.Count) {
        if ($O.JokePos -ge $Jokes.Count) { $O.JokeSeed = Get-Random; $O.JokePos = 0 }
        $rng = New-Object System.Random($O.JokeSeed)
        $order = [int[]](0..($Jokes.Count - 1))
        for ($i = $order.Length - 1; $i -gt 0; $i--) {
            $k = $rng.Next($i + 1)
            $tmp = $order[$i]; $order[$i] = $order[$k]; $order[$k] = $tmp
        }
        $script:JokeOrder = $order
    }
    $j = $Jokes[$script:JokeOrder[$O.JokePos]]
    $O.JokePos++
    Save-Stats
    return $j
}

function Tell-Joke {
    $j = Get-NextJoke
    $parts = $j.Split('|', 2)
    if ($parts.Count -eq 2) {
        # la question d'abord, la chute 4 secondes plus tard
        $q = $parts[0].Trim()
        Show-Bubble "$q 🤔" -Seconds 14
        $O.Punch = @{ Shown = "$q 🤔"; Full = "$q`n`n👉 $($parts[1].Trim())"; At = (Get-Date).AddSeconds(4) }
    } else {
        Show-Bubble $j -Seconds 10
    }
}

function Stop-Cycle {
    $O.State = 'Idle'
    $O.Paused = $false
    $O.AutoPaused = $false
    $O.NextMotivation = [datetime]::MaxValue
    $O.NextReminder = [datetime]::MaxValue
    Set-Mood 'Idle'
    Show-Bubble ((Pick $Lines.Stop) -f $O.FocusToday) -Force -Seconds 8
    Update-Pill
}

# ---------------------------------------------------------------------------
#  Bips de droide : une petite banque generee au demarrage, jouee a chaque bulle
# ---------------------------------------------------------------------------
$script:Chirps = @{ Talk = @(); Ask = @() }
$script:ChirpPlayer = $null
$script:LastChirp = [datetime]::MinValue
# la banque est refaite quand on change le volume dans les reglages
function Build-Chirps {
    if (-not $Native) { return }
    $vol = 0.55 * $Config.DroidVolume / 100
    try {
        $script:Chirps.Talk = @(1..10 | ForEach-Object { , [OrbitNative]::DroidChirp((Get-Random), $vol, $false) })
        $script:Chirps.Ask = @(1..6 | ForEach-Object { , [OrbitNative]::DroidChirp((Get-Random), $vol, $true) })
        $script:ChirpVolume = $Config.DroidVolume
    } catch { Write-Log "Bips : $($_.Exception.Message)" }
}
Build-Chirps

function Play-Chirp([switch]$Question) {
    if (-not $Config.DroidSounds -or $Config.DroidVolume -le 0) { return }
    if ($script:ChirpVolume -ne $Config.DroidVolume) { Build-Chirps }
    $bank = if ($Question) { $script:Chirps.Ask } else { $script:Chirps.Talk }
    if (-not $bank.Count) { return }
    # pas plus d'un bip toutes les 1,5 seconde
    if (((Get-Date) - $script:LastChirp).TotalSeconds -lt 1.5) { return }
    $script:LastChirp = Get-Date
    try {
        $wav = $bank[(Get-Random -Maximum $bank.Count)]
        $script:ChirpPlayer = New-Object System.Media.SoundPlayer (New-Object IO.MemoryStream (, $wav))
        $script:ChirpPlayer.Play()   # asynchrone : n'interrompt pas l'animation
    } catch { Write-Log "Bip : $($_.Exception.Message)" }
}

function Play-Sound {
    if ($Config.Sounds) { try { [System.Media.SystemSounds]::Asterisk.Play() } catch {} }
}

# ---------------------------------------------------------------------------
#  Absence : le focus se met en pause tout seul et Orbit t'accueille au retour
# ---------------------------------------------------------------------------
function Check-Idle {
    if (-not $Native -or -not $Config.IdlePause) { return }
    $idleS = [OrbitNative]::IdleMs() / 1000.0
    $now = Get-Date
    if ($O.State -eq 'Focus' -and -not $O.Paused -and $idleS -ge $Config.IdleMinutes * 60) {
        # on rend le temps passe loin du clavier : le chrono s'arrete au moment ou tu es parti
        $away = $now.AddSeconds(-$idleS)
        $remaining = $O.EndsAt - $away
        if ($remaining.TotalSeconds -le 5) { return }
        $O.Remaining = $remaining
        $O.Paused = $true
        $O.AutoPaused = $true
        $O.AwaySince = $away
        Update-Pill
        Write-Log "Absence detectee : focus mis en pause"
    } elseif ($O.AutoPaused -and $idleS -lt 3) {
        $O.AutoPaused = $false
        $mins = [math]::Max(1, [math]::Round(($now - $O.AwaySince).TotalMinutes))
        Ensure-Visible
        $left = [math]::Ceiling($O.Remaining.TotalMinutes)
        Show-Bubble ("Re ! 👋 Tu t'es absenté(e) environ $mins min, alors j'ai mis le focus en pause à " +
            "$($O.AwaySince.ToString('HH:mm')).`nIl te reste $left min. On reprend ?") -Force -Buttons @(
            @{ Label = '▶ On reprend'; Action = { Toggle-Pause }; Primary = $true },
            @{ Label = '⏹ Couper le focus'; Action = { Stop-Cycle } })
    }
}

function Toggle-Pause {
    if ($O.State -notin 'Focus', 'Break') { return }
    $O.AutoPaused = $false
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
        if ($next) { $Text += "`n`n🎯 Au programme (P$($next.prio)) : « $(Short-Text $next.text) »" }
    }
    Show-Bubble $Text -Buttons @($BtnAgain, $BtnStop) -Force
}

function On-TimerEnded {
    Ensure-Visible
    Play-Sound
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
        'Idle'       { '▶ ORBIT' }
        'AwaitBreak' { '☕ ?' }
        'AwaitFocus' { '🚀 ?' }
        default {
            $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
            if ($left -lt [timespan]::Zero) { $left = [timespan]::Zero }
            $t = '{0:00}:{1:00}' -f [math]::Floor($left.TotalMinutes), $left.Seconds
            # compte a rebours facon controle de mission pendant le focus
            $prefix = if ($O.Paused) { '⏸ ' } elseif ($O.State -eq 'Break') { '☕ ' } else { 'T-' }
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
        'Idle'       {
            $hello = Pick $Lines.Hello
            $due = Get-DeadlineSummary
            if ($due) { $hello += "`n`n$due" }
            Show-Bubble $hello -Buttons (@(Get-StartButtons) + @($BtnTodo, $BtnLater)) -Force
        }
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
    if (-not $Native -or -not $Config.AppComments) { return }
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

$script:BitOff = New-Object Windows.Media.SolidColorBrush((New-Color '#2A3442'))
function Update-Bits([double]$t) {
    $on = $O.AccentBrush
    if (-not $on) { return }
    $mask = 0; $blink = 1.0
    switch -Wildcard ($O.State) {
        'Await*' { $mask = 63; $blink = 0.3 + 0.7 * [math]::Abs([math]::Sin($t * 4)) }
        'Idle' {
            $pos = [int][math]::Floor($t * 6) % 10
            $i = if ($pos -lt 6) { $pos } else { 10 - $pos }
            $mask = 1 -shl (5 - $i)
        }
        default {
            $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - [datetime]::Now }
            $mask = [int][math]::Min(63, [math]::Max(0, [math]::Ceiling($left.TotalMinutes)))
            if ($O.Paused) { $blink = if (($t % 1.2) -lt 0.6) { 1 } else { 0.25 } }
        }
    }
    for ($b = 0; $b -lt 6; $b++) {
        $led = $ui["$($Skins[$O.Skin].Bits)$b"]
        if ($mask -band (1 -shl $b)) { $led.Fill = $on; $led.Opacity = $blink } else { $led.Fill = $script:BitOff; $led.Opacity = 1 }
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

    $sk = $Skins[$O.Skin]

    # balises : un flash regulier, clignotement rapide quand Orbit attend une reponse
    $beacon = if ($O.State -like 'Await*') { 0.3 + 0.7 * [math]::Abs([math]::Sin($t * 4)) }
              elseif (($t % 2.0) -lt 0.18) { 1 } else { 0.35 }
    foreach ($n in $sk.Beacons) { $ui[$n].Opacity = $beacon }

    # les yeux (ou la camera) suivent la souris
    $c = Get-CursorDip
    $scale = $ui.BotScale.ScaleX
    $cx = $window.Left + $window.Width - (120 - $sk.EyeX) * $scale
    $cy = $window.Top + $window.Height - (122 - $sk.EyeY) * $scale
    $vx = $c.X - $cx; $vy = $c.Y - $cy
    $len = [math]::Sqrt($vx * $vx + $vy * $vy)
    if ($len -gt 1) { $vx = $vx / $len * $sk.EyeMax; $vy = $vy / $len * $sk.EyeMax }
    foreach ($e in $sk.Eyes) {
        [Windows.Controls.Canvas]::SetLeft($ui[$e[0]], $e[1] + $vx)
        [Windows.Controls.Canvas]::SetTop($ui[$e[0]], $e[2] + $vy)
    }

    # reacteurs qui vacillent
    $i = 0
    foreach ($n in $sk.Glows) { $ui[$n].Opacity = 0.72 + 0.28 * [math]::Sin($t * 11 + $i * 1.7); $i++ }

    switch ($O.Skin) {
        'Satellite' {
            # voyant d'etat, feux de navigation (flashs alternes) et reflet du soleil sur les panneaux
            $ui.StatusLed.Opacity = if ($O.State -like 'Await*') { $beacon } else { 1 }
            $ui.NavL.Opacity = if (($t % 1.6) -lt 0.12) { 1 } else { 0.25 }
            $ui.NavR.Opacity = if ((($t + 0.8) % 1.6) -lt 0.12) { 1 } else { 0.25 }
            $g = $t % 7
            $ui.GlintL.X = -40 + [math]::Min(1, $g / 1.4) * 90
            $ui.GlintR.X = -40 + [math]::Min(1, [math]::Max(0, $g - 0.35) / 1.4) * 90
        }
        'Robot' {
            # petit terminal sur la poitrine, curseur clignotant
            $word = switch -Wildcard ($O.State) { 'Focus' { 'focus' } 'Break' { 'pause' } 'Await*' { 'input?' } default { 'idle' } }
            if ($O.Paused) { $word = 'paused' }
            $ui.RTerm.Text = '> ' + $word + $(if (($t % 1) -lt 0.5) { '_' } else { ' ' })
        }
        'Butler' {
            # l'anneau holographique tourne lentement, la vapeur du cafe ondule
            $ui.MHud.Angle = ($t * 14) % 360
            $ui.MSteam.Opacity = 0.45 + 0.35 * [math]::Sin($t * 2.3)
        }
    }

    # afficheur binaire : minutes restantes pendant une session, balayage au repos
    Update-Bits $t

    # chute de la blague en cours
    if ($O.Punch -and $now -ge $O.Punch.At) {
        if ($ui.BubbleWrap.Visibility -eq 'Visible' -and $ui.BubbleText.Text -eq $O.Punch.Shown) {
            $ui.BubbleText.Text = $O.Punch.Full
            Play-Chirp
            $O.BubbleUntil = $now.AddSeconds(9)
        }
        $O.Punch = $null
    }

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
            # une blague toutes les ~2 minutes pendant la pause (sauf dans les 20 dernieres secondes)
            $base = [math]::Max(20, $Config.JokeEveryMin * 60)
            $O.NextJoke = $now.AddSeconds((Get-Random -Minimum ([int]($base * 0.75)) -Maximum ([int]($base * 1.25) + 1)))
            if ($Config.Jokes -and $left.TotalSeconds -gt 20) { Tell-Joke }
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

    if ($script:slowCount % 2 -eq 0) { Check-Idle }
    if ($script:slowCount % 10 -eq 0) { Check-TaskReminders }
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

function Set-Autostart([bool]$on, [switch]$Silent) {
    if (-not $on) {
        if (Test-Path $StartupLink) { Remove-Item $StartupLink -Force }
        if (-not $Silent) { Show-Bubble "Ok, je ne me lancerai plus au démarrage." -Force }
        return
    }
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($StartupLink)
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$OrbitScript`""
    $lnk.WorkingDirectory = Split-Path $OrbitScript
    $lnk.WindowStyle = 7
    $lnk.Description = 'Orbit - compagnon de focus'
    $lnk.Save()
    if (-not $Silent) { Show-Bubble "C'est noté, je serai là à chaque démarrage de Windows 🚀 (sans droits admin)" -Force }
}

function Toggle-Autostart { Set-Autostart (-not (Test-Path $StartupLink)) }

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
    if ($NB.EditId) { End-EditTodo -NoRender } else { Save-Todos }
    $NB.Quitting = $true
    $script:frameTimer.Stop()
    $script:secondTimer.Stop()
    $app.Shutdown()
}

# ---------------------------------------------------------------------------
#  Carnet : to-do + historique des copier-coller (voir notebook.ps1)
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'notebook.ps1')
. (Join-Path $PSScriptRoot 'settings.ps1')

$menu = New-Object Windows.Controls.ContextMenu
$miTodo   = New-MenuItem "📝  Ma to-do" { Open-Notebook 'Todo' }
$miClip   = New-MenuItem "📋  Mes copier-coller du jour" { Open-Notebook 'Clip' }
$miFocus  = New-MenuItem "🚀  Lancer un focus" { Start-Focus }
$miBreak  = New-MenuItem "☕  Prendre ma pause" { Start-Break }
$miPause  = New-MenuItem "⏸  Mettre le chrono en pause" { Toggle-Pause }
$miStop   = New-MenuItem "⏹  Couper le chrono" { Stop-Cycle }
$miQuiet  = New-MenuItem "🤫  Mode silencieux (pas de blagues)" { $O.Quiet = -not $O.Quiet; Save-Settings; if ($O.Quiet) { Hide-Bubble } } -Checkable
$miWander = New-MenuItem "🚶  Balades sur les écrans" { $O.Wander = -not $O.Wander; $O.Walking = $false; Save-Settings } -Checkable
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
    $O.TaskReminders = -not $O.TaskReminders; Save-Settings
    Show-Bubble $(if ($O.TaskReminders) { "Je te rappellerai tes tâches au début et à la fin de chaque focus 🔔" } else { "Ok, plus de rappels de tâches 🔕" }) -Force -Seconds 4
} -Checkable
$miQuit   = New-MenuItem "❌  Quitter Orbit" { Quit-Orbit }
$miSettings = New-MenuItem "⚙️  Réglages…" { Open-Settings }
$miSkin = New-Object Windows.Controls.MenuItem
$miSkin.Header = "🎨  Apparence"
$skinItems = @{}
foreach ($k in $Skins.Keys) {
    $it = New-MenuItem $Skins[$k].Label ([scriptblock]::Create("Set-Skin '$k'; Save-Settings")) -Checkable
    $skinItems[$k] = $it
    [void]$miSkin.Items.Add($it)
}

foreach ($i in @($miTodo, $miClip, (New-Object Windows.Controls.Separator),
                 $miFocus, $miBreak, $miPause, $miStop, $miRhythm, $miTasks, (New-Object Windows.Controls.Separator),
                 $miSkin, $miQuiet, $miWander, $miMini, $miHome, $miHide, $miAuto, (New-Object Windows.Controls.Separator),
                 $miStats, $miSettings, $miQuit)) { [void]$menu.Items.Add($i) }

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
    foreach ($k in $skinItems.Keys) { $skinItems[$k].IsChecked = ($k -eq $O.Skin) }
    foreach ($name in $rhythmItems.Keys) {
        $r = $Rhythms[$name]
        $rhythmItems[$name].Header = "$($r.Icon)  $name  ($($r.Focus) min focus / $($r.Break) min pause)"
        $rhythmItems[$name].IsChecked = ($name -eq $O.Rhythm)
    }
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
    [void]$cms.Items.Add('Réglages…', $null, { Invoke-Safe { Open-Settings } })
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
        Set-Skin $O.Skin -Quiet
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
Set-Skin $O.Skin -Quiet
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
