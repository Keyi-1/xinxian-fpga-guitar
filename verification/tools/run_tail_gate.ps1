param([string]$RunName='tail_lock_audio_gate_01',[string]$ImplementationRun='tail_lock_v1',
 [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[A-Za-z0-9_-]+$' -or $ImplementationRun -notmatch '^[A-Za-z0-9_-]+$'){throw 'Simple run names required'}
$root=Split-Path -Parent $PSScriptRoot;$run=Join-Path $root "sim/temp/$RunName"
if(Test-Path -LiteralPath $run){throw 'Preserve prior evidence'}
$src=Join-Path $run 'sources';New-Item -ItemType Directory -Path $src | Out-Null
$rtl=@(Get-ChildItem (Join-Path $root 'rtl') -Recurse -Filter '*.v')
$names=foreach($f in $rtl){foreach($m in [regex]::Matches((Get-Content -Raw -Encoding UTF8 $f.FullName),'\bmodule\s+(\w+)')){$m.Groups[1].Value}}
$pattern='"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/|\b('+ (($names|ForEach-Object {[regex]::Escape($_)}) -join '|') +')\b'
$hashes=@{}
$files=@($rtl)+@(Get-ChildItem (Join-Path $root 'rtl/config') -Filter '*.vh')+@(Get-ChildItem (Join-Path $root 'sim/reference/tail_lock') -Filter '*.v')
$files+=Get-Item (Join-Path $root 'sim/tb/tb_tail_lock_audio.sv')
foreach($f in $files){
 $body=[regex]::Replace((Get-Content -Raw -Encoding UTF8 $f.FullName),$pattern,{param($m)if($m.Groups[1].Success){'rtlref_'+$m.Value}else{$m.Value}})
 $body=$body.Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$root.Replace('\','/')+'/mem/'))
 [IO.File]::WriteAllText((Join-Path $src $f.Name),$body,[Text.UTF8Encoding]::new($false))
 $hashes[$f.FullName.Substring($root.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()
}
foreach($f in Get-ChildItem (Join-Path $root 'mem') -File){$hashes[$f.FullName.Substring($root.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()}
foreach($p in 'tools/run_tail_gate.ps1','tools/prepare_tail_gate.py','tools/compare_synth_graph.py'){$hashes[$p]=(Get-FileHash (Join-Path $root $p)).Hash.ToLower()}
$vg=Join-Path $root 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
$review=Get-Content -Raw (Join-Path $root "build/vibrato/$ImplementationRun/synthesis_review.json") | ConvertFrom-Json
if($review.result -ne 'PASS' -or (Get-FileHash $vg).Hash.ToLower() -ne $review.netlist_sha256){throw 'Fresh reviewed netlist required'}
Copy-Item -LiteralPath $vg -Destination (Join-Path $run 'compiled.vg')
$record=[ordered]@{status='RUNNING';pid=$PID;bench='tb_tail_lock_audio';started=(Get-Date).ToString('o');source_sha256=$hashes;netlist_sha256=$review.netlist_sha256;scope='Actual original-project production audio-child gate vs RTL and independent frozen-chain pitch oracle; physical columns, production timing, registered ADC-event boundary only'}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run 'run.json') -Encoding utf8
Push-Location $run
try{
 & E:\anaconda3\python.exe -X utf8 (Join-Path $root 'tools/prepare_tail_gate.py') compiled.vg $run > mapping.log 2>&1
 if($LASTEXITCODE){throw 'Review actual audio-child map'}
 & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
 if($LASTEXITCODE){throw 'vlib failed'}
 $sources=@(Get-ChildItem $src -File | Where-Object {$_.Extension -in '.v','.sv'} | ForEach-Object FullName)
 & (Join-Path $ModelSimBin 'vlog.exe') -sv +define+TAIL_GATE "+incdir+$src" 'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v' compiled.vg tail_gate_audio.sv @sources > compile.log 2>&1
 if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Gate compile diagnostics'}
 & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_tail_lock_audio -l tb_tail_lock_audio.log -do 'run -all; quit -code 0 -f' > console.log 2>&1
 $body=Get-Content -Raw tb_tail_lock_audio.log
 $warnings=@($body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'})
 if($LASTEXITCODE -or $warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw 'Actual audio-child gate failed'}
 foreach($p in $hashes.Keys){if((Get-FileHash (Join-Path $root $p)).Hash.ToLower() -ne $hashes[$p]){throw "Source changed: $p"}}
 $record.status='PASS';$record['log_sha256']=(Get-FileHash tb_tail_lock_audio.log).Hash.ToLower();$record['mapping_sha256']=(Get-FileHash mapping.json).Hash.ToLower()
 $body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{$record['finished']=(Get-Date).ToString('o');$record | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8;Pop-Location}
