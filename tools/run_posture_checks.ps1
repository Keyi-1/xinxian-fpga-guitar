param([Parameter(Mandatory=$true)][string]$RunName,
      [string[]]$Benches=@('tb_mpu6050_reader','tb_imu_posture_classifier','tb_imu_calibration_full','tb_posture_timbre_policy','tb_posture_timbre_cdc','tb_i2c_fault_recovery','tb_gt911_touch'),
      [switch]$Integration,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple evidence name required'}
$repoDir=Split-Path $PSScriptRoot
$runDir=Join-Path $repoDir "sim/temp/$RunName"
if(Test-Path -LiteralPath $runDir){throw 'Preserve existing evidence; choose a new run name'}
$sourceDir=Join-Path $runDir 'sources'
New-Item -ItemType Directory -Path $sourceDir | Out-Null
$relative=@('rtl/input/i2c_register_master.v','rtl/input/gt911_touch.v','rtl/input/mpu6050_reader.v',
 'rtl/input/imu_serial_multiplier.v','rtl/input/imu_posture_classifier.v','rtl/control/posture_timbre_policy.v',
 'rtl/game/mode_command_cdc.v','rtl/game/posture_timbre_cdc.v')
if($Integration){
 $relative=@(Get-ChildItem (Join-Path $repoDir 'rtl') -Recurse -File | Where-Object {$_.Extension -in '.v','.vh'} | ForEach-Object {$_.FullName.Substring($repoDir.Length+1)})
 $relative+=@(Get-ChildItem (Join-Path $repoDir 'sim/reference/posture') -Filter '*.v' | ForEach-Object {$_.FullName.Substring($repoDir.Length+1)})
}
$relative+='sim/models/mpu6050_test_slave.sv'
$relative+=@($Benches | ForEach-Object {"sim/tb/$_.sv"})
$hashes=@{}
foreach($path in $relative){
 $full=Join-Path $repoDir $path
 $hashes[$path]=(Get-FileHash -LiteralPath $full).Hash.ToLower()
 $body=(Get-Content -Raw -LiteralPath $full).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
 [IO.File]::WriteAllText((Join-Path $sourceDir (Split-Path $path -Leaf)),$body,[Text.UTF8Encoding]::new($false))
}
$record=[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_commit=(& git -C $repoDir rev-parse HEAD);source_sha256=$hashes;benches=$Benches;scope=$(if($Integration){'P4 production RTL integration and frozen renderer comparison, explicit test stimuli/accelerations in each bench; not P&R or hardware acceptance'}else{'P4 component pin-level driver/classifier/policy/CDC simulation; not production integration, P&R or hardware acceptance'})}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'run.json') -Encoding UTF8
Push-Location $runDir
try{
 & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
 if($LASTEXITCODE){throw 'vlib failed'}
 $sources=@(Get-ChildItem $sourceDir -File | Where-Object {$_.Extension -in '.v','.sv'} | ForEach-Object FullName)
 $vendor=@();if($Integration){$vendor=@('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @vendor @sources > compile.log 2>&1
 if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Compile diagnostics; see compile.log'}
 $logs=@{}
 foreach($bench in $Benches){
  & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
  $log=Get-Content -Raw "$bench.log"
  if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed; see $runDir"}
  $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
  $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
 }
 foreach($path in $hashes.Keys){if((Get-FileHash (Join-Path $repoDir $path)).Hash.ToLower() -ne $hashes[$path]){throw "Source changed: $path"}}
 $record.status='PASS';$record['log_sha256']=$logs
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{
 $record['finished']=(Get-Date).ToString('o')
 $record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'verification.json') -Encoding UTF8
 Pop-Location
}
