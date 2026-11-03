param([Parameter(Mandatory=$true)][string]$RunDir,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$RunDir=[IO.Path]::GetFullPath($RunDir)
$allowed=[IO.Path]::GetFullPath((Join-Path $repoDir 'sim/temp'))+[IO.Path]::DirectorySeparatorChar
if(!$RunDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be under sim/temp'}
if(Test-Path -LiteralPath $RunDir){throw 'Choose fresh evidence directory'}
New-Item -ItemType Directory -Path $RunDir | Out-Null
$files=@('rtl/game/game_p2_window_controller.v','sim/reference/game_p2/game_p2_window_controller_a4.v',
    'sim/reference/game_p2/game_p2_window_controller_a4.json','rtl/config/game_p2_phase.vh',
    'sim/tb/tb_game_p2_window_equivalence.sv','tools/run_game_p2_window_equivalence.ps1')
$hashes=@{}
foreach($path in $files){
    $file=Join-Path $repoDir $path
    $hashes[$path]=(Get-FileHash $file).Hash.ToLower()
    $body=(Get-Content -Raw $file).Replace('`include "../config/','`include "')
    Set-Content (Join-Path $RunDir (Split-Path $file -Leaf)) $body -Encoding UTF8
}
Push-Location $RunDir
try{
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'vlib failed'}
    & (Join-Path $ModelSimBin 'vlog.exe') -sv +incdir+. game_p2_window_controller.v game_p2_window_controller_a4.v tb_game_p2_window_equivalence.sv > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Compile diagnostics'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_game_p2_window_equivalence -l equivalence.log -do 'run -all; quit -code 0 -f' > console.log 2>&1
    $code=$LASTEXITCODE;$body=Get-Content -Raw equivalence.log
    if($code -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw 'Equivalence failed'}
    [ordered]@{result='PASS';source_sha256=$hashes;reference_commit='a6009a3596d812402c06e7a2fadf8c6b881faae5';
        compile_log_sha256=(Get-FileHash compile.log).Hash.ToLower();log_sha256=(Get-FileHash equivalence.log).Hash.ToLower();
        scope='Every controller public output every clock; bounded time storage and one-hot commit mask only';
        finished=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content verification.json -Encoding UTF8
    $body -split "`n" | Where-Object {$_ -match 'PASS:|FAIL:'}
}finally{Pop-Location}
