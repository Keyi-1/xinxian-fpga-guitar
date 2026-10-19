param([Parameter(Mandatory=$true)][string]$RunName)
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple run name required'}
$repoDir=Split-Path $PSScriptRoot
$active=@(Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue)
if($active.Count){throw ('Inspect existing Gowin processes first: '+($active.Id -join ','))}
$runDir=Join-Path $repoDir "build/velocity_calibration/$RunName"
if(Test-Path -LiteralPath $runDir){throw 'Do not overwrite prior build evidence'}
$archive=Join-Path $repoDir 'build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs'
if((Get-FileHash -LiteralPath $archive).Hash.ToLower() -ne 'e97afee45346aad123a1ec525a2ddc0b344348898348eaf518fd7d9d7b0c4213'){throw 'Saved P4 archive missing or changed'}
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
Copy-Item -LiteralPath (Join-Path $repoDir 'gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json') -Destination (Join-Path $runDir 'protected_process_config.snapshot.json')
$project=Join-Path $repoDir 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
$tcl=@"
open_project $($project.Replace('\','/'))
if {[catch {run syn} message]} {puts stderr `$message;puts SYNTHESIS_TCL_FAILED;exit 1}
puts SYNTHESIS_TCL_FINISHED
flush stdout
exit
"@
$script=Join-Path $runDir 'build.tcl'
[IO.File]::WriteAllText($script,$tcl,[Text.UTF8Encoding]::new($false))
$proc=Start-Process -FilePath 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' -ArgumentList $script -WorkingDirectory (Split-Path $project) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runDir 'build.stdout.log') -RedirectStandardError (Join-Path $runDir 'build.stderr.log') -PassThru
[ordered]@{status='running';pid=$proc.Id;started=(Get-Date).ToString('o');source_commit=(& git -C $repoDir rev-parse HEAD);scope='Original gprj and original impl; evidence folder is not a build checkout';project=$project;log=(Join-Path $runDir 'build.stdout.log')} | ConvertTo-Json | Set-Content (Join-Path $runDir 'process.json') -Encoding utf8
Write-Output "Original-project synthesis PID=$($proc.Id); log=$runDir/build.stdout.log; synthesis-only as requested; existing P4 P&R/FS left in place."
