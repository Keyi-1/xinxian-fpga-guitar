param([string]$ModelSimBin='')
$ErrorActionPreference='Stop'
if(!$ModelSimBin) { $ModelSimBin=Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source }
$taskVsim=Join-Path $ModelSimBin 'vsim.exe'
$taskProject=$PSScriptRoot.Replace('\','/')
$taskDo=Join-Path $PSScriptRoot 'run_sim.do'
$taskMacro='do {'+$taskDo.Replace('\','/')+'} {'+$taskProject+'}'
Push-Location $PSScriptRoot
try {
    & $taskVsim -c -do $taskMacro *> simulation_console.log
    if($LASTEXITCODE) { throw 'LCD simulation failed; inspect simulation_console.log' }
    $taskLog=Get-Content -Raw -LiteralPath simulation_console.log
    if($taskLog -notmatch 'PASS: LISSAJOUS' -or $taskLog -match 'FAIL:|\*\* (Error|Fatal|Warning):') {
        throw 'LCD verification did not pass; inspect simulation_console.log'
    }
    Write-Output 'PASS: LCD scan, animation, buttons, pause/resume and reset'
} finally { Pop-Location }
