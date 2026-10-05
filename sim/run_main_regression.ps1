param(
    [string]$ModelSimBin = '',
    [string[]]$Benches = @(),
    [string]$PythonExe = ''
)
$ErrorActionPreference = 'Stop'
if (!$ModelSimBin) { $ModelSimBin = Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source }
$repoDir = Split-Path $PSScriptRoot
$simDir = Join-Path $PSScriptRoot 'temp'
$refDir = Join-Path $simDir 'verified_reference'
New-Item -ItemType Directory -Path $refDir -Force | Out-Null
$sourceDir = Join-Path $repoDir 'gowin\neo_full_chain_audio_test\src'
$referenceFiles = Get-ChildItem -LiteralPath $sourceDir -Filter '*.v'
$moduleNames = foreach ($file in $referenceFiles) {
    $body = Get-Content -Raw -LiteralPath $file.FullName
    foreach ($match in [regex]::Matches($body, '\bmodule\s+(\w+)')) { $match.Groups[1].Value }
}
$modulePattern = '\b(' + (($moduleNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
foreach ($file in $referenceFiles) {
    $body = Get-Content -Raw -LiteralPath $file.FullName
    $renamed = [regex]::Replace($body, $modulePattern, { param($match) 'ref_' + $match.Value })
    Set-Content -LiteralPath (Join-Path $refDir $file.Name) -Value $renamed -Encoding UTF8
}
Copy-Item -LiteralPath (Join-Path $sourceDir 'guitar_config.vh') -Destination $refDir
Copy-Item -LiteralPath (Join-Path $sourceDir 'note_phase_inc.mem') -Destination $simDir
Copy-Item -LiteralPath (Join-Path $sourceDir 'sine_lut.mem') -Destination $simDir
$excluded = @('tb_neo_full_chain_audio_test','tb_neo_full_chain_default_timing','tb_neo_guitar_link_control','tb_piano_gate_audio','tb_full_piano_gate_audio')
$tbFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tb') -Filter '*.sv' |
    Where-Object { $_.BaseName -notin $excluded }
if (!$Benches.Count) { $Benches = $tbFiles | ForEach-Object BaseName }
if ('tb_piano_voice_core' -in $Benches) {
    if (!$PythonExe) { $PythonExe = (Get-Command python.exe -ErrorAction Stop).Source }
    & $PythonExe (Join-Path $repoDir 'tools\gen_piano_golden.py')
    if ($LASTEXITCODE) { throw 'piano oracle generation failed' }
}
if ('tb_full_piano_voice' -in $Benches) {
    if (!$PythonExe) { $PythonExe = (Get-Command python.exe -ErrorAction Stop).Source }
    & $PythonExe (Join-Path $repoDir 'tools\gen_full_piano_golden.py')
    if ($LASTEXITCODE) { throw 'full piano oracle generation failed' }
}
Push-Location $simDir
try {
    if (!(Test-Path -LiteralPath 'work')) {
        & (Join-Path $ModelSimBin 'vlib.exe') work
        if ($LASTEXITCODE) { throw 'vlib failed' }
    }
    $sources = Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v' | ForEach-Object FullName
    $referenceSources = Get-ChildItem -LiteralPath $refDir -Filter '*.v' | ForEach-Object FullName
    $effectReferences = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'reference\effects_v1') -Filter '*.v' | ForEach-Object FullName
    $testSources = $tbFiles | ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$(Join-Path $repoDir 'rtl\config')" "+incdir+$refDir" @sources @referenceSources @effectReferences @testSources > compile.log 2>&1
    if ($LASTEXITCODE) { throw 'vlog failed; inspect sim/temp/compile.log' }
    $compileLog = Get-Content -Raw compile.log
    if ($compileLog -match '\*\* (Error|Fatal|Warning):') { throw 'compile diagnostics; inspect sim/temp/compile.log' }
    $passed = 0
    $failures = @()
    foreach ($bench in $Benches) {
        $logFile = Join-Path $simDir "$bench.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l $logFile -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $simExitCode = $LASTEXITCODE
        $log = Get-Content -Raw -LiteralPath $logFile
        if ($simExitCode -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):' -or $log -notmatch 'PASS:') {
            $failures += $bench
            Write-Output "FAILED $bench (inspect $logFile)"
            continue
        }
        $passed++
        Write-Output "PASS $bench"
    }
    Write-Output "MAIN REGRESSION PASSED: $passed benches"
    if ($failures.Count) { throw ("Failed benches: " + ($failures -join ', ')) }
}
finally { Pop-Location }
