# ---------------------------------------------------------------------------
#  Transfert vers un autre PC : un seul fichier zip qui contient Orbit (le
#  programme) et tes donnees (reglages, tableaux, modeles, favoris, sons, image).
#  Sur l'autre PC : decompresser, double-clic sur Orbit.cmd, et c'est pret.
# ---------------------------------------------------------------------------
$ExportManifest = 'orbit-export.json'
# ce qui ne voyage pas : propre a ce PC, temporaire ou prive
$ExportSkip = @('native-*.dll', '*.log', 'etat.json', 'derniere-relance.txt', '*.tmp', 'clipboard', 'avant-import-*', 'kanban-illisible-*')

function Test-ExportSkip([string]$relative) {
    $first = $relative.Split('\/')[0]
    foreach ($p in $ExportSkip) { if ($first -like $p -or [IO.Path]::GetFileName($relative) -like $p) { return $true } }
    return $false
}

function Copy-OrbitData([string]$from, [string]$to) {
    $n = 0
    if (-not (Test-Path -LiteralPath $from)) { return 0 }
    $base = (Resolve-Path -LiteralPath $from).ProviderPath.TrimEnd('\', '/')
    foreach ($f in Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $rel = $f.FullName.Substring($base.Length + 1)
        if (Test-ExportSkip $rel) { continue }
        $dest = Join-Path $to $rel
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $n++
    }
    return $n
}

# Prepare le dossier a zipper : <dossier>\Orbit\ (programme) + <dossier>\Orbit\donnees\ (tes donnees)
function New-OrbitPackageFolder([string]$stage, [string]$programDir = $PSScriptRoot) {
    $app = Join-Path $stage 'Orbit'
    New-Item -ItemType Directory -Path $app -Force | Out-Null
    foreach ($f in Get-ChildItem -LiteralPath $programDir -File | Where-Object { $_.Extension -in '.ps1', '.cmd', '.md' }) {
        Copy-Item -LiteralPath $f.FullName -Destination $app -Force
    }
    $jokes = Join-Path $programDir 'jokes'
    if (Test-Path -LiteralPath $jokes) { Copy-Item -LiteralPath $jokes -Destination $app -Recurse -Force }
    $data = Join-Path $app 'donnees'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    $n = Copy-OrbitData $DataDir $data
    $manifest = [ordered]@{ from = $DataDir; date = (Get-Date).ToString('s'); files = $n; computer = $env:COMPUTERNAME }
    [IO.File]::WriteAllText((Join-Path $data $ExportManifest), (ConvertTo-Json -InputObject $manifest), (New-Object Text.UTF8Encoding($true)))
    return $app
}

function Export-OrbitPackage([string]$zipPath) {
    if (-not $zipPath) {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'Exporter Orbit vers un autre PC'
        $dlg.Filter = 'Archive zip (*.zip)|*.zip'
        $dlg.FileName = "Orbit-transfert-$((Get-Date).ToString('yyyy-MM-dd')).zip"
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if (-not $dlg.ShowDialog()) { return $null }
        $zipPath = $dlg.FileName
    }
    # tout ce qui attend d'etre ecrit part dans le paquet
    Save-Stats; Save-Settings; Save-Todos; Flush-Notebook
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('orbit-export-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        [void](New-OrbitPackageFolder $stage)
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    $mb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
    Write-Log "Export : $zipPath ($mb Mo)"
    if (Get-Command Show-Bubble -ErrorAction SilentlyContinue) {
        Show-Bubble "📦 C'est prêt : $([IO.Path]::GetFileName($zipPath)) ($mb Mo).`nSur l'autre PC : décompresse-le, puis double-clic sur Orbit\Orbit.cmd. Je récupère tes tableaux, réglages, modèles, favoris et sons." -Force -Seconds 12
    }
    return $zipPath
}

# Copie des donnees d'un export dans %APPDATA%\Orbit. Les donnees deja presentes
# sont gardees dans avant-import-<date>. Renvoie $true si l'import a eu lieu.
function Import-OrbitData([string]$src, [switch]$NoConfirm) {
    $mf = Join-Path $src $ExportManifest
    if (-not (Test-Path -LiteralPath $mf)) { return $false }
    $manifest = ConvertFrom-Json ([IO.File]::ReadAllText($mf))
    $when = try { ([datetime]$manifest.date).ToString('dd/MM/yyyy à HH:mm') } catch { '?' }
    $hasData = Test-Path -LiteralPath (Join-Path $DataDir 'kanban.json')
    if ($hasData -and -not $NoConfirm) {
        $r = [Windows.MessageBox]::Show("Des données Orbit existent déjà sur ce PC.`n`nLes remplacer par celles exportées le $when$(if ($manifest.computer) { " (PC $($manifest.computer))" }) ?`n`nTes données actuelles seront gardées dans un dossier « avant-import ».", 'Orbit : importer', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return $false }
    }
    if ($hasData) {
        $keep = Join-Path $DataDir ('avant-import-' + (Get-Date).ToString('yyyy-MM-dd_HHmmss'))
        [void](Copy-OrbitData $DataDir $keep)
    }
    [void](Copy-OrbitData $src $DataDir)
    Remove-Item -LiteralPath (Join-Path $DataDir $ExportManifest) -Force -ErrorAction SilentlyContinue
    # les chemins de l'autre PC (image perso, sons) pointent maintenant vers ce PC
    $old = [string]$manifest.from
    $set = Join-Path $DataDir 'settings.json'
    if ($old -and $old -ne $DataDir -and (Test-Path -LiteralPath $set)) {
        $j = [IO.File]::ReadAllText($set)
        $esc = { param($p) (ConvertTo-Json -InputObject $p).Trim('"') }
        $j = $j.Replace((& $esc $old), (& $esc $DataDir))
        Write-FileSafe $set $j
    }
    Protect-ImportedSettings $set
    Write-Log "Import depuis $src (export du $when)"
    return $true
}

# Securite : des reglages venus d'un autre PC (ou d'un export recu de quelqu'un) ne
# doivent pas faire lire ou ecrire Orbit ailleurs que dans son propre dossier.
# Sinon un chemin reseau (\\serveur\partage) pourrait servir a recuperer tes notes
# (copie automatique) ou a faire se connecter ton PC a une machine inconnue (image, sons).
function Protect-ImportedSettings([string]$set) {
    if (-not (Test-Path -LiteralPath $set)) { return }
    try {
        $d = ConvertFrom-Json ([IO.File]::ReadAllText($set))
        $root = [IO.Path]::GetFullPath($DataDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $inside = {
            param($p)
            if (-not $p) { return $false }
            try { return [IO.Path]::GetFullPath([string]$p).StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { return $false }
        }
        $changed = $false
        if ($d.PSObject.Properties['notesMirror'] -and $d.notesMirror) { $d.notesMirror = ''; $changed = $true }   # a rechoisir sur ce PC
        if ($d.PSObject.Properties['customImage'] -and $d.customImage -and -not (& $inside $d.customImage)) { $d.customImage = ''; $changed = $true }
        if ($d.PSObject.Properties['endSoundFile'] -and $d.endSoundFile -and -not (& $inside $d.endSoundFile)) { $d.endSoundFile = ''; $changed = $true }
        if ($d.PSObject.Properties['bubbleSoundFiles']) {
            $keep = @(@($d.bubbleSoundFiles) | Where-Object { & $inside $_ })
            if ($keep.Count -ne @($d.bubbleSoundFiles | Where-Object { $_ }).Count) { $d.bubbleSoundFiles = $keep; $changed = $true }
        }
        if ($changed) {
            Write-FileSafe $set (ConvertTo-Json -InputObject $d)
            Write-Log "Import : chemins hors du dossier d'Orbit retires des reglages"
        }
    } catch {
        # reglages illisibles : on les ecarte plutot que de les appliquer a l'aveugle
        Remove-Item -LiteralPath $set -Force -ErrorAction SilentlyContinue
        Write-Log "Import : reglages illisibles ignores ($($_.Exception.Message))"
    }
}

# Au demarrage : un dossier « donnees » a cote d'Orbit = un export a recuperer (une seule fois)
function Invoke-PendingImport {
    $src = Join-Path $PSScriptRoot 'donnees'
    if (-not (Test-Path -LiteralPath (Join-Path $src $ExportManifest))) { return $null }
    $done = $false
    try { $done = Import-OrbitData $src } catch { Write-Log "Import : $($_.Exception.Message)" }
    # on renomme le dossier pour ne pas re-importer au prochain lancement
    $newName = if ($done) { 'donnees-importees' } else { 'donnees-non-importees' }
    try {
        $target = Join-Path $PSScriptRoot $newName
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Rename-Item -LiteralPath $src -NewName $newName
    } catch { Write-Log "Renommage du dossier importe : $($_.Exception.Message)" }
    if ($done) { return "📦 Bienvenue sur ce PC ! J'ai récupéré tes tableaux, réglages, modèles, favoris et sons." }
    return $null
}

# Menu « Importer » : depuis un zip d'export, puis Orbit redemarre pour tout recharger
function Import-OrbitPackage {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Importer un export d''Orbit'
    $dlg.Filter = 'Export Orbit (*.zip)|*.zip'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if (-not $dlg.ShowDialog()) { return }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('orbit-import-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($dlg.FileName, $tmp)
        $mf = Get-ChildItem -LiteralPath $tmp -Recurse -Filter $ExportManifest | Select-Object -First 1
        if (-not $mf) { [void][Windows.MessageBox]::Show("Ce fichier n'est pas un export d'Orbit.", 'Orbit'); return }
        if (Import-OrbitData $mf.DirectoryName) {
            Show-Bubble "📦 Import terminé, je redémarre pour tout recharger…" -Force -Seconds 3
            Restart-Orbit
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
