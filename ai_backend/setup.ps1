Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PythonCommandInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string[]]$Arguments = @()
    )

    return [pscustomobject]@{
        Command = $Command
        Arguments = $Arguments
    }
}

function Test-SupportedPythonVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    if ($VersionText -notmatch 'Python\s+(\d+)\.(\d+)\.(\d+)') {
        return $false
    }

    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    return $major -eq 3 -and ($minor -eq 11 -or $minor -eq 12 -or $minor -eq 14)
}

function Get-UsablePython {
    try {
        $py311 = & py -3.11 --version 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-SupportedPythonVersion -VersionText $py311)) {
            return New-PythonCommandInfo -Command 'py' -Arguments @('-3.11')
        }
    }
    catch {
    }

    try {
        $py312 = & py -3.12 --version 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-SupportedPythonVersion -VersionText $py312)) {
            return New-PythonCommandInfo -Command 'py' -Arguments @('-3.12')
        }
    }
    catch {
    }

    try {
        $versionOutput = & python --version 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-SupportedPythonVersion -VersionText $versionOutput)) {
            return New-PythonCommandInfo -Command 'python'
        }
    }
    catch {
    }

    return $null
}

$pythonCommand = Get-UsablePython

if (-not $pythonCommand) {
    Write-Host ''
    Write-Host 'Python 3.11, 3.12, or 3.14 is required for this backend.' -ForegroundColor Yellow
    Write-Host 'Install it with:' -ForegroundColor Yellow
    Write-Host '  winget install -e --id Python.Python.3.11' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'After installation, close and reopen PowerShell, then run .\setup.ps1 again.' -ForegroundColor Yellow
    Write-Host 'Use 3.11 or 3.12 later when you need faster-whisper model packages.' -ForegroundColor Yellow
    exit 1
}

Write-Host "Using Python command '$($pythonCommand.Command) $($pythonCommand.Arguments -join ' ')'." -ForegroundColor Green

if (-not (Test-Path '.venv')) {
    Write-Host 'Creating virtual environment...' -ForegroundColor Green
    & $pythonCommand.Command @($pythonCommand.Arguments + @('-m', 'venv', '.venv'))
}

$venvPython = Join-Path '.venv' 'Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    throw 'Virtual environment python executable was not created successfully.'
}

Write-Host 'Upgrading pip...' -ForegroundColor Green
& $venvPython -m pip install --upgrade pip

Write-Host 'Installing backend dependencies...' -ForegroundColor Green
& $venvPython -m pip install -r requirements.txt

if (-not (Test-Path '.env')) {
    Copy-Item '.env.example' '.env'
    Write-Host 'Created .env from .env.example.' -ForegroundColor Green
}
else {
    Write-Host '.env already exists. Keeping current values.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Backend setup complete.' -ForegroundColor Green
Write-Host 'Next steps:' -ForegroundColor Green
Write-Host '  1. Edit .env and set your real keys when ready.' -ForegroundColor Cyan
Write-Host '  2. Run .\run.ps1' -ForegroundColor Cyan
Write-Host '  3. Use Python 3.11 or 3.12 plus requirements-ml.txt later for faster-whisper inference.' -ForegroundColor Cyan