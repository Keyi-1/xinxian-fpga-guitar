param([string]$RunName='synth_v1')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple name required'}
if(@(Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue).Count){throw 'Inspect active Gowin jobs first'}
$runDir=Join-Path $repoDir "build/velocity_calibration/$RunName"
if(Test-Path (Join-Path $runDir 'route_process.json')){throw 'Existing routing attempt must be inspected, never overwritten'}
$review=Get-Content (Join-Path $runDir 'synthesis_review.json') -Raw | ConvertFrom-Json
$vg=Join-Path $repoDir 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
if($review.result -ne 'PASS' -or (Get-FileHash $vg).Hash.ToLower() -ne $review.netlist_sha256){throw 'Current reviewed VG required'}
$manifest=Get-Content (Join-Path $runDir 'source_manifest.json') -Raw | ConvertFrom-Json
foreach($p in $manifest.PSObject.Properties){if((Get-FileHash (Join-Path $repoDir $p.Name)).Hash.ToLower() -ne $p.Value){throw "Source drift: $($p.Name)"}}
$protected=Get-Content (Join-Path $runDir 'protected_user_files.json') -Raw | ConvertFrom-Json
foreach($p in $protected.PSObject.Properties){
 if((Get-FileHash (Join-Path $repoDir $p.Name)).Hash.ToLower() -ne $p.Value.sha256){throw 'Protected bytes changed'}
 if((& git -C $repoDir ls-files --stage -- $p.Name) -ne $p.Value.index){throw 'Protected index changed'}
}
$project=Join-Path $repoDir 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
$tcl=@"
open_project $($project.Replace('\','/'))
if {[catch {run pnr} message]} {puts stderr `$message;puts PNR_TCL_FAILED;exit 1}
puts PNR_TCL_FINISHED
flush stdout
exit
"@
$script=Join-Path $runDir 'route.tcl'
[IO.File]::WriteAllText($script,$tcl,[Text.UTF8Encoding]::new($false))
$proc=Start-Process -FilePath 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' -ArgumentList $script -WorkingDirectory (Split-Path $project) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runDir 'route.stdout.log') -RedirectStandardError (Join-Path $runDir 'route.stderr.log') -PassThru
[ordered]@{status='PNR_RUNNING';pid=$proc.Id;started=(Get-Date).ToString('o');source_commit=$review.source_commit;netlist_sha256=$review.netlist_sha256;scope='Continue reviewed synthesis in same original gprj/impl; no set_option or configuration edits';log=(Join-Path $runDir 'route.stdout.log')} | ConvertTo-Json | Set-Content (Join-Path $runDir 'route_process.json') -Encoding utf8
Write-Output "Original-project P&R PID=$($proc.Id); log=$runDir/route.stdout.log"
