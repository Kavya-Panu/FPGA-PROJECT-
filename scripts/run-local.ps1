param(
    [ValidateSet('Demo','Test')][string]$Mode = 'Demo',
    [string]$Python = '',
    [string]$Iverilog = '',
    [string]$Vvp = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)

function Resolve-Program([string]$explicitPath, [string]$program, [string[]]$fallbacks) {
    if ($explicitPath) { return (Resolve-Path -LiteralPath $explicitPath).Path }
    $command = Get-Command $program -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notmatch 'WindowsApps') { return $command.Source }
    foreach ($candidate in $fallbacks) {
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw "Cannot find $program. Install it or pass its executable path to this script."
}

$pythonExe = Resolve-Program $Python 'python' @(
    (Join-Path $projectRoot '.venv\Scripts\python.exe'),
    (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'))
$iverilogExe = Resolve-Program $Iverilog 'iverilog' @(
    (Join-Path $workspaceRoot 'work\tools\iverilog\bin\iverilog.exe'))
$vvpExe = Resolve-Program $Vvp 'vvp' @(
    (Join-Path (Split-Path -Parent $iverilogExe) 'vvp.exe'))
$previousIverilog = $env:IVERILOG
$previousVvp = $env:VVP
try {
    $env:IVERILOG = $iverilogExe
    $env:VVP = $vvpExe
    if ($Mode -eq 'Demo') {
        & $pythonExe (Join-Path $projectRoot 'tests\run.py') --demo --waves
    } else {
        & $pythonExe (Join-Path $projectRoot 'tools\check.py')
    }
    if ($LASTEXITCODE -ne 0) { throw "Verification failed with exit code $LASTEXITCODE" }
} finally {
    $env:IVERILOG = $previousIverilog
    $env:VVP = $previousVvp
}
