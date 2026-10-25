param([Parameter(Mandatory=$true)][string]$RunName,
      [string[]]$Benches=@('tb_performance_vibrato_gesture','tb_vibrato_serial'),
      [switch]$Integration,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[A-Za-z0-9_-]+$'){throw 'Simple evidence name required'}
$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root "sim/temp/$RunName"
if(Test-Path -LiteralPath $run){throw 'Preserve existing evidence; inspect before resuming'}
$sources=Join-Path $run 'sources';New-Item -ItemType Directory -Path $sources | Out-Null
if($Integration){
 $relative=@(Get-ChildItem (Join-Path $root 'rtl') -Recurse -File | Where-Object {$_.Extension -in '.v','.vh'} | ForEach-Object {$_.FullName.Substring($root.Length+1)})
 $relative+=@(Get-ChildItem (Join-Path $root 'sim/reference/vibrato') -Filter '*.v' | ForEach-Object {$_.FullName.Substring($root.Length+1)})
 $relative+=@(Get-ChildItem (Join-Path $root 'sim/reference/posture') -Filter '*.v' | ForEach-Object {$_.FullName.Substring($root.Length+1)})
}else{
 $relative=@('rtl/config/guitar_config.vh','rtl/control/performance_vibrato_gesture.v',
  'rtl/control/four_string_vibrato_serial.v','rtl/control/guitar_play_control.v','rtl/control/note_phase_table.v')
}
$relative+=@('sim/models/mpu6050_test_slave.sv','sim/models/mcp3208_test_slave.sv','tools/run_vibrato_checks.ps1')
$relative+=@($Benches | ForEach-Object {"sim/tb/$_.sv"})
$hashes=[ordered]@{}
foreach($f in Get-ChildItem (Join-Path $root 'mem') -File){$hashes[$f.FullName.Substring($root.Length+1)]=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLower()}
foreach($rel in $relative){
 $full=Join-Path $root $rel;$hashes[$rel]=(Get-FileHash -LiteralPath $full).Hash.ToLower()
 $body=(Get-Content -LiteralPath $full -Raw -Encoding UTF8).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$root.Replace('\','/')+'/mem/'))
 [IO.File]::WriteAllText((Join-Path $sources (Split-Path $rel -Leaf)),$body,[Text.UTF8Encoding]::new($false))
}
$record=[ordered]@{status='RUNNING';pid=$PID;started=(Get-Date).ToString('o');source_commit=(git -C $root rev-parse HEAD);source_sha256=$hashes;benches=$Benches;scope='Vibrato components or explicitly scoped production RTL integration; no gate/P&R/hardware acceptance'}
$record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'run.json') -Encoding utf8
Push-Location $run
try{
 & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
 if($LASTEXITCODE){throw 'vlib failed'}
 $files=@(Get-ChildItem -LiteralPath $sources -File | Where-Object {$_.Extension -in '.v','.sv'} | ForEach-Object FullName)
 $vendor=@();if($Integration){$vendor=@('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sources" @vendor @files > compile.log 2>&1
 if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Compile diagnostics; inspect compile.log'}
 $logs=[ordered]@{}
 foreach($bench in $Benches){
  & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
  $log=Get-Content -Raw "$bench.log"
  if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed"}
  $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
  $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
 }
 foreach($rel in $hashes.Keys){if((Get-FileHash -LiteralPath (Join-Path $root $rel)).Hash.ToLower() -ne $hashes[$rel]){throw "Source changed: $rel"}}
 $record.status='PASS';$record['log_sha256']=$logs
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{
 $record['finished']=(Get-Date).ToString('o');$record | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8
 Pop-Location
}
