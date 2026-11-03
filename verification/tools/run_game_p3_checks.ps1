param([Parameter(Mandatory=$true)][string]$RunName,
      [string[]]$Benches=@('tb_game_p3_storage'),[switch]$Integration,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple run name required'}
$repoDir=Split-Path $PSScriptRoot
$runDir=Join-Path $repoDir "sim/temp/$RunName"
if(Test-Path -LiteralPath $runDir){throw 'Existing evidence is preserved; choose a new run name'}
$sourceDir=Join-Path $runDir 'sources'
New-Item -ItemType Directory -Path $sourceDir | Out-Null
$files=@(Get-ChildItem (Join-Path $repoDir 'rtl/game') -Filter 'game_p3_*.v')
$files+=Get-Item (Join-Path $repoDir 'rtl/game/game_p2_score_bank.v')
$files+=Get-Item (Join-Path $repoDir 'rtl/game/game_p2_catalog.v')
if($Integration){$files=@(Get-ChildItem (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')}
$files+=Get-ChildItem (Join-Path $repoDir 'rtl/config') -Filter '*.vh'
if(Test-Path (Join-Path $repoDir 'sim/tb/game_p3_uart_host.vh')){$files+=Get-Item (Join-Path $repoDir 'sim/tb/game_p3_uart_host.vh')}
if(Test-Path (Join-Path $repoDir 'sim/tb/piano_mode_ram_checks.vh')){$files+=Get-Item (Join-Path $repoDir 'sim/tb/piano_mode_ram_checks.vh')}
if($Integration){$files+=@(Get-ChildItem (Join-Path $repoDir 'sim/reference/game_p3') -File)}
$files+=@(foreach($bench in $Benches){Get-Item (Join-Path $repoDir "sim/tb/$bench.sv")})
$hashes=@{}
foreach($file in $files){
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
    $body=(Get-Content -Raw -LiteralPath $file.FullName).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    [IO.File]::WriteAllText((Join-Path $sourceDir $file.Name),$body,[Text.UTF8Encoding]::new($false))
}
$hashes['mem/game_p2_static.mem']=(Get-FileHash (Join-Path $repoDir 'mem/game_p2_static.mem')).Hash.ToLower()
$hashes['mem/game_p3_initial.mem']=(Get-FileHash (Join-Path $repoDir 'mem/game_p3_initial.mem')).Hash.ToLower()
$record=[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_commit=(& git -C $repoDir rev-parse HEAD);source_sha256=$hashes;benches=$Benches;scope='P3 component RTL simulation; not production integration or P&R'}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'run.json') -Encoding UTF8
Push-Location $runDir
try{
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'vlib failed'}
    $sources=@(Get-ChildItem $sourceDir -File | Where-Object {$_.Extension -in '.v','.sv'} | ForEach-Object FullName)
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" 'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v' @sources > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Compile diagnostics; see compile.log'}
    $logs=@{}
    foreach($bench in $Benches){
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $log=Get-Content -Raw "$bench.log"
        if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed; see $runDir"}
        $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
        $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
    }
    foreach($path in $hashes.Keys){if((Get-FileHash (Join-Path $repoDir $path)).Hash.ToLower() -ne $hashes[$path]){throw "Source changed while running: $path"}}
    $record.status='PASS';$record['log_sha256']=$logs
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{
    $record['finished']=(Get-Date).ToString('o')
    $record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'verification.json') -Encoding UTF8
    Pop-Location
}
