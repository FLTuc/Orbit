# Outils partages par les tests (PowerShell 5.1 sous Windows, ou pwsh ailleurs)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$script:Pass = 0
$script:Fail = 0

function Check([string]$name, $ok, [string]$detail = '') {
    if ($ok) { $script:Pass++; Write-Host "  OK    $name" }
    else { $script:Fail++; Write-Host "  ECHEC $name $detail" -ForegroundColor Red }
}

function Section([string]$name) { Write-Host ''; Write-Host "== $name" -ForegroundColor Cyan }

function Finish {
    Write-Host ''
    Write-Host "$($script:Pass) verification(s) reussie(s), $($script:Fail) echec(s)"
    if ($script:Fail) { exit 1 } else { exit 0 }
}

function New-TempDir {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('orbit-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $d | Out-Null
    return $d
}

# Charge les fonctions d'un script sans executer le reste (pas de fenetre)
function Get-ScriptFunctions([string]$file, [string[]]$only) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
    $defs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    return @($defs | Where-Object { -not $only -or $only -contains $_.Name } | ForEach-Object { $_.Extent.Text })
}

function Get-ScriptAssignments([string]$file, [string]$pattern) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
    return @($ast.EndBlock.Statements | Where-Object { $_.Extent.Text -match $pattern } | ForEach-Object { $_.Extent.Text })
}
