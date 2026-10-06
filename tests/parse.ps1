# Syntaxe de tous les scripts + encodage (UTF-8 avec BOM, indispensable pour PowerShell 5.1)
. (Join-Path $PSScriptRoot 'common.ps1')
Section "Syntaxe ($($PSVersionTable.PSVersion))"
foreach ($f in Get-ChildItem -Path $Root, (Join-Path $Root 'tests') -Filter '*.ps1') {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    Check "$($f.Name) : aucune erreur de syntaxe" ($errors.Count -eq 0) (($errors | ForEach-Object { "ligne $($_.Extent.StartLineNumber) : $($_.Message)" }) -join ' ; ')
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    $ascii = -not ($b | Where-Object { $_ -gt 127 } | Select-Object -First 1)
    Check "$($f.Name) : encodage lisible par PowerShell 5.1" ($hasBom -or $ascii)
}
$cmd = Get-Content -Raw (Join-Path $Root 'Orbit.cmd')
Check 'Orbit.cmd lance orbit.ps1 en STA, sans profil' ($cmd -match '-STA' -and $cmd -match 'orbit\.ps1' -and $cmd -match '-NoProfile')
Check 'Orbit.cmd lance sans fenetre (conhost --headless)' ($cmd -match 'conhost\.exe" --headless' -and $cmd -match 'ORBIT_HEADLESS=1')
Finish
