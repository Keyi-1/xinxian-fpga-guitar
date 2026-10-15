param([Parameter(Mandatory=$true)][string]$GateDir,
      [string[]]$Benches=@('tb_game_p2_engine_gate','tb_game_p2_layout_gate','tb_game_p2_top_gate'),
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE',
      [string]$PythonExe='E:\anaconda3\python.exe')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$GateDir=[IO.Path]::GetFullPath($GateDir)
$allowed=[IO.Path]::GetFullPath((Join-Path $repoDir 'sim/temp'))+[IO.Path]::DirectorySeparatorChar
if(!$GateDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Gate output must be under sim/temp'}
if(Test-Path -LiteralPath $GateDir){throw 'Choose a fresh gate directory; existing evidence is preserved'}
$sourceDir=Join-Path $GateDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$rtl=Get-ChildItem (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v'
$names=foreach($f in $rtl){foreach($m in [regex]::Matches((Get-Content -Raw $f.FullName),'\bmodule\s+(\w+)')){$m.Groups[1].Value}}
$pattern='\b('+ (($names|ForEach-Object {[regex]::Escape($_)}) -join '|') +')\b'
$hashes=@{}
foreach($f in $rtl){
    $body=[regex]::Replace((Get-Content -Raw $f.FullName),$pattern,{param($m)'rtlref_'+$m.Value})
    # A generated header may share a module's basename (game_p2_catalog).
    # Rename module references while preserving every include filename.
    foreach($header in Get-ChildItem (Join-Path $repoDir 'rtl/config') -Filter '*.vh'){
        $body=$body.Replace(('rtlref_'+$header.Name),$header.Name)
    }
    $body=$body.Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    Set-Content (Join-Path $sourceDir $f.Name) $body -Encoding utf8
    $hashes[$f.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()
}
foreach($f in Get-ChildItem (Join-Path $repoDir 'rtl/config') -Filter '*.vh'){
    Copy-Item $f.FullName $sourceDir
    $hashes[$f.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()
}
foreach($f in Get-ChildItem (Join-Path $repoDir 'mem') -File){$hashes[$f.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $f.FullName).Hash.ToLower()}
$vg=Join-Path $repoDir 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
Copy-Item $vg (Join-Path $GateDir 'compiled.vg')
$generator=Join-Path $PSScriptRoot 'generate_game_p2_gate_bench.py'
& $PythonExe $generator (Join-Path $GateDir 'compiled.vg') $GateDir
if($LASTEXITCODE){throw 'P2 optimized port map failed; inspect the new netlist'}
$topBench=Join-Path $repoDir 'sim/tb/tb_game_p2_top_gate.sv'
$hashes['tools/generate_game_p2_gate_bench.py']=(Get-FileHash $generator).Hash.ToLower()
$hashes['tools/run_game_p2_gate.ps1']=(Get-FileHash $PSCommandPath).Hash.ToLower()
$hashes['sim/tb/tb_game_p2_top_gate.sv']=(Get-FileHash $topBench).Hash.ToLower()
foreach($name in @('engine','layout')){
    $path="sim/tb/tb_game_p2_${name}_gate.sv"
    $hashes[$path]=(Get-FileHash (Join-Path $repoDir $path)).Hash.ToLower()
}
[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_sha256=$hashes;
    netlist_sha256=(Get-FileHash $vg).Hash.ToLower()} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $GateDir 'run.json') -Encoding utf8
Push-Location $GateDir
try{
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'vlib failed'}
    $sources=Get-ChildItem $sourceDir -Filter '*.v' | ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir+$GateDir" (Join-Path $GowinHome 'simlib/gw5a/prim_sim.v') `
        compiled.vg @sources $topBench tb_game_p2_layout_gate.sv tb_game_p2_engine_gate.sv > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Gate compile diagnostics'}
    $logs=@{}
    foreach($bench in $Benches){
        if($bench -notin @('tb_game_p2_engine_gate','tb_game_p2_layout_gate','tb_game_p2_top_gate')){throw 'Unknown gate bench'}
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $code=$LASTEXITCODE;$body=Get-Content -Raw "$bench.log"
        $warnings=$body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and
            $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'}
        $body -split "`n" | Where-Object {$_ -match 'PASS:|FAIL:'} | Write-Output
        if($code -or $warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw "$bench failed"}
        $logs["$bench.log"]=(Get-FileHash "$bench.log").Hash.ToLower()
    }
    $result=if($logs.Count -eq 3){'PASS'}else{'COMPONENT_ONLY'}
    [ordered]@{result=$result;artifact_scope='Original gprj synthesis; partial bench selections certify components only';
        source_sha256=$hashes;netlist_sha256=(Get-FileHash compiled.vg).Hash.ToLower();log_sha256=$logs;
        generated_sha256=@{'p2_gate_pair.vh'=(Get-FileHash p2_gate_pair.vh).Hash.ToLower();
            'chart_outputs.vh'=(Get-FileHash chart_outputs.vh).Hash.ToLower();
            'engine_force.vh'=(Get-FileHash engine_force.vh).Hash.ToLower();
            'tb_game_p2_layout_gate.sv'=(Get-FileHash tb_game_p2_layout_gate.sv).Hash.ToLower();
            'tb_game_p2_engine_gate.sv'=(Get-FileHash tb_game_p2_engine_gate.sv).Hash.ToLower();
            'stage_force.vh'=(Get-FileHash stage_force.vh).Hash.ToLower()}} | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8
}finally{Pop-Location}
