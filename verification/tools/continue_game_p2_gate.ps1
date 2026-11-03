param([Parameter(Mandatory=$true)][string]$OriginGateDir,
      [Parameter(Mandatory=$true)][string]$GateDir,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$OriginGateDir=[IO.Path]::GetFullPath($OriginGateDir)
$GateDir=[IO.Path]::GetFullPath($GateDir)
$allowed=[IO.Path]::GetFullPath((Join-Path $repoDir 'sim/temp'))+[IO.Path]::DirectorySeparatorChar
if(!$OriginGateDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or !$GateDir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Simulation paths must be under sim/temp'}
if(Test-Path $GateDir){throw 'Choose a fresh continuation directory'}
$origin=Get-Content -Raw (Join-Path $OriginGateDir 'run.json') | ConvertFrom-Json
$hashes=@{}
foreach($p in $origin.source_sha256.PSObject.Properties){
    if((Get-FileHash (Join-Path $repoDir $p.Name)).Hash.ToLower() -ne $p.Value){throw "Changed origin source: $($p.Name)"}
    $hashes[$p.Name]=$p.Value
}
$netlist=Join-Path $repoDir 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
if((Get-FileHash $netlist).Hash.ToLower() -ne $origin.netlist_sha256){throw 'Netlist changed since engine started'}
New-Item -ItemType Directory $GateDir | Out-Null
Copy-Item (Join-Path $OriginGateDir 'sources') $GateDir -Recurse
Copy-Item (Join-Path $OriginGateDir 'compiled.vg') $GateDir
foreach($f in Get-ChildItem $OriginGateDir -File | Where-Object {$_.Extension -in @('.sv','.vh')}){Copy-Item $f.FullName $GateDir}
Copy-Item (Join-Path $repoDir 'sim/tb/tb_game_p2_top_gate.sv') $GateDir
$sourceDir=Join-Path $GateDir 'sources'
$hashes['tools/continue_game_p2_gate.ps1']=(Get-FileHash $PSCommandPath).Hash.ToLower()
$originProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$($origin.pid)"
$originCreation=if($originProcess){$originProcess.CreationDate}else{$null}
$workerScript=Join-Path $GateDir 'worker.ps1'
@'
param($Bench,$RunDir,$GateDir,$SourceDir,$ModelSimBin,$GowinHome)
$ErrorActionPreference='Stop'
Set-Location $RunDir
& (Join-Path $ModelSimBin 'vmap.exe') -c > map.log 2>&1
if($LASTEXITCODE){throw 'Cannot create private ModelSim configuration'}
& (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
if($LASTEXITCODE){throw 'Cannot create private simulator library'}
$ini=(Join-Path $RunDir 'modelsim.ini').Replace('\','/')
& (Join-Path $ModelSimBin 'vmap.exe') -modelsimini $ini work (Join-Path $RunDir 'work') >> map.log 2>&1
if($LASTEXITCODE){throw 'Cannot map private work library'}
Set-Location $GateDir
$sources=Get-ChildItem $SourceDir -Filter '*.v' | ForEach-Object FullName
$tests=@('tb_game_p2_top_gate.sv','tb_game_p2_layout_gate.sv','tb_game_p2_engine_gate.sv')
$compile=Join-Path $GateDir "$Bench.compile.log"
& (Join-Path $ModelSimBin 'vlog.exe') -modelsimini $ini -sv "+incdir+$SourceDir+$GateDir" `
    (Join-Path $GowinHome 'simlib/gw5a/prim_sim.v') (Join-Path $GateDir 'compiled.vg') @sources @tests > $compile 2>&1
if($LASTEXITCODE -or (Get-Content -Raw $compile) -match '\*\* (Error|Fatal|Warning):'){throw 'Private gate compile diagnostics'}
$log=(Join-Path $GateDir "$Bench.log").Replace('\','/')
& (Join-Path $ModelSimBin 'vsim.exe') -modelsimini $ini -c -onfinish stop "work.$Bench" -l $log `
    -do 'run -all; quit -code 0 -f' > (Join-Path $GateDir "$Bench.console.log") 2>&1
$code=$LASTEXITCODE;$body=Get-Content -Raw $log
$warnings=$body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and
    $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'}
if($code -or $warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw "$Bench failed"}
[ordered]@{result='PASS';bench=$Bench;pid=$PID;finished=(Get-Date).ToString('o');log_sha256=(Get-FileHash $log).Hash.ToLower()} |
    ConvertTo-Json | Set-Content (Join-Path $RunDir 'result.json') -Encoding utf8
'@ | Set-Content $workerScript -Encoding utf8
$jobs=@()
foreach($bench in @('tb_game_p2_layout_gate','tb_game_p2_top_gate')){
    $workDir=Join-Path $GateDir $bench
    New-Item -ItemType Directory $workDir | Out-Null
    $workerArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$workerScript+'"'),'-Bench',$bench,
        '-RunDir',('"'+$workDir+'"'),'-GateDir',('"'+$GateDir+'"'),'-SourceDir',('"'+$sourceDir+'"'),
        '-ModelSimBin',('"'+$ModelSimBin+'"'),'-GowinHome',('"'+$GowinHome+'"'))
    $job=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $workerArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $workDir 'worker.stdout.log') -RedirectStandardError (Join-Path $workDir 'worker.stderr.log')
    $jobs+=@{bench=$bench;process=$job;run_dir=$workDir}
}
[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_sha256=$hashes;netlist_sha256=$origin.netlist_sha256;
    engine_origin=$OriginGateDir;engine_origin_parent_pid=$origin.pid;
    workers=@($jobs|ForEach-Object {@{bench=$_.bench;pid=$_.process.Id;run_dir=$_.run_dir}})} |
    ConvertTo-Json -Depth 8 | Set-Content (Join-Path $GateDir 'run.json') -Encoding utf8
$engineLog=Join-Path $OriginGateDir 'tb_game_p2_engine_gate.log'
$engineCopied=$false
while(!$engineCopied -or @($jobs | Where-Object {!$_.process.HasExited}).Count){
    if(!$engineCopied -and (Test-Path $engineLog)){
        $body=Get-Content -Raw $engineLog
        if($body -match 'PASS: synthesized P2 engine' -and $body -match '# Errors: 0, Warnings:'){
            if($body -match 'FAIL:|\*\* (Error|Fatal)'){throw 'Origin musical check failed'}
            Copy-Item $engineLog $GateDir
            Copy-Item (Join-Path $OriginGateDir 'tb_game_p2_engine_gate.console.log') $GateDir
            Copy-Item (Join-Path $OriginGateDir 'engine_progress.log') $GateDir
            Copy-Item (Join-Path $OriginGateDir 'compile.log') (Join-Path $GateDir 'engine_origin.compile.log')
            Copy-Item (Join-Path $OriginGateDir 'run.json') (Join-Path $GateDir 'engine_origin.json')
            $engineCopied=$true
            # The completed audio proof is retained. Stop only this old
            # wrapper's now-redundant children before they repeat the other tests.
            $parent=Get-CimInstance Win32_Process -Filter "ProcessId=$($origin.pid)"
            if($parent -and $parent.CreationDate -eq $originCreation){
                $all=@(Get-CimInstance Win32_Process);$ids=@([int]$origin.pid);$children=@()
                do{
                    $next=@($all | Where-Object {$_.ParentProcessId -in $ids -and $_.ProcessId -notin $ids})
                    $children+=@($next.ProcessId);$ids+=@($next.ProcessId)
                }while($next.Count)
                foreach($id in @($children | Select-Object -Unique)){Stop-Process -Id $id -Force -ErrorAction SilentlyContinue}
                Stop-Process -Id $origin.pid -Force -ErrorAction SilentlyContinue
            }
            Write-Output 'PASS: retained completed musical engine proof from the exact same source and netlist'
        }elseif($body -match 'FAIL:|\*\* (Error|Fatal)'){throw 'Origin musical check failed'}
    }
    foreach($job in $jobs){
        $job.process.Refresh()
        if($job.process.HasExited){
            $job.process.WaitForExit()
            if($job.process.ExitCode -ne 0){throw "$($job.bench) worker failed; inspect $($job.run_dir)"}
        }
    }
    Start-Sleep -Seconds 2
}
$logs=@{}
foreach($bench in @('tb_game_p2_engine_gate','tb_game_p2_layout_gate','tb_game_p2_top_gate')){
    $log=Join-Path $GateDir "$bench.log";$body=Get-Content -Raw $log
    $warnings=$body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and
        $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'}
    if($warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw "$bench failed"}
    $logs["$bench.log"]=(Get-FileHash $log).Hash.ToLower()
    $body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
}
foreach($p in $hashes.GetEnumerator()){
    if((Get-FileHash (Join-Path $repoDir $p.Key)).Hash.ToLower() -ne $p.Value){throw "Changed final source: $($p.Key)"}
}
$generated=@{}
foreach($name in @('worker.ps1','p2_gate_pair.vh','chart_outputs.vh','engine_force.vh','tb_game_p2_engine_gate.sv','tb_game_p2_layout_gate.sv','stage_force.vh')){
    $generated[$name]=(Get-FileHash (Join-Path $GateDir $name)).Hash.ToLower()
}
[ordered]@{result='PASS';artifact_scope='Same final netlist: retained complete musical engine check plus parallel private-library layout/video checks';
    source_sha256=$hashes;netlist_sha256=$origin.netlist_sha256;log_sha256=$logs;generated_sha256=$generated;
    engine_origin_evidence_sha256=(Get-FileHash (Join-Path $GateDir 'engine_origin.json')).Hash.ToLower();
    vendor_primitive_path=(Join-Path $GowinHome 'simlib/gw5a/prim_sim.v');
    vendor_primitive_sha256=(Get-FileHash (Join-Path $GowinHome 'simlib/gw5a/prim_sim.v')).Hash.ToLower()} |
    ConvertTo-Json -Depth 8 | Set-Content (Join-Path $GateDir 'verification.json') -Encoding utf8
