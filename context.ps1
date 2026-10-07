# ---------------------------------------------------------------------------
#  « Je m'interromps » : savoir ou on s'est arrete.
#
#  Un clic (bouton ✋ a cote d'Orbit pendant un focus, clic droit sur Orbit,
#  ou l'icone pres de l'horloge) et Orbit garde :
#   - la fenetre sur laquelle tu travaillais (et les precedentes, au choix),
#     avec l'adresse de l'onglet (Edge, Chrome...), le dossier ouvert dans
#     l'Explorateur, le fichier Excel / Word / PowerPoint ;
#   - en option, une petite capture d'ecran ;
#   - deux lignes ecrites par toi : ce que tu faisais, et la prochaine etape.
#  Le focus en cours se met en pause. Au retour, Orbit te remet la ou tu en
#  etais : fenetres au premier plan (ou rouvertes), focus relance, et la
#  prochaine etape sous les yeux.
#
#  Tout reste sur ce PC : reprises.json (+ une copie par jour dans
#  sauvegardes\), les captures dans captures\ (jamais exportees).
#  Orbit ne rouvre que des adresses web (http/https), des dossiers et des
#  documents qui existent : jamais un programme.
# ---------------------------------------------------------------------------
$CtxFile = Join-Path $DataDir 'reprises.json'
$CtxShotDir = Join-Path $DataDir 'captures'
$CtxKeepDays = 14          # une reprise terminee reste visible 14 jours
$CtxMax = 200
$CtxMaxReminders = 3
$NB.Contexts = New-Object System.Collections.ArrayList
$NB.CtxBackupDay = ''

# icone et nom des applications les plus courantes (nom du processus -> icone, nom)
$CtxApps = @{
    'chrome' = @('🌐', 'Chrome'); 'msedge' = @('🌐', 'Edge'); 'firefox' = @('🌐', 'Firefox'); 'brave' = @('🌐', 'Brave')
    'opera' = @('🌐', 'Opera'); 'vivaldi' = @('🌐', 'Vivaldi')
    'excel' = @('📊', 'Excel'); 'winword' = @('📝', 'Word'); 'powerpnt' = @('📽', 'PowerPoint')
    'outlook' = @('📧', 'Outlook'); 'olk' = @('📧', 'Outlook'); 'onenote' = @('📓', 'OneNote')
    'ms-teams' = @('💬', 'Teams'); 'teams' = @('💬', 'Teams'); 'explorer' = @('📂', 'Explorateur')
    'code' = @('💻', 'VS Code'); 'notepad' = @('🗒', 'Bloc-notes'); 'acrobat' = @('📕', 'Acrobat'); 'acrord32' = @('📕', 'Acrobat Reader')
    'saplogon' = @('🏢', 'SAP')
}
$CtxBrowsers = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi')
$CtxOffice = @{ 'excel' = 'Excel.Application'; 'winword' = 'Word.Application'; 'powerpnt' = 'PowerPoint.Application' }
# documents qu'Orbit accepte de rouvrir (jamais un programme ni un script)
$CtxOpenExt = @('.xlsx', '.xlsm', '.xlsb', '.xls', '.csv', '.docx', '.docm', '.doc', '.rtf', '.odt', '.ods', '.odp',
                '.pptx', '.pptm', '.ppt', '.pdf', '.txt', '.md', '.vsdx', '.one', '.png', '.jpg', '.jpeg')

# ---------------------------------------------------------------------------
#  Petites fonctions (testees une a une dans tests\logic.ps1)
# ---------------------------------------------------------------------------
function Get-AppInfo([string]$app) {
    $k = ([string]$app).ToLowerInvariant()
    if ($CtxApps.ContainsKey($k)) { return @{ Icon = $CtxApps[$k][0]; Name = $CtxApps[$k][1] } }
    $name = if ($k) { $k.Substring(0, 1).ToUpperInvariant() + $k.Substring(1) } else { 'Fenêtre' }
    return @{ Icon = '🖥'; Name = $name }
}

# fenetre de navigation privee : ni adresse, ni titre, ni capture
function Test-PrivateTitle([string]$title) {
    return [string]$title -match '(?i)InPrivate|Incognito|Navigation privée|Private Browsing|\(privée\)'
}

# « Budget T3 - Excel » -> « Budget T3 » ; « Page et 2 autres pages - Profil 1 - Microsoft Edge » -> « Page »
function Get-CleanTitle([string]$title) {
    $t = ConvertTo-DisplayText $title
    $t = $t -replace '\s[-–—]\s(Google Chrome|Microsoft Edge|Mozilla Firefox|Brave|Opera|Vivaldi|Excel|Word|PowerPoint|Outlook|OneNote|Visual Studio Code|Bloc-notes|Notepad|Adobe Acrobat[^-–—]*|Explorateur de fichiers|File Explorer)$', ''
    $t = $t -replace '\s[-–—]\s(Profil(e)?\s*\d*|Personnel|Personal|Travail|Work)$', ''
    $t = $t -replace '\s(et|and)\s\d+\s(autres?\spages?|more\spages?)', ''
    $t = ($t -replace '\s+', ' ').Trim()
    if ($t.Length -gt 200) { $t = (Get-TextStart $t 199) + '…' }
    return $t
}

# Adresse web lue dans la barre d'adresse : seulement http(s), sans caractere qui pourrait
# servir a glisser autre chose a l'ouverture. Les navigateurs cachent souvent « https:// ».
function Get-SafeUrl($u) {
    $u = ([string]$u).Trim() -replace ' ', '%20'
    if (-not $u -or $u.Length -gt 2048) { return '' }
    if ($u -notmatch '^[A-Za-z][A-Za-z0-9+.-]*:' -and $u -match '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d{1,5})?([/?#]|$)') { $u = 'https://' + $u }
    if ($u -match '^https?://[^\s"''<>`^{}|\\]+$') { return $u }
    return ''
}

# Dossier ou document a rouvrir : chemin complet, qui existe, et un document (pas un programme)
function Test-SafeOpenPath([string]$p, [switch]$Folder) {
    if (-not $p -or $p.Length -gt 400 -or $p -match '["<>|*?]' -or $p.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return $false }
    if (-not [IO.Path]::IsPathRooted($p)) { return $false }
    # (un partage reseau injoignable fait echouer Test-Path : on refuse, sans erreur)
    try {
        if ($Folder) { return [bool](Test-Path -LiteralPath $p -PathType Container -ErrorAction Stop) }
        if ($CtxOpenExt -notcontains [IO.Path]::GetExtension($p).ToLowerInvariant()) { return $false }
        return [bool](Test-Path -LiteralPath $p -PathType Leaf -ErrorAction Stop)
    } catch { return $false }
}

function Format-Ago([string]$iso) {
    try { $d = [datetime]::Parse($iso) } catch { return '' }
    $min = ((Get-Date) - $d).TotalMinutes
    if ($min -lt 1) { return "à l'instant" }
    if ($min -lt 60) { return "il y a $([math]::Floor($min)) min" }
    if ($d.Date -eq (Get-Date).Date) { return "à $($d.ToString('HH:mm'))" }
    if ($d.Date -eq (Get-Date).Date.AddDays(-1)) { return "hier à $($d.ToString('HH:mm'))" }
    return "le $($d.ToString('dd/MM')) à $($d.ToString('HH:mm'))"
}

function ConvertTo-CtxWindow($w) {
    $priv = [bool]$w.private
    $url = if ($priv) { '' } else { Get-SafeUrl $w.url }
    $path = [string]$w.path
    if ($priv -or $path.Length -gt 400 -or $path -match '["<>|*?]') { $path = '' }
    [long]$h = 0; [void][long]::TryParse([string]$w.hwnd, [ref]$h)
    [int]$procId = 0; [void][int]::TryParse([string]$w.pid, [ref]$procId)
    return [pscustomobject]@{
        app = (([string]$w.app) -replace '[^A-Za-z0-9_.-]', '').ToLowerInvariant()
        title = $(if ($priv) { 'Fenêtre de navigation privée' } else { Get-TextStart ([string]$w.title) 200 })
        url = $url; path = $path; hwnd = $h; pid = $procId; private = $priv
    }
}

# Une reprise lue sur le disque : tout est verifie (identifiant, adresses, chemins, dates)
function ConvertTo-Context($c) {
    $wins = New-Object System.Collections.ArrayList
    foreach ($w in @($c.windows)) { if ($w) { [void]$wins.Add((ConvertTo-CtxWindow $w)) } }
    $cards = @(@($c.focusCards) | Where-Object { Test-SafeId $_ } | ForEach-Object { [string]$_ })
    $x = [pscustomobject]@{
        id = (Get-SafeId $c.id); created = To-IsoString $c.created
        status = $(if ([string]$c.status -eq 'done') { 'done' } else { 'open' }); doneAt = To-IsoString $c.doneAt
        doing = Get-TextStart ([string]$c.doing) 2000; next = Get-TextStart ([string]$c.next) 2000
        windows = $wins; focusCards = $cards; wasFocus = [bool]$c.wasFocus; focusLeftMin = [double]$c.focusLeftMin
        remindAt = To-IsoString $c.remindAt; reminders = [int]$c.reminders
    }
    if (-not $x.created) { $x.created = (Get-Date).ToString('s') }
    return $x
}

function Get-MainWindow($ctx) { if ($ctx -and @($ctx.windows).Count) { return @($ctx.windows)[0] } }

# « 📊 Budget T3 (Excel) »
function Get-WindowLabel($w, [int]$max = 70) {
    if (-not $w) { return '' }
    $a = Get-AppInfo $w.app
    $t = if ($w.title) { Short-Text $w.title $max } else { $a.Name }
    if ($w.title -and $a.Name -and $t -notmatch [regex]::Escape($a.Name)) { $t += " ($($a.Name))" }
    return "$($a.Icon) $t"
}

function Get-ContextTitle($ctx, [int]$max = 70) {
    if ($ctx.next) { return Short-Text $ctx.next $max }
    if ($ctx.doing) { return Short-Text $ctx.doing $max }
    $w = Get-MainWindow $ctx
    if ($w) { return Short-Text $w.title $max }
    return 'Reprise sans détail'
}

# ---------------------------------------------------------------------------
#  Fichier reprises.json
# ---------------------------------------------------------------------------
function Read-ContextsFile([string]$path) {
    # (PowerShell 5.1 renvoie la liste d'un bloc : on la parcourt avec foreach, sans @())
    $data = ConvertFrom-Json ([IO.File]::ReadAllText($path))
    $list = New-Object System.Collections.ArrayList
    foreach ($c in $data) { if ($c) { [void]$list.Add((ConvertTo-Context $c)) } }
    return , $list
}

function Load-Contexts {
    $NB.Contexts.Clear()
    if (Test-Path -LiteralPath $CtxFile) {
        try { foreach ($c in (Read-ContextsFile $CtxFile)) { [void]$NB.Contexts.Add($c) } }
        catch {
            Write-Log "Lecture reprises : $($_.Exception.Message)"
            $bad = Join-Path $DataDir ("reprises-illisible-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
            try { Move-Item -LiteralPath $CtxFile -Destination $bad -Force } catch {}
            $backs = @(Get-ChildItem -Path $BackupDir -Filter 'reprises-????-??-??.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
            foreach ($f in $backs) {
                try {
                    foreach ($c in (Read-ContextsFile $f.FullName)) { [void]$NB.Contexts.Add($c) }
                    $NB.LoadNotice = (@($NB.LoadNotice, "Ton fichier de reprises était abîmé 😬 J'ai repris la copie du $($f.BaseName.Substring(9)).") | Where-Object { $_ }) -join "`n"
                    break
                } catch {}
            }
        }
    }
    Limit-Contexts
}

# reprises terminees depuis plus de 14 jours : oubliees ; captures orphelines : effacees
function Limit-Contexts {
    $limit = (Get-Date).AddDays(-$CtxKeepDays).ToString('s')
    foreach ($c in @($NB.Contexts)) {
        if ($c.status -eq 'done' -and $c.doneAt -and $c.doneAt -lt $limit) { $NB.Contexts.Remove($c) }
    }
    while ($NB.Contexts.Count -gt $CtxMax) { $NB.Contexts.RemoveAt($NB.Contexts.Count - 1) }
    if (Test-Path -LiteralPath $CtxShotDir) {
        $keep = @{}
        foreach ($c in $NB.Contexts) { if ($c.status -eq 'open') { $keep["$($c.id).jpg"] = $true } }
        Get-ChildItem -LiteralPath $CtxShotDir -Filter '*.jpg' -ErrorAction SilentlyContinue |
            Where-Object { -not $keep.ContainsKey($_.Name) } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Save-Contexts {
    try {
        $day = (Get-Date).ToString('yyyy-MM-dd')
        if ($NB.CtxBackupDay -ne $day -and (Test-Path -LiteralPath $CtxFile)) {
            if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
            $dest = Join-Path $BackupDir "reprises-$day.json"
            if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $CtxFile -Destination $dest -Force }
            Limit-Backups 'reprises-????-??-??.json' 7
            $NB.CtxBackupDay = $day
        }
        Write-FileSafe $CtxFile (ConvertTo-JsonArray $NB.Contexts)
    } catch { Write-Log "Ecriture reprises : $($_.Exception.Message)" }
}

function Find-Context([string]$id) { foreach ($c in $NB.Contexts) { if ($c.id -eq $id) { return $c } } }

function Get-OpenContexts {
    @($NB.Contexts | Where-Object { $_.status -eq 'open' } | Sort-Object -Property @{ e = { [string]$_.created }; Descending = $true })
}

# la reprise ouverte la plus recente (-Hours : seulement si elle date de moins de N heures)
function Get-LatestOpenContext([double]$Hours = 0) {
    $c = @(Get-OpenContexts) | Select-Object -First 1
    if (-not $c) { return $null }
    if ($Hours -gt 0) {
        try { if (((Get-Date) - [datetime]::Parse($c.created)).TotalHours -gt $Hours) { return $null } } catch { return $null }
    }
    return $c
}

function Get-ContextShotPath([string]$id) { Join-Path $CtxShotDir ((Get-SafeId $id) + '.jpg') }

function Remove-ContextShot([string]$id) {
    $f = Get-ContextShotPath $id
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
#  Capture : fenetres, adresses, capture d'ecran
# ---------------------------------------------------------------------------
# Les fenetres de travail du moment (la plus recente d'abord), hors fenetres d'Orbit
function Get-CapturedWindows([int]$others = $Config.ContextWindows) {
    $list = New-Object System.Collections.ArrayList
    if (-not $Native) { return , $list }
    foreach ($row in [OrbitNative]::RecentWindows(1 + [math]::Max(0, $others), [uint32]$O.MyPid)) {
        $p = $row.Split('|', 4)
        if ($p.Count -lt 4) { continue }
        $proc = try { (Get-Process -Id ([int]$p[1]) -ErrorAction Stop).ProcessName } catch { '' }
        $priv = Test-PrivateTitle $p[3]
        [void]$list.Add((ConvertTo-CtxWindow ([pscustomobject]@{
                        app = $proc; title = $(if ($priv) { '' } else { Get-CleanTitle $p[3] }); hwnd = $p[0]; pid = $p[1]; private = $priv })))
    }
    return , $list
}

# Lecture des adresses et des fichiers, dans un fil a part (un navigateur ou Excel occupe
# ne doit jamais bloquer Orbit) : barre d'adresse des navigateurs (accessibilite de Windows),
# dossier de l'Explorateur, document Excel / Word / PowerPoint actif.
$CtxProbeScript = {
    param($reqs)
    try { Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes } catch {}
    $shell = $null
    foreach ($r in $reqs) {
        $v = ''
        try {
            if ($r.Kind -eq 'browser') {
                $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$r.Hwnd)
                $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
                $edit = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
                if ($edit) {
                    $vp = $null
                    if ($edit.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { $v = [string]$vp.Current.Value }
                }
            } elseif ($r.Kind -eq 'explorer') {
                if (-not $shell) { $shell = New-Object -ComObject Shell.Application }
                foreach ($w in $shell.Windows()) {
                    try { if ([long]$w.HWND -eq [long]$r.Hwnd) { $v = [string]$w.Document.Folder.Self.Path; break } } catch {}
                }
            } elseif ($r.Kind -eq 'office') {
                $o = [Runtime.InteropServices.Marshal]::GetActiveObject([string]$r.ProgId)
                if ($r.ProgId -eq 'Excel.Application') { $v = [string]$o.ActiveWorkbook.FullName }
                elseif ($r.ProgId -eq 'Word.Application') { $v = [string]$o.ActiveDocument.FullName }
                elseif ($r.ProgId -eq 'PowerPoint.Application') { $v = [string]$o.ActivePresentation.FullName }
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
            }
        } catch {}
        [string]$v
    }
}

function Get-ProbeRequests($ctx) {
    $reqs = @()
    $i = 0
    foreach ($w in @($ctx.windows)) {
        if (-not $w.private -and $w.hwnd) {
            if ($CtxBrowsers -contains $w.app) { $reqs += @{ Index = $i; Kind = 'browser'; Hwnd = $w.hwnd } }
            elseif ($w.app -eq 'explorer') { $reqs += @{ Index = $i; Kind = 'explorer'; Hwnd = $w.hwnd } }
            elseif ($i -eq 0 -and $CtxOffice.ContainsKey($w.app)) { $reqs += @{ Index = $i; Kind = 'office'; Hwnd = $w.hwnd; ProgId = $CtxOffice[$w.app] } }
        }
        $i++
    }
    return , $reqs
}

# Applique ce que la lecture a trouve (tout est reverifie : adresse web, dossier, document)
function Set-ProbeResults($ctx, $reqs, $values) {
    $values = @($values)
    for ($j = 0; $j -lt $reqs.Count -and $j -lt $values.Count; $j++) {
        $r = $reqs[$j]; $v = [string]$values[$j]
        $w = @($ctx.windows)[$r.Index]
        if (-not $w -or -not $v) { continue }
        if ($r.Kind -eq 'browser') { $w.url = Get-SafeUrl $v }
        elseif ($r.Kind -eq 'explorer') { if (Test-SafeOpenPath $v -Folder) { $w.path = $v } }
        elseif ($r.Kind -eq 'office') {
            # le document actif doit bien etre celui de la fenetre
            $name = [IO.Path]::GetFileNameWithoutExtension($v)
            if ($name -and $w.title -and $w.title.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and (Test-SafeOpenPath $v)) { $w.path = $v }
        }
    }
}

function Start-ContextProbe($ctx) {
    $reqs = Get-ProbeRequests $ctx
    if (-not $reqs.Count) { return }
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($CtxProbeScript.ToString()).AddArgument($reqs)
        $script:CtxProbe = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Reqs = $reqs; Ctx = $ctx; Until = (Get-Date).AddSeconds(6) }
        if (-not $script:CtxProbeTimer) {
            $script:CtxProbeTimer = New-Object Windows.Threading.DispatcherTimer
            $script:CtxProbeTimer.Interval = [timespan]::FromMilliseconds(200)
            $script:CtxProbeTimer.Add_Tick({ Invoke-Safe { Step-ContextProbe } 'reprise' })
        }
        $script:CtxProbeTimer.Start()
    } catch { Write-Log "Reprise : lecture des adresses impossible ($($_.Exception.Message))" }
}

# Renvoie $true quand la lecture est terminee (ou abandonnee)
function Step-ContextProbe {
    $p = $script:CtxProbe
    if (-not $p) { if ($script:CtxProbeTimer) { $script:CtxProbeTimer.Stop() }; return $true }
    if ($p.Handle.IsCompleted) {
        try { Set-ProbeResults $p.Ctx $p.Reqs @($p.Ps.EndInvoke($p.Handle)) } catch { Write-Log "Reprise : $($_.Exception.Message)" }
        try { $p.Ps.Dispose(); $p.Rs.Dispose() } catch {}
    } elseif ((Get-Date) -gt $p.Until) {
        # un programme ne repond pas : tant pis pour l'adresse, on garde le titre
        try { [void]$p.Ps.BeginStop($null, $null) } catch {}
        Write-Log "Reprise : lecture des adresses trop longue, ignoree"
    } else { return $false }
    $script:CtxProbe = $null
    if ($script:CtxProbeTimer) { $script:CtxProbeTimer.Stop() }
    Update-ContextSummary
    if (Find-Context $p.Ctx.id) { Save-Contexts; Render-Contexts }
    return $true
}

# Petite capture de l'ecran ou se trouve la fenetre de travail (JPEG, 1600 px de large au plus)
function Save-ContextShot([string]$id, $win) {
    $scr = if ($win -and $win.hwnd) { [System.Windows.Forms.Screen]::FromHandle([IntPtr][long]$win.hwnd) } else { [System.Windows.Forms.Screen]::PrimaryScreen }
    $b = $scr.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $small = $null
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size) } finally { $g.Dispose() }
        $w = [math]::Min(1600, $b.Width)
        $h = [int][math]::Round($b.Height * $w / $b.Width)
        $small = New-Object System.Drawing.Bitmap $w, $h
        $g2 = [System.Drawing.Graphics]::FromImage($small)
        try {
            $g2.InterpolationMode = 'HighQualityBicubic'
            $g2.DrawImage($bmp, 0, 0, $w, $h)
        } finally { $g2.Dispose() }
        if (-not (Test-Path -LiteralPath $CtxShotDir)) { New-Item -ItemType Directory -Path $CtxShotDir | Out-Null }
        $jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $prm = New-Object System.Drawing.Imaging.EncoderParameters 1
        $prm.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]72)
        $path = Get-ContextShotPath $id
        $small.Save($path, $jpg, $prm)
        $prm.Dispose()
        return $path
    } finally {
        $bmp.Dispose()
        if ($small) { $small.Dispose() }
    }
}

# ---------------------------------------------------------------------------
#  « ✋ Je m'interromps »
# ---------------------------------------------------------------------------
# Prochaine etape proposee : la premiere sous-tache pas cochee de la carte du focus
function Get-SuggestedNext {
    foreach ($t in @(Get-FocusCards -Open)) {
        foreach ($ck in @($t.checks)) { if ($ck -and -not $ck.done -and $ck.text) { return [string]$ck.text } }
    }
    return ''
}

function New-Context {
    $wins = Get-CapturedWindows
    $ctx = [pscustomobject]@{
        id = New-Id; created = (Get-Date).ToString('s'); status = 'open'; doneAt = ''
        doing = ''; next = ''; windows = $wins
        focusCards = @(Get-FocusCards -Open | ForEach-Object { $_.id }); wasFocus = $O.State -eq 'Focus'; focusLeftMin = 0
        remindAt = ''; reminders = 0
    }
    return $ctx
}

function Start-Interruption {
    if ($script:ctxWin -and $ctxWin.IsVisible) { $ctxWin.Activate() | Out-Null; return }
    $ctx = New-Context
    # le focus en cours se met en pause tout de suite (le temps de l'interruption ne compte pas)
    $paused = $false
    if ($O.State -eq 'Focus' -and -not $O.Paused) {
        $O.Remaining = $O.EndsAt - (Get-Date)
        $O.Paused = $true
        $O.AutoPaused = $false
        $paused = $true
        Update-Pill
    }
    if ($O.State -eq 'Focus') { $ctx.focusLeftMin = [math]::Round($O.Remaining.TotalMinutes, 1) }
    $script:CtxEdit = @{ Ctx = $ctx; IsNew = $true; Paused = $paused; Shot = $false }
    Start-ContextProbe $ctx
    $main = Get-MainWindow $ctx
    if ($Config.ContextScreenshot -and $main -and -not $main.private) {
        # Orbit (et ses fenetres) se cachent le temps de la capture
        $script:CtxHidden = @()
        foreach ($wnd in @($window, $script:panel, $script:qnWin)) {
            if ($wnd -and $wnd.IsVisible -and $wnd.Opacity -gt 0) { $script:CtxHidden += $wnd; $wnd.Opacity = 0 }
        }
        if (-not $script:CtxShotTimer) {
            $script:CtxShotTimer = New-Object Windows.Threading.DispatcherTimer
            $script:CtxShotTimer.Interval = [timespan]::FromMilliseconds(250)
            $script:CtxShotTimer.Add_Tick({ $script:CtxShotTimer.Stop(); Invoke-Safe { Complete-InterruptionShot } 'reprise' })
        }
        $script:CtxShotTimer.Start()
        return
    }
    Show-ContextEditor
}

function Complete-InterruptionShot {
    try {
        $e = $script:CtxEdit
        if ($e -and $e.IsNew) {
            try { [void](Save-ContextShot $e.Ctx.id (Get-MainWindow $e.Ctx)); $e.Shot = $true }
            catch { Write-Log "Capture d'ecran : $($_.Exception.Message)" }
        }
    } finally {
        foreach ($wnd in @($script:CtxHidden)) { if ($wnd) { $wnd.Opacity = 1 } }
        $script:CtxHidden = @()
    }
    Show-ContextEditor
}

# Enregistre la reprise (nouvelle) : rappel programme, bulle de confirmation
function Add-Context($ctx) {
    if ($Config.ContextRemind -and $Config.ContextRemindMin -gt 0) { $ctx.remindAt = (Get-Date).AddMinutes($Config.ContextRemindMin).ToString('s') }
    $NB.Contexts.Insert(0, $ctx)
    while ($NB.Contexts.Count -gt $CtxMax) { $NB.Contexts.RemoveAt($NB.Contexts.Count - 1) }
    Save-Contexts
}

# ---------------------------------------------------------------------------
#  Reprendre
# ---------------------------------------------------------------------------
# Remet une fenetre devant si elle est encore ouverte, sinon rouvre l'adresse, le dossier
# ou le document. Renvoie 'front', 'opened' ou ''.
function Restore-ContextWindow($w) {
    if (-not $w -or $w.private) { return '' }
    if ($Native -and $w.hwnd -and [OrbitNative]::WindowAlive([long]$w.hwnd, [uint32]$w.pid)) {
        $same = try { (Get-Process -Id $w.pid -ErrorAction Stop).ProcessName.ToLowerInvariant() -eq $w.app } catch { $false }
        if ($same -and [OrbitNative]::BringToFront([long]$w.hwnd, [uint32]$w.pid)) { return 'front' }
        if ($same) { return 'front' }
    }
    $url = Get-SafeUrl $w.url
    if ($url) { Start-Process explorer.exe $url; return 'opened' }
    if ($w.path -and (Test-SafeOpenPath $w.path -Folder)) { Start-Process explorer.exe "`"$($w.path)`""; return 'opened' }
    if ($w.path -and (Test-SafeOpenPath $w.path)) { Start-Process explorer.exe "`"$($w.path)`""; return 'opened' }
    return ''
}

function Resume-Context([string]$id) {
    $ctx = Find-Context $id
    if (-not $ctx) { return }
    $wins = @($ctx.windows)
    $done = 0
    # les fenetres precedentes d'abord, la fenetre de travail en dernier (elle finit devant)
    for ($i = $wins.Count - 1; $i -ge 0; $i--) {
        if (Restore-ContextWindow $wins[$i]) { $done++ }
    }
    # le chrono reprend
    $focusMsg = ''
    if ($O.State -eq 'Focus' -and $O.Paused) {
        $O.EndsAt = (Get-Date) + $O.Remaining
        $O.Paused = $false
        $O.AutoPaused = $false
        $focusMsg = "`n▶ Le focus reprend : encore $([math]::Ceiling($O.Remaining.TotalMinutes)) min."
        Update-Pill
    } elseif ($O.State -eq 'Idle' -and $ctx.wasFocus) {
        if (@($ctx.focusCards).Count) { Set-FocusCards @($ctx.focusCards) }
        Start-Focus
        $focusMsg = "`n▶ Nouveau focus lancé."
    }
    $ctx.status = 'done'; $ctx.doneAt = (Get-Date).ToString('s')
    Remove-ContextShot $ctx.id
    Save-Contexts
    Render-Contexts; Update-Tabs
    $text = "▶ C'est reparti !"
    if ($ctx.next) { $text += "`n➡ Prochaine étape : $($ctx.next)" }
    elseif ($ctx.doing) { $text += "`n✍ Tu étais en train de : $($ctx.doing)" }
    if (-not $done -and @($wins).Count) { $text += "`n(La fenêtre n'existe plus et je n'ai rien pu rouvrir : $(Get-WindowLabel $wins[0] 50).)" }
    $text += $focusMsg
    Ensure-Visible
    Show-Bubble $text -Force -Seconds 15
}

function Complete-Context([string]$id) {
    $ctx = Find-Context $id
    if (-not $ctx) { return }
    $ctx.status = 'done'; $ctx.doneAt = (Get-Date).ToString('s')
    Remove-ContextShot $ctx.id
    Save-Contexts
    Render-Contexts; Update-Tabs
}

function Remove-Context([string]$id) {
    $ctx = Find-Context $id
    if (-not $ctx) { return }
    $NB.Contexts.Remove($ctx)
    Remove-ContextShot $ctx.id
    Save-Contexts
    Render-Contexts; Update-Tabs
}

function Snooze-Context([string]$id) {
    $ctx = Find-Context $id
    if (-not $ctx) { return }
    if ($Config.ContextRemind -and $Config.ContextRemindMin -gt 0) {
        $ctx.remindAt = (Get-Date).AddMinutes($Config.ContextRemindMin).ToString('s')
        Save-Contexts
        Show-Bubble "Ok ⏰ Je te le rappelle dans $($Config.ContextRemindMin) min. Tout est gardé dans clic droit > ↩ Mes reprises." -Force -Seconds 5
    } else {
        Show-Bubble "Ok ! Tout est gardé dans clic droit > ↩ Mes reprises." -Force -Seconds 4
    }
}

# Texte de la carte : titre = prochaine etape (ou ce que tu faisais), le reste en description
function Get-ContextCardText($ctx) {
    $lines = @()
    if ($ctx.doing) { $lines += "J'étais en train de : $($ctx.doing)" }
    if ($ctx.next -and $ctx.doing) { $lines += "Prochaine étape : $($ctx.next)" }
    foreach ($w in @($ctx.windows)) {
        if ($w.private) { continue }
        $l = "$((Get-AppInfo $w.app).Name) : $($w.title)"
        if ($w.url) { $l += "`n   $($w.url)" } elseif ($w.path) { $l += "`n   $($w.path)" }
        $lines += $l
    }
    $lines += "(Interrompu $(Format-Ago $ctx.created))"
    return @{ Title = (Get-ContextTitle $ctx 140); Desc = ($lines -join "`r`n") }
}

function Convert-ContextToCard([string]$id) {
    $ctx = Find-Context $id
    if (-not $ctx) { return $null }
    $c = Get-ContextCardText $ctx
    $NB.LastAddedId = ''
    Add-Todo $c.Title
    $t = Find-Todo $NB.LastAddedId
    if (-not $t) { return $null }
    $t.desc = $c.Desc
    Save-Todos
    Complete-Context $id
    $b = Get-Board $t.board
    Show-Bubble "🗂 Reprise transformée en carte dans « $($b.name) »." -Force -Seconds 4
    return $t
}

# ---------------------------------------------------------------------------
#  Bulle « Où j'en étais ? »
# ---------------------------------------------------------------------------
$script:BubbleCtxId = ''
function Get-ResumeText($ctx, [switch]$Reminder) {
    $when = Format-Ago $ctx.created
    $text = if ($Reminder) { "⏰ Tu reprends ? Tu t'étais arrêté(e) $when sur :" } else { "↩ Tu t'étais arrêté(e) $when sur :" }
    $w = Get-MainWindow $ctx
    if ($w) { $text += "`n$(Get-WindowLabel $w 60)" }
    $others = @($ctx.windows).Count - 1
    if ($others -gt 0) { $text += "  (+ $others autre(s) fenêtre(s))" }
    if ($ctx.doing) { $text += "`n✍ J'étais en train de : $($ctx.doing)" }
    if ($ctx.next) { $text += "`n➡ Prochaine étape : $($ctx.next)" }
    $more = @(Get-OpenContexts).Count - 1
    if ($more -gt 0) { $text += "`n($more autre(s) reprise(s) en attente)" }
    return $text
}

function Show-ResumeBubble($ctx, [switch]$Reminder) {
    if (-not $ctx) { return }
    $script:BubbleCtxId = $ctx.id
    $btns = @(
        @{ Label = '▶ Reprendre'; Action = { Resume-Context $script:BubbleCtxId }; Primary = $true },
        @{ Label = '⏰ Plus tard'; Action = { Snooze-Context $script:BubbleCtxId } },
        @{ Label = '🗂 En carte'; Action = { [void](Convert-ContextToCard $script:BubbleCtxId) } },
        @{ Label = '✓ Déjà fait'; Action = { Complete-Context $script:BubbleCtxId; Show-Bubble "Super ✅ Une chose de moins dans la tête." -Force -Seconds 3 } })
    if (@(Get-OpenContexts).Count -gt 1) { $btns += @{ Label = '↩ Toutes'; Action = { Open-Notebook 'Ctx' } } }
    Ensure-Visible
    Show-Bubble (Get-ResumeText $ctx -Reminder:$Reminder) -Force -AutoHide -Seconds 120 -Buttons $btns
}

# Au retour apres une absence (2 min sans clavier ni souris) : « Où j'en étais ? »
$script:CtxAwayId = ''
function Check-ContextReturn {
    if (-not $Native) { return }
    $idle = [OrbitNative]::IdleMs() / 1000.0
    if ($idle -ge 120) {
        if (-not $script:CtxAwayId) {
            $c = Get-LatestOpenContext -Hours 12
            if ($c) { $script:CtxAwayId = $c.id }
        }
        return
    }
    if ($script:CtxAwayId -and $idle -lt 3) {
        $c = Find-Context $script:CtxAwayId
        $script:CtxAwayId = ''
        if ($c -and $c.status -eq 'open' -and -not $O.AutoPaused) { Show-ResumeBubble $c }
    }
}

# Relance si la reprise attend (option des reglages, 3 fois au plus) : jamais pendant un
# focus en cours, ni par-dessus une question, ni quand personne n'est la
function Get-DueContext([datetime]$now) {
    if (-not $Config.ContextRemind -or $Config.ContextRemindMin -le 0) { return $null }
    $s = $now.ToString('s')
    foreach ($c in @(Get-OpenContexts)) {
        if ($c.remindAt -and $c.remindAt -le $s -and $c.reminders -lt $CtxMaxReminders) { return $c }
    }
    return $null
}

function Check-ContextReminders([datetime]$now) {
    if ($O.State -eq 'Focus' -and -not $O.Paused) { return }
    if ($O.State -like 'Await*' -or $ui.BubbleButtons.Children.Count -gt 0) { return }
    if ($Native -and [OrbitNative]::IdleMs() -gt 60000) { return }
    $c = Get-DueContext $now
    if (-not $c) { return }
    $c.reminders++
    $c.remindAt = $now.AddMinutes([math]::Max(5, $Config.ContextRemindMin)).ToString('s')
    Save-Contexts
    Show-ResumeBubble $c -Reminder
}

# ---------------------------------------------------------------------------
#  Le post-it « Je m'interromps »
# ---------------------------------------------------------------------------
[xml]$CtxNoteXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Je m'interromps" Width="420" SizeToContent="Height" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" FontFamily="Segoe UI, Segoe UI Emoji, Segoe UI Symbol" FontSize="13.5">
  <Border Margin="8" CornerRadius="14" Background="#EEF4FF" BorderBrush="#1E1B3A" BorderThickness="2.5">
    <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="-45" Opacity="0.25"/></Border.Effect>
    <StackPanel Margin="14,8,14,12">
      <Grid x:Name="CtxHeader" Background="Transparent" Margin="0,0,0,6" Cursor="SizeAll">
        <TextBlock x:Name="CtxTitle" Text="✋ Je m'interromps" FontWeight="Bold" FontSize="14.5" Foreground="#1E1B3A" VerticalAlignment="Center"/>
        <Button x:Name="CtxClose" Content="✕" HorizontalAlignment="Right" Width="24" Height="22" Background="Transparent" BorderThickness="0"
                Cursor="Hand" ToolTip="Fermer (c'est gardé)"/>
      </Grid>
      <Border Background="#FFFFFF" BorderBrush="#C9D6F2" BorderThickness="1" CornerRadius="8" Padding="8,5">
        <TextBlock x:Name="CtxSummary" TextWrapping="Wrap" FontSize="12" Foreground="#4A4766"/>
      </Border>
      <TextBlock Text="J'étais en train de…" FontWeight="SemiBold" Foreground="#1E1B3A" Margin="0,10,0,3"/>
      <TextBox x:Name="CtxDoing" TextWrapping="Wrap" AcceptsReturn="False" MinHeight="44" MaxHeight="120" VerticalScrollBarVisibility="Auto"
               Padding="6,4" BorderBrush="#9FB4E3" ToolTip="Ex. : vérifier les totaux du T3 dans le budget"/>
      <TextBlock Text="➡ Prochaine étape exacte (pour m'y remettre sans réfléchir) :" FontWeight="SemiBold" Foreground="#1E1B3A" Margin="0,10,0,3" TextWrapping="Wrap"/>
      <TextBox x:Name="CtxNext" TextWrapping="Wrap" AcceptsReturn="False" MinHeight="44" MaxHeight="120" VerticalScrollBarVisibility="Auto"
               Padding="6,4" BorderBrush="#9FB4E3" ToolTip="Ex. : corriger la cellule F12 puis envoyer à Julie"/>
      <Grid Margin="0,10,0,0">
        <TextBlock x:Name="CtxHint" Text="Les deux sont facultatifs · Entrée = enregistrer" Foreground="#6B7AA0" FontSize="11" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="CtxCancel" Content="Annuler" Padding="10,3" Margin="0,0,6,0" Cursor="Hand" Background="#FFFFFF" BorderBrush="#C9D6F2"
                  ToolTip="Ne rien garder (le focus reprend)"/>
          <Button x:Name="CtxSave" Content="✓ Enregistrer" Padding="12,3" Cursor="Hand" Background="#1E1B3A" Foreground="White" BorderThickness="0"/>
        </StackPanel>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@
$script:ctxWin = $null
$script:CtxEdit = $null
$script:ctxClosing = $false

function Initialize-ContextEditor {
    if ($script:ctxWin) { return }
    $script:ctxWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $CtxNoteXaml))
    $script:cx = @{}
    foreach ($n in 'CtxHeader', 'CtxTitle', 'CtxClose', 'CtxSummary', 'CtxDoing', 'CtxNext', 'CtxHint', 'CtxCancel', 'CtxSave') { $cx[$n] = $ctxWin.FindName($n) }
    $cx.CtxHeader.Add_MouseLeftButtonDown({ try { $ctxWin.DragMove() } catch {} })
    $cx.CtxClose.Add_Click({ Invoke-Safe { Close-ContextEditor } })
    $cx.CtxSave.Add_Click({ Invoke-Safe { Close-ContextEditor } })
    $cx.CtxCancel.Add_Click({ Invoke-Safe { Close-ContextEditor -Cancel } })
    # Entree : de « ce que je faisais » a « prochaine etape », puis enregistrer
    $cx.CtxDoing.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $e.Handled = $true; $cx.CtxNext.Focus() | Out-Null } })
    $cx.CtxNext.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $e.Handled = $true; Invoke-Safe { Close-ContextEditor } } })
    # on est appele ailleurs (c'est le principe d'une interruption) : c'est garde
    $ctxWin.Add_Deactivated({ Invoke-Safe { Close-ContextEditor } })
    $ctxWin.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $e.Handled = $true; Invoke-Safe { Close-ContextEditor } } })
    $ctxWin.Add_Closing({ param($s, $e) if (-not $NB.Quitting) { $e.Cancel = $true; Invoke-Safe { Close-ContextEditor } } })
}

function Get-ContextSummary($ctx, [bool]$shot, [bool]$paused) {
    $lines = @()
    $wins = @($ctx.windows)
    if (-not $wins.Count) { $lines += "🖥 Aucune fenêtre trouvée : écris juste où tu en es." }
    $i = 0
    foreach ($w in $wins) {
        $l = if ($i -eq 0) { "📌 $(Get-WindowLabel $w 55)" } else { "     $(Get-WindowLabel $w 50)" }
        if ($w.url) { $l += "`n      🔗 $(Short-Text ($w.url -replace '^https?://', '') 60)" }
        elseif ($w.path) { $l += "`n      📁 $(Short-Text $w.path 60)" }
        $lines += $l
        $i++
        if ($i -ge 6) { break }
    }
    if ($script:CtxProbe -and $script:CtxProbe.Ctx -eq $ctx) { $lines += "🔎 Je lis les adresses des onglets…" }
    if ($shot -or (Test-Path -LiteralPath (Get-ContextShotPath $ctx.id))) { $lines += "📷 Capture d'écran gardée (sur ce PC uniquement)" }
    $cards = @($ctx.focusCards | ForEach-Object { Find-Todo $_ } | Where-Object { $_ })
    if ($cards.Count) { $lines += "🎯 $(($cards | Select-Object -First 2 | ForEach-Object { Short-Text $_.text 35 }) -join ', ')" }
    if ($paused) { $lines += "⏸ Focus en pause ($([math]::Ceiling($O.Remaining.TotalMinutes)) min restantes)" }
    return ($lines -join "`n")
}

function Update-ContextSummary {
    if (-not $script:ctxWin -or -not $ctxWin.IsVisible -or -not $script:CtxEdit) { return }
    $cx.CtxSummary.Text = ConvertTo-DisplayText (Get-ContextSummary $script:CtxEdit.Ctx $script:CtxEdit.Shot $script:CtxEdit.Paused)
}

# Ouvre le post-it : pour la reprise en cours de creation, ou pour modifier une reprise ($id)
function Show-ContextEditor([string]$id = '') {
    Initialize-ContextEditor
    if ($id) {
        if ($ctxWin.IsVisible) { Close-ContextEditor }
        $ctx = Find-Context $id
        if (-not $ctx) { return }
        $script:CtxEdit = @{ Ctx = $ctx; IsNew = $false; Paused = $false; Shot = $false }
    }
    $e = $script:CtxEdit
    if (-not $e) { return }
    $cx.CtxTitle.Text = if ($e.IsNew) { "✋ Je m'interromps" } else { "✏ Reprise du $(([datetime]$e.Ctx.created).ToString('dd/MM à HH:mm'))" }
    $cx.CtxDoing.Text = $e.Ctx.doing
    $cx.CtxNext.Text = if ($e.IsNew -and -not $e.Ctx.next) { Get-SuggestedNext } else { $e.Ctx.next }
    $cx.CtxCancel.Content = if ($e.IsNew) { 'Annuler' } else { 'Fermer sans changer' }
    $cx.CtxSummary.Text = ConvertTo-DisplayText (Get-ContextSummary $e.Ctx $e.Shot $e.Paused)
    if (-not $ctxWin.IsVisible) {
        $wa = Get-WorkArea ([System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position))
        $ctxWin.Left = ($wa.L + $wa.R) / 2 - 210
        $ctxWin.Top = [math]::Max($wa.T, ($wa.T + $wa.B) / 2 - 220)
        $ctxWin.Show()
    }
    $ctxWin.Activate() | Out-Null
    $cx.CtxDoing.Focus() | Out-Null
    if ($cx.CtxNext.Text -and -not $cx.CtxDoing.Text) { $cx.CtxNext.SelectAll() }
}

function Close-ContextEditor([switch]$Cancel) {
    if (-not $script:ctxWin -or $script:ctxClosing -or -not $ctxWin.IsVisible) { return }
    $script:ctxClosing = $true
    try {
        $e = $script:CtxEdit
        $ctxWin.Hide()
        if (-not $e) { return }
        $script:CtxEdit = $null
        if ($Cancel) {
            if ($e.IsNew) {
                Remove-ContextShot $e.Ctx.id
                if ($e.Paused -and $O.State -eq 'Focus' -and $O.Paused) {
                    $O.EndsAt = (Get-Date) + $O.Remaining; $O.Paused = $false; Update-Pill
                }
                Show-Bubble "Ok, rien de gardé.$(if ($e.Paused) { ' Le focus continue ▶' })" -Force -Seconds 3
            }
            return
        }
        $e.Ctx.doing = $cx.CtxDoing.Text.Trim()
        $e.Ctx.next = $cx.CtxNext.Text.Trim()
        if ($e.IsNew) {
            Add-Context $e.Ctx
            $msg = "✋ C'est noté, je garde où tu en es."
            if ($e.Ctx.next) { $msg += "`n➡ $(Short-Text $e.Ctx.next 80)" }
            $msg += "`nQuand tu reviens, clique sur moi : je te remets là où tu en étais."
            if ($e.Paused) { $msg += "`n⏸ Focus en pause." }
            Show-Bubble $msg -Force -Seconds 8
        } else {
            Save-Contexts
        }
        Render-Contexts
        Update-Tabs
    } finally { $script:ctxClosing = $false }
}

# ---------------------------------------------------------------------------
#  L'onglet « ↩ Reprises » du carnet : le tableau de bord
# ---------------------------------------------------------------------------
function New-CtxButton([string]$label, [string]$tip, [string]$id, [scriptblock]$onClick, [switch]$Primary) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $label; $b.ToolTip = $tip; $b.Tag = $id
    $b.Padding = '7,2'; $b.Margin = '0,0,4,0'; $b.Cursor = 'Hand'
    if ($Primary) { $b.Background = '#1E1B3A'; $b.Foreground = 'White'; $b.BorderThickness = '0' }
    else { $b.Background = 'Transparent'; $b.BorderThickness = '0' }
    $b.Add_Click($onClick)
    return $b
}

function New-CtxText([string]$text, [double]$size = 12.5, [string]$color = '#1E1B3A', [string]$weight = 'Normal') {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = ConvertTo-DisplayText $text; $tb.TextWrapping = 'Wrap'; $tb.FontSize = $size; $tb.Foreground = $color; $tb.FontWeight = $weight
    $tb.Margin = '0,2,0,0'
    return $tb
}

function New-ContextCard($ctx) {
    $open = $ctx.status -eq 'open'
    $card = New-Object Windows.Controls.Border
    $card.Margin = '0,0,0,8'; $card.Padding = '10,6,6,8'; $card.CornerRadius = '10'
    $card.Background = if ($open) { '#EEF4FF' } else { '#F4F4F8' }
    $card.BorderBrush = if ($open) { '#9FB4E3' } else { '#E2E2EA' }
    $card.BorderThickness = '1'
    $sp = New-Object Windows.Controls.StackPanel
    $head = New-Object Windows.Controls.DockPanel
    $btns = New-Object Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    if ($open) {
        [void]$btns.Children.Add((New-CtxButton '▶ Reprendre' 'Remettre les fenêtres devant (ou les rouvrir) et relancer le focus' $ctx.id { param($s, $e) Invoke-Safe { Resume-Context $s.Tag } } -Primary))
        [void]$btns.Children.Add((New-CtxButton '✏' 'Modifier' $ctx.id { param($s, $e) Invoke-Safe { Show-ContextEditor $s.Tag } }))
        [void]$btns.Children.Add((New-CtxButton '🗂' 'En faire une carte' $ctx.id { param($s, $e) Invoke-Safe { [void](Convert-ContextToCard $s.Tag) } }))
        [void]$btns.Children.Add((New-CtxButton '✓' 'Terminé (sans rien rouvrir)' $ctx.id { param($s, $e) Invoke-Safe { Complete-Context $s.Tag } }))
    }
    [void]$btns.Children.Add((New-CtxButton '🗑' 'Supprimer' $ctx.id {
                param($s, $e) Invoke-Safe {
                    $c = Find-Context $s.Tag
                    if ($c -and ($c.status -ne 'open' -or (Confirm-Action "Supprimer cette reprise ?`n« $(Get-ContextTitle $c 60) »"))) { Remove-Context $s.Tag }
                } }))
    [Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    [void]$head.Children.Add($btns)
    $when = if ($open) { "✋ $(Format-Ago $ctx.created)" } else { "✓ reprise $(Format-Ago $ctx.doneAt)" }
    $whenTb = New-CtxText $when 11 '#6B7AA0'
    $whenTb.VerticalAlignment = 'Center'
    [void]$head.Children.Add($whenTb)
    [void]$sp.Children.Add($head)
    $w = Get-MainWindow $ctx
    if ($w) { [void]$sp.Children.Add((New-CtxText (Get-WindowLabel $w 80) 13 '#1E1B3A' 'SemiBold')) }
    if ($w -and $w.url) { [void]$sp.Children.Add((New-CtxText "🔗 $(Short-Text $w.url 90)" 11 '#6B7AA0')) }
    elseif ($w -and $w.path) { [void]$sp.Children.Add((New-CtxText "📁 $(Short-Text $w.path 90)" 11 '#6B7AA0')) }
    if ($ctx.doing) { [void]$sp.Children.Add((New-CtxText "✍ $($ctx.doing)" 12.5 '#4A4766')) }
    if ($ctx.next) { [void]$sp.Children.Add((New-CtxText "➡ $($ctx.next)" 13 '#5B3FD6' 'Bold')) }
    $others = @($ctx.windows | Select-Object -Skip 1)
    if ($others.Count) {
        [void]$sp.Children.Add((New-CtxText ("+ " + (($others | ForEach-Object { Get-WindowLabel $_ 30 }) -join ' · ')) 11 '#6B7AA0'))
    }
    $shot = Get-ContextShotPath $ctx.id
    if ($open -and (Test-Path -LiteralPath $shot)) {
        try {
            $bi = New-Object Windows.Media.Imaging.BitmapImage
            $bi.BeginInit()
            $bi.CacheOption = 'OnLoad'     # le fichier n'est pas verrouille (on peut l'effacer)
            $bi.DecodePixelWidth = 260
            $bi.UriSource = New-Object Uri($shot)
            $bi.EndInit()
            $img = New-Object Windows.Controls.Image
            $img.Source = $bi; $img.Width = 260; $img.HorizontalAlignment = 'Left'; $img.Margin = '0,6,0,0'
            $img.Cursor = 'Hand'; $img.ToolTip = 'Clic : voir la capture en grand'; $img.Tag = $ctx.id
            $img.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { $f = Get-ContextShotPath $s.Tag; if (Test-Path -LiteralPath $f) { Start-Process explorer.exe "`"$f`"" } } })
            [void]$sp.Children.Add($img)
        } catch { Write-Log "Capture illisible : $($_.Exception.Message)" }
    }
    $card.Child = $sp
    return $card
}

function Render-Contexts {
    if (-not $script:panel -or -not $pn.CtxList -or $NB.Tab -ne 'Ctx') { return }
    $pn.CtxList.Children.Clear()
    $open = @(Get-OpenContexts)
    foreach ($c in $open) { [void]$pn.CtxList.Children.Add((New-ContextCard $c)) }
    if (-not $open.Count) {
        $e = New-Object Windows.Controls.TextBlock
        $e.Text = "Aucune reprise en attente 🎉`nQuand on t'interrompt, clique sur « ✋ Je m'interromps » : je garde la fenêtre, l'onglet et la prochaine étape pour t'y remettre en un clic."
        $e.Foreground = '#9A98B0'; $e.TextWrapping = 'Wrap'; $e.TextAlignment = 'Center'; $e.Margin = '4,14,4,10'
        [void]$pn.CtxList.Children.Add($e)
    }
    $done = @($NB.Contexts | Where-Object { $_.status -eq 'done' } | Sort-Object -Property @{ e = { [string]$_.doneAt }; Descending = $true } | Select-Object -First 15)
    if ($done.Count) {
        [void]$pn.CtxList.Children.Add((New-SectionTitle "✓ Déjà reprises ($CtxKeepDays derniers jours)"))
        foreach ($c in $done) { [void]$pn.CtxList.Children.Add((New-ContextCard $c)) }
    }
    $txt = "$($open.Count) en attente"
    if ($Config.ContextRemind -and $Config.ContextRemindMin -gt 0) { $txt += " · rappel après $($Config.ContextRemindMin) min" }
    $txt += " · tout reste sur ce PC"
    $pn.CtxCount.Text = $txt
}

Load-Contexts
