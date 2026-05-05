param(
    [string]$OutputDir = "ml/artifacts/cropcare_v2",
    [string]$LabelProfile = "cropcare_v2_subset_100",
    [Nullable[int]]$MaxPerLabel = $null,
    [int]$DigigreenMaxPerLabel = 1500,
    [int]$MinPerLabel = 80,
    [int]$Epochs = 30,
    [int]$BatchSize = 32,
    [string]$PlantVillageZipPath = "",
    [string]$BaseModelPath = "assets/models/cropcare_efficientnet_with_eggplant.tflite",
    [string]$BaseLabelsPath = "assets/models/labels_with_eggplant.txt",
    [string]$FlutterCommand = "flutter",
    [switch]$BuildAndroid,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$VenvPython = Join-Path $RepoRoot "ml/.venv/Scripts/python.exe"

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [string[]]$Arguments = @()
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path $VenvPython)) {
    Invoke-Native "py" @("-3.11", "-m", "venv", (Join-Path $RepoRoot "ml/.venv"))
}

if (-not $SkipInstall) {
    Invoke-Native $VenvPython @("-m", "pip", "install", "--upgrade", "pip")
    Invoke-Native $VenvPython @("-m", "pip", "install", "-r", (Join-Path $RepoRoot "ml/requirements.txt"))
    Invoke-Native $VenvPython @("-m", "pip", "install", "-e", (Join-Path $RepoRoot "ml"))
}

$env:CUDA_VISIBLE_DEVICES = "-1"
$env:TF_CPP_MIN_LOG_LEVEL = "2"

$ArgsList = @(
    "-m", "cropcare_training.release", "run",
    "--output-dir", $OutputDir,
    "--label-profile", $LabelProfile,
    "--min-per-label", "$MinPerLabel",
    "--epochs", "$Epochs",
    "--batch-size", "$BatchSize",
    "--base-model-path", $BaseModelPath,
    "--base-labels-path", $BaseLabelsPath,
    "--digigreen-max-per-label", "$DigigreenMaxPerLabel",
    "--flutter-command", $FlutterCommand
)

if ($null -ne $MaxPerLabel) {
    $ArgsList += @("--max-per-label", "$MaxPerLabel")
}

if ($PlantVillageZipPath) {
    $ArgsList += @("--plantvillage-zip-path", $PlantVillageZipPath)
}

if ($BuildAndroid) {
    $ArgsList += "--build-android"
}

Invoke-Native $VenvPython $ArgsList
