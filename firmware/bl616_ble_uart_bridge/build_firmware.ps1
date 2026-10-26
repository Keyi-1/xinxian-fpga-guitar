param(
    [string]$SdkRoot = 'E:\BL616\bouffalo_sdk',
    [string]$ToolchainRoot = 'E:\BL616\toolchain_gcc_t-head_windows',
    [string]$PythonExe = 'python',
    [switch]$UseSubst,
    [ValidatePattern('^[A-Z]$')]
    [string]$BuildDrive = 'R'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = $PSScriptRoot
$makeExe = Join-Path $SdkRoot 'tools\make\make.exe'
$cmakeBin = Join-Path $SdkRoot 'tools\cmake\bin'
$toolchainBin = Join-Path $ToolchainRoot 'bin'
$driveName = "${BuildDrive}:"
$driveRoot = "${driveName}\"
$mappedHere = $false

foreach ($required in @(
    $makeExe,
    (Join-Path $cmakeBin 'cmake.exe'),
    (Join-Path $toolchainBin 'riscv64-unknown-elf-gcc.exe')
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required installed tool not found: $required"
    }
}

if ($UseSubst -and (Test-Path -LiteralPath $driveRoot)) {
    throw "$driveName is already in use. Pass another free letter with -BuildDrive."
}

try {
    $buildRoot = $projectRoot
    if ($UseSubst) {
        & subst.exe $driveName $projectRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create temporary $driveName mapping."
        }
        $mappedHere = $true
        $buildRoot = $driveRoot
    }

    $env:BL_SDK_BASE = $SdkRoot.Replace('\', '/')
    $env:PATH = "$toolchainBin;$($SdkRoot)\tools\make;$cmakeBin;$env:PATH"

    Push-Location $buildRoot
    try {
        & $makeExe CHIP=bl616 BOARD=bl616dk "PYTHON=$PythonExe"
        if ($LASTEXITCODE -ne 0) {
            throw "BouffaloSDK build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($mappedHere) {
        & subst.exe $driveName /D | Out-Null
    }
}

$image = Join-Path $projectRoot 'build\build_out\xinxian_ble_uart_bl616.bin'
if (-not (Test-Path -LiteralPath $image)) {
    throw "Build completed without the expected image: $image"
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $image
Write-Host "Built: $image"
Write-Host "SHA256: $($hash.Hash)"
Write-Host 'No flash command was run.'
