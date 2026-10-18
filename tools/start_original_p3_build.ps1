param([Parameter(Mandatory=$true)][string]$RunName)
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple run name required'}
$repoDir=Split-Path $PSScriptRoot
$active=@(Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue)
if($active.Count){throw ('Inspect existing Gowin processes first: '+($active.Id -join ','))}
$runDir=Join-Path $repoDir "build/p3_import/$RunName"
if(Test-Path -LiteralPath $runDir){throw 'Do not overwrite prior build evidence'}
$archive=Join-Path $repoDir 'build/releases/touch_game/neo_guitar_touch_game_qing_ge_melody.fs'
if((Get-FileHash -LiteralPath $archive).Hash.ToLower() -ne 'c0a138912edbf2504f64143049066234c4f10ea381fd974b9c58f6b147bd3bf4'){throw 'Accepted melody archive missing or changed'}
New-Item -ItemType Directory -Path $runDir | Out-Null
$hashes=@{}
$paths=@(Get-ChildItem (Join-Path $repoDir 'rtl') -Recurse -File)+@(Get-ChildItem (Join-Path $repoDir 'mem') -File)
$paths+=@(Get-Item (Join-Path $repoDir 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'))
$paths+=@(Get-Item (Join-Path $repoDir 'constraints/neo_guitar_touch_game.cst'),(Join-Path $repoDir 'constraints/neo_guitar_touch_game.sdc'))
foreach($file in $paths){
    $name=$file.FullName.Substring($repoDir.Length+1);$hashes[$name]=(Get-FileHash $file.FullName).Hash.ToLower()
    $dest=Join-Path $runDir "source_archive/$name";New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest
}
$protected=@{}
foreach($name in @('gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json','docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md')){
    $protected[$name]=@{sha256=(Get-FileHash (Join-Path $repoDir $name)).Hash.ToLower();index=(& git -C $repoDir ls-files --stage -- $name)}
}
$hashes | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $runDir 'source_manifest.json') -Encoding utf8
$protected | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $runDir 'protected_user_files.json') -Encoding utf8
$project=Join-Path $repoDir 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
$route=Join-Path $runDir 'route.ready';$abort=Join-Path $runDir 'abort.ready'
$tcl=@"
open_project $($project.Replace('\','/'))
if {[catch {run syn} message]} {puts stderr `$message;puts SYNTHESIS_TCL_FAILED;exit 1}
puts SYNTHESIS_READY_FOR_REVIEW
flush stdout
while {![file exists $($route.Replace('\','/'))]} {if {[file exists $($abort.Replace('\','/'))]} {puts REVIEW_ABORT;exit 2};after 1000}
if {[catch {run pnr} message]} {puts stderr `$message;puts PNR_TCL_FAILED;flush stdout;exit 1}
puts PNR_TCL_FINISHED
flush stdout
exit
"@
$script=Join-Path $runDir 'build.tcl'
[IO.File]::WriteAllText($script,$tcl,[Text.UTF8Encoding]::new($false))
$proc=Start-Process -FilePath 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' -ArgumentList $script -WorkingDirectory (Split-Path $project) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runDir 'build.stdout.log') -RedirectStandardError (Join-Path $runDir 'build.stderr.log') -PassThru
[ordered]@{status='running';pid=$proc.Id;started=(Get-Date).ToString('o');source_commit=(& git -C $repoDir rev-parse HEAD);scope='Original gprj and original impl; evidence folder is not a build checkout';project=$project;log=(Join-Path $runDir 'build.stdout.log')} | ConvertTo-Json | Set-Content (Join-Path $runDir 'process.json') -Encoding utf8
Write-Output "Original-project synthesis PID=$($proc.Id); log=$runDir/build.stdout.log; P&R awaits explicit synthesis review marker."
