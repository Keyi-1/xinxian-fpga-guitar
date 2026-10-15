param([string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE',
      [string]$PythonExe='E:\anaconda3\python.exe')
$ErrorActionPreference='Stop'
$repoDir=Split-Path (Split-Path $PSScriptRoot)
$gateDir=Join-Path $repoDir 'sim\temp\touch_game_gate'
$sourceDir=Join-Path $gateDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$rtlFiles=Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v'
$moduleNames=foreach($file in $rtlFiles){
    foreach($match in [regex]::Matches((Get-Content -Raw -LiteralPath $file.FullName),'\bmodule\s+(\w+)')){$match.Groups[1].Value}
}
$pattern='\b('+ (($moduleNames|ForEach-Object {[regex]::Escape($_)}) -join '|') +')\b'
$hashes=@{}
foreach($file in $rtlFiles){
    $body=[regex]::Replace((Get-Content -Raw -LiteralPath $file.FullName),$pattern,{param($m)'rtlref_'+$m.Value})
    $body=$body.Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $sourceDir $file.Name) -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl\config') -Filter '*.vh')){
    Copy-Item -LiteralPath $file.FullName -Destination $sourceDir
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'mem') -File)){
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
$netlist=Join-Path $PSScriptRoot 'impl\gwsynthesis\neo_guitar_touch_game.vg'
Copy-Item -LiteralPath $netlist -Destination (Join-Path $gateDir 'compiled.vg')
$chartGenerator=Join-Path $repoDir 'tools\generate_game_chart_gate_bench.py'
$chartBench=Join-Path $gateDir 'tb_game_chart_gate.sv'
$stageForces=Join-Path $gateDir 'stage_force.vh'
& $PythonExe $chartGenerator $netlist $chartBench
if($LASTEXITCODE){throw 'Cannot map synthesized chart ports'}
$hashes['tools\generate_game_chart_gate_bench.py']=(Get-FileHash -LiteralPath $chartGenerator).Hash.ToLower()
$bench=Join-Path $repoDir 'sim\tb\tb_touch_game_gate.sv'
$hashes['sim\tb\tb_touch_game_gate.sv']=(Get-FileHash -LiteralPath $bench).Hash.ToLower()
Push-Location $gateDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null}
    $sources=Get-ChildItem -LiteralPath $sourceDir -Filter '*.v' | ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir+$gateDir" `
        (Join-Path $GowinHome 'simlib\gw5a\prim_sim.v') (Join-Path $gateDir 'compiled.vg') @sources $bench $chartBench > compile.log 2>&1
    if($LASTEXITCODE){throw 'Gate compilation failed'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_touch_game_gate -l run.log `
        -do 'run -all; quit -code 0 -f' > console.log 2>&1
    $log=Get-Content -Raw -LiteralPath run.log
    $unexpectedWarnings=$log -split "`n" | Where-Object {
        $_ -match '^# \*\* Warning:' -and
        $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'
    }
    $log -split "`n" | Where-Object {$_ -match 'PASS:|FAIL:|\*\* (Error|Fatal)'} | Write-Output
    if($LASTEXITCODE -or $unexpectedWarnings.Count -or $log -match 'FAIL:|\*\* (Error|Fatal)' -or $log -notmatch 'PASS:'){
        throw "Gate check failed; inspect $gateDir"
    }
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_game_chart_gate -l chart_run.log `
        -do 'run -all; quit -code 0 -f' > chart_console.log 2>&1
    $chartLog=Get-Content -Raw -LiteralPath chart_run.log
    $chartWarnings=$chartLog -split "`n" | Where-Object {
        $_ -match '^# \*\* Warning:' -and
        $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'
    }
    $chartLog -split "`n" | Where-Object {$_ -match 'PASS:|FAIL:|\*\* (Error|Fatal)'} | Write-Output
    if($LASTEXITCODE -or $chartWarnings.Count -or $chartLog -match 'FAIL:|\*\* (Error|Fatal)' -or $chartLog -notmatch 'PASS:'){
        throw "Synthesized moving chart check failed; inspect $gateDir"
    }
    [ordered]@{result='PASS';scope='Six full-top frames: home/countdown/full-width moving stage/repeated feedback/result; touch and silent audio; full-score successive chart';
        source_sha256=$hashes;netlist_sha256=(Get-FileHash -LiteralPath 'compiled.vg').Hash.ToLower();
        log_sha256=(Get-FileHash -LiteralPath 'run.log').Hash.ToLower();
        chart_log_sha256=(Get-FileHash -LiteralPath 'chart_run.log').Hash.ToLower();
        chart_bench_sha256=(Get-FileHash -LiteralPath $chartBench).Hash.ToLower();
        stage_forces_sha256=(Get-FileHash -LiteralPath $stageForces).Hash.ToLower()} |
        ConvertTo-Json -Depth 5 | Set-Content verification.json -Encoding UTF8
}finally{Pop-Location}
