param(
    [string]$ModelSimBin = '',
    [string]$GowinHome = 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE'
)
$ErrorActionPreference='Stop'
if(!$ModelSimBin){$ModelSimBin=Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source}
$repoDir=Split-Path (Split-Path $PSScriptRoot)
$gateDir=Join-Path $repoDir 'sim\temp\guitar_radial_gate'
$netlist='gowin\neo_guitar_radial\impl\gwsynthesis\neo_guitar_radial.vg'
$bench='tb_neo_guitar_radial_gate'
$refDir=Join-Path $gateDir 'rtl_reference'
New-Item -ItemType Directory -Path $refDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoDir $netlist) -Destination (Join-Path $gateDir 'compiled.vg')
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
    $body=$body.Replace('`include "../config/piano_bright_coeffs.vh"','`include "piano_bright_coeffs.vh"')
    $body=$body.Replace('`include "../config/rock_coeffs.vh"','`include "rock_coeffs.vh"')
    $body=$body.Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $refDir $file.Name) -Value $body -Encoding UTF8
}
Push-Location $gateDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work}
    $refFiles=Get-ChildItem -LiteralPath $refDir -Filter '*.v'|ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$(Join-Path $repoDir 'rtl\config')" `
        (Join-Path $GowinHome 'simlib\gw5a\prim_sim.v') `
        (Join-Path $gateDir 'compiled.vg') `
        @refFiles (Join-Path $repoDir "sim\tb\$bench.sv") > compile.log 2>&1
    if($LASTEXITCODE){throw 'Gate compilation failed; inspect sim/temp/guitar_radial_gate/compile.log'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l run.log `
        -do 'run -all; quit -code 0 -f' > console.log 2>&1
    $simulationExit=$LASTEXITCODE
    $log=Get-Content -Raw -LiteralPath run.log
    # Ignore only the known unused memory-width branches in DPB/SP/SDPB models;
    # warnings in our netlist/reference/bench still fail the acceptance check.
    $unexpectedWarnings=$log -split "`n" | Where-Object {
        $_ -match '^# \*\* Warning:' -and
        $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'
    }
    $log -split "`n" | Where-Object {$_ -match 'MISMATCH|FAIL:|PASS:|\*\* (Error|Fatal)\b'} | Write-Output
    if($simulationExit -or $unexpectedWarnings.Count -or $log -match 'FAIL:|\*\* (Error|Fatal)\b' -or $log -notmatch 'PASS:'){
        throw 'Gate audio check failed; inspect sim/temp/guitar_radial_gate/run.log'
    }
    @{netlist_sha256=(Get-FileHash -LiteralPath 'compiled.vg' -Algorithm SHA256).Hash.ToLower();
      result='PASS';vendor_unused_width_warnings=$true} | ConvertTo-Json |
        Set-Content -LiteralPath 'verification.json' -Encoding UTF8
}finally{Pop-Location}
