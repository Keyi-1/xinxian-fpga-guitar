param([Parameter(Mandatory=$true)][string]$RunName,
      [string]$Bench='tb_game_p3_full_gate',
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple name required'}
$repoDir=Split-Path $PSScriptRoot;$runDir=Join-Path $repoDir "sim/temp/$RunName"
if(Test-Path $runDir){throw 'Preserve prior evidence'}
$src=Join-Path $runDir 'sources';New-Item -ItemType Directory $src | Out-Null
$rtl=@(Get-ChildItem (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')
$names=foreach($f in $rtl){foreach($m in [regex]::Matches((Get-Content -Raw $f.FullName),'\bmodule\s+(\w+)')){$m.Groups[1].Value}}
$pattern='\b('+ (($names|ForEach-Object {[regex]::Escape($_)}) -join '|') +')\b'
$headers=@(Get-ChildItem (Join-Path $repoDir 'rtl/config') -Filter '*.vh');$hashes=@{}
foreach($f in $rtl){
    $body=[regex]::Replace((Get-Content -Raw $f.FullName),$pattern,{param($m)'rtlref_'+$m.Value})
    foreach($h in $headers){$body=$body.Replace(('rtlref_'+$h.Name),$h.Name)}
    $body=$body.Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    [IO.File]::WriteAllText((Join-Path $src $f.Name),$body,[Text.UTF8Encoding]::new($false))
    $hashes[$f.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()
}
foreach($f in $headers){Copy-Item $f.FullName $src;$hashes[$f.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()}
foreach($f in Get-ChildItem (Join-Path $repoDir 'mem') -File){$hashes[$f.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()}
foreach($path in @("sim/tb/$Bench.sv",'sim/tb/game_p3_uart_host.vh','tools/prepare_game_p3_gate.py','tools/run_game_p3_gate.ps1','tools/compare_synth_graph.py')){
    $file=Join-Path $repoDir $path;$hashes[$path]=(Get-FileHash $file).Hash.ToLower()
    if($path -match '\.(sv|vh)$'){Copy-Item $file $runDir}
}
$vg=Join-Path $repoDir 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
$review=Get-Content -Raw (Join-Path $repoDir 'build/p3_import/impl_c2/synthesis_review.json') | ConvertFrom-Json
if((Get-FileHash $vg).Hash.ToLower() -ne $review.netlist_sha256){throw 'Inspect current netlist before testing'}
Copy-Item $vg (Join-Path $runDir 'compiled.vg')
$record=[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_sha256=$hashes;netlist_sha256=$review.netlist_sha256;scope='Complete actual production VG versus current full RTL; no ROM/phase injection'}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'run.json') -Encoding utf8
Push-Location $runDir
try{
    & E:\anaconda3\python.exe (Join-Path $repoDir 'tools/prepare_game_p3_gate.py') compiled.vg $runDir > mapping.log 2>&1
    if($LASTEXITCODE){throw 'Actual VG map requires review'}
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    $sources=@(Get-ChildItem $src -Filter '*.v' | ForEach-Object FullName)
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$src+$runDir" 'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v' compiled.vg @sources "$Bench.sv" > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Gate compile diagnostics'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$Bench" -l "$Bench.log" -do 'run -all; quit -code 0 -f' > "$Bench.console.log" 2>&1
    $body=Get-Content -Raw "$Bench.log"
    $warnings=@($body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'})
    if($LASTEXITCODE -or $warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw 'Full gate check failed'}
    foreach($p in $hashes.Keys){if((Get-FileHash (Join-Path $repoDir $p)).Hash.ToLower() -ne $hashes[$p]){throw "Source changed: $p"}}
    $record.status='PASS';$record['log_sha256']=(Get-FileHash "$Bench.log").Hash.ToLower()
    $record['mapping_sha256']=(Get-FileHash mapping.json).Hash.ToLower()
    $body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{$record['finished']=(Get-Date).ToString('o');$record | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8;Pop-Location}
