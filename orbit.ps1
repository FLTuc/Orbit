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
    [switch]$Demo,
    [switch]$Restarted     # relance automatique apres un plantage
)

# Durees imposees en ligne de commande (ou mode demo) : elles priment sur le rythme choisi dans le menu
$CustomDurations = $Demo -or $PSBoundParameters.ContainsKey('FocusMinutes') -or $PSBoundParameters.ContainsKey('BreakMinutes')
if ($Demo) { $FocusMinutes = 1; $BreakMinutes = 0.5 }

$ErrorActionPreference = 'Stop'
$OrbitScript = $PSCommandPath

# ---------------------------------------------------------------------------
#  Lancement sans fenetre. Sous Windows 11, la console par defaut est Windows
#  Terminal, qui ignore « -WindowStyle Hidden » : une fenetre powershell.exe
#  resterait ouverte a cote d'Orbit. conhost.exe --headless (fourni avec
#  Windows 10 1809 et plus) execute PowerShell sans aucune fenetre.
# ---------------------------------------------------------------------------
$OrbitConhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$OrbitPowerShell = Join-Path $PSHOME 'powershell.exe'
$OrbitCanHeadless = (Test-Path -LiteralPath $OrbitConhost) -and [Environment]::OSVersion.Version.Build -ge 17763

# Lance une nouvelle copie d'Orbit, sans fenetre (redemarrage, relance apres un plantage...)
function Start-OrbitDetached([string[]]$extra = @()) {
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$OrbitScript`"") + $extra
    $env:ORBIT_HEADLESS = '1'   # herite par la nouvelle copie : elle ne se relancera pas elle-meme
    if ($OrbitCanHeadless) {
        Start-Process -FilePath $OrbitConhost -WindowStyle Hidden -ArgumentList (@('--headless', "`"$OrbitPowerShell`"") + $psArgs)
    } else {
        Start-Process -FilePath $OrbitPowerShell -WindowStyle Hidden -ArgumentList $psArgs
    }
}

# Lance dans Windows Terminal (raccourci ancien, double-clic sur orbit.ps1...) :
# on se relance sans fenetre et on se ferme, ce qui ferme aussi l'onglet du terminal
$OrbitArgs = @()
foreach ($k in $PSBoundParameters.Keys) {
    $v = $PSBoundParameters[$k]
    if ($v -is [switch]) { if ($v) { $OrbitArgs += "-$k" } } else { $OrbitArgs += "-$k"; $OrbitArgs += [string]$v }
}

# Fichiers d'Orbit re-enregistres sans BOM (copie, editeur de texte...) : PowerShell 5.1
# les lit alors en ANSI et les accents deviennent des "Ã©" au milieu des bulles.
# On remet le BOM (le texte lui-meme ne change pas) ; si orbit.ps1 etait concerne, on relance.
function Repair-ScriptEncoding([string]$dir) {
    $fixed = @()
    $strict = New-Object Text.UTF8Encoding($false, $true)
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
        try {
            $b = [IO.File]::ReadAllBytes($f.FullName)
            if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { continue }
            $t = $strict.GetString($b)                 # pas de l'UTF-8 valide : vrai ANSI, deja bien lu
            if ($t.Length -eq $b.Length) { continue }  # que de l'ASCII : rien a corriger
            [IO.File]::WriteAllText($f.FullName, $t, (New-Object Text.UTF8Encoding($true)))
            $fixed += $f.Name
        } catch {}
    }
    return , $fixed
}
$RepairedScripts = Repair-ScriptEncoding $PSScriptRoot
if ($RepairedScripts -contains 'orbit.ps1' -and -not $env:ORBIT_SELFTEST) {
    Start-OrbitDetached $OrbitArgs
    exit
}

if ($env:WT_SESSION -and -not $env:ORBIT_HEADLESS -and -not $env:ORBIT_SELFTEST -and $OrbitCanHeadless) {
    Start-OrbitDetached $OrbitArgs
    exit
}

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
    BreakLines          = $true  # petites phrases sympas pendant la pause
    BreakLineEveryMin   = 2      # une toutes les ~2 minutes de pause
    AppComments         = $true  # pendant un focus, rappel bienveillant sur un site de distraction
    Sounds              = $true
    DroidSounds         = $true  # petits bips de droide a chaque bulle
    DroidVolume         = 40     # volume des sons, de 0 a 100
    BubbleSound         = 'Droide'   # Droide | Carillon | Marimba | Pop | Bip | Fichier | Aleatoire
    BubbleSoundFiles    = @()        # ancienne liste de sons : copiee une fois dans le dossier « sons »
    EndSound            = 'Carillon' # Carillon | Windows | Fichier  (fin de session et rappels)
    EndSoundFile        = ''
    CustomImage         = ''         # apparence "Mon image"
    IdlePause           = $true  # met le focus en pause si tu t'absentes
    IdleMinutes         = 5
    MorningPlan         = $true  # le matin, propose les 3 cartes les plus urgentes
    TickSound           = $true  # zone finale du focus : un tic doux qui s'accelere jusqu'a la fin
    TickZoneMin         = 5      # ... pendant les N dernieres minutes (1 a 15)
    UrgencyBar          = $true  # barre de compte a rebours qui change de couleur, a cote d'Orbit
    IdleNudge           = $true  # aucun focus depuis un moment : Orbit propose 2-3 cartes qui attendent
    IdleNudgeMin        = 45     # ... au bout de combien de minutes sans focus
    NotesMirror         = ''     # dossier ou copier automatiquement les notes (vide = non)
    ContextButton       = $true  # bouton ✋ « Je m'interromps » a cote d'Orbit pendant un focus
    ContextWindows      = 3      # fenetres precedentes gardees en plus de la fenetre active (0 a 5)
    ContextScreenshot   = $false # petite capture d'ecran a chaque interruption
    ContextRemind       = $true  # relancer si la reprise attend
    ContextRemindMin    = 30
    AnchorButton        = $true  # boutons ronds a cote d'Orbit (📝 🚨 🗂 📒 ↩)
}
# (tous ces reglages se modifient aussi depuis clic droit > Reglages)

# Rythmes Pomodoro disponibles : focus / pause, en minutes
$Rhythms = [ordered]@{
    '50/10' = @{ Focus = 50; Break = 10; Icon = '🚀' }
    '25/5'  = @{ Focus = 25; Break = 5;  Icon = '⚡' }
    'Perso' = @{ Focus = 40; Break = 8;  Icon = '🎛' }   # modifiable dans les reglages
}

$DataDir = Join-Path $env:APPDATA 'Orbit'
$StatsFile = Join-Path $DataDir 'stats.json'
$SettingsFile = Join-Path $DataDir 'settings.json'
$LogFile = Join-Path $DataDir 'orbit.log'
# Mes sons : tous les fichiers audio poses dans ce dossier (%APPDATA%\Orbit\sons)
$SoundsDir = Join-Path $DataDir 'sons'
$SoundExt = @('.wav', '.mp3', '.m4a', '.wma')
$StateFile = Join-Path $DataDir 'etat.json'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

# Journal : au-dela de 1 Mo, il est renomme en orbit.old.log et on repart de zero
function Write-Log([string]$msg) {
    try {
        $fi = New-Object IO.FileInfo($LogFile)
        if ($fi.Exists -and $fi.Length -gt 1MB) {
            Move-Item -LiteralPath $LogFile -Destination (Join-Path $DataDir 'orbit.old.log') -Force
        }
        Add-Content -Path $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8
    } catch {}
}

if ($RepairedScripts.Count) { Write-Log "Encodage repare (BOM remis) : $($RepairedScripts -join ', ')" }

# ---------------------------------------------------------------------------
#  Texte affichable dans les bulles : pas de caractere bizarre au milieu des phrases
# ---------------------------------------------------------------------------
# Debut d'un texte sur $max caracteres au plus, sans couper un emoji en deux (un emoji
# hors BMP occupe 2 "char" en .NET : couper entre les deux laisse un caractere casse)
# ni laisser un modificateur orphelin (selecteur de variante, liant ZWJ, touche numerotee...).
function Get-TextStart([string]$text, [int]$max) {
    if ($max -le 0) { return '' }
    if ($text.Length -le $max) { return $text }
    $n = $max
    if ([char]::IsHighSurrogate($text[$n - 1])) { $n-- }
    while ($n -gt 0 -and ([int]$text[$n - 1] -in 0x200D, 0xFE0E, 0xFE0F, 0x20E3)) { $n-- }
    return $text.Substring(0, $n)
}

# Polices des bulles : Segoe UI pour le texte, puis les polices d'emoji et de symboles.
$BubbleFonts = 'Segoe UI', 'Segoe UI Emoji', 'Segoe UI Symbol'
$script:GlyphMaps = $null
$script:GlyphOk = @{}
function Test-Glyph([int]$cp) {
    if ($null -eq $script:GlyphMaps) {
        $maps = New-Object System.Collections.ArrayList
        try {
            foreach ($name in $BubbleFonts) {
                foreach ($tf in (New-Object Windows.Media.FontFamily($name)).GetTypefaces()) {
                    $gt = $null
                    if ($tf.TryGetGlyphTypeface([ref]$gt)) { [void]$maps.Add($gt.CharacterToGlyphMap); break }
                }
            }
        } catch {}
        $script:GlyphMaps = $maps
    }
    if ($script:GlyphMaps.Count -eq 0) { return $true }   # polices introuvables : on ne filtre pas
    if (-not $script:GlyphOk.ContainsKey($cp)) {
        $ok = $false
        foreach ($m in $script:GlyphMaps) { if ($m.ContainsKey($cp)) { $ok = $true; break } }
        $script:GlyphOk[$cp] = $ok
    }
    return $script:GlyphOk[$cp]
}

# Nettoie un texte avant de l'afficher. WPF ne sait pas assembler les emoji composes :
# un selecteur de variante, un liant ZWJ, une teinte de peau ou un drapeau s'affichent
# sinon comme des carres ou des symboles parasites en plein milieu de la phrase.
# Les titres de fenetres et le presse-papiers apportent aussi des caracteres invisibles
# (marques de direction, controles) et parfois des moities d'emoji.
$script:TextJunk = '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u200B\u200E\u200F\u202A-\u202E\u2060\u2066-\u2069\uFE0E\uFE0F\u20E3\uFEFF\uFFFC\uFFFD]'
$script:TextCompound = '\u200D(?:[\uD800-\uDBFF][\uDC00-\uDFFF]|[\u2000-\u2BFF])?|\uD83C[\uDFFB-\uDFFF\uDDE6-\uDDFF]|\uDB40[\uDC20-\uDC7F]'
$script:TextLone = '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]'
$script:TextSymbol = '[\uD83C-\uD83E][\uDC00-\uDFFF]|[\u2190-\u2BFF]'
function ConvertTo-DisplayText([string]$text) {
    if (-not $text) { return '' }
    $t = $text -replace "`r`n?", "`n" -replace "`t", ' '
    $t = $t -replace $script:TextJunk, '' -replace $script:TextCompound, '' -replace $script:TextLone, ''
    # guillemets « » : espaces insecables, pour qu'un « ne reste jamais seul en fin de ligne
    $t = $t -replace '«[ ]+', "«$([char]0xA0)" -replace '[ ]+»', "$([char]0xA0)»"
    # symbole ou emoji absent de toutes les polices : un carre vide, on l'enleve
    if ($t -match $script:TextSymbol) {
        $t = [regex]::Replace($t, $script:TextSymbol, [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            if (Test-Glyph ([char]::ConvertToUtf32($m.Value, 0))) { $m.Value } else { '' }
        })
    }
    return ($t -replace '(?<=\S)[ ]{2,}(?=\S)', ' ').TrimEnd()
}

# Ecriture "atomique" : on ecrit un fichier a cote puis on l'echange d'un coup avec
# l'ancien. Une coupure de courant ou un plantage pendant l'ecriture laisse donc
# toujours soit l'ancienne version, soit la nouvelle, jamais un fichier a moitie ecrit.
function Write-FileSafe([string]$path, [string]$content) {
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, $content, (New-Object Text.UTF8Encoding($true)))
    if ([IO.File]::Exists($path)) {
        try { [IO.File]::Replace($tmp, $path, [NullString]::Value); return }
        catch { Write-Log "Remplacement de $([IO.Path]::GetFileName($path)) : $($_.Exception.Message)" }
    }
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

# Une seule instance a la fois
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\OrbitFocusBot', [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# Transfert depuis un autre PC : si un export (dossier « donnees ») est a cote, on le recupere
# avant de lire les reglages et les tableaux
. (Join-Path $PSScriptRoot 'transfer.ps1')
$script:ImportNote = if (-not $env:ORBIT_SELFTEST) { Invoke-PendingImport }

# ---------------------------------------------------------------------------
#  Fonctions natives (facultatives : si elles ne compilent pas, Orbit marche
#  quand meme, il perd juste les commentaires sur les applis)
# ---------------------------------------------------------------------------
$Native = $false
$NativeSrc = @'
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

    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);

    // ---- fenetres ouvertes (pour « Je m'interromps ») ----
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int v, int size);

    // Les fenetres de travail, de la plus recente a la plus ancienne (ordre d'empilement) :
    // visibles, non reduites, ni bureau, ni barre des taches, ni fenetres d'Orbit.
    // Chaque ligne : poignee|processus|classe|titre
    public static string[] RecentWindows(int max, uint exceptPid) {
        System.Collections.Generic.List<string> list = new System.Collections.Generic.List<string>();
        EnumWindows(delegate (IntPtr h, IntPtr p) {
            if (list.Count >= max) return false;
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            if (GetWindow(h, 4) != IntPtr.Zero) return true;                 // fenetre secondaire (boite de dialogue...)
            int ex = GetWindowLong(h, -20);
            if ((ex & 0x80) != 0 || (ex & 0x08) != 0) return true;           // fenetre outil, ou toujours au-dessus
            int cloaked = 0;
            if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;   // autre bureau virtuel...
            StringBuilder cls = new StringBuilder(256);
            GetClassName(h, cls, 256);
            string c = cls.ToString();
            if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return true;
            StringBuilder sb = new StringBuilder(512);
            GetWindowText(h, sb, 512);
            if (sb.Length == 0) return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (pid == exceptPid) return true;
            list.Add(h.ToInt64() + "|" + pid + "|" + c + "|" + sb.ToString());
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }

    // La fenetre existe encore et appartient toujours au meme programme
    public static bool WindowAlive(long hv, uint pid) {
        IntPtr h = new IntPtr(hv);
        if (hv == 0 || !IsWindow(h)) return false;
        uint p;
        GetWindowThreadProcessId(h, out p);
        return p == pid;
    }

    // Remet une fenetre devant (et la restaure si elle a ete reduite)
    public static bool BringToFront(long hv, uint pid) {
        if (!WindowAlive(hv, pid)) return false;
        IntPtr h = new IntPtr(hv);
        if (IsIconic(h)) ShowWindow(h, 9);
        return SetForegroundWindow(h);
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSize(IntPtr proc, IntPtr min, IntPtr max);

    // Rend a Windows la memoire dont Orbit ne se sert pas en ce moment
    public static void TrimMemory() {
        SetProcessWorkingSetSize(GetCurrentProcess(), (IntPtr)(-1), (IntPtr)(-1));
    }

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

    // ---- Autres styles de sons (meme format WAV en memoire) ----
    static byte[] Wav(double[] buf, double volume) {
        const int rate = 22050;
        System.IO.MemoryStream ms = new System.IO.MemoryStream();
        System.IO.BinaryWriter w = new System.IO.BinaryWriter(ms);
        int bytes = buf.Length * 2;
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + bytes); w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(bytes);
        foreach (double v in buf) w.Write((short)(Math.Max(-1, Math.Min(1, v * volume)) * 32767));
        w.Flush();
        return ms.ToArray();
    }

    // Bruit brun (ambiance pour se concentrer) : boucle de quelques secondes, debut et fin en fondu
    public static byte[] BrownNoise(double volume, int seconds) {
        const int rate = 22050;
        int n = rate * seconds;
        double[] buf = new double[n];
        Random rnd = new Random(7);
        double last = 0;
        for (int i = 0; i < n; i++) {
            last = (last + 0.02 * (rnd.NextDouble() * 2 - 1)) / 1.02;
            buf[i] = last * 3.5;
        }
        int fade = rate / 10;
        for (int i = 0; i < fade; i++) { double k = (double)i / fade; buf[i] *= k; buf[n - 1 - i] *= k; }
        return Wav(buf, volume);
    }

    // ajoute une note "percussive" (somme de partiels qui s'eteignent) a partir de 'start' secondes
    static void Strike(double[] buf, double start, double f, double[] ratios, double[] amps, double[] decays) {
        const int rate = 22050;
        int s0 = (int)(start * rate);
        for (int i = 0; s0 + i < buf.Length; i++) {
            double t = (double)i / rate, v = 0;
            for (int k = 0; k < ratios.Length; k++) v += amps[k] * Math.Exp(-t / decays[k]) * Math.Sin(2 * Math.PI * f * ratios[k] * t);
            double attack = Math.Min(1, t / 0.004);
            buf[s0 + i] += v * attack;
        }
    }

    // style : 0 droide doux, 1 carillon, 2 marimba, 3 pop, 4 bip, 10 fin de session (arpege de carillon)
    public static byte[] Synth(int style, int seed, double volume, bool question) {
        if (style == 0) return DroidChirp(seed, volume, question);
        Random rnd = new Random(seed);
        const int rate = 22050;
        double[] penta = { 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51 };
        double[] bellR = { 1, 2.0, 2.76, 5.4 }, bellA = { 0.6, 0.2, 0.14, 0.05 }, bellD = { 0.45, 0.22, 0.14, 0.06 };
        double[] maribR = { 1, 4.0, 9.8 }, maribA = { 0.7, 0.18, 0.05 }, maribD = { 0.22, 0.05, 0.02 };
        double[] buf;
        switch (style) {
            case 1: {
                buf = new double[(int)(rate * 0.95)];
                double f = penta[rnd.Next(3, 8)];
                Strike(buf, 0, f, bellR, bellA, bellD);
                if (question) Strike(buf, 0.14, f * 1.335, bellR, bellA, bellD);
                else if (rnd.NextDouble() < 0.5) Strike(buf, 0.13, penta[rnd.Next(2, 7)], bellR, bellA, bellD);
                break;
            }
            case 2: {
                buf = new double[(int)(rate * 0.6)];
                int notes = question ? 2 : rnd.Next(2, 4);
                double f = penta[rnd.Next(0, 5)] / 2 * 1.5;
                for (int n = 0; n < notes; n++) {
                    Strike(buf, n * 0.11, f, maribR, maribA, maribD);
                    f = question && n == notes - 2 ? f * 1.335 : penta[rnd.Next(0, 6)] / 2 * 1.5;
                }
                break;
            }
            case 3: {
                buf = new double[(int)(rate * 0.25)];
                int pops = question ? 2 : rnd.Next(1, 3);
                for (int n = 0; n < pops; n++) {
                    int s0 = (int)(n * 0.09 * rate), len = (int)(0.06 * rate);
                    bool up = question && n == pops - 1;
                    double ph = 0;
                    for (int i = 0; i < len && s0 + i < buf.Length; i++) {
                        double p = (double)i / len;
                        double f = up ? 420 * Math.Pow(2.6, p) : 1150 * Math.Pow(0.32, p);
                        ph += 2 * Math.PI * f / rate;
                        double env = Math.Min(1, i / (rate * 0.002)) * Math.Exp(-p * 3.2);
                        buf[s0 + i] += Math.Sin(ph) * env * 0.8;
                    }
                }
                break;
            }
            case 4: {
                buf = new double[(int)(rate * 0.32)];
                double[] fs = question ? new double[] { 660, 990 } : new double[] { 880 };
                for (int n = 0; n < fs.Length; n++) {
                    int s0 = (int)(n * 0.13 * rate), len = (int)(0.1 * rate);
                    for (int i = 0; i < len; i++) {
                        double env = Math.Sin(Math.PI * i / len);
                        buf[s0 + i] += Math.Sin(2 * Math.PI * fs[n] * i / rate) * env * 0.7;
                    }
                }
                break;
            }
            default: {
                buf = new double[(int)(rate * 1.5)];
                double[] arp = { 1046.50, 1318.51, 1567.98 };
                for (int n = 0; n < arp.Length; n++) Strike(buf, n * 0.16, arp[n], bellR, bellA, bellD);
                break;
            }
        }
        double peak = 0.0001;
        foreach (double v in buf) peak = Math.Max(peak, Math.Abs(v));
        for (int i = 0; i < buf.Length; i++) buf[i] = buf[i] / peak * 0.9;
        return Wav(buf, volume);
    }
}
'@

# Compiler ce code prend 1 a 2 secondes : la version compilee est gardee dans
# %APPDATA%\Orbit (native-<empreinte>.dll) et rechargee directement aux lancements
# suivants. L'empreinte change avec le code, donc une mise a jour recompile toute
# seule. Si le PC interdit de charger ce fichier, on compile en memoire comme avant.
function Import-NativeCode {
    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = [Text.Encoding]::UTF8.GetBytes($NativeSrc + '|' + [Environment]::Version + '|' + [IntPtr]::Size)
    $hash = (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })).Substring(0, 16)
    $dll = Join-Path $DataDir "native-$hash.dll"
    if (Test-Path -LiteralPath $dll) {
        try { Add-Type -Path $dll } catch {
            Write-Log "Cache natif illisible, recompilation : $($_.Exception.Message)"
            Remove-Item -LiteralPath $dll -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not ('OrbitNative' -as [type])) {
        try {
            Add-Type -Language CSharp -TypeDefinition $NativeSrc -OutputAssembly $dll -OutputType Library
            if (-not ('OrbitNative' -as [type])) { Add-Type -Path $dll }
        } catch {
            Write-Log "Cache natif impossible : $($_.Exception.Message)"
            Remove-Item -LiteralPath $dll -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not ('OrbitNative' -as [type])) { Add-Type -Language CSharp -TypeDefinition $NativeSrc }
    # menage des anciennes versions
    Get-ChildItem -Path $DataDir -Filter 'native-*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "native-$hash.dll" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

try {
    Import-NativeCode
    $Native = $true
    if (-not $env:ORBIT_SELFTEST) { [OrbitNative]::HideConsole() }
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
        "Décollage ! On se retrouve dans {0} minutes 🛰"
    )
    Motivation = @(
        "Tu avances bien, continue comme ça 💪",
        "Une tâche à la fois. Tu gères.",
        "Les notifications peuvent attendre. Toi, tu avances.",
        "Petit rappel : le focus, c'est ton super-pouvoir ⚡",
        "Respire un coup… et on continue 🧘",
        "Chaque minute de focus compte. Celle-ci aussi.",
        "Si c'est difficile, c'est que ça vaut le coup.",
        "Tu fais du super boulot. Si si, je vois tout d'ici 🛰",
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
        "Va prendre l'air, je garde l'écran 🛡"
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
        "Toujours là ? Je suis prêt à repartir 🛰"
    )
    Stop = @(
        "Ok, on coupe. Bien joué : {0} session(s) de focus aujourd'hui 🏆",
        "Chrono coupé. {0} session(s) aujourd'hui, respect 🙌"
    )
    # pendant la pause : de petites phrases sympas (ni blagues ni culture G)
    BreakLines = @(
        "Lève-toi et étire-toi un peu, ton dos te dira merci 🙆",
        "Un verre d'eau ? Ton cerveau adore ça 💧",
        "Regarde au loin quelques secondes, tes yeux respirent 👀",
        "Trois respirations lentes… voilà, c'est tout 🌬",
        "Fais rouler tes épaules, ça détend 😌",
        "Ouvre la fenêtre une minute, un peu d'air frais 🌿",
        "Profite, tu as bien bossé 🙌",
        "Une petite marche jusqu'à la machine à café ? ☕",
        "Desserre la mâchoire, relâche les épaules 😊",
        "Pense à un truc qui t'a fait sourire aujourd'hui 🙂",
        "Tu avances bien, sois fier(e) de toi ✨",
        "Rien à faire pendant la pause, c'est le principe 😌",
        "Range un objet sur ton bureau, juste un 🗂",
        "Envoie un petit message sympa à quelqu'un ? 💌",
        "Bouge un peu les mains et les poignets 🙌"
    )
    Wander = @(
        "Petite balade… 🚶",
        "Je vais voir ce qui se passe par là-bas 🔭",
        "Je me dégourdis les antennes 📡",
        "Tour d'orbite en cours… 🛰"
    )
    Poke = @(
        "Hé ! Ça chatouille 😆",
        "Je suis là, je suis là 👋",
        "Bip boup 🤖"
    )
}

# Commentaires par application (nom du processus, en minuscules)
# Pendant un focus, sur un site de distraction : un petit rappel bienveillant (pas de piques)
$TitleLines = @(
    @{ k = 'youtube';   l = @("Une vidéo ? On la garde pour la pause 😉") }
    @{ k = 'netflix';   l = @("Netflix attendra la pause, promis 🙂") }
    @{ k = 'twitch';    l = @("Le live peut attendre la pause 🎮") }
    @{ k = 'facebook';  l = @("Facebook, ce sera pour la pause 😉") }
    @{ k = 'instagram'; l = @("Insta peut attendre la pause 📸") }
    @{ k = 'tiktok';    l = @("TikTok, ce sera pour la pause 🙂") }
    @{ k = 'reddit';    l = @("Reddit peut attendre la pause 😉") }
    @{ k = 'amazon';    l = @("Les achats, après le focus 🛒") }
    @{ k = 'leboncoin'; l = @("Leboncoin, après le focus 😉") }
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
          Margin="0,0,10,127" MaxWidth="300" Visibility="Collapsed" RenderTransformOrigin="0.8,1">
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
          <ScrollViewer x:Name="BubbleScroll" VerticalScrollBarVisibility="Auto" MaxHeight="420">
            <TextBlock x:Name="BubbleText" TextWrapping="Wrap" FontFamily="Segoe UI, Segoe UI Emoji, Segoe UI Symbol"
                       FontSize="13.5" Foreground="#1E1B3A" LineHeight="19"/>
          </ScrollViewer>
          <WrapPanel x:Name="BubbleButtons" HorizontalAlignment="Right"/>
        </StackPanel>
      </Border>
      <!-- queue de bulle "parole" -->
      <Path x:Name="SpeechTail" Grid.Row="1" HorizontalAlignment="Right" Margin="0,-3.5,61,0"
            Fill="White" Stroke="#1E1B3A" StrokeThickness="2.5" StrokeLineJoin="Round"
            Data="M 0,0 Q 8,12 22,20 Q 14,9 16,0"/>
      <!-- queue de bulle "pensee" : petits ronds -->
      <Canvas x:Name="ThoughtTail" Grid.Row="1" HorizontalAlignment="Right" Width="26" Height="22"
              Margin="0,3,59,0" Visibility="Collapsed">
        <Ellipse Canvas.Left="0" Canvas.Top="0" Width="12" Height="10" Fill="White" Stroke="#1E1B3A" StrokeThickness="2.2"/>
        <Ellipse Canvas.Left="14" Canvas.Top="12" Width="7" Height="6" Fill="White" Stroke="#1E1B3A" StrokeThickness="2"/>
      </Canvas>
    </Grid>

    <Canvas x:Name="Bot" Width="120" Height="98" HorizontalAlignment="Right" VerticalAlignment="Bottom"
            Background="#01000000" Cursor="Hand" RenderTransformOrigin="1,1">
      <Canvas.RenderTransform>
        <ScaleTransform x:Name="BotScale" ScaleX="1.25" ScaleY="1.25"/>
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
        <RadialGradientBrush x:Key="OSkin" GradientOrigin="0.4,0.35" Center="0.45,0.4" RadiusX="0.7" RadiusY="0.7">
          <GradientStop Color="#F6D8BF" Offset="0"/><GradientStop Color="#EDC3A3" Offset="0.6"/><GradientStop Color="#D9A583" Offset="1"/>
        </RadialGradientBrush>
        <RadialGradientBrush x:Key="OBrainRealistic" GradientOrigin="0.38,0.25" Center="0.45,0.38" RadiusX="0.72" RadiusY="0.78">
          <GradientStop Color="#F4D8CF" Offset="0"/><GradientStop Color="#E3B2A8" Offset="0.5"/><GradientStop Color="#C68A82" Offset="0.85"/><GradientStop Color="#A9706A" Offset="1"/>
        </RadialGradientBrush>
        <LinearGradientBrush x:Key="OBrainDeep" StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#D9A39A" Offset="0"/><GradientStop Color="#A9706A" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="OTray" StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FAFBFC" Offset="0"/><GradientStop Color="#9AA3B0" Offset="1"/>
        </LinearGradientBrush>
      </Canvas.Resources>


      <Canvas x:Name="Bobber" Width="120" Height="100" RenderTransformOrigin="0.5,0.5">
        <Canvas.RenderTransform>
          <TransformGroup>
            <RotateTransform x:Name="Tilt" Angle="0"/>
            <RotateTransform x:Name="Lean" Angle="0"/>
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

        <!-- ecran du chrono -->
        <Border x:Name="SClockBox" Canvas.Left="42" Canvas.Top="53.6" Width="36" Height="13.8" CornerRadius="1.6" Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="0.8"><TextBlock x:Name="SClock" Text="▶ FOCUS" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="7.56" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>

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
          <Canvas.RenderTransform><ScaleTransform CenterX="60" CenterY="88" ScaleX="1.25" ScaleY="1.25"/></Canvas.RenderTransform>
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
          <Border x:Name="DClockBox" Canvas.Left="45.6" Canvas.Top="56.6" Width="28.8" Height="11.04" CornerRadius="1.4" Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="0.7"><TextBlock x:Name="DClock" Text="▶ FOCUS" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="6.05" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
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
          <Path Data="M 50,79 L 56,79 L 55,84 L 51,84 Z" Fill="{StaticResource ODark}"/>
          <Path Data="M 64,79 L 70,79 L 69,84 L 65,84 Z" Fill="{StaticResource ODark}"/>
          <Ellipse x:Name="DJet1" Canvas.Left="51.00" Canvas.Top="84.30" Width="4.00" Height="2.40" Fill="#7FD8FF"/>
          <Ellipse x:Name="DJet2" Canvas.Left="65.00" Canvas.Top="84.30" Width="4.00" Height="2.40" Fill="#7FD8FF"/>
        </Canvas>

        <!-- ===== Apparence 3 : robot assistant ===== -->
        <Canvas x:Name="SkinRobot" Visibility="Collapsed">
          <Canvas.RenderTransform><ScaleTransform CenterX="60" CenterY="88" ScaleX="1.1" ScaleY="1.1"/></Canvas.RenderTransform>
          <Ellipse x:Name="RGlow" Canvas.Left="38.00" Canvas.Top="81.00" Width="44.00" Height="14.00" Fill="{StaticResource OGlow}" Opacity="0.8"/>
          <Rectangle Canvas.Left="30" Canvas.Top="58" Width="12" Height="9" RadiusX="4" RadiusY="4" Fill="{StaticResource OMetalV}" Stroke="#4A5260" StrokeThickness="0.9"/>
          <Rectangle Canvas.Left="78" Canvas.Top="58" Width="12" Height="9" RadiusX="4" RadiusY="4" Fill="{StaticResource OMetalV}" Stroke="#4A5260" StrokeThickness="0.9"/>
          <Path Data="M 33,67 L 31,79" Stroke="#7F8A99" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Path Data="M 87,67 L 89,79" Stroke="#7F8A99" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="28.40" Canvas.Top="78.40" Width="5.20" Height="5.20" Fill="#4D5766"/>
          <Ellipse Canvas.Left="86.40" Canvas.Top="78.40" Width="5.20" Height="5.20" Fill="#4D5766"/>
          <Path Data="M 40,56 L 80,56 L 77,84 L 43,84 Z" Fill="{StaticResource OMetal}" Stroke="#4A5260" StrokeThickness="1"/>
          <Path Data="M 42.5,59.5 L 77.5,59.5 L 76,73.5 L 44,73.5 Z" Fill="#1B2330" Stroke="#3A4556" StrokeThickness="0.7"/>
          <Rectangle x:Name="RBit0" Canvas.Left="70.0" Canvas.Top="56.6" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit1" Canvas.Left="65.7" Canvas.Top="56.6" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit2" Canvas.Left="61.4" Canvas.Top="56.6" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit3" Canvas.Left="57.1" Canvas.Top="56.6" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit4" Canvas.Left="52.8" Canvas.Top="56.6" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Rectangle x:Name="RBit5" Canvas.Left="48.5" Canvas.Top="56.6" Width="2.8" Height="2.6" RadiusX="0.4" RadiusY="0.4" Fill="#2A3442"/>
          <Border x:Name="RClockBox" Canvas.Left="43.64" Canvas.Top="60.2" Width="32.73" Height="12.55" CornerRadius="1" Background="#00000000" BorderBrush="#5FD3FF" BorderThickness="0"><TextBlock x:Name="RClock" Text="▶ FOCUS" Foreground="#5FD3FF" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="6.87" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Rectangle Canvas.Left="43.5" Canvas.Top="76" Width="33" Height="2.2" Fill="{StaticResource OStripe}"/>
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
          <Canvas.RenderTransform><ScaleTransform CenterX="60" CenterY="88" ScaleX="1.05" ScaleY="1.05"/></Canvas.RenderTransform>
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
          <Ellipse Canvas.Left="80.50" Canvas.Top="51.50" Width="34.00" Height="5.00" Fill="{StaticResource OTray}" Stroke="#7F8A99" StrokeThickness="0.6"/>
          <Border x:Name="MClockBox" Canvas.Left="80.4" Canvas.Top="38.86" Width="34.29" Height="13.14" CornerRadius="1.3" Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="0.7"><TextBlock x:Name="MClock" Text="▶ FOCUS" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="7.2" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
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
          <!-- tasse de cafe tenue dans la main gauche (au premier plan) -->
          <Ellipse Canvas.Left="39.80" Canvas.Top="65.40" Width="8.40" Height="2.00" Fill="{StaticResource OTray}" Stroke="#7F8A99" StrokeThickness="0.4"/><Path Data="M 41.6,61.6 L 46.4,61.6 L 45.9,65.8 L 42.1,65.8 Z" Fill="White" Stroke="#AEB6C2" StrokeThickness="0.5"/>
          <Path Data="M 46.3,62.4 Q 48.4,63.2 46,65" Stroke="#AEB6C2" StrokeThickness="0.6"/>
          <Path x:Name="MSteam" Data="M 43,60.6 Q 42.3,58.8 43.3,57.2 M 45,60.6 Q 44.3,58.4 45.3,56.8" Stroke="#C9D0D9" StrokeThickness="0.55" Opacity="0.8"/>
        </Canvas>

        <!-- ===== Apparence 7 : ton image telle quelle, chrono en dessous ===== -->
        <Canvas x:Name="SkinCustom" Visibility="Collapsed">
          <Image x:Name="CustomImg" Width="120" Height="72" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
          <Border x:Name="UClockBox" Canvas.Left="42" Canvas.Top="74" Width="36" Height="13.8" CornerRadius="2.5" Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="1"><TextBlock x:Name="UClock" Text="▶ FOCUS" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="7.56" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        </Canvas>

        <!-- ===== Apparence 6 : majordome humain ===== -->
        <Canvas x:Name="SkinHuman" Visibility="Collapsed">
          <Canvas.RenderTransform><ScaleTransform CenterX="60" CenterY="88" ScaleX="1.1" ScaleY="1.1"/></Canvas.RenderTransform>
          <Ellipse Canvas.Left="43.00" Canvas.Top="85.40" Width="34.00" Height="5.20" Fill="#33000000"/>
          <Path Data="M 41,49 L 36,62 L 44,68" Stroke="#1A2540" StrokeThickness="4.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Path Data="M 36.5,60 L 41.5,61 L 40.5,73 L 35,71 Z" Fill="#F4F6F9" Stroke="#C9D0D9" StrokeThickness="0.5"/>
          <Ellipse Canvas.Left="42.80" Canvas.Top="65.80" Width="4.40" Height="4.40" Fill="White" Stroke="#D5DAE1" StrokeThickness="0.4"/>
          <Path Data="M 79,49 L 86,60 L 95,57" Stroke="#1A2540" StrokeThickness="4.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="93.80" Canvas.Top="54.30" Width="4.40" Height="4.40" Fill="White" Stroke="#D5DAE1" StrokeThickness="0.4"/>
          <Ellipse Canvas.Left="80.50" Canvas.Top="51.50" Width="34.00" Height="5.00" Fill="{StaticResource OTray}" Stroke="#7F8A99" StrokeThickness="0.6"/>
          <Border x:Name="HClockBox" Canvas.Left="81.4" Canvas.Top="39.45" Width="32.73" Height="12.55" CornerRadius="1.3" Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="0.7"><TextBlock x:Name="HClock" Text="▶ FOCUS" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="6.87" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Path Data="M 41,46 Q 60,42 79,46 L 80,72 L 74,82 L 66,72 L 54,72 L 46,82 L 40,72 Z" Fill="{StaticResource OCoat}" Stroke="#0A0F1A" StrokeThickness="0.8"/>
          <Path Data="M 52.5,45 L 67.5,45 L 60,71 Z" Fill="#F4F6F9" Stroke="#C9D0D9" StrokeThickness="0.5"/>
          <Path Data="M 52.5,45 L 60,71 L 49,56 Z" Fill="#26355A" Stroke="#0A0F1A" StrokeThickness="0.5"/>
          <Path Data="M 67.5,45 L 60,71 L 71,56 Z" Fill="#26355A" Stroke="#0A0F1A" StrokeThickness="0.5"/>
          <Path x:Name="HPocket" Data="M 70,57.5 L 75,57.5 L 73.5,60.5 L 72.5,59 L 71.5,60.5 Z" Fill="#4C8DFF"/>
          <Line X1="69.5" Y1="60.6" X2="75.5" Y2="60.6" Stroke="#0A0F1A" StrokeThickness="0.7"/>
          <Ellipse x:Name="HBit0" Canvas.Left="58.90" Canvas.Top="65.90" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="HBit1" Canvas.Left="58.90" Canvas.Top="62.70" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="HBit2" Canvas.Left="58.90" Canvas.Top="59.50" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="HBit3" Canvas.Left="58.90" Canvas.Top="56.30" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="HBit4" Canvas.Left="58.90" Canvas.Top="53.10" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Ellipse x:Name="HBit5" Canvas.Left="58.90" Canvas.Top="49.90" Width="2.20" Height="2.20" Fill="#2A3442"/>
          <Rectangle Canvas.Left="56.5" Canvas.Top="37.5" Width="7" Height="6.5" Fill="{StaticResource OSkin}"/>
          <Path Data="M 54,43.5 L 60,46 L 66,43.5 L 65,41.5 L 60,43.5 L 55,41.5 Z" Fill="White" Stroke="#C9D0D9" StrokeThickness="0.4"/>
          <Path Data="M 54.5,44 L 59.2,46 L 54.5,48 Z" Fill="#111722"/>
          <Path Data="M 65.5,44 L 60.8,46 L 65.5,48 Z" Fill="#111722"/>
          <Rectangle Canvas.Left="58.6" Canvas.Top="44.9" Width="2.8" Height="2.2" RadiusX="0.6" RadiusY="0.6" Fill="#2B323D"/>
          <Ellipse Canvas.Left="45.40" Canvas.Top="23.20" Width="4.40" Height="6.60" Fill="#E2AE8C"/>
          <Ellipse Canvas.Left="70.20" Canvas.Top="23.20" Width="4.40" Height="6.60" Fill="#E2AE8C"/>
          <Ellipse Canvas.Left="48.00" Canvas.Top="11.50" Width="24.00" Height="28.00" Fill="{StaticResource OSkin}" Stroke="#C9967A" StrokeThickness="0.5"/>
          <Path Data="M 48.2,23.5 C 46.5,13 53,9.4 60,9.6 C 67.5,9.4 74,13 71.8,23.5 C 70.8,18.5 68,16 63.5,15.6 C 59,17.3 54.5,15.8 51.2,18.2 C 49.4,19.6 48.6,21.4 48.2,23.5 Z" Fill="#B9BFC7"/>
          <Path Data="M 52,13.2 C 55,12 58,12.4 60.5,14.2 M 62,11.6 C 65.5,11.4 69,13 70.6,16.4 M 54,15.4 C 56,14.6 58,15 59.5,16" Stroke="#8E959E" StrokeThickness="0.45"/>
          <Path Data="M 52.4,21 Q 55,19.6 57.6,20.8 M 62.4,20.8 Q 65,19.6 67.6,21" Stroke="#8E959E" StrokeThickness="0.9" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="52.60" Canvas.Top="22.80" Width="4.80" Height="3.20" Fill="White" Stroke="#C9967A" StrokeThickness="0.3"/>
          <Ellipse Canvas.Left="62.60" Canvas.Top="22.80" Width="4.80" Height="3.20" Fill="White" Stroke="#C9967A" StrokeThickness="0.3"/>
          <Ellipse x:Name="HEyeL" Canvas.Left="53.95" Canvas.Top="23.35" Width="2.10" Height="2.10" Fill="#3B5876"/>
          <Ellipse x:Name="HEyeR" Canvas.Left="63.95" Canvas.Top="23.35" Width="2.10" Height="2.10" Fill="#3B5876"/>
          <Ellipse x:Name="HGlintL" Canvas.Left="54.25" Canvas.Top="23.65" Width="0.70" Height="0.70" Fill="White"/>
          <Ellipse x:Name="HGlintR" Canvas.Left="64.25" Canvas.Top="23.65" Width="0.70" Height="0.70" Fill="White"/>
          <Path Data="M 60,24.5 C 59.2,28 58.6,29.6 60.8,30.2" Stroke="#BF8A6C" StrokeThickness="0.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Path Data="M 60,31.4 Q 56,30.6 53.2,33.2 Q 56.6,34 60,32.8 Q 63.4,34 66.8,33.2 Q 64,30.6 60,31.4 Z" Fill="#A3AAB3"/>
          <Path Data="M 57.2,35.6 Q 60,37 62.8,35.6" Stroke="#A86B57" StrokeThickness="0.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
          <Ellipse Canvas.Left="50.40" Canvas.Top="29.20" Width="4.40" Height="2.60" Fill="#33E58F7A"/>
          <Ellipse Canvas.Left="65.20" Canvas.Top="29.20" Width="4.40" Height="2.60" Fill="#33E58F7A"/>
          <!-- tasse de cafe tenue dans la main gauche (au premier plan) -->
          <Ellipse Canvas.Left="39.80" Canvas.Top="65.40" Width="8.40" Height="2.00" Fill="{StaticResource OTray}" Stroke="#7F8A99" StrokeThickness="0.4"/><Path Data="M 41.6,61.6 L 46.4,61.6 L 45.9,65.8 L 42.1,65.8 Z" Fill="White" Stroke="#AEB6C2" StrokeThickness="0.5"/>
          <Path Data="M 46.3,62.4 Q 48.4,63.2 46,65" Stroke="#AEB6C2" StrokeThickness="0.6"/>
          <Path x:Name="HSteam" Data="M 43,60.6 Q 42.3,58.8 43.3,57.2 M 45,60.6 Q 44.3,58.4 45.3,56.8" Stroke="#C9D0D9" StrokeThickness="0.55" Opacity="0.8"/>
        </Canvas>

        <!-- ===== Apparence 5 : cerveau augmente (plaque chromee, circuits, oeil bionique) ===== -->
        <Canvas x:Name="SkinBrain" Visibility="Collapsed">
          <Canvas.RenderTransform><ScaleTransform CenterX="60" CenterY="88" ScaleX="1.1" ScaleY="1.1"/></Canvas.RenderTransform>
          <Ellipse Canvas.Left="39.00" Canvas.Top="87.40" Width="42.00" Height="4.80" Fill="#38000000"/>
          <Rectangle Canvas.Left="38" Canvas.Top="70" Width="44" Height="17.5" RadiusX="4" RadiusY="4" Fill="{StaticResource OMetalV}" Stroke="#4A5260" StrokeThickness="1"/>
          <Rectangle x:Name="CRing" Canvas.Left="40" Canvas.Top="86.2" Width="40" Height="0.6" RadiusX="0.5" RadiusY="0.5" Fill="#5FD3FF" Opacity="0.85"/>
          <Rectangle Canvas.Left="57.8" Canvas.Top="66.5" Width="4.4" Height="4.2" Fill="{StaticResource ODark}"/>
          <Path Data="M 63.2,58.5 C 65.6,62 65.4,65.6 63.6,68.8 L 59,68.8 C 60.2,65.4 60.2,62.4 59,59.4 Z" Fill="{StaticResource OBrainDeep}" Stroke="#8E5751" StrokeThickness="0.7"/>
          <Path Data="M 70,58 C 74,55 84,54 89,57 C 92,61 88,67 80,67 C 74,67 70,63 70,58 Z" Fill="{StaticResource OBrainDeep}" Stroke="#8E5751" StrokeThickness="0.8"/>
          <Path Data="M 71.0,57.8 C 76,56.6 83,56.4 89.5,57.6 M 71.2,59.3 C 76,58.1 83,57.9 89.1,59.1 M 71.4,60.8 C 76,59.6 83,59.4 88.7,60.6 M 71.6,62.3 C 76,61.1 83,60.9 88.3,62.1 M 71.8,63.8 C 76,62.6 83,62.4 87.9,63.6 M 72.0,65.3 C 76,64.1 83,63.9 87.5,65.1" Stroke="#8A4D49" StrokeThickness="0.45" Opacity="0.7"/>
          <Path Data="M 30,46 C 28,34 36,22 49,19 C 57,13 71,13 80,17 C 90,21 95,31 93,41 C 93,47 90,51 86,53 C 84,57 80,59 75,58 C 72,61 66,61 62,59 C 57,62 49,62 44,59 C 37,58 31,53 30,46 Z" Fill="{StaticResource OBrainRealistic}" Stroke="#8E5751" StrokeThickness="0.9"/>
          <!-- circonvolutions fines (generees) : relief clair puis sillon sombre -->
          <Path Canvas.Left="-0.5" Canvas.Top="-0.5" Data="M 63.4,18.3 Q 62.3,16.8 63.7,15.7 M 67.1,17.2 Q 66.6,18.9 64.8,19.0 Q 66.4,20.0 65.4,21.6 Q 64.4,23.1 65.8,24.3 M 47.8,21.9 Q 46.4,22.5 46.5,24.1 Q 47.4,25.2 46.6,26.3 Q 45.1,27.4 45.6,29.1 M 53.7,20.9 Q 54.9,21.7 56.0,20.7 Q 57.4,21.0 58.2,19.8 Q 59.2,18.1 60.8,19.1 M 60.0,20.4 Q 58.5,20.6 57.7,19.2 Q 56.8,20.3 55.4,19.8 Q 54.0,20.7 53.9,22.4 M 67.2,22.3 Q 65.9,21.0 67.0,19.6 Q 68.9,19.9 69.7,18.2 Q 71.3,18.3 72.0,16.9 M 69.8,20.2 Q 70.9,18.8 72.3,19.8 Q 73.7,20.5 73.7,22.2 Q 73.6,24.1 75.6,23.7 M 75.3,20.9 Q 73.7,21.7 74.2,23.4 Q 73.8,25.2 75.6,25.2 Q 76.8,26.4 76.0,27.9 M 43.8,25.7 Q 45.3,26.2 45.2,27.7 Q 46.6,29.1 45.2,30.4 Q 45.3,32.2 47.1,32.3 M 48.2,26.4 Q 47.9,24.7 49.6,24.2 Q 49.2,22.5 50.8,22.0 Q 51.8,20.2 53.6,21.2 M 55.6,24.2 Q 56.3,22.4 58.1,23.3 Q 60.2,23.5 60.7,21.4 Q 59.9,20.2 60.8,19.2 M 59.3,24.9 Q 60.0,23.1 58.3,22.3 Q 57.2,21.2 57.8,19.8 Q 57.2,17.9 58.9,17.0 M 64.2,24.8 Q 65.2,23.3 64.3,21.8 Q 65.9,21.4 66.0,19.7 Q 67.1,18.1 65.3,17.2 M 67.5,25.9 Q 65.7,25.1 66.1,23.2 Q 64.5,22.0 63.4,23.6 Q 61.7,23.7 61.0,22.2 M 70.9,25.6 Q 70.3,23.8 68.6,24.6 Q 67.1,24.8 66.6,23.4 Q 65.1,22.8 64.7,24.5 M 75.7,26.2 Q 74.9,27.9 73.1,27.1 Q 71.5,26.3 70.5,27.8 Q 69.0,26.5 68.1,28.2 M 80.1,24.2 Q 78.5,24.2 78.0,25.7 Q 76.7,27.1 78.3,28.1 Q 79.2,29.6 81.0,29.6 M 84.1,26.3 Q 83.9,28.1 85.5,29.1 Q 86.2,31.2 88.1,30.2 Q 89.2,31.5 90.7,30.7 M 56.2,29.9 Q 54.5,29.1 54.0,30.9 Q 55.2,32.0 54.0,33.2 Q 53.6,34.9 52.0,34.1 M 61.8,30.0 Q 60.3,28.9 59.3,30.4 Q 57.6,31.4 57.2,29.5 Q 55.5,28.9 55.0,30.6 M 70.8,29.5 Q 69.5,30.5 67.9,29.9 Q 66.4,31.2 64.9,30.0 Q 63.5,28.9 62.5,30.4 M 75.1,30.1 Q 75.0,28.4 76.6,28.1 Q 77.6,26.5 79.4,26.9 Q 78.7,25.6 79.5,24.4 M 79.4,30.1 Q 78.2,28.6 77.1,30.1 Q 76.6,32.0 74.7,31.6 Q 73.3,32.5 74.3,33.8 M 88.3,29.1 Q 88.3,31.0 89.9,31.9 M 33.9,33.9 Q 34.4,35.6 36.1,35.5 Q 37.9,35.6 37.7,37.4 Q 36.0,38.4 36.9,40.2 M 39.6,33.0 Q 39.5,35.0 41.5,35.1 Q 42.8,33.6 44.5,34.9 Q 46.0,35.5 46.1,37.2 M 48.3,32.7 Q 49.5,33.8 48.3,34.9 Q 48.4,36.6 46.7,36.5 Q 45.3,35.2 44.5,36.8 M 52.0,32.3 Q 53.6,31.7 53.0,30.0 Q 54.8,29.4 53.9,27.6 Q 53.9,25.7 55.8,25.6 M 59.5,33.3 Q 61.4,33.4 61.4,35.3 Q 62.5,36.8 64.2,36.0 Q 64.5,34.3 66.2,34.2 M 66.4,31.8 Q 67.0,30.0 65.6,28.7 Q 63.8,28.6 63.0,27.0 Q 62.0,25.4 63.5,24.3 M 79.0,34.1 Q 78.5,32.5 76.9,32.9 Q 75.8,31.5 74.1,32.1 Q 72.1,32.6 72.5,34.7 M 87.6,34.1 Q 88.7,35.4 87.7,36.7 Q 89.3,37.2 89.2,38.8 Q 90.4,39.8 89.6,41.1 M 36.3,38.1 Q 37.5,36.6 39.1,37.8 Q 39.5,39.4 41.1,38.8 Q 40.4,40.1 41.3,41.2 M 40.2,36.0 Q 38.5,35.9 38.3,37.6 Q 36.7,37.8 36.5,39.2 Q 35.7,41.0 37.2,42.0 M 47.7,36.8 Q 47.2,38.3 45.6,38.1 Q 44.0,39.2 43.2,37.4 Q 41.7,36.0 40.2,37.3 M 55.7,37.0 Q 54.3,36.5 54.2,34.9 Q 53.7,33.1 51.8,33.0 Q 50.7,31.9 51.5,30.5 M 58.8,37.7 Q 58.2,35.9 59.8,34.7 Q 61.8,35.5 62.6,33.5 Q 61.9,32.1 63.0,31.1 M 64.3,35.9 Q 65.9,36.5 67.2,35.3 Q 66.3,33.8 67.4,32.4 Q 69.5,31.7 68.8,29.6 M 67.4,37.1 Q 65.9,38.4 67.0,40.0 Q 68.6,41.2 67.4,42.8 Q 66.4,43.9 67.5,45.0 M 70.5,38.0 Q 71.9,39.4 70.3,40.7 Q 71.8,41.6 71.5,43.3 Q 72.6,44.8 71.6,46.4 M 75.5,38.2 Q 75.1,39.7 76.7,40.1 Q 78.3,41.1 79.2,39.4 Q 78.9,37.7 80.5,37.0 M 82.2,37.7 Q 83.3,39.7 81.4,40.8 Q 80.4,42.6 78.8,41.4 Q 78.1,42.7 76.7,42.5 M 42.1,41.4 Q 40.4,40.5 39.6,42.3 Q 38.6,43.8 36.8,43.8 Q 36.9,45.5 35.2,45.7 M 47.7,40.7 Q 48.2,39.2 49.7,39.1 Q 51.2,38.5 51.2,36.9 Q 52.5,35.6 53.7,37.0 M 54.7,40.7 Q 55.8,42.4 54.1,43.6 Q 53.4,45.3 54.8,46.6 Q 56.1,48.4 57.9,47.2 M 58.4,41.6 Q 57.9,40.0 59.0,38.7 Q 60.7,37.7 59.3,36.3 Q 59.9,34.4 58.0,34.0 M 62.0,41.0 Q 62.8,39.1 64.8,39.6 Q 66.7,39.5 66.3,37.6 Q 68.3,37.4 68.1,35.4 M 74.5,42.3 Q 73.9,40.6 75.2,39.2 Q 76.6,40.1 77.8,39.0 Q 78.7,37.5 80.1,38.6 M 80.0,41.5 Q 81.2,42.9 82.9,42.1 Q 83.7,40.6 85.4,40.6 Q 85.0,39.0 86.5,38.4 M 87.0,40.2 Q 88.5,39.6 89.9,40.5 M 90.9,40.6 Q 89.0,40.1 90.0,38.4 Q 91.7,38.0 91.4,36.2 M 35.6,44.6 Q 37.0,44.0 37.1,42.5 Q 38.7,41.3 40.0,42.9 Q 41.4,43.5 42.5,42.3 M 43.0,44.7 Q 41.0,44.3 41.3,42.4 Q 40.6,40.7 38.9,41.5 Q 37.2,41.6 37.1,43.3 M 65.9,45.2 Q 67.4,46.4 66.6,48.1 Q 66.4,50.0 64.5,50.0 Q 63.0,51.1 61.4,50.4 M 70.4,45.1 Q 70.9,43.6 72.4,44.0 Q 73.3,42.3 72.1,40.9 Q 71.0,39.2 72.8,38.2 M 75.3,45.9 Q 76.4,47.6 78.2,46.7 Q 79.6,46.2 80.5,47.3 Q 82.3,47.0 83.0,45.3 M 84.1,43.7 Q 82.4,44.2 82.1,45.9 Q 80.2,45.7 79.9,47.6 Q 78.3,48.5 79.3,50.0 M 89.7,45.3 Q 89.5,43.4 87.7,43.9 Q 86.0,44.2 84.9,42.9 Q 83.1,42.8 82.9,44.6 M 34.0,50.2 Q 33.9,52.1 35.8,52.4 Q 36.7,50.4 38.6,51.4 Q 40.3,51.2 41.2,52.7 M 47.5,49.6 Q 46.4,51.0 47.2,52.6 Q 47.1,54.4 48.6,55.4 Q 48.9,57.2 47.1,57.6 M 51.3,48.3 Q 49.6,48.6 50.1,50.3 Q 49.8,52.1 51.2,53.3 Q 49.6,54.6 51.2,56.0 M 54.9,49.1 Q 54.3,47.1 52.2,47.5 Q 51.2,46.0 49.7,46.9 Q 49.7,45.3 48.1,44.9 M 59.3,50.3 Q 58.2,51.9 59.9,52.9 Q 60.3,54.9 62.2,54.7 Q 63.8,54.8 64.3,56.4 M 62.2,49.4 Q 63.0,48.0 64.4,48.9 Q 66.2,49.4 66.8,47.7 Q 68.1,48.4 69.2,47.4 M 65.6,49.8 Q 64.1,51.1 63.0,49.4 Q 61.4,48.0 60.1,49.7 Q 60.1,48.0 58.4,48.1 M 71.2,49.3 Q 70.8,50.8 69.3,51.1 Q 69.3,52.8 67.8,53.4 Q 69.3,54.4 69.2,56.2 M 79.0,49.4 Q 80.2,48.1 78.8,47.0 Q 80.7,46.3 80.3,44.2 Q 81.5,44.8 82.4,43.8 M 83.4,48.1 Q 85.0,47.5 85.7,48.9 M 39.4,54.3 Q 40.8,56.0 42.5,54.6 Q 42.8,52.6 44.8,52.7 Q 45.6,54.3 47.2,53.5 M 42.7,54.0 Q 43.7,55.7 45.6,55.2 Q 45.6,53.4 47.3,53.1 Q 49.4,53.2 49.5,51.2 M 46.7,53.2 Q 46.5,54.7 45.1,54.9 M 50.0,51.7 Q 52.0,51.4 52.4,53.3 Q 52.4,54.8 53.9,55.0 Q 56.0,55.4 55.8,57.6 M 55.7,53.6 Q 56.5,54.9 55.5,56.0 Q 55.3,58.1 53.2,58.0 M 63.7,52.2 Q 63.6,54.2 65.6,54.0 Q 64.4,55.3 65.9,56.2 Q 64.9,57.8 66.5,59.0 M 70.8,53.8 Q 70.9,55.8 68.9,56.0 Q 67.2,56.2 66.6,57.9 M 75.7,54.3 Q 77.1,52.8 78.4,54.4 M 79.0,53.2 Q 79.2,55.1 77.4,55.8 M 55.7,57.7 Q 53.9,58.5 53.4,56.6 Q 52.9,55.0 51.3,55.0 Q 50.1,54.0 50.6,52.5 M 66.0,56.0 Q 67.0,57.3 65.9,58.6" Stroke="#FFF3EE" StrokeThickness="0.45" Opacity="0.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          <Path Data="M 63.4,18.3 Q 62.3,16.8 63.7,15.7 M 67.1,17.2 Q 66.6,18.9 64.8,19.0 Q 66.4,20.0 65.4,21.6 Q 64.4,23.1 65.8,24.3 M 47.8,21.9 Q 46.4,22.5 46.5,24.1 Q 47.4,25.2 46.6,26.3 Q 45.1,27.4 45.6,29.1 M 53.7,20.9 Q 54.9,21.7 56.0,20.7 Q 57.4,21.0 58.2,19.8 Q 59.2,18.1 60.8,19.1 M 60.0,20.4 Q 58.5,20.6 57.7,19.2 Q 56.8,20.3 55.4,19.8 Q 54.0,20.7 53.9,22.4 M 67.2,22.3 Q 65.9,21.0 67.0,19.6 Q 68.9,19.9 69.7,18.2 Q 71.3,18.3 72.0,16.9 M 69.8,20.2 Q 70.9,18.8 72.3,19.8 Q 73.7,20.5 73.7,22.2 Q 73.6,24.1 75.6,23.7 M 75.3,20.9 Q 73.7,21.7 74.2,23.4 Q 73.8,25.2 75.6,25.2 Q 76.8,26.4 76.0,27.9 M 43.8,25.7 Q 45.3,26.2 45.2,27.7 Q 46.6,29.1 45.2,30.4 Q 45.3,32.2 47.1,32.3 M 48.2,26.4 Q 47.9,24.7 49.6,24.2 Q 49.2,22.5 50.8,22.0 Q 51.8,20.2 53.6,21.2 M 55.6,24.2 Q 56.3,22.4 58.1,23.3 Q 60.2,23.5 60.7,21.4 Q 59.9,20.2 60.8,19.2 M 59.3,24.9 Q 60.0,23.1 58.3,22.3 Q 57.2,21.2 57.8,19.8 Q 57.2,17.9 58.9,17.0 M 64.2,24.8 Q 65.2,23.3 64.3,21.8 Q 65.9,21.4 66.0,19.7 Q 67.1,18.1 65.3,17.2 M 67.5,25.9 Q 65.7,25.1 66.1,23.2 Q 64.5,22.0 63.4,23.6 Q 61.7,23.7 61.0,22.2 M 70.9,25.6 Q 70.3,23.8 68.6,24.6 Q 67.1,24.8 66.6,23.4 Q 65.1,22.8 64.7,24.5 M 75.7,26.2 Q 74.9,27.9 73.1,27.1 Q 71.5,26.3 70.5,27.8 Q 69.0,26.5 68.1,28.2 M 80.1,24.2 Q 78.5,24.2 78.0,25.7 Q 76.7,27.1 78.3,28.1 Q 79.2,29.6 81.0,29.6 M 84.1,26.3 Q 83.9,28.1 85.5,29.1 Q 86.2,31.2 88.1,30.2 Q 89.2,31.5 90.7,30.7 M 56.2,29.9 Q 54.5,29.1 54.0,30.9 Q 55.2,32.0 54.0,33.2 Q 53.6,34.9 52.0,34.1 M 61.8,30.0 Q 60.3,28.9 59.3,30.4 Q 57.6,31.4 57.2,29.5 Q 55.5,28.9 55.0,30.6 M 70.8,29.5 Q 69.5,30.5 67.9,29.9 Q 66.4,31.2 64.9,30.0 Q 63.5,28.9 62.5,30.4 M 75.1,30.1 Q 75.0,28.4 76.6,28.1 Q 77.6,26.5 79.4,26.9 Q 78.7,25.6 79.5,24.4 M 79.4,30.1 Q 78.2,28.6 77.1,30.1 Q 76.6,32.0 74.7,31.6 Q 73.3,32.5 74.3,33.8 M 88.3,29.1 Q 88.3,31.0 89.9,31.9 M 33.9,33.9 Q 34.4,35.6 36.1,35.5 Q 37.9,35.6 37.7,37.4 Q 36.0,38.4 36.9,40.2 M 39.6,33.0 Q 39.5,35.0 41.5,35.1 Q 42.8,33.6 44.5,34.9 Q 46.0,35.5 46.1,37.2 M 48.3,32.7 Q 49.5,33.8 48.3,34.9 Q 48.4,36.6 46.7,36.5 Q 45.3,35.2 44.5,36.8 M 52.0,32.3 Q 53.6,31.7 53.0,30.0 Q 54.8,29.4 53.9,27.6 Q 53.9,25.7 55.8,25.6 M 59.5,33.3 Q 61.4,33.4 61.4,35.3 Q 62.5,36.8 64.2,36.0 Q 64.5,34.3 66.2,34.2 M 66.4,31.8 Q 67.0,30.0 65.6,28.7 Q 63.8,28.6 63.0,27.0 Q 62.0,25.4 63.5,24.3 M 79.0,34.1 Q 78.5,32.5 76.9,32.9 Q 75.8,31.5 74.1,32.1 Q 72.1,32.6 72.5,34.7 M 87.6,34.1 Q 88.7,35.4 87.7,36.7 Q 89.3,37.2 89.2,38.8 Q 90.4,39.8 89.6,41.1 M 36.3,38.1 Q 37.5,36.6 39.1,37.8 Q 39.5,39.4 41.1,38.8 Q 40.4,40.1 41.3,41.2 M 40.2,36.0 Q 38.5,35.9 38.3,37.6 Q 36.7,37.8 36.5,39.2 Q 35.7,41.0 37.2,42.0 M 47.7,36.8 Q 47.2,38.3 45.6,38.1 Q 44.0,39.2 43.2,37.4 Q 41.7,36.0 40.2,37.3 M 55.7,37.0 Q 54.3,36.5 54.2,34.9 Q 53.7,33.1 51.8,33.0 Q 50.7,31.9 51.5,30.5 M 58.8,37.7 Q 58.2,35.9 59.8,34.7 Q 61.8,35.5 62.6,33.5 Q 61.9,32.1 63.0,31.1 M 64.3,35.9 Q 65.9,36.5 67.2,35.3 Q 66.3,33.8 67.4,32.4 Q 69.5,31.7 68.8,29.6 M 67.4,37.1 Q 65.9,38.4 67.0,40.0 Q 68.6,41.2 67.4,42.8 Q 66.4,43.9 67.5,45.0 M 70.5,38.0 Q 71.9,39.4 70.3,40.7 Q 71.8,41.6 71.5,43.3 Q 72.6,44.8 71.6,46.4 M 75.5,38.2 Q 75.1,39.7 76.7,40.1 Q 78.3,41.1 79.2,39.4 Q 78.9,37.7 80.5,37.0 M 82.2,37.7 Q 83.3,39.7 81.4,40.8 Q 80.4,42.6 78.8,41.4 Q 78.1,42.7 76.7,42.5 M 42.1,41.4 Q 40.4,40.5 39.6,42.3 Q 38.6,43.8 36.8,43.8 Q 36.9,45.5 35.2,45.7 M 47.7,40.7 Q 48.2,39.2 49.7,39.1 Q 51.2,38.5 51.2,36.9 Q 52.5,35.6 53.7,37.0 M 54.7,40.7 Q 55.8,42.4 54.1,43.6 Q 53.4,45.3 54.8,46.6 Q 56.1,48.4 57.9,47.2 M 58.4,41.6 Q 57.9,40.0 59.0,38.7 Q 60.7,37.7 59.3,36.3 Q 59.9,34.4 58.0,34.0 M 62.0,41.0 Q 62.8,39.1 64.8,39.6 Q 66.7,39.5 66.3,37.6 Q 68.3,37.4 68.1,35.4 M 74.5,42.3 Q 73.9,40.6 75.2,39.2 Q 76.6,40.1 77.8,39.0 Q 78.7,37.5 80.1,38.6 M 80.0,41.5 Q 81.2,42.9 82.9,42.1 Q 83.7,40.6 85.4,40.6 Q 85.0,39.0 86.5,38.4 M 87.0,40.2 Q 88.5,39.6 89.9,40.5 M 90.9,40.6 Q 89.0,40.1 90.0,38.4 Q 91.7,38.0 91.4,36.2 M 35.6,44.6 Q 37.0,44.0 37.1,42.5 Q 38.7,41.3 40.0,42.9 Q 41.4,43.5 42.5,42.3 M 43.0,44.7 Q 41.0,44.3 41.3,42.4 Q 40.6,40.7 38.9,41.5 Q 37.2,41.6 37.1,43.3 M 65.9,45.2 Q 67.4,46.4 66.6,48.1 Q 66.4,50.0 64.5,50.0 Q 63.0,51.1 61.4,50.4 M 70.4,45.1 Q 70.9,43.6 72.4,44.0 Q 73.3,42.3 72.1,40.9 Q 71.0,39.2 72.8,38.2 M 75.3,45.9 Q 76.4,47.6 78.2,46.7 Q 79.6,46.2 80.5,47.3 Q 82.3,47.0 83.0,45.3 M 84.1,43.7 Q 82.4,44.2 82.1,45.9 Q 80.2,45.7 79.9,47.6 Q 78.3,48.5 79.3,50.0 M 89.7,45.3 Q 89.5,43.4 87.7,43.9 Q 86.0,44.2 84.9,42.9 Q 83.1,42.8 82.9,44.6 M 34.0,50.2 Q 33.9,52.1 35.8,52.4 Q 36.7,50.4 38.6,51.4 Q 40.3,51.2 41.2,52.7 M 47.5,49.6 Q 46.4,51.0 47.2,52.6 Q 47.1,54.4 48.6,55.4 Q 48.9,57.2 47.1,57.6 M 51.3,48.3 Q 49.6,48.6 50.1,50.3 Q 49.8,52.1 51.2,53.3 Q 49.6,54.6 51.2,56.0 M 54.9,49.1 Q 54.3,47.1 52.2,47.5 Q 51.2,46.0 49.7,46.9 Q 49.7,45.3 48.1,44.9 M 59.3,50.3 Q 58.2,51.9 59.9,52.9 Q 60.3,54.9 62.2,54.7 Q 63.8,54.8 64.3,56.4 M 62.2,49.4 Q 63.0,48.0 64.4,48.9 Q 66.2,49.4 66.8,47.7 Q 68.1,48.4 69.2,47.4 M 65.6,49.8 Q 64.1,51.1 63.0,49.4 Q 61.4,48.0 60.1,49.7 Q 60.1,48.0 58.4,48.1 M 71.2,49.3 Q 70.8,50.8 69.3,51.1 Q 69.3,52.8 67.8,53.4 Q 69.3,54.4 69.2,56.2 M 79.0,49.4 Q 80.2,48.1 78.8,47.0 Q 80.7,46.3 80.3,44.2 Q 81.5,44.8 82.4,43.8 M 83.4,48.1 Q 85.0,47.5 85.7,48.9 M 39.4,54.3 Q 40.8,56.0 42.5,54.6 Q 42.8,52.6 44.8,52.7 Q 45.6,54.3 47.2,53.5 M 42.7,54.0 Q 43.7,55.7 45.6,55.2 Q 45.6,53.4 47.3,53.1 Q 49.4,53.2 49.5,51.2 M 46.7,53.2 Q 46.5,54.7 45.1,54.9 M 50.0,51.7 Q 52.0,51.4 52.4,53.3 Q 52.4,54.8 53.9,55.0 Q 56.0,55.4 55.8,57.6 M 55.7,53.6 Q 56.5,54.9 55.5,56.0 Q 55.3,58.1 53.2,58.0 M 63.7,52.2 Q 63.6,54.2 65.6,54.0 Q 64.4,55.3 65.9,56.2 Q 64.9,57.8 66.5,59.0 M 70.8,53.8 Q 70.9,55.8 68.9,56.0 Q 67.2,56.2 66.6,57.9 M 75.7,54.3 Q 77.1,52.8 78.4,54.4 M 79.0,53.2 Q 79.2,55.1 77.4,55.8 M 55.7,57.7 Q 53.9,58.5 53.4,56.6 Q 52.9,55.0 51.3,55.0 Q 50.1,54.0 50.6,52.5 M 66.0,56.0 Q 67.0,57.3 65.9,58.6" Stroke="#8A4D49" StrokeThickness="0.8" Opacity="0.58" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          <Path Canvas.Left="-0.55" Canvas.Top="-0.55" Data="M 62,14.6 C 64,19 60,23 63,28 C 65,32 61,36 62,41 M 55,15.2 C 57,20 53,24 56,29 C 58,33 54,37 55,42 M 69.5,15.6 C 71.5,20 67.5,24 70.5,29 C 72.5,33 68.5,36 70.5,40.5 M 33,36 C 37,33 41,34 44,30 C 47,26 51,27 53,23 M 31,42.5 C 35,40.5 39,41.5 42,38.5 C 45,35.5 49,36.5 52,33.5 M 37,27.5 C 40,24.5 44,24.5 47,21.5 M 33,49 C 36,47.6 38.4,49.6 41.4,48.6 M 46,32 C 48.4,34 47.4,37 50,39 M 74,21.5 C 77,25.5 81,24.5 84,28.5 M 72.5,32 C 76,34 80,32 84,35 C 87,37 89,36 91.5,39 M 76,39 C 78.5,41 77.5,43.5 80,45 M 86,43 C 88,46 90,45 92,48 M 79.5,46 C 82,48.5 85,47.6 87,51 M 46,54 C 51,52 56,54 61,51 C 66,49 71,50 76,48 C 80,47 83,48 86,47 M 48.5,58 C 53.5,57 57.5,59 62.5,57 C 66.5,56 70.5,57 74,55.4 M 58,22.5 C 59.5,25 58,27 59.6,29.5 M 65.6,23 C 67,25.4 65.6,27.6 67.2,30" Stroke="#FFF3EE" StrokeThickness="0.55" Opacity="0.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          <Path Data="M 62,14.6 C 64,19 60,23 63,28 C 65,32 61,36 62,41 M 55,15.2 C 57,20 53,24 56,29 C 58,33 54,37 55,42 M 69.5,15.6 C 71.5,20 67.5,24 70.5,29 C 72.5,33 68.5,36 70.5,40.5 M 33,36 C 37,33 41,34 44,30 C 47,26 51,27 53,23 M 31,42.5 C 35,40.5 39,41.5 42,38.5 C 45,35.5 49,36.5 52,33.5 M 37,27.5 C 40,24.5 44,24.5 47,21.5 M 33,49 C 36,47.6 38.4,49.6 41.4,48.6 M 46,32 C 48.4,34 47.4,37 50,39 M 74,21.5 C 77,25.5 81,24.5 84,28.5 M 72.5,32 C 76,34 80,32 84,35 C 87,37 89,36 91.5,39 M 76,39 C 78.5,41 77.5,43.5 80,45 M 86,43 C 88,46 90,45 92,48 M 79.5,46 C 82,48.5 85,47.6 87,51 M 46,54 C 51,52 56,54 61,51 C 66,49 71,50 76,48 C 80,47 83,48 86,47 M 48.5,58 C 53.5,57 57.5,59 62.5,57 C 66.5,56 70.5,57 74,55.4 M 58,22.5 C 59.5,25 58,27 59.6,29.5 M 65.6,23 C 67,25.4 65.6,27.6 67.2,30" Stroke="#8A4D49" StrokeThickness="0.85" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Opacity="0.78"/>
          <Path Canvas.Left="-0.6" Canvas.Top="-0.6" Data="M 39.5,49.5 C 46.5,46.5 52.5,47.5 57.5,44.5 C 62.5,41.5 67.5,42.5 72.5,40" Stroke="#FFF3EE" StrokeThickness="0.6" Opacity="0.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          <Path Data="M 39.5,49.5 C 46.5,46.5 52.5,47.5 57.5,44.5 C 62.5,41.5 67.5,42.5 72.5,40" Stroke="#7A403D" StrokeThickness="1.25" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Opacity="0.85"/>
          <Path Data="M 37,30 C 42,23 50,19 58,17.6" Stroke="White" StrokeThickness="1.1" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Opacity="0.28"/>
          <Ellipse x:Name="CSpark1" Canvas.Left="43.25" Canvas.Top="30.25" Width="1.50" Height="1.50" Fill="#5FD3FF"/>
          <Ellipse x:Name="CSpark2" Canvas.Left="65.30" Canvas.Top="23.30" Width="1.40" Height="1.40" Fill="#5FD3FF"/>
          <Ellipse x:Name="CSpark3" Canvas.Left="80.30" Canvas.Top="32.30" Width="1.40" Height="1.40" Fill="#5FD3FF"/>
          <Ellipse x:Name="CSpark4" Canvas.Left="56.30" Canvas.Top="51.30" Width="1.40" Height="1.40" Fill="#5FD3FF"/>
          <Rectangle x:Name="CBit0" Canvas.Left="66.6" Canvas.Top="84.1" Width="2.2" Height="1.5" RadiusX="0.3" RadiusY="0.3" Fill="#2A3442"/>
          <Rectangle x:Name="CBit1" Canvas.Left="63.7" Canvas.Top="84.1" Width="2.2" Height="1.5" RadiusX="0.3" RadiusY="0.3" Fill="#2A3442"/>
          <Rectangle x:Name="CBit2" Canvas.Left="60.8" Canvas.Top="84.1" Width="2.2" Height="1.5" RadiusX="0.3" RadiusY="0.3" Fill="#2A3442"/>
          <Rectangle x:Name="CBit3" Canvas.Left="57.9" Canvas.Top="84.1" Width="2.2" Height="1.5" RadiusX="0.3" RadiusY="0.3" Fill="#2A3442"/>
          <Rectangle x:Name="CBit4" Canvas.Left="55.0" Canvas.Top="84.1" Width="2.2" Height="1.5" RadiusX="0.3" RadiusY="0.3" Fill="#2A3442"/>
          <Rectangle x:Name="CBit5" Canvas.Left="52.1" Canvas.Top="84.1" Width="2.2" Height="1.5" RadiusX="0.3" RadiusY="0.3" Fill="#2A3442"/>
          <Border x:Name="CClockBox" Canvas.Left="43.64" Canvas.Top="70.7" Width="32.73" Height="12.55" CornerRadius="1.6" Background="#F0141B24" BorderBrush="#5FD3FF" BorderThickness="0.7"><TextBlock x:Name="CClock" Text="▶ FOCUS" Foreground="#E8EEF5" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="6.87" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        </Canvas>
      </Canvas>

    </Canvas>

    <!-- Compte a rebours visible : une barre qui se vide et change de couleur (bleu, jaune,
         orange, puis rouge qui pulse la derniere minute), juste au-dessus des boutons ronds -->
    <Border x:Name="UrgencyChip" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,146,108"
            Width="68" Height="18" CornerRadius="9" Background="#FF1E1B3A" BorderBrush="#1E1B3A" BorderThickness="1.5"
            Visibility="Collapsed" IsHitTestVisible="False">
      <Grid>
        <Border x:Name="UrgencyFill" HorizontalAlignment="Left" Width="65" CornerRadius="8" Background="#FF4C8DFF"/>
        <TextBlock x:Name="UrgencyText" Text="50:00" FontFamily="Consolas, Segoe UI" FontWeight="Bold" FontSize="11"
                   Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <!-- Les boutons ronds colles a Orbit (option des reglages) : 2 colonnes de 3, en partant d'Orbit.
         Les boutons caches (✋ hors focus, ↩ sans reprise) laissent la place aux suivants. -->
    <WrapPanel x:Name="Dock" Orientation="Vertical" FlowDirection="RightToLeft" Height="102"
               HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,146,6">
      <Border x:Name="AnchorBadge" Width="30" Height="30" CornerRadius="15" Margin="2" Background="#FF6C5CE7" BorderBrush="#1E1B3A" BorderThickness="2"
              Cursor="Hand" FlowDirection="LeftToRight" ToolTip="📝 Note rapide : note ce qui te passe par la tête, tout de suite">
        <TextBlock Text="📝" FontSize="14" FontFamily="Segoe UI Emoji" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <Border x:Name="CtxBadge" Width="30" Height="30" CornerRadius="15" Margin="2" Background="#FFFDFBFF" BorderBrush="#1E1B3A" BorderThickness="2"
              Cursor="Hand" FlowDirection="LeftToRight" ToolTip="✋ Je m'interromps : je garde où tu en es (fenêtre, onglet, prochaine étape)">
        <TextBlock Text="✋" FontSize="14" FontFamily="Segoe UI Emoji" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <Border x:Name="SosBadge" Width="30" Height="30" CornerRadius="15" Margin="2" Background="#FFFFE3E3" BorderBrush="#1E1B3A" BorderThickness="2"
              Cursor="Hand" FlowDirection="LeftToRight" ToolTip="🚨 S.O.S : je bloque, découpe-moi ça en toutes petites étapes">
        <TextBlock Text="🚨" FontSize="14" FontFamily="Segoe UI Emoji" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <Border x:Name="BoardsBadge" Width="30" Height="30" CornerRadius="15" Margin="2" Background="#FFFFF4D6" BorderBrush="#1E1B3A" BorderThickness="2"
              Cursor="Hand" FlowDirection="LeftToRight" ToolTip="🗂 Mes tableaux">
        <TextBlock Text="🗂" FontSize="14" FontFamily="Segoe UI Emoji" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <Border x:Name="CtxListBadge" Width="30" Height="30" CornerRadius="15" Margin="2" Background="#FFE8F1FF" BorderBrush="#1E1B3A" BorderThickness="2"
              Cursor="Hand" Visibility="Collapsed" FlowDirection="LeftToRight" ToolTip="↩ Mes reprises : là où tu t'es arrêté(e)">
        <TextBlock Text="↩" FontSize="14" FontFamily="Segoe UI Emoji" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </WrapPanel>
  </Grid>
</Window>
'@

$nsm = New-Object Xml.XmlNamespaceManager($xaml.NameTable)
$nsm.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
$nsm.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')

# Les 7 dessins ne sont pas tous construits : on les retire du XAML et on ne
# fabrique que celui qui est affiche (voir Ensure-Skin). Demarrage plus rapide,
# et quelques centaines d'elements graphiques en moins en memoire.
$SkinXml = @{}
$SkinResources = $xaml.SelectSingleNode("//w:Canvas[@x:Name='Bot']/w:Canvas.Resources", $nsm)
foreach ($node in @($xaml.SelectNodes("//w:Canvas[@x:Name='Bobber']/w:Canvas[starts-with(@x:Name,'Skin')]", $nsm))) {
    $SkinXml[$node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml').Substring(4)] = $node
    [void]$node.ParentNode.RemoveChild($node)
}
$LoadedSkins = @{}    # nom du dessin -> @{ Host = <Canvas>; Names = @(...) }

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
# tous les elements nommes (x:Name) de la fenetre, accessibles par $ui.Nom
foreach ($node in $xaml.SelectNodes('//@x:Name', $nsm)) { $ui[$node.Value] = $window.FindName($node.Value) }

# Construit un dessin s'il ne l'est pas encore, et range ses elements dans $ui
function Ensure-Skin([string]$name) {
    if ($LoadedSkins.ContainsKey($name)) { return }
    $src = $SkinXml[$name]
    if (-not $src) { throw "Dessin inconnu : $name" }
    $doc = New-Object Xml.XmlDocument
    $root = $doc.CreateElement('Canvas', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    # declarations explicites : WPF s'en sert pour comprendre Canvas.Left, x:Name...
    [void]$root.SetAttribute('xmlns', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    [void]$root.SetAttribute('xmlns:x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    [void]$doc.AppendChild($root)
    if ($SkinResources) { [void]$root.AppendChild($doc.ImportNode($SkinResources, $true)) }
    [void]$root.AppendChild($doc.ImportNode($src, $true))
    $holder = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $doc))
    $names = @()
    foreach ($node in $src.SelectNodes('descendant-or-self::*/@x:Name', $nsm)) {
        $ui[$node.Value] = $holder.FindName($node.Value)
        $names += $node.Value
    }
    [void]$ui.Bobber.Children.Add($holder)
    $LoadedSkins[$name] = @{ Host = $holder; Names = $names }
    if ($name -eq 'Butler') { Start-HudSpin }
}

# Libere les dessins qui ne sont plus affiches
function Remove-OtherSkins([string]$keep) {
    foreach ($k in @($LoadedSkins.Keys)) {
        if ($k -eq $keep) { continue }
        $ui.Bobber.Children.Remove($LoadedSkins[$k].Host)
        foreach ($n in $LoadedSkins[$k].Names) { $ui.Remove($n) }
        $LoadedSkins.Remove($k)
    }
}

# ---------------------------------------------------------------------------
#  Etat
# ---------------------------------------------------------------------------
$O = @{
    State        = 'Idle'      # Idle | Focus | AwaitBreak | Break | AwaitFocus
    LastBusy     = [datetime]::Now   # dernier moment avec un focus ou une pause en cours (ou derniere relance)
    NudgeOffDay  = ''          # « Pas aujourd'hui » : plus de relance ce jour-la
    NudgeIds     = @()
    NextTick     = [datetime]::MinValue
    UrgencyLevel = ''
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
    LastCursor   = $null
    CursorMovedAt = [datetime]::Now
    NextTrim     = [datetime]::Now.AddSeconds(45)
    TrimCount    = 0
    Busy         = $false
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
    PlanDay      = ''
    PlanIds      = @()
    NextBreakLine = [datetime]::MaxValue
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
        if ($s.planDay) { $O.PlanDay = [string]$s.planDay }
    }
} catch { Write-Log "Lecture stats : $($_.Exception.Message)" }

function Save-Stats {
    try {
        $today = (Get-Date).ToString('yyyy-MM-dd')
        if ($today -ne $O.Today) { $O.Today = $today; $O.FocusToday = 0; $O.FocusMinToday = 0 }
        $data = @{ date = $O.Today; focus = $O.FocusToday; minutes = $O.FocusMinToday; planDay = $O.PlanDay }
        Write-FileSafe $StatsFile (ConvertTo-Json -InputObject $data)
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
        breakLines         = $Config.BreakLines
        breakLineEveryMin  = $Config.BreakLineEveryMin
        appComments        = $Config.AppComments
        sounds             = $Config.Sounds
        droidSounds        = $Config.DroidSounds
        droidVolume        = $Config.DroidVolume
        bubbleSound        = $Config.BubbleSound
        bubbleSoundFiles   = @($Config.BubbleSoundFiles)
        endSound           = $Config.EndSound
        endSoundFile       = $Config.EndSoundFile
        customImage        = $Config.CustomImage
        skin               = $O.Skin
        idlePause          = $Config.IdlePause
        idleMinutes        = $Config.IdleMinutes
        morningPlan        = $Config.MorningPlan
        idleNudge          = $Config.IdleNudge
        tickSound          = $Config.TickSound
        tickZoneMin        = $Config.TickZoneMin
        urgencyBar         = $Config.UrgencyBar
        idleNudgeMin       = $Config.IdleNudgeMin
        notesMirror        = $Config.NotesMirror
        contextButton      = $Config.ContextButton
        contextWindows     = $Config.ContextWindows
        contextScreenshot  = $Config.ContextScreenshot
        contextRemind      = $Config.ContextRemind
        contextRemindMin   = $Config.ContextRemindMin
        anchorButton       = $Config.AnchorButton
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
    if (Has 'morningPlan') { $Config.MorningPlan = [bool]$d.morningPlan }
    if (Has 'idleNudge') { $Config.IdleNudge = [bool]$d.idleNudge }
    if (Has 'tickSound') { $Config.TickSound = [bool]$d.tickSound }
    if (Has 'tickZoneMin') { $Config.TickZoneMin = [math]::Min(15, [math]::Max(1, [int]$d.tickZoneMin)) }
    if (Has 'urgencyBar') { $Config.UrgencyBar = [bool]$d.urgencyBar }
    if (Has 'idleNudgeMin') { $Config.IdleNudgeMin = [math]::Min(240, [math]::Max(10, [int]$d.idleNudgeMin)) }
    if (Has 'notesMirror') { $Config.NotesMirror = [string]$d.notesMirror }
    if (Has 'reminderEveryMin') { $Config.ReminderEveryMin = [int]$d.reminderEveryMin }
    if (Has 'motivationEveryMin') { $Config.MotivationEveryMin = [int]$d.motivationEveryMin }
    # (« jokes » / « jokeEveryMin » : anciens noms du meme reglage, avant le retrait des blagues)
    if (Has 'breakLines') { $Config.BreakLines = [bool]$d.breakLines } elseif (Has 'jokes') { $Config.BreakLines = [bool]$d.jokes }
    $every = if (Has 'breakLineEveryMin') { $d.breakLineEveryMin } elseif (Has 'jokeEveryMin') { $d.jokeEveryMin } else { $null }
    if ($null -ne $every) { $Config.BreakLineEveryMin = [math]::Min(30, [math]::Max(0.5, [double]$every)) }
    if (Has 'appComments') { $Config.AppComments = [bool]$d.appComments }
    if (Has 'sounds') { $Config.Sounds = [bool]$d.sounds }
    if (Has 'droidSounds') { $Config.DroidSounds = [bool]$d.droidSounds }
    if (Has 'droidVolume') { $Config.DroidVolume = [math]::Min(100, [math]::Max(0, [int]$d.droidVolume)) }
    if ($d.bubbleSound) { $Config.BubbleSound = [string]$d.bubbleSound }
    if (Has 'bubbleSoundFiles') { $Config.BubbleSoundFiles = @($d.bubbleSoundFiles | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
    elseif ($d.bubbleSoundFile) { $Config.BubbleSoundFiles = @([string]$d.bubbleSoundFile) }   # ancienne version : un seul fichier
    if ($d.endSound) { $Config.EndSound = [string]$d.endSound }
    if (Has 'endSoundFile') { $Config.EndSoundFile = [string]$d.endSoundFile }
    if (Has 'customImage') { $Config.CustomImage = [string]$d.customImage }
    if ($d.skin) { $O.Skin = [string]$d.skin }   # verifie par Set-Skin
    if (Has 'idlePause') { $Config.IdlePause = [bool]$d.idlePause }
    if (Has 'idleMinutes') { $Config.IdleMinutes = [int]$d.idleMinutes }
    if (Has 'contextButton') { $Config.ContextButton = [bool]$d.contextButton }
    if (Has 'contextWindows') { $Config.ContextWindows = [math]::Min(5, [math]::Max(0, [int]$d.contextWindows)) }
    if (Has 'contextScreenshot') { $Config.ContextScreenshot = [bool]$d.contextScreenshot }
    if (Has 'contextRemind') { $Config.ContextRemind = [bool]$d.contextRemind }
    if (Has 'anchorButton') { $Config.AnchorButton = [bool]$d.anchorButton }
    if (Has 'contextRemindMin') { $Config.ContextRemindMin = [math]::Min(480, [math]::Max(5, [int]$d.contextRemindMin)) }
    if ($Config.WanderMaxMin -le $Config.WanderMinMin) { $Config.WanderMaxMin = $Config.WanderMinMin + 1 }
}

function Save-Settings {
    try { Write-FileSafe $SettingsFile (ConvertTo-Json -InputObject (Get-SettingsSnapshot)) }
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
    Satellite = @{ Label = '🛰 Satellite'; Root = 'SkinSatellite'; Clock = 'SClock'; Bits = 'Bit'; EyeX = 60; EyeY = 39.5; EyeMax = 1.8
                   Eyes = @(@('Lens', 56.7, 36.2), @('LensGlint', 57.9, 37.4))
                   Fill = @('Lens', 'Beacon', 'StatusLed'); Stroke = @(); Beacons = @('Beacon'); Glows = @() }
    Droid     = @{ Label = '🤖 Droïde de maintenance'; Root = 'SkinDroid'; Scale = 1.25; Clock = 'DClock'; Bits = 'DBit'; EyeX = 62; EyeY = 49.5; EyeMax = 1.6
                   Eyes = @(@('DLens', 59, 46.5), @('DGlint', 60, 47.3))
                   Fill = @('DLens', 'DBeacon'); Stroke = @('DRing'); Beacons = @('DBeacon'); Glows = @('DGlow', 'DJet1', 'DJet2') }
    Robot     = @{ Label = '🦾 Robot assistant'; Root = 'SkinRobot'; Scale = 1.1; Clock = 'RClock'; Bits = 'RBit'; EyeX = 60; EyeY = 34.5; EyeMax = 1.3
                   Eyes = @(@('REyeL', 50.2, 31.2), @('REyeR', 63.2, 31.2), @('RGlintL', 51.6, 32.5), @('RGlintR', 64.6, 32.5))
                   Fill = @('REyeL', 'REyeR', 'RBeacon'); Stroke = @(); Beacons = @('RBeacon'); Glows = @('RGlow') }
    Butler    = @{ Label = '🎩 Majordome robot'; Root = 'SkinButler'; Scale = 1.05; Clock = 'MClock'; Bits = 'MBit'; EyeX = 60; EyeY = 25.7; EyeMax = 0.9
                   Eyes = @(@('MEyeL', 52.9, 23.6), @('MEyeR', 62.9, 23.6), @('MGlintL', 53.6, 24.3), @('MGlintR', 63.6, 24.3))
                   Fill = @('MEyeL', 'MEyeR', 'MPocket'); Stroke = @('MHud1', 'MHud2', 'MHud3'); Beacons = @(); Glows = @('MGlow') }
    Human     = @{ Label = '🤵 Majordome humain'; Root = 'SkinHuman'; Scale = 1.1; Clock = 'HClock'; Bits = 'HBit'; EyeX = 60; EyeY = 24.4; EyeMax = 0.9
                   Eyes = @(@('HEyeL', 53.95, 23.35), @('HEyeR', 63.95, 23.35), @('HGlintL', 54.25, 23.65), @('HGlintR', 64.25, 23.65))
                   Fill = @('HPocket'); Stroke = @(); Beacons = @(); Glows = @() }
    Custom    = @{ Label = '🖼 Mon image'; Root = 'SkinCustom'; Clock = 'UClock'; Bits = $null; EyeX = 60; EyeY = 40; EyeMax = 0
                   Eyes = @(); Fill = @(); Stroke = @(); Beacons = @(); Glows = @() }
    Brain     = @{ Label = '🧠 Cerveau humain'; Root = 'SkinBrain'; Scale = 1.1; Clock = 'CClock'; Bits = 'CBit'; EyeX = 60; EyeY = 40; EyeMax = 0
                   Eyes = @(); Fill = @('CSpark1', 'CSpark2', 'CSpark3', 'CSpark4', 'CRing'); Stroke = @(); Beacons = @(); Glows = @() }
}

# Charge l'image personnalisee (affichee telle quelle)
function Load-CustomImage {
    $path = $Config.CustomImage
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $false }
    Ensure-Skin 'Custom'
    try {
        $bmp = New-Object Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object Uri ((Resolve-Path -LiteralPath $path).ProviderPath)
        $bmp.DecodePixelWidth = 360      # largement assez pour la taille d'Orbit, et rapide
        $bmp.CacheOption = 'OnLoad'
        $bmp.EndInit()
        $ui.CustomImg.Source = $bmp
        return $true
    } catch { Write-Log "Image : $($_.Exception.Message)"; return $false }
}

# Choix d'une image : elle est copiee dans le dossier d'Orbit pour rester disponible
function Choose-CustomImage {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Choisis une image pour Orbit'
    $dlg.Filter = 'Images (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif'
    if (-not $dlg.ShowDialog()) { return $false }
    try {
        Get-ChildItem -Path $DataDir -Filter 'mon-image.*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $dest = Join-Path $DataDir ('mon-image' + [IO.Path]::GetExtension($dlg.FileName).ToLowerInvariant())
        Copy-Item -LiteralPath $dlg.FileName -Destination $dest -Force
        $Config.CustomImage = $dest
        return (Load-CustomImage)
    } catch { Write-Log "Copie image : $($_.Exception.Message)"; return $false }
}

function Set-Skin([string]$name, [switch]$Quiet) {
    if (-not $Skins.Contains($name)) { $name = 'Satellite' }
    if ($name -eq 'Custom' -and -not (Load-CustomImage)) {
        if ($Quiet -or -not (Choose-CustomImage)) {
            if (-not $Quiet) { Show-Bubble "Pas d'image choisie, je garde mon apparence actuelle." -Force -Seconds 4 }
            if ($O.Skin -eq 'Custom') { $name = 'Satellite' } else { return }
        }
    }
    Ensure-Skin $name
    $ui[$Skins[$name].Root].Visibility = 'Visible'
    $O.Skin = $name
    Remove-OtherSkins $name
    if ($O.Mood) { Set-Mood $O.Mood }
    Update-Pill
    if (-not $Quiet) {
        $hello = switch ($name) {
            'Satellite' { "Retour en orbite 🛰" }
            'Droid'     { "Droïde de maintenance opérationnel. Je répare… surtout ta motivation 🔧" }
            'Robot'     { "Robot assistant en ligne. > focus_ 🦾" }
            'Butler'    { "Votre majordome est à votre service. Un café avec votre focus ? ☕🎩" }
            'Brain'     { "Cerveau en place. Rappel : il se muscle par séries de focus 🧠" }
            'Human'     { "Bonjour. Votre majordome est à votre service : un café, l'heure, et votre liste de tâches ☕🤵" }
            'Custom'    { "Nouveau look ! J'adore 😎" }
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
    $ui["$($sk.Clock)Box"].BorderBrush = $accent
    $O.AccentBrush = $accent
    $O.MoodBrush = New-Object Windows.Media.SolidColorBrush((New-Color $c[1]))
}

# ---------------------------------------------------------------------------
#  Bulle de dialogue
# ---------------------------------------------------------------------------
function Show-Bubble {
    param([string]$Text, [object[]]$Buttons = @(), [double]$Seconds = $Config.BubbleSeconds,
          [switch]$Force, [switch]$Thought, [switch]$AutoHide)
    # Une bulle avec des boutons reste jusqu'a la reponse (et Orbit ne part pas en balade
    # pendant ce temps). -AutoHide : elle se range quand meme apres $Seconds, pour les
    # propositions qui n'attendent pas forcement de reponse (accueil, plan du matin...).

    if (-not $Force -and $Buttons.Count -eq 0 -and ($O.Quiet -or $O.Mini)) { return }
    if (-not $Force -and $Buttons.Count -eq 0 -and $ui.BubbleButtons.Children.Count -gt 0 -and
        $ui.BubbleWrap.Visibility -eq 'Visible') { return }   # ne pas ecraser une question en attente

    $wasVisible = $ui.BubbleWrap.Visibility -eq 'Visible'

    $ui.BubbleText.Text = ConvertTo-DisplayText $Text
    $ui.BubbleButtons.Children.Clear()
    $ui.BubbleButtons.Margin = if ($Buttons.Count) { '0,8,0,0' } else { '0' }
    foreach ($b in $Buttons) {
        $btn = New-Object Windows.Controls.Button
        $btn.Content = ConvertTo-DisplayText $b.Label
        $btn.Tag = $b.Action
        $btn.Margin = '4,2,0,2'
        $btn.Padding = '10,4,10,4'
        $btn.FontFamily = 'Segoe UI Semibold, Segoe UI Emoji, Segoe UI Symbol'
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
    # bulle de pensee (petits ronds) pour les petites phrases et reflexions, bulle de parole sinon
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
    $O.BubbleUntil = if ($Buttons.Count -and -not $AutoHide) { [datetime]::MaxValue } else { (Get-Date).AddSeconds($Seconds) }
    $ui.BubbleScroll.ScrollToTop()
    Fit-BubbleWindow
}

function Hide-Bubble {
    $ui.BubbleWrap.Visibility = 'Collapsed'
    $ui.BubbleButtons.Children.Clear()
    $O.BubbleUntil = [datetime]::MinValue
    Fit-BubbleWindow
}

# La fenetre d'Orbit grandit vers le haut quand la bulle est longue (plan du matin,
# quiz, boutons...) : la bulle n'est plus rognee, et le robot reste exactement a sa place
# (le bas de la fenetre ne bouge pas). Elle reprend sa taille quand la bulle disparait.
$BaseWindowHeight = 340
function Fit-BubbleWindow {
    $need = $BaseWindowHeight
    if ($ui.BubbleWrap.Visibility -eq 'Visible') {
        # le nouveau texte et les boutons doivent d'abord etre pris en compte par WPF,
        # sinon la mesure renvoie encore la taille de la bulle precedente
        $ui.BubbleScroll.MaxHeight = 420
        $window.UpdateLayout()
        $ui.BubbleWrap.Measure((New-Object Windows.Size(300, [double]::PositiveInfinity)))
        # DesiredSize compte deja la marge (la place du robot sous la bulle)
        $need = [math]::Max([double]$BaseWindowHeight, [math]::Ceiling([double]$ui.BubbleWrap.DesiredSize.Height + 14))
    }
    $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int]($window.Left + $window.Width / 2), [int]($window.Top + $window.Height - 20))))
    # on grandit vers le haut seulement : le bas de la fenetre (le robot) ne bouge pas,
    # et le haut ne depasse pas le haut de l'ecran (au-dela, le texte defile dans la bulle)
    $old = $window.Height
    $bottom = $window.Top + $old
    $room = [math]::Max([double]$BaseWindowHeight, [double]($bottom - $wa.T))
    if ($need -gt $room) {
        # pas assez de place au-dessus : la zone de texte raccourcit et defile
        $ui.BubbleScroll.MaxHeight = [math]::Max(60.0, $ui.BubbleScroll.DesiredSize.Height - ($need - $room))
        $need = $room
    }
    if ([math]::Abs($need - $old) -lt 1) { return }
    $window.Height = $need
    $window.Top = [math]::Max($wa.T, $bottom - $need)
    # une balade en cours vise toujours le meme endroit pour le robot (le bas de la fenetre)
    if ($O.Walking -and $O.WalkTarget) { $O.WalkTarget = [Windows.Point]::new($O.WalkTarget.X, $O.WalkTarget.Y + ($old - $need)) }
    $O.Home = Get-HomePos
}

$script:lastErr = ''
$script:lastErrAt = [datetime]::MinValue
function Invoke-Safe([scriptblock]$sb, [string]$where = '') {
    try { & $sb } catch {
        $msg = "Erreur$(if ($where) { " ($where)" }) : $($_.Exception.Message) @ ligne $($_.InvocationInfo.ScriptLineNumber)"
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
$BtnTodo       = @{ Label = "🗂 Mes tableaux"; Action = { Open-Notebook 'Todo' } }
$BtnLater      = @{ Label = "Plus tard"; Action = { Show-Bubble "Ok ! Clique sur moi quand tu veux te lancer 😉" -Force } }
$BtnPickCards  = @{ Label = "🎯 Choisir mes cartes"; Action = { Choose-FocusCards -Start } }

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
    $secs = 6
    # cartes liees au focus (plusieurs possibles) ; a defaut, la plus prioritaire
    Clear-FocusCardsDone
    $cards = @(Get-FocusCards -Open)
    $auto = $false
    if (-not $cards.Count -and $O.TaskReminders) {
        $next = Get-NextTodo
        if ($next) { [void]$NB.FocusCards.Add($next.id); $cards = @($next); $auto = $true }
    }
    foreach ($t in $cards) { Move-CardToDoing $t }
    Save-Todos
    Render-Todos
    if ($cards.Count -eq 1) {
        $t = $cards[0]
        $msg += "`n`n🎯 Objectif (P$($t.prio)) : « $(Short-Text $t.text) »"
        if ($t.pomos) { $msg += "  🍅 $($t.pomos + 1)e focus dessus" }
        if ($t.desc) { $msg += "`n   📄 $(Short-Text $t.desc 90)" }
        if ($auto) { $msg += "`n(Autre chose ? Clique sur 🎯 sur tes cartes, ou clic droit sur moi > ☰ Plus > 🎯 Cartes du focus.)" }
        $secs = 12
    } elseif ($cards.Count -gt 1) {
        $msg += "`n`n🎯 Au programme de ce focus :"
        foreach ($t in ($cards | Select-Object -First 4)) {
            $msg += "`n   • P$($t.prio) $(Short-Text $t.text 45)$(if ($t.pomos) { "  🍅 $($t.pomos)" })"
        }
        if ($cards.Count -gt 4) { $msg += "`n   … et $($cards.Count - 4) autre(s)" }
        $secs = 12
    } elseif ($O.TaskReminders) {
        $msg += "`n`nTes tableaux sont vides : clic droit > 🗂 Mes tableaux pour noter tes tâches."
        $secs = 8
    }
    Show-Bubble $msg -Force -Seconds $secs
    Update-Pill
}

function Start-Break {
    $O.State = 'Break'
    $O.Paused = $false
    $O.EndsAt = (Get-Date).AddMinutes($Config.BreakMinutes)
    $O.NextBreakLine = (Get-Date).AddSeconds(40)
    $O.NextMotivation = [datetime]::MaxValue
    $O.NextReminder = [datetime]::MaxValue
    Set-Mood 'Break'
    Show-Bubble (Pick $Lines.BreakStart) -Force -Seconds 8
    Update-Pill
}

# ---------------------------------------------------------------------------
#  Pendant la pause : de petites phrases sympas (ni blagues ni culture G),
#  chacune son tour dans un ordre au hasard
# ---------------------------------------------------------------------------
$script:BreakBag = $null
function Get-NextBreakLine {
    if (-not $script:BreakBag -or $script:BreakBag.Count -eq 0) {
        $script:BreakBag = New-Object System.Collections.Queue (, @($Lines.BreakLines | Sort-Object { Get-Random }))
    }
    return $script:BreakBag.Dequeue()
}

function Tell-BreakItem { Show-Bubble (Get-NextBreakLine) -Thought -Seconds 10 }

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
$SoundStyles = @{ Droide = 0; Carillon = 1; Marimba = 2; Pop = 3; Bip = 4 }

# la banque de sons est refaite quand on change de style ou de volume dans les reglages
function Build-Chirps {
    $script:ChirpKey = "$($Config.BubbleSound)|$($Config.DroidVolume)"
    $script:StyleBanks = @{}; $script:EndWav = $null
    if (-not $Native) { return }
    try { $script:EndWav = [OrbitNative]::Synth(10, 1, [math]::Min(0.9, 0.55 * $Config.DroidVolume / 100 * 1.3), $false) }
    catch { Write-Log "Sons : $($_.Exception.Message)" }
}

# banque de sons d'un style, fabriquee a la premiere utilisation
function Get-StyleBank([int]$style) {
    if (-not $script:StyleBanks.ContainsKey($style)) {
        $vol = 0.55 * $Config.DroidVolume / 100
        try {
            $script:StyleBanks[$style] = @{
                Talk = @(1..6 | ForEach-Object { , [OrbitNative]::Synth($style, (Get-Random), $vol, $false) })
                Ask  = @(1..4 | ForEach-Object { , [OrbitNative]::Synth($style, (Get-Random), $vol, $true) })
            }
        } catch { Write-Log "Sons : $($_.Exception.Message)"; $script:StyleBanks[$style] = @{ Talk = @(); Ask = @() } }
    }
    return $script:StyleBanks[$style]
}

# Mes sons = les fichiers audio du dossier « sons » d'Orbit (on peut en ajouter ou en retirer
# directement dans l'Explorateur : la liste suit le dossier)
function Get-MySounds {
    if (-not (Test-Path -LiteralPath $SoundsDir)) { return @() }
    @(Get-ChildItem -LiteralPath $SoundsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $SoundExt -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name | ForEach-Object { $_.FullName })
}

# copie un son dans le dossier « sons » (sans ecraser un autre son du meme nom) ; renvoie son chemin
function Copy-ToSoundsDir([string]$f) {
    if (-not (Test-Path -LiteralPath $SoundsDir)) { New-Item -ItemType Directory -Path $SoundsDir -Force | Out-Null }
    $full = [IO.Path]::GetFullPath($f)
    if ([IO.Path]::GetDirectoryName($full) -eq [IO.Path]::GetFullPath($SoundsDir).TrimEnd('\', '/')) { return $full }
    $dest = Join-Path $SoundsDir ([IO.Path]::GetFileName($f))
    $i = 2
    while ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -ne (Get-Item -LiteralPath $f).Length)) {
        $dest = Join-Path $SoundsDir ("{0} ({1}){2}" -f [IO.Path]::GetFileNameWithoutExtension($f), $i, [IO.Path]::GetExtension($f)); $i++
    }
    if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $f -Destination $dest }
    return $dest
}

# ancienne version : la liste de sons etait dans les reglages -> on les range une fois dans le dossier
function Move-OldSoundList {
    $old = @($Config.BubbleSoundFiles | Where-Object { $_ })
    if (-not $old.Count) { return }
    foreach ($f in $old) {
        try { if ((Test-Path -LiteralPath $f) -and $SoundExt -contains [IO.Path]::GetExtension($f).ToLowerInvariant()) { [void](Copy-ToSoundsDir $f) } }
        catch { Write-Log "Son $f : $($_.Exception.Message)" }
    }
    $Config.BubbleSoundFiles = @()
    Save-Settings
    Write-Log "Sons : $($old.Count) son(s) ranges dans le dossier $SoundsDir"
}

# Chacun son tour, dans un ordre au hasard : on melange la liste, on la joue en entier,
# puis on remelange (sans rejouer tout de suite le dernier son entendu).
function Pick-NotLast([object[]]$items) {
    $items = @($items | Where-Object { $_ })
    if ($items.Count -le 1) { $script:LastSoundPick = $items[0]; return $items[0] }
    $key = ($items | ForEach-Object { "$_" }) -join '|'
    if ($script:SoundBagKey -ne $key -or -not $script:SoundBag -or $script:SoundBag.Count -eq 0) {
        $script:SoundBagKey = $key
        $mixed = @($items | Sort-Object { Get-Random })
        if ("$($mixed[0])" -eq "$($script:LastSoundPick)") { $mixed = @($mixed[1..($mixed.Count - 1)]) + @($mixed[0]) }
        $script:SoundBag = New-Object System.Collections.Queue (, $mixed)
    }
    $it = $script:SoundBag.Dequeue()
    $script:LastSoundPick = $it
    return $it
}
Build-Chirps
Move-OldSoundList

# joue un son choisi par l'utilisateur (renvoie $false s'il est introuvable ou illisible)
#  - .wav : lecteur simple de Windows
#  - .mp3, .m4a, .wma : lecteur multimedia integre a Windows (meme volume que les sons d'Orbit)
function Play-AudioFile([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $false }
    try {
        if ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.wav') {
            $script:ChirpPlayer = New-Object System.Media.SoundPlayer $path
            $script:ChirpPlayer.Play()
        } else {
            if ($script:MediaPlayer) { $script:MediaPlayer.Close() }
            $script:MediaPlayer = New-Object Windows.Media.MediaPlayer
            $script:MediaPlayer.Add_MediaFailed({ param($s, $e) Write-Log "Son illisible : $($e.ErrorException.Message)" })
            $script:MediaPlayer.Volume = [math]::Min(1, [math]::Max(0.05, $Config.DroidVolume / 100))
            $script:MediaPlayer.Open((New-Object Uri ((Resolve-Path -LiteralPath $path).ProviderPath)))
            $script:MediaPlayer.Play()
        }
        return $true
    } catch { Write-Log "Son $path : $($_.Exception.Message)"; return $false }
}

function Play-Bytes([byte[]]$wav) {
    if (-not $wav) { return }
    try {
        $script:ChirpPlayer = New-Object System.Media.SoundPlayer (New-Object IO.MemoryStream (, $wav))
        $script:ChirpPlayer.Play()   # asynchrone : n'interrompt pas l'animation
    } catch { Write-Log "Son : $($_.Exception.Message)" }
}

# son des bulles
function Play-Chirp([switch]$Question, [switch]$Force) {
    if (-not $Config.DroidSounds -or $Config.DroidVolume -le 0) { return }
    # pas plus d'un son toutes les 1,5 seconde
    if (-not $Force -and ((Get-Date) - $script:LastChirp).TotalSeconds -lt 1.5) { return }
    $script:LastChirp = Get-Date
    if ($script:ChirpKey -ne "$($Config.BubbleSound)|$($Config.DroidVolume)") { Build-Chirps }
    $mine = Get-MySounds
    $choice = switch ($Config.BubbleSound) {
        'Fichier'   { if ($mine.Count) { Pick-NotLast $mine } }
        # aleatoire : un des 5 sons integres ou un de mes fichiers, au hasard
        'Aleatoire' { Pick-NotLast (@('Droide', 'Carillon', 'Marimba', 'Pop', 'Bip') + $mine) }
        default     { $Config.BubbleSound }
    }
    if (-not $choice) { return }
    if ($SoundStyles.ContainsKey([string]$choice)) {
        if (-not $Native) { return }
        $bank = Get-StyleBank $SoundStyles[[string]$choice]
        $list = if ($Question) { $bank.Ask } else { $bank.Talk }
        if ($list.Count) { Play-Bytes $list[(Get-Random -Maximum $list.Count)] }
    } else {
        [void](Play-AudioFile $choice)
    }
}

# son de fin de session et des rappels
function Play-Sound([switch]$Force) {
    if (-not $Config.Sounds -and -not $Force) { return }
    switch ($Config.EndSound) {
        'Fichier' { if (Play-AudioFile $Config.EndSoundFile) { return } }
        'Carillon' {
            if ($script:ChirpKey -ne "$($Config.BubbleSound)|$($Config.DroidVolume)") { Build-Chirps }
            if ($script:EndWav) { Play-Bytes $script:EndWav; return }
        }
    }
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
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
        # une reprise attend (« Je m'interromps ») : on propose directement de s'y remettre
        $script:CtxAwayId = ''
        $ctx = Get-ContextToOffer 30
        if ($ctx) { Show-ResumeBubble $ctx; return }
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

# Cartes liees au focus : voir notebook.ps1 (Get-FocusCards, Choose-FocusCards...)
$BtnTaskDone  = @{ Label = "✅ C'est fait !"; Action = { Complete-FocusTask } }
$BtnCardsDone = @{ Label = "✅ Cocher les cartes finies"; Action = { Choose-DoneFocusCards } }

function Get-AwaitBreakButtons {
    $n = @(Get-FocusCards -Open).Count
    if ($n -eq 1) { return @($BtnBreak, $BtnTaskDone, $BtnStop) }
    if ($n -gt 1) { return @($BtnBreak, $BtnCardsDone, $BtnStop) }
    return @($BtnBreak, $BtnStop)
}

function Ask-Break([string]$Text, [switch]$NoTaskInfo) {
    if (-not $Text) { $Text = (Pick $Lines.FocusEnd) -f (Format-Min $O.SessionMin) }
    # bilan des cartes du focus
    $cards = @(if (-not $NoTaskInfo) { Get-FocusCards -Open })
    if ($cards.Count -eq 1) {
        $t = $cards[0]
        $Text += "`n`n🎯 Et « $(Short-Text $t.text) », c'est bouclé ?"
        if ($t.pomos) { $Text += "`n   (🍅 $($t.pomos) focus dessus, $(Format-FocusTime $t.focusMin))" }
    } elseif ($cards.Count -gt 1) {
        $Text += "`n`n🎯 Tu as avancé sur :"
        foreach ($t in ($cards | Select-Object -First 4)) { $Text += "`n   • $(Short-Text $t.text 45)  🍅 $($t.pomos)" }
        if ($cards.Count -gt 4) { $Text += "`n   … et $($cards.Count - 4) autre(s)" }
        $Text += "`nDes cartes finies ?"
    } elseif ($O.TaskReminders -and -not $NoTaskInfo) {
        $open = @(Get-OpenTodos)
        if ($open.Count) { $Text += "`n`n📝 Il te reste $($open.Count) tâche(s), dont « $(Short-Text $open[0].text 45) »." }
    }
    $btns = if ($NoTaskInfo) { @($BtnBreak, $BtnStop) } else { Get-AwaitBreakButtons }
    Show-Bubble $Text -Buttons $btns -Force
}

# Une seule carte liee : « C'est fait ! »
function Complete-FocusTask {
    $cards = @(Get-FocusCards -Open)
    foreach ($t in $cards) { Set-TodoDone $t.id $true -Quiet }
    Clear-FocusCardsDone
    Save-Todos
    Complete-FocusMessage $cards.Count
}

function Complete-FocusMessage([int]$n) {
    $left = @(Get-OpenTodos).Count
    $msg = if ($n -gt 1) { "Bravo, $n cartes cochées ✅" } elseif ($n -eq 1) { "Bravo, c'est coché ✅" } else { "Pas de souci, elles restent liées au prochain focus 🎯" }
    if ($n -gt 0) {
        if ($left -eq 0) { $msg += " Et toutes tes cartes sont terminées, quelle journée ! 🎉" } else { $msg += " Plus que $left tâche(s)." }
    }
    $rest = @(Get-FocusCards -Open).Count
    if ($n -gt 0 -and $rest) { $msg += "`n🎯 $rest carte(s) restent liées au prochain focus." }
    Ask-Break ($msg + "`nOn fait la pause ?") -NoTaskInfo
}

function Ask-Focus {
    $Text = (Pick $Lines.BreakEnd) -f (Format-Min $Config.FocusMinutes)
    $cards = @(Get-FocusCards -Open)
    if ($cards.Count) {
        $Text += "`n`n🎯 On continue sur : " + (($cards | Select-Object -First 3 | ForEach-Object { "« $(Short-Text $_.text 35) »" }) -join ', ')
        if ($cards.Count -gt 3) { $Text += " et $($cards.Count - 3) autre(s)" }
    } elseif ($O.TaskReminders) {
        $next = Get-NextTodo
        if ($next) { $Text += "`n`n🎯 Au programme (P$($next.prio)) : « $(Short-Text $next.text) »" }
    }
    Show-Bubble $Text -Buttons @($BtnAgain, $BtnPickCards, $BtnStop) -Force
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
        [void](Add-FocusToCards ([int][math]::Round($O.SessionMin)))
        [void](Add-Win "Focus de $([int][math]::Round($O.SessionMin)) min" 'focus')
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
        'Idle'       { '▶ FOCUS' }
        'AwaitBreak' { '☕ ?' }
        'AwaitFocus' { '🚀 ?' }
        default {
            $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
            if ($left -lt [timespan]::Zero) { $left = [timespan]::Zero }
            $t = '{0:00}:{1:00}' -f [math]::Floor($left.TotalMinutes), $left.Seconds
            $prefix = if ($O.Paused) { '⏸' } elseif ($O.State -eq 'Break') { '☕' } else { '' }
            $prefix + $t
        }
    }
    $clock = $ui[$Skins[$O.Skin].Clock]
    if ($clock) { $clock.Text = $txt }
    # ✋ toujours la, a portee de clic (on peut etre interrompu aussi en dehors d'un focus)
    $badge = if ($Config.ContextButton) { 'Visible' } else { 'Collapsed' }
    if ($ui.CtxBadge.Visibility -ne $badge) { $ui.CtxBadge.Visibility = $badge }
    $dock = if ($Config.AnchorButton) { 'Visible' } else { 'Collapsed' }
    if ($ui.Dock.Visibility -ne $dock) { $ui.Dock.Visibility = $dock }
    $back = if ($NB -and @($NB.Contexts | Where-Object { $_ -and $_.status -eq 'open' }).Count) { 'Visible' } else { 'Collapsed' }
    if ($ui.CtxListBadge.Visibility -ne $back) { $ui.CtxListBadge.Visibility = $back }
    if ($script:tray) {
        $tip = "Orbit - $txt - $($O.FocusToday) focus aujourd'hui"
        $tip = Get-TextStart $tip 63
        $script:tray.Text = $tip
    }
}

# ---------------------------------------------------------------------------
#  Plan du matin : a la premiere apparition de la journee (a partir de 5 h),
#  Orbit propose les 3 cartes les plus urgentes et lance le focus dessus
# ---------------------------------------------------------------------------
function Test-MorningPlanDue {
    $now = Get-Date
    return ($Config.MorningPlan -and $O.State -eq 'Idle' -and $now.Hour -ge 5 -and $O.PlanDay -ne $now.ToString('yyyy-MM-dd'))
}

function Show-MorningPlan {
    $O.PlanDay = (Get-Date).ToString('yyyy-MM-dd')
    Save-Stats
    $plan = @(Get-PlanCards 3)
    $hello = if ((Get-Date).Hour -lt 12) { '☀ Bonjour !' } else { '👋 Re-bonjour !' }
    if (-not $plan.Count -and (Get-LatestOpenContext)) { Show-ResumeBubble (Get-LatestOpenContext); return }
    if (-not $plan.Count) {
        Show-Bubble "$hello Tes tableaux sont vides : note tes tâches du jour et je t'aiderai à les attaquer dans le bon ordre." -Force -AutoHide -Seconds 90 -Buttons @(
            $BtnTodo, @{ Label = '🚀 Focus quand même'; Action = { Start-Focus } }, $BtnLater)
        return
    }
    $O.PlanIds = @($plan | ForEach-Object { $_.Card.id })
    $text = "$hello Mon plan pour ta journée :"
    $ctx = Get-LatestOpenContext
    $ctxBtn = @()
    if ($ctx) {
        $script:BubbleCtxId = $ctx.id
        $text = "$hello ↩ Tu t'étais arrêté(e) $(Format-Ago $ctx.created) sur « $(Get-ContextTitle $ctx 50) »."
        $text += "`n`nEnsuite, mon plan pour ta journée :"
        $ctxBtn = @(@{ Label = '↩ Reprendre là'; Action = { Resume-Context $script:BubbleCtxId } })
    }
    $i = 1
    foreach ($p in $plan) {
        $text += "`n$i. P$($p.Card.prio) « $(Short-Text $p.Card.text 45) »"
        if ($p.Why) { $text += "`n     $($p.Why)" }
        $i++
    }
    $rest = @(Get-OpenTodos).Count - $plan.Count
    if ($rest -gt 0) { $text += "`n(+ $rest autre(s) carte(s) dans tes tableaux)" }
    $text += "`n`nOn s'y met ?"
    Show-Bubble $text -Force -AutoHide -Seconds 180 -Buttons (@($ctxBtn) + @(
        @{ Label = '🎯 Go, focus sur ces cartes'; Action = { Accept-MorningPlan }; Primary = $true },
        @{ Label = '✏ Choisir autre chose'; Action = { Choose-FocusCards -Start -Preselect $O.PlanIds } },
        $BtnTodo,
        @{ Label = 'Plus tard'; Action = { Show-Bubble "Ok ! Clic droit > ☰ Plus > ☀ Plan du jour pour le revoir." -Force -Seconds 4 } }))
}

# ---------------------------------------------------------------------------
#  Zone finale du focus : compte a rebours sonore et visuel
#  Choix de conception : pas de tic-tac pendant tout le focus (il capterait l'attention
#  et ferait l'inverse du but). Le son ne commence qu'a l'approche de la fin et
#  s'accelere : toutes les 20 s, puis 10 s (2 dernieres min), 5 s (derniere minute),
#  2 s (30 dernieres s), et chaque seconde, plus aigu, pour les 10 dernieres.
# ---------------------------------------------------------------------------
function Get-TickInterval([double]$leftSec, [double]$zoneSec) {
    if ($leftSec -le 0 -or $leftSec -gt $zoneSec) { return 0 }
    if ($leftSec -gt 120) { return 20 }
    if ($leftSec -gt 60) { return 10 }
    if ($leftSec -gt 30) { return 5 }
    if ($leftSec -gt 10) { return 2 }
    return 1
}

# niveau d'urgence pour les couleurs : calme > 50 %, attention > 25 %, presse, puis final (derniere minute)
function Get-UrgencyLevel([double]$frac, [double]$leftSec) {
    if ($leftSec -le 60) { return 'final' }
    if ($frac -gt 0.5) { return 'calm' }
    if ($frac -gt 0.25) { return 'mid' }
    return 'high'
}
$UrgencyColors = @{ calm = '#FF4C8DFF'; mid = '#FFFFC93C'; high = '#FFFF8A1C'; final = '#FFFF4D4D'; break = '#FF3DDC84'; paused = '#FF8A8FA3' }

# un « tic » court et doux (WAV en memoire), plus aigu pour les 10 dernieres secondes
function New-TickWav([double]$freq, [int]$volume) {
    $rate = 22050; $n = [int]($rate * 0.045)
    $amp = 9000 * [math]::Min(1, [math]::Max(0.05, $volume / 100))
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $ms
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n * 2)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n * 2))
    for ($i = 0; $i -lt $n; $i++) {
        $env = [math]::Exp(-$i / ($n / 5.0)) * [math]::Min(1, $i / 40.0)
        $w.Write([int16]($amp * $env * [math]::Sin(2 * [math]::PI * $freq * $i / $rate)))
    }
    $w.Flush()
    return $ms.ToArray()
}

function Play-Tick([bool]$high) {
    $key = "$high|$($Config.DroidVolume)"
    if ($script:TickKey -ne $key) { $script:TickKey = $key; $script:TickWav = New-TickWav $(if ($high) { 1568 } else { 1046 }) $Config.DroidVolume }
    try {
        $script:TickPlayer = New-Object System.Media.SoundPlayer (New-Object IO.MemoryStream (, $script:TickWav))
        $script:TickPlayer.Play()
    } catch { Write-Log "Tic : $($_.Exception.Message)" }
}

function Step-Ticks([datetime]$now) {
    if (-not $Config.TickSound -or $Config.DroidVolume -le 0 -or $O.State -ne 'Focus' -or $O.Paused) { $O.NextTick = [datetime]::MinValue; return }
    $left = ($O.EndsAt - $now).TotalSeconds
    $iv = Get-TickInterval $left ($Config.TickZoneMin * 60)
    if (-not $iv) { $O.NextTick = [datetime]::MinValue; return }
    if ($now -lt $O.NextTick) { return }
    Play-Tick ($left -le 10)
    $O.NextTick = $now.AddSeconds($iv - 0.1)
}

# la barre : longueur = temps restant, couleur = urgence (rafraichie chaque seconde)
function Update-UrgencyChip([datetime]$now = (Get-Date)) {
    $show = $Config.UrgencyBar -and $O.State -in 'Focus', 'Break' -and -not $O.Mini
    $vis = if ($show) { 'Visible' } else { 'Collapsed' }
    if ($ui.UrgencyChip.Visibility -ne $vis) { $ui.UrgencyChip.Visibility = $vis }
    if (-not $show) { $O.UrgencyLevel = ''; return }
    $total = 60 * $(if ($O.State -eq 'Focus') { [math]::Max(1, $O.SessionMin) } else { [math]::Max(1, $Config.BreakMinutes) })
    $left = if ($O.Paused) { $O.Remaining.TotalSeconds } else { ($O.EndsAt - $now).TotalSeconds }
    $left = [math]::Max(0, $left)
    $frac = [math]::Min(1, $left / $total)
    $level = if ($O.Paused) { 'paused' } elseif ($O.State -eq 'Break') { 'break' } else { Get-UrgencyLevel $frac $left }
    $O.UrgencyLevel = $level
    # derniere minute : la barre « zoome » sur ces 60 secondes (rouge, elle se vide seconde par seconde)
    $shown = if ($level -eq 'final') { [math]::Min(1, $left / 60) } else { $frac }
    $ui.UrgencyFill.Width = [math]::Max(4, 65 * $shown)
    $ui.UrgencyFill.Background = $UrgencyColors[$level]
    $ui.UrgencyText.Foreground = if ($level -eq 'mid') { '#FF1E1B3A' } else { '#FFFFFFFF' }
    $ui.UrgencyText.Text = '{0}{1}:{2:00}' -f $(if ($O.Paused) { '⏸' } else { '' }), [math]::Floor($left / 60), [math]::Floor($left % 60)
    if ($level -ne 'final') { $ui.UrgencyChip.Opacity = 1 }
}

# ---------------------------------------------------------------------------
#  Relance « Tu attends quoi ? » : aucun focus depuis 45 min (reglable) alors que des
#  cartes attendent -> 2 ou 3 propositions, un clic lance le focus sur l'une d'elles.
#  Jamais pendant un focus ou une pause, ni si tu n'es pas devant l'ecran, ni par-dessus
#  une autre question, ni quand Orbit est cache ou reduit ; « Plus tard » = dans 45 min, « Pas aujourd'hui » = jusqu'a demain.
# ---------------------------------------------------------------------------
function Test-IdleNudgeDue([datetime]$now, [double]$idleMs = 0) {
    if (-not $Config.IdleNudge) { return $false }
    if ($O.State -ne 'Idle') { $O.LastBusy = $now; return $false }
    if ($O.NudgeOffDay -eq $now.ToString('yyyy-MM-dd')) { return $false }
    if (($now - $O.LastBusy).TotalMinutes -lt $Config.IdleNudgeMin) { return $false }
    if ($idleMs -gt 120000) { return $false }   # pas devant l'ecran : on attend ton retour
    return $true
}

function Show-IdleNudge([datetime]$now = (Get-Date)) {
    $plan = @(Get-PlanCards 3)
    $O.LastBusy = $now   # prochaine relance dans 45 min au plus tot
    if (-not $plan.Count) { return $false }
    $O.NudgeIds = @($plan | ForEach-Object { $_.Card.id })
    $text = (Pick @("Tiens ! Ça fait un moment qu'on n'a pas lancé de focus 👀", "Psst… tes tâches t'attendent 👀", "Hé, on se lance ? Il y a du monde qui attend 😄")) +
        "`nTu as des tâches en cours, qu'est-ce que tu attends ? Je te propose :"
    $i = 1
    foreach ($p in $plan) {
        $text += "`n$i. « $(Short-Text $p.Card.text 45) »$(if ($p.Why) { " ($($p.Why))" })"
        $i++
    }
    $text += "`nOn lance un focus sur l'une d'elles ?"
    $buttons = @(
        @{ Label = "🎯 1. $(Short-Text $plan[0].Card.text 22)"; Action = { Start-NudgeCard 0 }; Primary = $true }
    )
    if ($plan.Count -ge 2) { $buttons += @{ Label = "🎯 2. $(Short-Text $plan[1].Card.text 22)"; Action = { Start-NudgeCard 1 } } }
    if ($plan.Count -ge 3) { $buttons += @{ Label = "🎯 3. $(Short-Text $plan[2].Card.text 22)"; Action = { Start-NudgeCard 2 } } }
    $buttons += @{ Label = '⏰ Plus tard'; Action = { $O.LastBusy = Get-Date } }
    $buttons += @{ Label = "🌙 Pas aujourd'hui"; Action = { $O.NudgeOffDay = (Get-Date).ToString('yyyy-MM-dd'); Show-Bubble "Ok, je ne te relance plus aujourd'hui 🌙" -Seconds 4 } }
    Ensure-Visible
    Show-Bubble $text -Force -AutoHide -Seconds 300 -Buttons $buttons
    return $true
}

function Start-NudgeCard([int]$i) {
    $id = @($O.NudgeIds)[$i]
    if (-not $id -or -not (Find-Todo $id)) { Show-Bubble "Cette carte n'existe plus 🤔" -Force -Seconds 4; return }
    Set-FocusCards @($id)
    Start-Focus
}

function Check-IdleNudge([datetime]$now) {
    $idle = if ($Native) { [OrbitNative]::IdleMs() } else { 0 }
    if (-not (Test-IdleNudgeDue $now $idle)) { return }
    # pas par-dessus une autre question, ni quand Orbit est cache, ni avant le plan du matin
    # (ni en mode « Réduire », ou Orbit a promis de se taire)
    if (-not $window.IsVisible -or $O.Mini -or $ui.BubbleButtons.Children.Count -or (Test-MorningPlanDue)) { return }
    [void](Show-IdleNudge $now)
}

function Accept-MorningPlan {
    Set-FocusCards $O.PlanIds
    Start-Focus
}

function Show-Status {
    # une reprise recente attend : « Où j'en étais ? » (sauf pendant un focus qui tourne)
    # (une seule fois par quart d'heure : ensuite, un bouton « ↩ Où j'en étais » suffit)
    if ($O.State -eq 'Idle' -or ($O.State -in 'Focus', 'Break' -and $O.Paused)) {
        $ctx = Get-ContextToOffer 15
        if ($ctx -and -not ($O.State -eq 'Idle' -and (Test-MorningPlanDue))) { Show-ResumeBubble $ctx; return }
    }
    switch ($O.State) {
        'Idle'       {
            if (Test-MorningPlanDue) { Show-MorningPlan; return }
            $hello = Pick $Lines.Hello
            $due = Get-DeadlineSummary
            if ($due) { $hello += "`n`n$due" }
            $ctxBtn = @()
            $open = Get-LatestOpenContext
            if ($open) { $script:BubbleCtxId = $open.id; $ctxBtn = @(@{ Label = "↩ Où j'en étais"; Action = { Show-ResumeBubble (Find-Context $script:BubbleCtxId) } }) }
            Show-Bubble $hello -Buttons (@(Get-StartButtons) + @($BtnPickCards, $BtnTodo) + $ctxBtn + @($BtnLater)) -Force -AutoHide -Seconds 60
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
    if ($O.State -eq 'Focus' -and -not $O.Paused) {
        foreach ($t in $TitleLines) { if ($lowTitle.Contains($t.k)) { $line = Pick $t.l; break } }
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
    if (-not $Skins[$O.Skin].Bits) { return }
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
    if ($dt -gt 0.3) { $dt = 0.3 }
    $O.LastFrame = $now
    $O.Time += $dt
    $t = $O.Time
    # derniere minute : la barre pulse (de plus en plus vite)
    if ($O.UrgencyLevel -eq 'final') {
        $left = [math]::Max(1, ($O.EndsAt - $now).TotalSeconds)
        $ui.UrgencyChip.Opacity = 0.55 + 0.45 * [math]::Abs([math]::Sin($t * [math]::Min(12, 3 + 40 / $left)))
    }

    # (la derive lente dans l'espace est une animation WPF : voir Start-Floating)

    # animations (yeux, balises, LED...) : isolees, pour qu'un souci d'affichage
    # n'empeche jamais Orbit de se deplacer ou de ranger sa bulle
    Invoke-Safe {
        $sk = $Skins[$O.Skin]

        # balises : un flash regulier, clignotement rapide quand Orbit attend une reponse
        $beacon = if ($O.State -like 'Await*') { 0.3 + 0.7 * [math]::Abs([math]::Sin($t * 4)) }
                  elseif (($t % 2.0) -lt 0.18) { 1 } else { 0.35 }
        foreach ($n in $sk.Beacons) { $ui[$n].Opacity = $beacon }

        # les yeux (ou la camera) suivent la souris
        $c = Get-CursorDip
        if ($O.LastCursor -and ([math]::Abs($c.X - $O.LastCursor.X) + [math]::Abs($c.Y - $O.LastCursor.Y)) -gt 0.5) { $O.CursorMovedAt = $now }
        $O.LastCursor = $c
        $scale = $ui.BotScale.ScaleX
        # centre du regard, en tenant compte de l'agrandissement propre a chaque dessin (autour de 60,88)
        $k = if ($sk.Scale) { $sk.Scale } else { 1 }
        $ex = 60 + ($sk.EyeX - 60) * $k
        $ey = 88 + ($sk.EyeY - 88) * $k
        $cx = $window.Left + $window.Width - (120 - $ex) * $scale
        $cy = $window.Top + $window.Height - (98 - $ey) * $scale
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
                $ui.NavL.Opacity = if (($t % 1.6) -lt 0.16) { 1 } else { 0.25 }
                $ui.NavR.Opacity = if ((($t + 0.8) % 1.6) -lt 0.16) { 1 } else { 0.25 }
                $g = $t % 7
                $ui.GlintL.X = -40 + [math]::Min(1, $g / 1.4) * 90
                $ui.GlintR.X = -40 + [math]::Min(1, [math]::Max(0, $g - 0.35) / 1.4) * 90
            }
            'Brain' {
                # activite neuronale discrete : de petites etincelles s'allument a tour de role
                for ($k = 1; $k -le 4; $k++) {
                    $ph = ($t * 0.9 + $k * 0.53) % 2.2
                    $ui["CSpark$k"].Opacity = if ($ph -lt 0.22) { 0.75 } else { 0 }
                }
            }
            'Human' {
                $ui.HSteam.Opacity = 0.45 + 0.35 * [math]::Sin($t * 2.3)
            }
            'Butler' {
                # la vapeur du cafe ondule (l'anneau holographique tourne tout seul : Start-Floating)
                $ui.MSteam.Opacity = 0.45 + 0.35 * [math]::Sin($t * 2.3)
            }
        }

        # afficheur binaire : minutes restantes pendant une session, balayage au repos
        Update-Bits $t
    } 'animation'

    Invoke-Safe {

        # bulle temporaire
        if ($ui.BubbleWrap.Visibility -eq 'Visible' -and $now -ge $O.BubbleUntil) { Hide-Bubble }
    } 'bulle'

    # deplacements
    $O.Busy = $false
    if ($O.Dragging -or $window.Visibility -ne 'Visible') { $O.Busy = $O.Dragging; Set-FrameRate; return }
    if ($O.Pinned) { Set-FrameRate; return }

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
            if ($ui.Lean.Angle -ne 0) { $ui.Lean.Angle = 0 }
            Set-FrameRate
            return
        }
        $step = [math]::Min($d, 140 * $dt)      # balade tranquille
        $window.Left += $wx / $d * $step
        $window.Top += $wy / $d * $step
        $ui.Lean.Angle = 6 * $wx / $d   # s'incline dans le sens du deplacement
        $O.Busy = $true
        Set-FrameRate
        return
    }
    if ($ui.Lean.Angle -ne 0) { $ui.Lean.Angle = 0 }

    $h = $O.Home
    if ($h) {
        $hx = $h.X - $window.Left; $hy = $h.Y - $window.Top
        $hd = [math]::Sqrt($hx * $hx + $hy * $hy)
        if ($hd -gt 0.5) {
            $k = [math]::Min(1, $dt * 4)
            $mv = [math]::Max($hd * $k, [math]::Min($hd, 300 * $dt))
            $window.Left += $hx / $hd * $mv
            $window.Top += $hy / $hd * $mv
            $O.Busy = $true
        }
    }
    Set-FrameRate
}

# ---------------------------------------------------------------------------
#  Economie de processeur : 25 images/s seulement quand Orbit bouge (balade,
#  retour a sa place, glisser) ou que la souris bouge (ses yeux la suivent).
#  Sinon ~7 images/s, et plus rien du tout quand il est cache. Le flottement
#  et l'anneau du majordome sont des animations WPF, fluides sans PowerShell.
# ---------------------------------------------------------------------------
$FrameFastMs = 40
$FrameCalmMs = 150

function Set-FrameRate {
    $fast = $O.Busy -or (([datetime]::Now - $O.CursorMovedAt).TotalSeconds -lt 1.5)
    $ms = if ($fast) { $FrameFastMs } else { $FrameCalmMs }
    if ($script:frameTimer -and $script:frameTimer.Interval.TotalMilliseconds -ne $ms) {
        $script:frameTimer.Interval = [timespan]::FromMilliseconds($ms)
    }
}

function Start-Floating {
    $loop = [Windows.Media.Animation.RepeatBehavior]::Forever
    $ease = New-Object Windows.Media.Animation.SineEase
    $ease.EasingMode = 'EaseInOut'
    $bob = New-Object Windows.Media.Animation.DoubleAnimation(-2.5, 2.5, [timespan]::FromSeconds(1.96))
    $bob.AutoReverse = $true; $bob.RepeatBehavior = $loop; $bob.EasingFunction = $ease
    $tilt = New-Object Windows.Media.Animation.DoubleAnimation(-3, 3, [timespan]::FromSeconds(4.5))
    $tilt.AutoReverse = $true; $tilt.RepeatBehavior = $loop; $tilt.EasingFunction = $ease
    # ~30 images/s suffisent largement pour des mouvements aussi doux
    foreach ($a in $bob, $tilt) { [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($a, 30) }
    $ui.Bob.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $bob)
    $ui.Tilt.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $tilt)
}

# l'anneau holographique du majordome (lance quand ce dessin est construit)
function Start-HudSpin {
    if (-not $ui.MHud) { return }
    $hud = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, [timespan]::FromSeconds(25.7))
    $hud.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($hud, 30)
    $ui.MHud.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $hud)
}

# ---------------------------------------------------------------------------
#  Etat du cycle (etat.json) : enregistre a chaque changement, pour qu'apres un
#  plantage ou un redemarrage force Orbit reprenne le chrono la ou il en etait.
#  Une fermeture normale (Quitter) l'efface ; au-dela de 4 h, il est ignore.
# ---------------------------------------------------------------------------
function Get-StateMood {
    switch -Wildcard ($O.State) { 'Focus' { 'Focus' } 'Break' { 'Break' } 'Await*' { 'Await' } default { 'Idle' } }
}

function Save-State {
    try {
        if ($O.State -eq 'Idle') { Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue; return }
        $data = [ordered]@{
            state = $O.State; paused = [bool]$O.Paused; endsAt = $O.EndsAt.ToString('o')
            remainingSec = [math]::Round($O.Remaining.TotalSeconds); sessionMin = $O.SessionMin
            savedAt = (Get-Date).ToString('o')
        }
        Write-FileSafe $StateFile (ConvertTo-Json -InputObject $data)
    } catch { Write-Log "Ecriture etat : $($_.Exception.Message)" }
}

# Renvoie la phrase a afficher si un cycle a ete repris, sinon rien
function Restore-State {
    if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
    try {
        $d = ConvertFrom-Json ([IO.File]::ReadAllText($StateFile))
        $saved = if ($d.savedAt -is [datetime]) { $d.savedAt } else { [datetime]::Parse([string]$d.savedAt, $null, 'RoundtripKind') }
        if (((Get-Date) - $saved.ToLocalTime()).TotalHours -gt 4) { return $null }
        $state = [string]$d.state
        if ($state -notin 'Focus', 'Break', 'AwaitBreak', 'AwaitFocus') { return $null }
        $O.State = $state
        $O.SessionMin = [double]$d.sessionMin
        $O.Paused = [bool]$d.paused
        $O.Remaining = [timespan]::FromSeconds([double]$d.remainingSec)
        $O.EndsAt = if ($d.endsAt -is [datetime]) { $d.endsAt.ToLocalTime() } else { [datetime]::Parse([string]$d.endsAt, $null, 'RoundtripKind').ToLocalTime() }
        $O.NextReminder = (Get-Date).AddMinutes($Config.ReminderEveryMin)
        Write-Log "Cycle repris : $state"
        $intro = if ($Restarted) { "Oups, j'ai eu un petit bug, mais je suis de retour 🛠" } else { "Je reprends là où on en était 🔄" }
        switch ($state) {
            'Focus' {
                $O.NextMotivation = (Get-Date).AddMinutes($Config.MotivationEveryMin)
                $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
                if ($left.TotalSeconds -le 0) { return "$intro Ton focus s'est terminé entre-temps." }
                return "$intro Encore $([math]::Ceiling($left.TotalMinutes)) min de focus$(if ($O.Paused) { ' (en pause ⏸)' }). 🎯"
            }
            'Break' {
                $O.NextBreakLine = (Get-Date).AddSeconds(40)
                $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
                if ($left.TotalSeconds -le 0) { return "$intro Ta pause s'est terminée entre-temps." }
                return "$intro Encore $([math]::Ceiling($left.TotalMinutes)) min de pause ☕"
            }
            default { return $null }   # Orbit repose sa question (Show-Status)
        }
    } catch { Write-Log "Lecture etat : $($_.Exception.Message)" }
    return $null
}

# ---------------------------------------------------------------------------
#  Menage memoire : quand tu ne touches a rien depuis une minute (ou qu'Orbit
#  est cache), on libere ce qui ne sert plus et on rend la memoire a Windows.
#  45 s apres le demarrage, puis toutes les 10 minutes au plus.
# ---------------------------------------------------------------------------
function Trim-Memory {
    $idle = if ($Native) { [OrbitNative]::IdleMs() } else { 120000 }
    if ($idle -lt 60000 -and $window.IsVisible -and $O.TrimCount -gt 0) {
        $O.NextTrim = (Get-Date).AddMinutes(1)      # tu es actif : on reessaie plus tard
        return
    }
    $proc = [Diagnostics.Process]::GetCurrentProcess()
    $before = $proc.WorkingSet64
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
    if ($Native) { [OrbitNative]::TrimMemory() }
    $O.TrimCount++
    $O.NextTrim = (Get-Date).AddMinutes(10)
    if ($O.TrimCount -eq 1 -or $O.TrimCount % 12 -eq 0) {
        $proc.Refresh()
        Write-Log ("Memoire : {0:N0} Mo -> {1:N0} Mo" -f ($before / 1MB), ($proc.WorkingSet64 / 1MB))
    }
}

# ---------------------------------------------------------------------------
#  Boucle lente (1 fois / seconde) : chrono, commentaires, premier plan
# ---------------------------------------------------------------------------
$script:slowCount = 0
function On-Second {
    $now = Get-Date
    $script:slowCount++
    $n = $script:slowCount
    # chaque tache est isolee : si l'une echoue (presse-papiers occupe, fichier verrouille...),
    # les autres continuent, et l'erreur est notee dans le journal avec le nom de la tache
    Invoke-Safe { $O.Home = Get-HomePos } 'position'
    if ($env:ORBIT_AUTOPILOT) { Invoke-Safe { Step-Autopilot $now } 'autopilote' }
    $script:TimerEnded = $false
    Invoke-Safe { $script:TimerEnded = Step-Timer $now } 'chrono'
    if ($script:TimerEnded) { Invoke-Safe { Update-Pill } 'chrono'; return }
    Invoke-Safe { Step-AwaitReminder $now } 'relance'
    Invoke-Safe { Step-Ticks $now } 'compte a rebours sonore'
    Invoke-Safe { Update-UrgencyChip $now } 'compte a rebours visuel'
    if ($n % 2 -eq 0) { Invoke-Safe { Check-Idle } 'absence' }
    if ($n % 2 -eq 1) { Invoke-Safe { Check-ContextReturn } 'reprise au retour' }
    if ($n % 15 -eq 7) { Invoke-Safe { Check-ContextReminders $now } 'rappel de reprise' }
    if ($now -ge $O.NextTrim) { Invoke-Safe { Trim-Memory } 'memoire' }
    Invoke-Safe { Update-TrayIcon } 'icone'
    if ($n -eq 20) { Invoke-Safe { [void](Set-TrayPromoted $true -OnlyIfUnset) } 'epinglage' }
    if ($n % 15 -eq 0) {
        Invoke-Safe {
            if ($window.IsVisible -and (Test-MorningPlanDue) -and $ui.BubbleButtons.Children.Count -eq 0 -and
                (-not $Native -or [OrbitNative]::IdleMs() -lt 60000)) { Show-MorningPlan }
        } 'plan du matin'
    }
    Invoke-Safe {
        $sig = "$($O.State)|$($O.Paused)|$($O.EndsAt.Ticks)|$($O.SessionMin)"
        if ($sig -ne $script:StateSig) { $script:StateSig = $sig; Save-State }
    } 'etat'
    if ($n % 10 -eq 0) { Invoke-Safe { Check-TaskReminders } 'rappels' }
    if ($n % 15 -eq 11) { Invoke-Safe { Check-IdleNudge $now } 'relance sans focus' }
    if ($Native -or $n % 2 -eq 0) { Invoke-Safe { Check-Clipboard } 'presse-papiers' }
    if ($n % 2 -eq 0 -and $window.Visibility -eq 'Visible') { Invoke-Safe { Check-App } 'appli' }
    if ($n % 5 -eq 0 -and $Native -and $O.Hwnd -ne [IntPtr]::Zero -and $window.Visibility -eq 'Visible') {
        Invoke-Safe { [OrbitNative]::KeepOnTop($O.Hwnd) } 'premier plan'
    }
    if ($n % 5 -eq 0) { Invoke-Safe { Test-Watchdogs } 'surveillance' }
    Invoke-Safe { Update-Pill } 'affichage'
}

# Chrono focus / pause. Renvoie $true quand la session vient de se terminer.
function Step-Timer($now) {
    if (($O.State -notin 'Focus', 'Break') -or $O.Paused) { return $false }
    $left = $O.EndsAt - $now
    if ($left.TotalSeconds -le 0) { On-TimerEnded; return $true }
    if ($O.State -eq 'Break' -and $now -ge $O.NextBreakLine) {
        # une petite phrase sympa toutes les ~2 minutes pendant la pause (sauf dans les 20 dernieres secondes)
        $base = [math]::Max(20, $Config.BreakLineEveryMin * 60)
        $O.NextBreakLine = $now.AddSeconds((Get-Random -Minimum ([int]($base * 0.75)) -Maximum ([int]($base * 1.25) + 1)))
        if ($Config.BreakLines -and $left.TotalSeconds -gt 20) { Tell-BreakItem }
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
    return $false
}

# Orbit attend une reponse : il relance gentiment de temps en temps
function Step-AwaitReminder($now) {
    if ($O.State -notlike 'Await*' -or $now -lt $O.NextReminder) { return }
    $O.NextReminder = $now.AddMinutes($Config.ReminderEveryMin)
    Ensure-Visible
    $pool = if ($O.State -eq 'AwaitBreak') { $Lines.AwaitBreak } else { $Lines.AwaitFocus }
    if ($O.State -eq 'AwaitBreak') { Ask-Break (Pick $pool) }
    else { Show-Bubble (Pick $pool) -Buttons @($BtnAgain, $BtnStop) -Force }
}

# Chiens de garde : remettent Orbit d'aplomb si quelque chose a deraille
function Test-Watchdogs {
    # l'animation doit tourner quand Orbit est affiche
    if ($window.IsVisible -and -not $script:frameTimer.IsEnabled -and -not $NB.Quitting) {
        $O.LastFrame = [datetime]::Now
        $script:frameTimer.Start()
        Write-Log "Surveillance : animation relancee"
    }
    # un ecran debranche peut laisser Orbit hors de tout ecran : on le ramene
    if ($window.IsVisible -and -not $O.Dragging) {
        $onScreen = $false
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            $wa = Get-WorkArea $scr
            if ($window.Left + $window.Width -gt $wa.L + 40 -and $window.Left -lt $wa.R - 40 -and
                $window.Top + $window.Height -gt $wa.T + 40 -and $window.Top -lt $wa.B - 40) { $onScreen = $true; break }
        }
        if (-not $onScreen) {
            $O.Pinned = $false; $O.Walking = $false
            $h = Get-HomePos
            $window.Left = $h.X; $window.Top = $h.Y
            Write-Log "Surveillance : Orbit etait hors de l'ecran, ramene a sa place"
        }
    }
    # Orbit se cache le temps d'une capture d'ecran (« Je m'interromps ») : jamais plus longtemps
    if ($window.Opacity -lt 1 -and -not ($script:CtxShotTimer -and $script:CtxShotTimer.IsEnabled)) {
        $window.Opacity = 1
        Write-Log "Surveillance : Orbit etait reste transparent, il reapparait"
    }
    # la bulle ne doit jamais rester bloquee « visible » sans texte
    if ($ui.BubbleWrap.Visibility -eq 'Visible' -and -not $ui.BubbleText.Text -and $ui.BubbleButtons.Children.Count -eq 0) { Hide-Bubble }
}

# Mode « pilote automatique » pour les tests d'endurance (variable ORBIT_AUTOPILOT) :
# Orbit enchaine tout seul focus et pauses, se balade, ouvre ses fenetres...
function Step-Autopilot($now) {
    if ($script:ApNext -and $now -lt $script:ApNext) { return }
    $script:ApNext = $now.AddSeconds(3)
    # personne devant la machine de test : la pause automatique en cas d'absence bloquerait tout
    $Config.IdlePause = $false
    if ($O.Paused -and $O.State -in 'Focus', 'Break') { Toggle-Pause }
    switch ($O.State) {
        'Idle'       { Start-Focus }
        'AwaitBreak' { Hide-Bubble; Start-Break }
        'AwaitFocus' { Hide-Bubble; Start-Focus }
    }
    if (-not $O.Walking) { $O.NextWalk = $now }
    # compteur propre au pilote (un tour toutes les 3 s) : chaque action revient a coup sur
    $script:ApTicks++
    $k = $script:ApTicks
    if ($k % 9 -eq 0) { Show-QuickNote; $qn.QnText.Text = "autopilote $($now.ToString('HH:mm:ss'))"; Close-QuickNote }
    if ($k % 11 -eq 0) { Open-Notebook 'Todo'; Close-Notebook }
    if ($k % 13 -eq 0) { Tell-BreakItem }
    # une interruption complete (une fois sur deux avec capture d'ecran) : fenetres, post-it,
    # enregistrement au tour suivant, puis terminee
    if ($script:ctxWin -and $ctxWin.IsVisible) {
        $cx.CtxNext.Text = "autopilote $($now.ToString('HH:mm:ss'))"
        Close-ContextEditor
        $c = Get-LatestOpenContext
        if ($c) { Complete-Context $c.id }
        if ($O.State -eq 'Focus' -and $O.Paused) { Toggle-Pause }
    } elseif ($k % 17 -eq 0) {
        $Config.ContextScreenshot = ($k % 34 -eq 0)
        Start-Interruption
    }
    # S.O.S : se debloquer etape par etape, puis le journal des victoires
    if ($k % 23 -eq 0) {
        Start-UnstickFor "Répondre au mail $k"
        while ($Anchor.Unstick) { Complete-UnstickUi }
        Close-AnchorFocus
        [void](Get-WinsText)
    }
    if ($k % 10 -eq 0) {
        $p = [Diagnostics.Process]::GetCurrentProcess()
        Write-Log ("Autopilote : etat {0}, focus {1}, reprises {4}, victoires {5}, memoire {2:N0} Mo, poignees {3}" -f $O.State, $O.FocusToday, ($p.PrivateMemorySize64 / 1MB), $p.HandleCount, @($NB.Contexts).Count, @($Anchor.Wins).Count)
    }
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
    # via conhost --headless : aucune fenetre, meme avec Windows Terminal comme console par defaut
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$OrbitScript`""
    if ($OrbitCanHeadless) {
        $lnk.TargetPath = $OrbitConhost
        $lnk.Arguments = "--headless `"$OrbitPowerShell`" $psArgs"
    } else {
        $lnk.TargetPath = $OrbitPowerShell
        $lnk.Arguments = $psArgs
    }
    $lnk.WorkingDirectory = Split-Path $OrbitScript
    $lnk.WindowStyle = 7
    $lnk.Description = 'Orbit - compagnon de focus'
    $lnk.Save()
    if (-not $Silent) { Show-Bubble "C'est noté, je serai là à chaque démarrage de Windows 🚀 (sans droits admin)" -Force }
}

function Toggle-Autostart { Set-Autostart (-not (Test-Path $StartupLink)) }

# Un ancien raccourci de demarrage (lancement direct de powershell.exe) ouvrirait une
# fenetre Windows Terminal : on le remplace par la version sans fenetre
if (-not $env:ORBIT_SELFTEST -and (Test-Path $StartupLink)) {
    try { Set-Autostart $true -Silent } catch { Write-Log "Raccourci de demarrage : $($_.Exception.Message)" }
}

function Set-Mini([bool]$on) {
    $O.Mini = $on
    $s = if ($on) { 0.7 } else { 1.25 }
    $ui.BotScale.ScaleX = $s
    $ui.BotScale.ScaleY = $s
    $ui.BubbleWrap.Margin = if ($on) { '0,0,10,72' } else { '0,0,10,127' }
    $ui.SpeechTail.Margin = if ($on) { '0,-3.5,28,0' } else { '0,-3.5,61,0' }
    $ui.ThoughtTail.Margin = if ($on) { '0,3,26,0' } else { '0,3,59,0' }
    $ui.Dock.Margin = if ($on) { '0,0,86,2' } else { '0,0,146,6' }
    if ($on) { $O.Walking = $false }
    Fit-BubbleWindow
}

function Toggle-OrbitVisible {
    if ($window.Visibility -eq 'Visible') { Hide-Orbit } else { Ensure-Visible; Show-Status }
}

function Hide-Orbit {
    $window.Hide()
    Hide-Bubble
    if (-not $script:HideTipShown) {
        $script:HideTipShown = $true
        Show-Tray "Orbit est caché 🛰" "Je reste près de l'horloge : mon icône affiche le chrono. Un clic dessus pour me faire revenir."
    }
}

# Redemarrage sans rien enregistrer (apres un import : les fichiers viennent d'etre remplaces)
function Restart-Orbit {
    $script:RelaunchAfterExit = $true
    $NB.Quitting = $true
    $NB.MdPending = $false; $NB.ClipPending = $false
    $script:frameTimer.Stop()
    $script:secondTimer.Stop()
    $app.Shutdown()
}

function Quit-Orbit {
    Save-Stats
    if ($NB.EditId) { End-EditTodo -NoRender } else { Save-Todos }
    Flush-Notebook
    if ($script:qnWin -and $qnWin.IsVisible) { Close-QuickNote }
    # fermeture voulue : au prochain lancement, on repart de zero
    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    $NB.Quitting = $true
    $script:frameTimer.Stop()
    $script:secondTimer.Stop()
    $app.Shutdown()
}

# ---------------------------------------------------------------------------
#  Carnet : tableaux Kanban + historique des copier-coller (voir notebook.ps1)
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'notebook.ps1')
. (Join-Path $PSScriptRoot 'notes.ps1')
. (Join-Path $PSScriptRoot 'context.ps1')
. (Join-Path $PSScriptRoot 'anchor.ps1')
. (Join-Path $PSScriptRoot 'settings.ps1')

$menu = New-Object Windows.Controls.ContextMenu
$miCtx    = New-MenuItem "✋  Je m'interromps (garder où j'en suis)" { Start-Interruption }
$miCtxList = New-MenuItem "↩  Mes reprises" { Open-Notebook 'Ctx' }
$miSos    = New-MenuItem "🚨  S.O.S : je bloque (une seule chose à la fois)" { Show-Sos }
$miNote   = New-MenuItem "📝  Note rapide" { Show-QuickNote }
$miNotes  = New-MenuItem "📒  Mes notes" { Open-Notebook 'Notes' }
$miTodo   = New-MenuItem "🗂  Mes tableaux (Kanban)" { Open-Notebook 'Todo' }
$miClip   = New-MenuItem "📋  Mes copier-coller du jour" { Open-Notebook 'Clip' }
$miFocus  = New-MenuItem "🚀  Lancer un focus" { Start-Focus }
$miBreak  = New-MenuItem "☕  Prendre ma pause" { Start-Break }
$miPause  = New-MenuItem "⏸  Mettre le chrono en pause" { Toggle-Pause }
$miStop   = New-MenuItem "⏹  Couper le chrono" { Stop-Cycle }
$miCards  = New-MenuItem "🎯  Cartes du focus…" { Choose-FocusCards }
$miPlan   = New-MenuItem "☀  Plan du jour" { Show-MorningPlan }
$miQuiet  = New-MenuItem "🤫  Mode silencieux (moins de bulles)" { $O.Quiet = -not $O.Quiet; Save-Settings; if ($O.Quiet) { Hide-Bubble } } -Checkable
$miWander = New-MenuItem "🚶  Balades sur les écrans" { $O.Wander = -not $O.Wander; $O.Walking = $false; Save-Settings } -Checkable
$miHome   = New-MenuItem "🏠  Revenir en bas à droite" { $O.Pinned = $false; $O.Walking = $false }
$miMini   = New-MenuItem "🔽  Réduire" { Set-Mini (-not $O.Mini) } -Checkable
$miHide   = New-MenuItem "🙈  Masquer (icône près de l'horloge)" { Hide-Orbit }
$miAuto   = New-MenuItem "⚡  Lancer au démarrage de Windows" { Toggle-Autostart } -Checkable
$miStats  = New-MenuItem "🏆  Mes victoires du jour" { Show-Bubble (("Aujourd'hui : {0} session(s) de focus, soit {1} min. 🔥" -f $O.FocusToday, [math]::Round($O.FocusMinToday)) + "`n`n" + (Get-WinsText)) -Force -Seconds 15 }
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
$miSettings = New-MenuItem "⚙  Réglages…" { Open-Settings }
$miSearch = New-MenuItem "🔍  Rechercher partout…" { Open-Notebook 'Search' }
$miMove   = New-Object Windows.Controls.MenuItem
$miMove.Header = "📦  Autre PC"
[void]$miMove.Items.Add((New-MenuItem "📦  Exporter Orbit et mes données (zip)…" { [void](Export-OrbitPackage) }))
[void]$miMove.Items.Add((New-MenuItem "📥  Importer un export…" { Import-OrbitPackage }))
$miSkin = New-Object Windows.Controls.MenuItem
$miSkin.Header = "🎨  Apparence"
$skinItems = @{}
foreach ($k in $Skins.Keys) {
    $it = New-MenuItem $Skins[$k].Label ([scriptblock]::Create("Set-Skin '$k'; Save-Settings")) -Checkable
    $skinItems[$k] = $it
    [void]$miSkin.Items.Add($it)
}
[void]$miSkin.Items.Add((New-Object Windows.Controls.Separator))
[void]$miSkin.Items.Add((New-MenuItem "🖼  Choisir une autre image…" { if (Choose-CustomImage) { Set-Skin 'Custom'; Save-Settings } }))

# Le menu tient en un coup d'oeil : le chrono (seulement ce qui sert maintenant), les 3 gestes
# du quotidien, les 3 endroits ou tout est range ; le reste est dans « ☰ Plus ».
$miMore = New-Object Windows.Controls.MenuItem
$miMore.Header = "☰  Plus"
foreach ($i in @($miCards, $miPlan, $miRhythm, $miTasks, (New-Object Windows.Controls.Separator),
                 $miSearch, $miClip, $miStats, (New-Object Windows.Controls.Separator),
                 $miSkin, $miQuiet, $miWander, $miMini, $miHide, $miAuto, (New-Object Windows.Controls.Separator),
                 $miMove)) { [void]$miMore.Items.Add($i) }
foreach ($i in @($miFocus, $miBreak, $miPause, $miStop, $miHome, (New-Object Windows.Controls.Separator),
                 $miNote, $miCtx, $miSos, (New-Object Windows.Controls.Separator),
                 $miTodo, $miNotes, $miCtxList, (New-Object Windows.Controls.Separator),
                 $miMore, $miSettings, $miQuit)) { [void]$menu.Items.Add($i) }
function Show-If([bool]$cond) { if ($cond) { 'Visible' } else { 'Collapsed' } }

$menu.Add_Opened({
    $miPause.Header = if ($O.Paused) { "▶  Reprendre le chrono" } else { "⏸  Mettre le chrono en pause" }
    # chrono : seulement les commandes utiles a cet instant
    $miFocus.Visibility = Show-If ($O.State -ne 'Focus')
    $miBreak.Visibility = Show-If ($O.State -in 'Focus', 'AwaitBreak')
    $miPause.Visibility = Show-If ($O.State -in 'Focus', 'Break')
    $miStop.Visibility = Show-If ($O.State -ne 'Idle')
    $miHome.Visibility = Show-If ($O.Pinned -or $O.Walking)
    $miQuiet.IsChecked = $O.Quiet
    $miWander.IsChecked = $O.Wander
    $miMini.IsChecked = $O.Mini
    $miAuto.IsChecked = Test-Path $StartupLink
    $miTasks.IsChecked = $O.TaskReminders
    $nCtx = @(Get-OpenContexts).Count
    $miCtxList.Header = if ($nCtx) { "↩  Mes reprises ($nCtx en attente)" } else { "↩  Mes reprises" }
    $miSos.Header = if ($Anchor.Unstick) { "🚨  S.O.S : reprendre « $(Short-Text $Anchor.Unstick.title 30) »" } else { "🚨  S.O.S : je bloque (une seule chose à la fois)" }
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
            Show-Bubble "Ok, je reste ici 📌" -AutoHide -Seconds 8 -Buttons @(
                @{ Label = '🏠 Retourner en bas à droite'; Action = { $O.Pinned = $false; $O.Walking = $false } })
        } else {
            if ($ui.BubbleWrap.Visibility -eq 'Visible' -and $ui.BubbleButtons.Children.Count -eq 0 -and (Get-Random -Maximum 100) -lt 25) {
                Show-Bubble (Pick $Lines.Poke) -Force -Seconds 3
            } else { Show-Status }
        }
    }
})

# Le bouton ✋ a cote d'Orbit (pendant un focus)
$ui.CtxBadge.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-Safe { Start-Interruption } })
# Les autres boutons ronds a cote d'Orbit
$ui.AnchorBadge.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-Safe { Show-QuickNote } })
$ui.SosBadge.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-Safe { Show-Sos } })
$ui.BoardsBadge.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-Safe { Open-Notebook 'Todo' } })
$ui.CtxListBadge.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-Safe { Open-Notebook 'Ctx' } })

# ---------------------------------------------------------------------------
#  Icone dans la zone de notification
# ---------------------------------------------------------------------------
# Sans texte : le petit satellite. Avec texte : une pastille de couleur avec le chrono
# (bleu = focus, vert = pause, gris = chrono en pause, orange = Orbit attend ta reponse)
function New-TrayIcon([string]$label = '', [string]$kind = 'Idle') {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    if (-not $label) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(108, 92, 231))), 5, 5, 22, 22)
        $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200, 190, 255)), 2), 1, 12, 30, 9)
        $g.FillEllipse([System.Drawing.Brushes]::White, 10, 11, 5, 6)
        $g.FillEllipse([System.Drawing.Brushes]::White, 17, 11, 5, 6)
    } else {
        $rgb = switch ($kind) { 'Focus' { 59, 91, 219 } 'Break' { 47, 158, 68 } 'Paused' { 120, 126, 140 } default { 232, 89, 12 } }
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = 9
        $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90); $path.AddArc(31 - $r * 2, 0, $r * 2, $r * 2, 270, 90)
        $path.AddArc(31 - $r * 2, 31 - $r * 2, $r * 2, $r * 2, 0, 90); $path.AddArc(0, 31 - $r * 2, $r * 2, $r * 2, 90, 90)
        $path.CloseFigure()
        $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]))), $path)
        $size = if ($label.Length -le 1) { 21 } elseif ($label.Length -eq 2) { 18 } else { 13 }
        $font = New-Object System.Drawing.Font('Segoe UI', $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $g.DrawString($label, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 1, 32, 32)), $fmt)
        $font.Dispose(); $path.Dispose()
    }
    $g.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $bmp.Dispose()
    return $icon
}

# Le chrono dans la zone de notification : mis a jour quand la minute change
function Update-TrayIcon {
    if (-not $script:tray) { return }
    $kind = 'Idle'; $label = ''
    switch -Wildcard ($O.State) {
        'Focus'  { $kind = 'Focus' }
        'Break'  { $kind = 'Break' }
        'Await*' { $kind = 'Await'; $label = '!' }
    }
    if ($kind -in 'Focus', 'Break') {
        $left = if ($O.Paused) { $O.Remaining } else { $O.EndsAt - (Get-Date) }
        $m = [math]::Min(99, [math]::Max(1, [math]::Ceiling($left.TotalMinutes)))
        $label = "$m"
        if ($O.Paused) { $kind = 'Paused' }
    }
    $key = "$kind|$label"
    if ($key -eq $script:TrayKey) { return }
    $script:TrayKey = $key
    $old = $script:tray.Icon
    $script:tray.Icon = New-TrayIcon $label $kind
    if ($old -and $Native) { [void][OrbitNative]::DestroyIcon($old.Handle) }
}

# Windows 11 range les nouvelles icones dans la fleche ^ : on epingle celle d'Orbit
# a cote de l'horloge (reglage de ton compte, sans droits admin), sauf si tu l'as
# deja deplacee toi-meme. Renvoie $true si l'icone a ete trouvee.
function Set-TrayPromoted([bool]$on, [switch]$OnlyIfUnset) {
    $root = 'HKCU:\Control Panel\NotifyIconSettings'
    if (-not (Test-Path $root)) { return $false }   # Windows 10 : pas ce reglage
    $found = $false
    foreach ($k in Get-ChildItem -Path $root -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p -or [string]$p.ExecutablePath -notmatch 'powershell\.exe$' -or -not ([string]$p.InitialTooltip).StartsWith('Orbit')) { continue }
        $found = $true
        if ($OnlyIfUnset -and $null -ne $p.IsPromoted) { continue }
        Set-ItemProperty -Path $k.PSPath -Name 'IsPromoted' -Value ([int]$on) -Type DWord
    }
    return $found
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
    [void]$cms.Items.Add('Afficher / masquer Orbit  (clic sur l''icône)', $null, { Invoke-Safe { Toggle-OrbitVisible } })
    [void]$cms.Items.Add('Réduire / agrandir Orbit', $null, { Invoke-Safe { Ensure-Visible; Set-Mini (-not $O.Mini) } })
    [void]$cms.Items.Add('-')
    [void]$cms.Items.Add('Lancer un focus 50/10', $null, { Invoke-Safe { Ensure-Visible; Set-Rhythm '50/10' -Quiet; Start-Focus } })
    [void]$cms.Items.Add('Lancer un focus 25/5', $null, { Invoke-Safe { Ensure-Visible; Set-Rhythm '25/5' -Quiet; Start-Focus } })
    [void]$cms.Items.Add('Prendre ma pause', $null, { Invoke-Safe { Ensure-Visible; Start-Break } })
    [void]$cms.Items.Add('Couper le chrono', $null, { Invoke-Safe { Stop-Cycle } })
    [void]$cms.Items.Add('-')
    [void]$cms.Items.Add('🚨 S.O.S : je bloque', $null, { Invoke-Safe { Show-Sos } })
    [void]$cms.Items.Add('🏆 Mes victoires du jour', $null, { Invoke-Safe { Show-Wins } })
    [void]$cms.Items.Add('✋ Je m''interromps', $null, { Invoke-Safe { Start-Interruption } })
    [void]$cms.Items.Add('↩ Mes reprises', $null, { Invoke-Safe { Open-Notebook 'Ctx' } })
    [void]$cms.Items.Add('📝 Note rapide', $null, { Invoke-Safe { Show-QuickNote } })
    [void]$cms.Items.Add('Mes notes', $null, { Invoke-Safe { Open-Notebook 'Notes' } })
    [void]$cms.Items.Add('Mes tableaux', $null, { Invoke-Safe { Open-Notebook 'Todo' } })
    [void]$cms.Items.Add('Mes copier-coller du jour', $null, { Invoke-Safe { Open-Notebook 'Clip' } })
    [void]$cms.Items.Add('Rechercher partout…', $null, { Invoke-Safe { Open-Notebook 'Search' } })
    [void]$cms.Items.Add('Cartes du focus…', $null, { Invoke-Safe { Choose-FocusCards } })
    [void]$cms.Items.Add('Plan du jour', $null, { Invoke-Safe { Ensure-Visible; Show-MorningPlan } })
    [void]$cms.Items.Add('-')
    [void]$cms.Items.Add('Réglages…', $null, { Invoke-Safe { Open-Settings } })
    [void]$cms.Items.Add('Épingler l''icône près de l''horloge', $null, {
        Invoke-Safe {
            if (Set-TrayPromoted $true) { $script:tray.Visible = $false; $script:tray.Visible = $true; Show-Tray 'Orbit' "C'est fait : mon icône reste à côté de l'horloge 📌" }
            else { Show-Tray 'Orbit' "Fais glisser mon icône depuis la flèche ^ jusqu'à côté de l'horloge 📌" }
        }
    })
    [void]$cms.Items.Add('Quitter Orbit', $null, { Invoke-Safe { Quit-Orbit } })
    $script:tray.ContextMenuStrip = $cms
    # un clic gauche sur l'icone : afficher / cacher Orbit (le clic droit ouvre le menu)
    $script:tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Invoke-Safe { Toggle-OrbitVisible } } })
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
        Set-Mood (Get-StateMood)
        Start-Floating
        Update-Pill
        if ($script:ImportNote) { Show-Bubble $script:ImportNote -Force -Seconds 10 }
        elseif ($script:ResumeNote) { Show-Bubble $script:ResumeNote -Force -Seconds 8 } else { Show-Status }
        # le carnet est prepare en douce 3 s apres le demarrage : Orbit apparait plus vite,
        # et la premiere ouverture des tableaux reste instantanee
        $script:prepTimer = New-Object Windows.Threading.DispatcherTimer
        $script:prepTimer.Interval = [timespan]::FromSeconds(3)
        $script:prepTimer.Add_Tick({ $script:prepTimer.Stop(); Invoke-Safe { Initialize-Notebook } })
        $script:prepTimer.Start()
        if ($NB.LoadNotice) { Show-Bubble $NB.LoadNotice -Force -Seconds 10; $NB.LoadNotice = '' }
    }
})

$script:frameTimer = New-Object Windows.Threading.DispatcherTimer
$script:frameTimer.Interval = [timespan]::FromMilliseconds(40)
$script:frameTimer.Add_Tick({ Invoke-Safe { On-Frame } })
# Orbit cache = aucune animation a calculer
$window.Add_IsVisibleChanged({
    Invoke-Safe {
        if ($window.IsVisible) { $O.LastFrame = [datetime]::Now; $script:frameTimer.Start() }
        elseif (-not $NB.Quitting) { $script:frameTimer.Stop() }
    }
})

$script:secondTimer = New-Object Windows.Threading.DispatcherTimer
$script:secondTimer.Interval = [timespan]::FromSeconds(1)
$script:secondTimer.Add_Tick({ Invoke-Safe { On-Second } })

# placement initial hors ecran le temps de calculer la bonne position
$window.Left = -10000
$window.Top = -10000
Set-Skin $O.Skin -Quiet
$script:ResumeNote = Restore-State
Set-Mood (Get-StateMood)

# Une erreur imprevue dans un evenement ne doit pas faire tomber Orbit : on la note et on continue
$script:CrashCount = 0
$script:Crashed = $false

$app = New-Object Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$app.Add_DispatcherUnhandledException({
    param($s, $e)
    $script:CrashCount++
    Write-Log "Erreur imprevue ($($script:CrashCount)) : $($e.Exception.Message)"
    # au-dela de 50 erreurs, quelque chose est vraiment casse : on laisse tomber (et on se relance)
    $e.Handled = $script:CrashCount -le 50
})
$script:frameTimer.Start()
$script:secondTimer.Start()
Write-Log "Orbit demarre (focus $($Config.FocusMinutes) min, pause $($Config.BreakMinutes) min, natif=$Native)"
if ($env:ORBIT_SELFTEST) { return }    # tests automatiques : tout est charge, on ne lance pas la boucle
try {
    [void]$app.Run($window)
} catch {
    $script:Crashed = $true
    Write-Log "Arret inattendu : $($_.Exception.Message)"
    try { Save-State; Save-Stats; Save-Todos; Flush-Notebook } catch {}
} finally {
    if ($script:tray) { $script:tray.Visible = $false; $script:tray.Dispose() }
    $mutex.ReleaseMutex()
}

if ($script:RelaunchAfterExit) {
    Start-OrbitDetached
}

# Plantage : Orbit se relance tout seul (une fois toutes les 10 minutes au plus,
# pour ne pas boucler si le probleme revient a chaque demarrage)
if ($script:Crashed) {
    $stamp = Join-Path $DataDir 'derniere-relance.txt'
    $last = if (Test-Path -LiteralPath $stamp) { (Get-Item -LiteralPath $stamp).LastWriteTime } else { [datetime]::MinValue }
    if (((Get-Date) - $last).TotalMinutes -ge 10) {
        Set-Content -LiteralPath $stamp -Value (Get-Date -Format s)
        Write-Log "Relance automatique"
        Start-OrbitDetached @('-Restarted')
    } else {
        Write-Log "Pas de relance : deja relance il y a moins de 10 minutes"
    }
}
