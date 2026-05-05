Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$venvPython = Join-Path '.venv' 'Scripts\python.exe'

if (-not (Test-Path $venvPython)) {
    Write-Host 'Virtual environment not found. Run .\setup.ps1 first.' -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path '.env')) {
    Copy-Item '.env.example' '.env'
    Write-Host 'Created .env from .env.example.' -ForegroundColor Green
}

Write-Host 'Starting CropCare AI backend on http://127.0.0.1:8000 ...' -ForegroundColor Green
& $venvPython -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000