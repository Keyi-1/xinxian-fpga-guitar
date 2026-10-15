param([Parameter(Mandatory=$true)][string]$RunDir,
      [ValidateSet('direct_log','balanced_log')][string]$Candidate='direct_log',
      [string]$GateNetlist='',
      [string]$BaselineNetlist='',
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE')
$ErrorActionPreference='Stop'
if($BaselineNetlist -and !$GateNetlist){throw 'BaselineNetlist requires GateNetlist'}
$repoDir=Split-Path $PSScriptRoot
$RunDir=[IO.Path]::GetFullPath($RunDir)
if(Test-Path -LiteralPath $RunDir){throw 'Choose a new run directory; existing evidence is preserved'}
$allowedRoot=[IO.Path]::GetFullPath((Join-Path $repoDir 'sim\temp'))+[IO.Path]::DirectorySeparatorChar
if(!$RunDir.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Simulation output must be under sim/temp'}
New-Item -ItemType Directory -Path $RunDir | Out-Null
$files=@('sim\tb\tb_radial_bands_equivalence.sv')
if(!$BaselineNetlist){$files+=@('sim\reference\radial_bands\guitar_radial_bands_frozen.v')}
if(!$GateNetlist){$files+=@("experiments\radial_bands\guitar_radial_bands_$Candidate.v")}
$hashes=@{}
$sources=@(foreach($file in $files){
    $source=Join-Path $repoDir $file
    $hashes[$file]=(Get-FileHash -LiteralPath $source).Hash.ToLower()
    Copy-Item -LiteralPath $source -Destination $RunDir
    Join-Path $RunDir (Split-Path $source -Leaf)
})
$hashes['tools\run_radial_bands_experiment_checks.ps1']=(Get-FileHash $PSCommandPath).Hash.ToLower()
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $RunDir 'runner_snapshot.ps1')
$defines=@("+define+BANDS_CANDIDATE=guitar_radial_bands_$Candidate")
if($GateNetlist){
    $GateNetlist=(Resolve-Path -LiteralPath $GateNetlist).Path
    $hashes['synthesized_netlist']=(Get-FileHash -LiteralPath $GateNetlist).Hash.ToLower()
    Copy-Item -LiteralPath $GateNetlist -Destination (Join-Path $RunDir 'candidate.vg')
    $primitives=Join-Path $GowinHome 'simlib\gw5a\prim_sim.v'
    $hashes['gw5a_prim_sim.v']=(Get-FileHash -LiteralPath $primitives).Hash.ToLower()
    $sources+=@($primitives,(Join-Path $RunDir 'candidate.vg'))
    $defines+=@('+define+BANDS_GATE')
}
if($BaselineNetlist){
    $BaselineNetlist=(Resolve-Path -LiteralPath $BaselineNetlist).Path
    $hashes['baseline_synthesized_netlist']=(Get-FileHash -LiteralPath $BaselineNetlist).Hash.ToLower()
    $body=Get-Content -Raw -LiteralPath $BaselineNetlist
    $top="guitar_radial_bands_$Candidate"
    if(([regex]::Matches($body,"\bmodule\s+$top\b")).Count -ne 1){throw 'Unexpected baseline top module'}
    $body=[regex]::Replace($body,"\bmodule\s+$top\b",'module guitar_radial_bands_frozen')
    $renamed=Join-Path $RunDir 'baseline_renamed.vg'
    Set-Content -LiteralPath $renamed -Value $body -Encoding UTF8
    $hashes['baseline_renamed_netlist']=(Get-FileHash -LiteralPath $renamed).Hash.ToLower()
    $sources+=@($renamed)
}
[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');
    base_commit='8230217e56952ee2793b97d98ef90e2740fff54b';candidate=$Candidate;
    scope= $(if($BaselineNetlist){'candidate synthesized component vs frozen synthesized component, exact-cycle outputs including warm resets'}elseif($GateNetlist){'synthesized component vs frozen RTL, exact-cycle outputs'}else{'exhaustive log and RTL component state/output equivalence'});
    source_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RunDir 'run.json') -Encoding UTF8
Push-Location $RunDir
try{
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'ModelSim library creation failed'}
    & (Join-Path $ModelSimBin 'vlog.exe') -sv @defines @sources > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Bands experiment compilation failed'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_radial_bands_equivalence -l run.log -do 'run -all; quit -code 0 -f' > console.log 2>&1
    $exit=$LASTEXITCODE
    $log=Get-Content -Raw run.log
    $log -split "`n"|Where-Object {$_ -match 'PASS:|FAIL:'}|Write-Output
    if($exit -or $log -notmatch 'PASS: exact-cycle' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw 'Bands experiment failed'}
    $record=Get-Content -Raw run.json | ConvertFrom-Json
    $record.status='PASS'
    $record|Add-Member finished (Get-Date).ToString('o')
    $record|Add-Member log_sha256 (Get-FileHash run.log).Hash.ToLower()
    $record|Add-Member compile_log_sha256 (Get-FileHash compile.log).Hash.ToLower()
    $record | ConvertTo-Json -Depth 5 | Set-Content verification.json -Encoding UTF8
}catch{
    $record=Get-Content -Raw run.json | ConvertFrom-Json
    $record.status='FAIL'
    $record|Add-Member failure $_.Exception.Message
    $record | ConvertTo-Json -Depth 5 | Set-Content failed.json -Encoding UTF8
    throw
}finally{Pop-Location}
