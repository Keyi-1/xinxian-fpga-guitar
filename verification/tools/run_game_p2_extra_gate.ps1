param([Parameter(Mandatory=$true)][string]$OriginGateDir,
      [Parameter(Mandatory=$true)][string]$RunDir,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE',
      [string]$PythonExe='E:\anaconda3\python.exe')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$RunDir=[IO.Path]::GetFullPath($RunDir);$OriginGateDir=[IO.Path]::GetFullPath($OriginGateDir)
$allowed=[IO.Path]::GetFullPath((Join-Path $repoDir 'sim/temp'))+[IO.Path]::DirectorySeparatorChar
if(!$RunDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or !$OriginGateDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Simulation paths must be under sim/temp'}
if(Test-Path $RunDir){throw 'Choose new evidence directory'}
$origin=Get-Content -Raw (Join-Path $OriginGateDir 'run.json') | ConvertFrom-Json
$hashes=@{}
foreach($p in $origin.source_sha256.PSObject.Properties){
    if((Get-FileHash (Join-Path $repoDir $p.Name)).Hash.ToLower() -ne $p.Value){throw "Origin source changed: $($p.Name)"}
    $hashes[$p.Name]=$p.Value
}
$vg=Join-Path $repoDir 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
if((Get-FileHash $vg).Hash.ToLower() -ne $origin.netlist_sha256){throw 'Production netlist changed'}
New-Item -ItemType Directory $RunDir | Out-Null
Copy-Item (Join-Path $OriginGateDir 'sources') $RunDir -Recurse
Copy-Item (Join-Path $OriginGateDir 'compiled.vg') $RunDir
foreach($f in Get-ChildItem $OriginGateDir -File | Where-Object {$_.Extension -in @('.sv','.vh')}){Copy-Item $f.FullName $RunDir}
foreach($path in @('tools/generate_game_p2_extra_gate.py','tools/run_game_p2_extra_gate.ps1',
    'tools/compare_synth_graph.py','sim/tb/tb_game_p2_actual_bank_gate.sv','sim/tb/tb_game_p2_range_gate.sv')){
    $hashes[$path]=(Get-FileHash (Join-Path $repoDir $path)).Hash.ToLower()
}
[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_sha256=$hashes;
    netlist_sha256=$origin.netlist_sha256;origin_gate=$OriginGateDir} | ConvertTo-Json -Depth 6 |
    Set-Content (Join-Path $RunDir 'run.json') -Encoding utf8
Push-Location $RunDir
try{
    & $PythonExe (Join-Path $repoDir 'tools/generate_game_p2_extra_gate.py') (Join-Path $RunDir 'compiled.vg') $RunDir > mapping.log 2>&1
    if($LASTEXITCODE){throw 'Inspect actual VG architectural map; no guessed net forcing permitted'}
    & (Join-Path $ModelSimBin 'vmap.exe') -c > map.log 2>&1
    if($LASTEXITCODE){throw 'vmap configuration failed'}
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'vlib failed'}
    $ini=(Join-Path $RunDir 'modelsim.ini').Replace('\','/')
    & (Join-Path $ModelSimBin 'vmap.exe') -modelsimini $ini work (Join-Path $RunDir 'work') >> map.log 2>&1
    if($LASTEXITCODE){throw 'Private work map failed'}
    $sourceDir=Join-Path $RunDir 'sources'
    $sources=Get-ChildItem $sourceDir -Filter '*.v' | ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -modelsimini $ini -sv "+incdir+$sourceDir+$RunDir" `
        (Join-Path $GowinHome 'simlib/gw5a/prim_sim.v') compiled.vg @sources `
        tb_game_p2_actual_bank_gate.sv tb_game_p2_range_gate.sv > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Extra gate compile diagnostics'}
    $logs=@{}
    foreach($bench in @('tb_game_p2_actual_bank_gate','tb_game_p2_range_gate')){
        & (Join-Path $ModelSimBin 'vsim.exe') -modelsimini $ini -c -onfinish stop "work.$bench" -l "$bench.log" `
            -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $code=$LASTEXITCODE;$body=Get-Content -Raw "$bench.log"
        $warnings=$body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and
            $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'}
        if($code -or $warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw "$bench failed"}
        $logs["$bench.log"]=(Get-FileHash "$bench.log").Hash.ToLower()
        $body -split "`n" | Where-Object {$_ -match 'PASS:|FAIL:'} | Write-Output
    }
    foreach($p in $hashes.GetEnumerator()){
        if((Get-FileHash (Join-Path $repoDir $p.Key)).Hash.ToLower() -ne $p.Value){throw "Changed verified source: $($p.Key)"}
    }
    $generated=@{}
    foreach($name in @('bank_actual_map.vh','range_actual_force.vh','range_actual_observe.vh',
        'p2_gate_pair.vh','engine_force.vh','tb_game_p2_actual_bank_gate.sv','tb_game_p2_range_gate.sv')){
        $generated[$name]=(Get-FileHash $name).Hash.ToLower()
    }
    [ordered]@{result='PASS';artifact_scope='Actual production VG: full static DPB input/read checks plus registered-controller-output audio component injection';
        source_sha256=$hashes;netlist_sha256=$origin.netlist_sha256;log_sha256=$logs;generated_sha256=$generated;
        compile_log_sha256=(Get-FileHash compile.log).Hash.ToLower();mapping_log_sha256=(Get-FileHash mapping.log).Hash.ToLower();
        finished=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 7 | Set-Content verification.json -Encoding utf8
}catch{
    [ordered]@{result='FAIL';error=$_.Exception.Message;netlist_sha256=$origin.netlist_sha256} |
        ConvertTo-Json | Set-Content failed.json -Encoding utf8
    throw
}finally{Pop-Location}
