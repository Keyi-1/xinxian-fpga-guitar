param([string]$ModelSimBin = '')
$ErrorActionPreference = 'Stop'
if (!$ModelSimBin) {
    $ModelSimBin = Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source
}
$projectDir = $PSScriptRoot
$srcDir = Join-Path $projectDir 'src'
$repoDir = Split-Path (Split-Path $projectDir)
$simDir = Join-Path $projectDir 'temp\modelsim'
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $srcDir 'note_phase_inc.mem') -Destination $simDir
Copy-Item -LiteralPath (Join-Path $srcDir 'sine_lut.mem') -Destination $simDir
Push-Location $simDir
try {
    & (Join-Path $ModelSimBin 'vlib.exe') work
    if ($LASTEXITCODE) { throw 'vlib failed' }
    $sources = Get-ChildItem -LiteralPath $srcDir -Filter '*.v' | ForEach-Object FullName
    $benches = @('tb_neo_full_chain_audio_test','tb_neo_guitar_link_control','tb_neo_full_chain_default_timing')
    $testFiles = $benches | ForEach-Object { Join-Path $repoDir "sim\tb\$_.sv" }
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$srcDir" @sources @testFiles
    if ($LASTEXITCODE) { throw 'vlog failed' }
    foreach ($bench in $benches) {
        $logFile = Join-Path $simDir "$bench.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l $logFile -do 'run -all; quit -code 0 -f'
        if ($LASTEXITCODE) { throw "$bench failed" }
        $log = Get-Content -Raw -LiteralPath $logFile
        if ($log -match 'FAIL:|\*\* (Error|Fatal|Warning):' -or $log -notmatch 'PASS:') {
            throw "$bench did not finish cleanly; inspect $logFile"
        }
    }
}
finally { Pop-Location }
