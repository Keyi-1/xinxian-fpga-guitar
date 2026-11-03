param([ValidateSet('Synthesis','Route')][string]$Stage='Synthesis',[string]$RunName='v1')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[A-Za-z0-9_-]+$'){throw 'Simple run name required'}
$root=Split-Path -Parent $PSScriptRoot
if(@(Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue).Count){throw 'Inspect active Gowin jobs first'}
$run=Join-Path $root ('build/imu_id70/'+$RunName)
$project=Join-Path $root 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
if($Stage -eq 'Synthesis'){
 if(Test-Path -LiteralPath $run){throw 'Preserve prior build evidence'}
 New-Item -ItemType Directory -Path $run | Out-Null
 $before=Get-Content -Raw (Join-Path $root 'build/imu_id70/before_20261023/snapshot.json') | ConvertFrom-Json
 $hashes=[ordered]@{}
 foreach($p in $before.hashes.PSObject.Properties){
  if($p.Name -notmatch '^(rtl/|mem/|constraints/neo_guitar_touch_game\.|gowin/neo_guitar_touch_game/neo_guitar_touch_game\.gprj$)'){continue}
  $full=Join-Path $root $p.Name;$hashes[$p.Name]=(Get-FileHash -LiteralPath $full).Hash.ToLower()
  $dest=Join-Path $run ('source_archive/'+$p.Name);New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
  Copy-Item -LiteralPath $full -Destination $dest
 }
 $hashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'source_manifest.json') -Encoding utf8
 $protected=[ordered]@{}
 foreach($p in @('gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json','docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md')){
  $protected[$p]=@{sha256=(Get-FileHash -LiteralPath (Join-Path $root $p)).Hash.ToLower();index=(git -C $root ls-files --stage -- $p)}
 }
 $protected | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'protected_user_files.json') -Encoding utf8
 Copy-Item -LiteralPath (Join-Path $root 'gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json') -Destination (Join-Path $run 'protected_process_config.snapshot.json')
 $prefix='build';$command='run syn';$marker='SYNTHESIS_TCL_FINISHED'
}else{
 if(Test-Path -LiteralPath (Join-Path $run 'route_process.json')){throw 'Inspect the previous route attempt first'}
 $review=Get-Content -Raw (Join-Path $run 'synthesis_review.json') | ConvertFrom-Json
 $vg=Join-Path $root 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
 if($review.result -ne 'PASS' -or (Get-FileHash -LiteralPath $vg).Hash.ToLower() -ne $review.netlist_sha256){throw 'Current reviewed synthesis required'}
 $manifest=Get-Content -Raw (Join-Path $run 'source_manifest.json') | ConvertFrom-Json
 foreach($p in $manifest.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $root $p.Name)).Hash.ToLower() -ne $p.Value){throw ('Source changed: '+$p.Name)}}
 $prefix='route';$command='run pnr';$marker='PNR_TCL_FINISHED'
}
$protected=Get-Content -Raw (Join-Path $run 'protected_user_files.json') | ConvertFrom-Json
foreach($p in $protected.PSObject.Properties){
 if((Get-FileHash -LiteralPath (Join-Path $root $p.Name)).Hash.ToLower() -ne $p.Value.sha256){throw 'Protected bytes changed'}
 if((git -C $root ls-files --stage -- $p.Name) -ne $p.Value.index){throw 'Protected index changed'}
}
$tcl=Join-Path $run ($prefix+'.tcl')
@"
open_project {$($project.Replace('\','/'))}
if {[catch {$command} message]} {puts stderr `$message;puts BUILD_TCL_FAILED;exit 1}
puts $marker
flush stdout
exit
"@ | Set-Content -LiteralPath $tcl -Encoding ascii
$stdout=Join-Path $run ($prefix+'.stdout.log');$stderr=Join-Path $run ($prefix+'.stderr.log')
$proc=Start-Process -FilePath 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' -ArgumentList @($tcl) -WorkingDirectory (Split-Path -Parent $project) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$record=[ordered]@{status='RUNNING';stage=$Stage;pid=$proc.Id;started=$proc.StartTime.ToString('o');source_commit=(git -C $root rev-parse HEAD);scope='Original guitar gprj/impl; only MPU reader runtime change, no configuration writes';project=$project;log=$stdout}
$receipt=if($Stage -eq 'Synthesis'){'process.json'}else{'route_process.json'}
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run $receipt) -Encoding utf8
Write-Output ("Original guitar $Stage PID="+$proc.Id+'; logs '+$run)
$proc.WaitForExit()
$record.status='EXITED';$record['exit_code']=$proc.ExitCode;$record['finished']=[DateTime]::UtcNow.ToString('o')
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run $receipt) -Encoding utf8
exit $proc.ExitCode
