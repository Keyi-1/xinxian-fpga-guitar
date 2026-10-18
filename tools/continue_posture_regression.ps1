param([Parameter(Mandatory=$true)][string]$RunName,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple evidence name required'}
$repoDir=Split-Path $PSScriptRoot;$runDir=Join-Path $repoDir "sim/temp/$RunName"
$original=Get-Content -Raw (Join-Path $runDir 'run.json') | ConvertFrom-Json
$hashes=@{};$repairs=@()
foreach($p in $original.source_sha256.PSObject.Properties){
 $path=Join-Path $repoDir $p.Name;$hash=(Get-FileHash -LiteralPath $path).Hash.ToLower()
 if($hash -ne $p.Value){
  if($p.Name.Replace('\','/') -notmatch '^sim/tb/\w+\.sv$'){throw "Runtime source changed: $($p.Name)"}
  $snapshot=Join-Path $runDir ('sources/'+(Split-Path $p.Name -Leaf))
  $before=(Get-Content -Raw -LiteralPath $snapshot).Replace("`r`n","`n")
  $after=(Get-Content -Raw -LiteralPath $path).Replace("`r`n","`n").Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
  $restored=$after
  foreach($addition in @(".imu_status(10'd0),",'.control_pipeline_idle(),.control_timbre_busy(),','.manual_timbre_press(),')){$restored=$restored.Replace($addition,'')}
  if($restored -ne $before){throw "Only new named port ties may change; assertions/stimulus must match: $($p.Name)"}
  if(Test-Path -LiteralPath "$snapshot.before_imu_ports"){throw 'Preserve previous repair'}
  Copy-Item -LiteralPath $snapshot -Destination "$snapshot.before_imu_ports"
  [IO.File]::WriteAllText($snapshot,$after,[Text.UTF8Encoding]::new($false))
  $repairs+=$snapshot
 }
 $hashes[$p.Name]=$hash
}
if(!$repairs.Count){throw 'No exact interface repair found'}
$record=[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');reason='Only named new observation output/disabled IMU input port ties, exact inverse text audit; no assertion/stimulus changes. Retain clean passed benches.';source_sha256=$hashes;original_run='run.json';recompiled=$repairs}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'resume_imu_ports.json') -Encoding utf8
Push-Location $runDir
try{
 & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$runDir/sources" @repairs > resume_imu_compile.log 2>&1
 if($LASTEXITCODE -or (Get-Content -Raw resume_imu_compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Port repair compile diagnostic'}
 $logs=@{};$reused=@();$continued=@()
 foreach($bench in $original.benches){
  $body=if(Test-Path -LiteralPath "$bench.log"){Get-Content -Raw "$bench.log"}else{''}
  if($body -match 'PASS:' -and $body -notmatch 'FAIL:|\*\* (Error|Fatal|Warning):'){$reused+=$bench}
  else{
   foreach($file in @("$bench.log","$bench.console.log")){
    if(Test-Path -LiteralPath $file){
     if(Test-Path -LiteralPath "$file.before_imu_ports"){throw 'Preserve earlier diagnostics'}
     Move-Item -LiteralPath $file -Destination "$file.before_imu_ports"
    }
   }
   & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
   $body=Get-Content -Raw "$bench.log"
   if($LASTEXITCODE -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed"}
   $continued+=$bench;$body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
  }
  $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
 }
 foreach($p in $hashes.Keys){if((Get-FileHash (Join-Path $repoDir $p)).Hash.ToLower() -ne $hashes[$p]){throw "Source drift: $p"}}
 $record.status='PASS';$record['reused_passed_benches']=$reused;$record['continued_benches']=$continued
 [ordered]@{status='PASS';result='PASS';source_sha256=$hashes;log_sha256=$logs;benches=$original.benches;recovery='resume_imu_ports.json';scope='Current exact runtime hashes, retained clean passes, inverse-audited optional port ties; no relaxed assertions or warning filters'} | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{$record['finished']=(Get-Date).ToString('o');$record | ConvertTo-Json -Depth 6 | Set-Content resume_imu_ports.json -Encoding utf8;Pop-Location}
