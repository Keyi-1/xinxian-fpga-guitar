param([string]$RunName='p5_bridge_rtl_01')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^p5_[a-zA-Z0-9_]+$'){throw 'P5 run name required'}
$repo=Split-Path $PSScriptRoot
$run=Join-Path $repo "build/p5_bluetooth/$RunName"
if(Test-Path -LiteralPath $run){throw 'Existing evidence preserved; choose new RunName'}
$py='E:\anaconda3\python.exe';$ms='S:\BaiduNetdiskDownload\modelsim\win64'
& $py (Join-Path $repo 'tools/p5_rtl_vectors.py') generate $run
if($LASTEXITCODE){throw 'Vector generation failed'}
$files=@(Get-ChildItem (Join-Path $repo 'rtl/game') -Filter 'game_p3_*.v')
$files+=Get-Item (Join-Path $repo 'rtl/game/game_p2_score_bank.v')
$files+=Get-Item (Join-Path $repo 'rtl/game/game_p2_catalog.v')
$files+=Get-Item (Join-Path $repo 'sim/tb/tb_p5_bridge_replay.sv')
$bound=@($files)+@(Get-ChildItem (Join-Path $repo 'rtl/config') -Filter '*.vh')
$bound+=Get-Item (Join-Path $repo 'sim/tb/game_p3_uart_host.vh')
$bound+=Get-Item (Join-Path $repo 'tools/p5_rtl_vectors.py')
$bound+=Get-Item (Join-Path $repo 'tools/run_p5_rtl.ps1')
$hashes=@{};foreach($file in $bound){$hashes[$file.FullName.Substring($repo.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()}
$record=[ordered]@{status='RUNNING';pid=$PID;started=(Get-Date).ToString('o');commit=(& git -C $repo rev-parse HEAD);sources=$hashes;scope='New C transport trace replay through unchanged RTL, accelerated UART; no new synthesis/netlist/radio'}
$record | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $run 'process.json') -Encoding utf8
Push-Location $run
try {
    & "$ms/vlib.exe" work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'vlib failed'}
    $includeGame=(Join-Path $repo 'rtl/game').Replace('\','/')
    $includeTB=(Join-Path $repo 'sim/tb').Replace('\','/')
    & "$ms/vlog.exe" -sv "+incdir+$includeGame" "+incdir+$includeTB" 'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v' @($files.FullName) > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Warning|Error|Fatal):'){throw 'Compile diagnostics'}
    & "$ms/vsim.exe" -c -onfinish stop work.tb_p5_bridge_replay "+vectors=$($run.Replace('\','/'))" -l replay.log -do 'run -all; quit -code 0 -f' > replay.console.log 2>&1
    $log=Get-Content -Raw replay.log
    if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Warning|Error|Fatal):'){throw 'RTL replay failed'}
    & $py (Join-Path $repo 'tools/p5_rtl_vectors.py') check $run > return_check.log 2>&1
    if($LASTEXITCODE){throw 'Actual response C return check failed'}
    foreach($path in $hashes.Keys){if((Get-FileHash (Join-Path $repo $path)).Hash.ToLower() -ne $hashes[$path]){throw "Source changed: $path"}}
    $record.status='PASS';$record['logs']=@{};foreach($p in @('replay.log','return_check.log','requests.hex','responses.hex','expected.hex','allowed.hex','compile.log')){$record.logs[$p]=(Get-FileHash $p).Hash.ToLower()}
    $log -split "`n" | Where-Object {$_ -match 'PASS:'};Get-Content return_check.log
}catch{$record.status='FAIL';$record['error']=$_.Exception.Message;throw}
finally{$record['finished']=(Get-Date).ToString('o');$record | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8;Pop-Location}
