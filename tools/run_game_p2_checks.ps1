param([Parameter(Mandatory=$true)][string]$RunDir,
      [string[]]$Benches=@('tb_game_p2_window','tb_game_p2_legacy_equivalence','tb_game_p2_static_bank','tb_game_p2_judgement'),
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$PythonExe='E:\anaconda3\python.exe')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$RunDir=[IO.Path]::GetFullPath($RunDir)
$allowed=[IO.Path]::GetFullPath((Join-Path $repoDir 'sim/temp'))+[IO.Path]::DirectorySeparatorChar
if(!$RunDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Simulation output must be under sim/temp'}
if(Test-Path -LiteralPath $RunDir){throw 'Choose a new simulation directory; existing logs are preserved'}
$sourceDir=Join-Path $RunDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$paths=@('rtl/game/game_p2_catalog.v','rtl/game/game_p2_score_bank.v',
    'rtl/game/game_p2_window_controller.v','rtl/game/game_p2_static_engine.v',
    'sim/reference/game_p2/game_note_controller_p1.v','sim/reference/game_p2/game_score_rom_p1.v')
$paths+=@(Get-ChildItem (Join-Path $repoDir 'rtl/config') -Filter '*.vh' | ForEach-Object {$_.FullName.Substring($repoDir.Length+1)})
$hashes=@{}
foreach($path in $paths){
    $file=Join-Path $repoDir $path
    $body=(Get-Content -Raw -LiteralPath $file).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    Set-Content -LiteralPath (Join-Path $sourceDir (Split-Path $file -Leaf)) -Value $body -Encoding UTF8
    $hashes[$path]=(Get-FileHash -LiteralPath $file).Hash.ToLower()
}
foreach($path in @('mem/game_p2_static.mem','mem/jasmine_game.mem','scores/p2/catalog.json',
                  'tools/game_score_v2.py','tools/generate_p2_static_scores.py','tools/compile_p2_score.py',
                  'tools/test_game_score_v2.py','tools/run_game_p2_checks.ps1')){
    $hashes[$path]=(Get-FileHash (Join-Path $repoDir $path)).Hash.ToLower()
}
$tests=@(foreach($bench in $Benches){
    $test=Join-Path $repoDir "sim/tb/$bench.sv"
    $hashes[$test.Substring($repoDir.Length+1)]=(Get-FileHash $test).Hash.ToLower()
    $body=(Get-Content -Raw -LiteralPath $test).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    $copy=Join-Path $RunDir "$bench.sv"
    Set-Content -LiteralPath $copy -Value $body -Encoding UTF8
    $copy
})
[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');baseline_commit='704fc14';
    scope='P2 core prototype RTL and event-data checks; no production top integration or P&R';
    source_sha256=$hashes;benches=$Benches} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'run.json') -Encoding UTF8
Push-Location $RunDir
try{
    & $PythonExe (Join-Path $repoDir 'tools/generate_p2_static_scores.py') --check > generated.log 2>&1
    if($LASTEXITCODE){throw 'P2 generated score drift'}
    & $PythonExe (Join-Path $repoDir 'tools/test_game_score_v2.py') > python.log 2>&1
    if($LASTEXITCODE){throw 'P2 score compiler checks failed'}
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'Cannot create simulator library'}
    $sources=@(Get-ChildItem $sourceDir -Filter '*.v' | ForEach-Object FullName)
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @sources @tests > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'P2 compile diagnostics'}
    $logs=@{}
    foreach($bench in $Benches){
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $exit=$LASTEXITCODE;$log=Get-Content -Raw "$bench.log"
        $log -split "`n" | Where-Object {$_ -match 'PASS:|FAIL:'} | Write-Output
        if($exit -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed"}
        $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
    }
    $record=Get-Content -Raw run.json | ConvertFrom-Json
    $record.status='PASS';$record | Add-Member log_sha256 $logs
    $record | Add-Member python_log_sha256 (Get-FileHash python.log).Hash.ToLower()
    $record | Add-Member compile_log_sha256 (Get-FileHash compile.log).Hash.ToLower()
    $record | Add-Member finished (Get-Date).ToString('o')
    $record | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding UTF8
}catch{
    $record=Get-Content -Raw run.json | ConvertFrom-Json
    $record.status='FAIL';$record | Add-Member failure $_.Exception.Message
    $record | ConvertTo-Json -Depth 6 | Set-Content failed.json -Encoding UTF8
    throw
}finally{Pop-Location}
