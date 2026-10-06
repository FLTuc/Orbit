# Controle de securite automatique (statique : lit le code, ne l'execute pas)
#  1. PSScriptAnalyzer (l'analyseur officiel de Microsoft) : regles de securite
#  2. Regles propres a Orbit, verifiees dans tout le code :
#     - aucun code fabrique a partir de donnees (cartes, notes, fichiers importes)
#     - aucun acces reseau, aucun Invoke-Expression
#     - le registre : seulement le reglage d'epinglage de l'icone, dans le compte de l'utilisateur
#     - pas d'elevation de droits (administrateur)
#     - seuls explorer.exe et powershell.exe (Orbit lui-meme) peuvent etre lances
#     - les fenetres (XAML) ne sont construites qu'a partir de textes fixes du programme
. (Join-Path $PSScriptRoot 'common.ps1')
$files = @(Get-ChildItem -Path $Root -Filter '*.ps1' -File)

Section 'PSScriptAnalyzer (regles de securite de Microsoft)'
$rules = 'PSAvoidUsingInvokeExpression', 'PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingConvertToSecureStringWithPlainText',
         'PSAvoidUsingUsernameAndPasswordParams', 'PSUsePSCredentialType', 'PSAvoidUsingComputerNameHardcoded',
         'PSAvoidUsingBrokenHashAlgorithms', 'PSAvoidAssignmentToAutomaticVariable', 'PSAvoidGlobalVars'
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    try { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -ErrorAction Stop } catch { Write-Host "  (PSScriptAnalyzer indisponible : $($_.Exception.Message))" }
}
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $found = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -IncludeRule $rules })
    foreach ($f in $found) { Write-Host "  $(Split-Path -Leaf $f.ScriptPath):$($f.Line) $($f.RuleName) - $($f.Message)" -ForegroundColor Yellow }
    Check "aucune alerte de securite ($($rules.Count) regles)" ($found.Count -eq 0) "$($found.Count) alerte(s)"
} else { Write-Host '  analyse sautee' }

Section 'Regles propres a Orbit'
function Find-Code([string]$pattern) {
    foreach ($f in $files) {
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
            $n++
            $code = ($line -split '(?<!`)#', 2)[0]   # sans les commentaires
            if ($code -match $pattern) { [pscustomobject]@{ File = $f.Name; Line = $n; Text = $line.Trim() } }
        }
    }
}
function Report($hits) { foreach ($h in $hits) { Write-Host "  $($h.File):$($h.Line)  $($h.Text)" -ForegroundColor Yellow } }

# du code fabrique a partir d'un texte : seulement avec des noms fixes du programme (rythmes, dessins)
$creates = @(Find-Code '\[scriptblock\]::Create\(')
# on regarde le texte passe a Create(...) : il ne doit contenir que $name ou $k (cles fixes des tables du programme)
$bad = @($creates | Where-Object {
        $arg = [regex]::Match($_.Text, 'Create\("([^"]*)"\)').Groups[1].Value
        -not $arg -or $arg -match '\$\(' -or @([regex]::Matches($arg, '\$[A-Za-z_][A-Za-z0-9_]*') | ForEach-Object Value | Where-Object { $_ -notin '$name', '$k' }).Count })
Report $bad
Check "code genere uniquement a partir de noms fixes ($($creates.Count) endroits verifies)" ($bad.Count -eq 0)

$net = @(Find-Code '(?i)Invoke-Expression|\biex\b|Invoke-WebRequest|Invoke-RestMethod|Net\.WebClient|DownloadString|DownloadFile|TcpClient|Net\.Sockets|HttpClient|Start-BitsTransfer')
Report $net
Check 'aucun acces reseau ni Invoke-Expression' ($net.Count -eq 0)

$reg = @(Find-Code '(?i)HKLM:|HKEY_LOCAL_MACHINE|Registry::|New-ItemProperty|Set-ItemProperty|Remove-ItemProperty')
$regBad = @($reg | Where-Object { $_.Text -notmatch "Set-ItemProperty -Path \`$k\.PSPath -Name 'IsPromoted'" })
Report $regBad
Check "registre : seulement l'epinglage de l'icone ($($reg.Count) ecriture verifiee)" ($regBad.Count -eq 0)
$hkcu = @(Find-Code 'HKCU:')
Check "registre : uniquement le compte de l'utilisateur (HKCU), reglage des icones" (@($hkcu | Where-Object { $_.Text -notmatch 'NotifyIconSettings' }).Count -eq 0)

$elev = @(Find-Code '(?i)-Verb\s+RunAs|runas\.exe|Set-ExecutionPolicy|Add-MpPreference|Disable-|New-Service|schtasks')
Report $elev
Check "pas d'elevation de droits ni de changement de securite du PC" ($elev.Count -eq 0)

$procs = @(Find-Code '(?i)Start-Process')
$procBad = @($procs | Where-Object { $_.Text -notmatch "Start-Process (-FilePath )?('?explorer\.exe|\`$OrbitConhost\b|\`$OrbitPowerShell\b)" })
Report $procBad
Check "programmes lances : seulement explorer.exe et Orbit ($($procs.Count) endroits)" ($procBad.Count -eq 0)
$orb = [IO.File]::ReadAllText((Join-Path $Root 'orbit.ps1'))
Check 'Orbit relance : chemins fixes de Windows (conhost.exe, powershell.exe)' (
    $orb -match "\`$OrbitConhost = Join-Path \`$env:SystemRoot 'System32\\conhost\.exe'" -and
    $orb -match "\`$OrbitPowerShell = Join-Path \`$PSHOME 'powershell\.exe'")

$xaml = @(Find-Code 'XamlReader\]::(Load|Parse)')
$xamlBad = @($xaml | Where-Object { $_.Text -notmatch 'XmlNodeReader \$(xaml|panelXaml|settingsXaml|QuickNoteXaml|doc)\)' })
Report $xamlBad
Check "fenetres construites seulement a partir du programme ($($xaml.Count) endroits)" ($xamlBad.Count -eq 0)

$dll = @(Find-Code 'Add-Type -Path|LoadFrom\(|LoadFile\(')
$dllBad = @($dll | Where-Object { $_.Text -notmatch 'Add-Type -Path \$dll' })
Report $dllBad
Check "seul le code natif compile par Orbit lui-meme est charge" ($dllBad.Count -eq 0)

# les identifiants lus sur le disque passent tous par le filtre
$nb = [IO.File]::ReadAllText((Join-Path $Root 'notebook.ps1'))
$nt = [IO.File]::ReadAllText((Join-Path $Root 'notes.ps1'))
Check 'identifiants des cartes et notes filtres a la lecture' ($nb -match 'id = \(Get-SafeId \$t\.id\)' -and $nt -match 'id = \(Get-SafeId \$n\.id\)' -and $nb -match 'Test-SafeId \$b\.id')
$tr = [IO.File]::ReadAllText((Join-Path $Root 'transfer.ps1'))
Check "import : fichiers de code et d'etat jamais copies" ($tr -match "'native-\*\.dll'" -and $tr -match "'etat\.json'")
Check 'import : reglages nettoyes (chemins hors du dossier d''Orbit)' ($tr -match 'Protect-ImportedSettings \$set')
Finish
