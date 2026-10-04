param(
    [string]$ModelSimBin = '',
    [string]$GowinHome = 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE'
)
$ErrorActionPreference='Stop'
if(!$ModelSimBin){$ModelSimBin=Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source}
$repoDir=Split-Path $PSScriptRoot
$gateDir=Join-Path $repoDir 'sim\temp\piano_gate'
$refDir=Join-Path $gateDir 'rtl_reference'
New-Item -ItemType Directory -Path $refDir -Force | Out-Null
$rtlFiles=Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v'
$moduleNames=foreach($file in $rtlFiles){
    $body=Get-Content -Raw -LiteralPath $file.FullName
    foreach($m in [regex]::Matches($body,'\bmodule\s+(\w+)')){$m.Groups[1].Value}
}
$pattern='\b('+ (($moduleNames|ForEach-Object {[regex]::Escape($_)}) -join '|') +')\b'
foreach($file in $rtlFiles){
    $body=Get-Content -Raw -LiteralPath $file.FullName
    $body=[regex]::Replace($body,$pattern,{param($m)'rtlref_'+$m.Value})
    $body=$body.Replace('`include "../config/guitar_config.vh"','`include "guitar_config.vh"')
    $body=$body.Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $refDir $file.Name) -Value $body -Encoding UTF8
}
Push-Location $gateDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work}
    $refFiles=Get-ChildItem -LiteralPath $refDir -Filter '*.v'|ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$(Join-Path $repoDir 'rtl\config')" `
        (Join-Path $GowinHome 'simlib\gw5a\prim_sim.v') `
        (Join-Path $repoDir 'gowin\xinxian_mega60k\impl\gwsynthesis\neo_guitar_main.vg') `
        @refFiles (Join-Path $repoDir 'sim\tb\tb_piano_gate_audio.sv') > compile.log 2>&1
    if($LASTEXITCODE){throw 'Gate compilation failed; inspect sim/temp/piano_gate/compile.log'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_piano_gate_audio -l run.log `
        -do 'run -all; quit -code 0 -f' > console.log 2>&1
    $simulationExit=$LASTEXITCODE
    $log=Get-Content -Raw -LiteralPath run.log
    $log -split "`n" | Where-Object {$_ -match 'MISMATCH|FAIL:|PASS:|\*\* (Error|Fatal)\b'} | Write-Output
    if($simulationExit -or $log -match 'FAIL:|\*\* (Error|Fatal)\b' -or $log -notmatch 'PASS:'){
        throw 'Gate audio check failed; inspect sim/temp/piano_gate/run.log'
    }
}finally{Pop-Location}
