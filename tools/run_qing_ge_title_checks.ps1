param([string]$RunName='qing_ge_title_rtl',
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple run name required'}
$runDir=Join-Path $repoDir ('sim/temp/'+$RunName)
if(Test-Path $runDir){throw 'Choose a new title evidence directory'}
$sourceDir=Join-Path $runDir 'sources'
New-Item -ItemType Directory $sourceDir -Force | Out-Null
$hashes=@{}
foreach($base in @('rtl','mem')){
    foreach($file in Get-ChildItem (Join-Path $repoDir $base) -Recurse -File){
        $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $file.FullName).Hash.ToLower()
        if($file.Extension -eq '.v'){
            $body=(Get-Content -Raw $file.FullName).Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
            Set-Content (Join-Path $sourceDir $file.Name) $body -Encoding utf8
        }elseif($file.Extension -eq '.vh'){Copy-Item $file.FullName $sourceDir}
    }
}
foreach($path in @('sim/reference/qing_ge/touch_game_renderer_m1.v','sim/reference/qing_ge/touch_game_renderer_m1.json',
    'sim/tb/tb_qing_ge_title_alignment.sv','tools/run_qing_ge_title_checks.ps1')){
    $file=Join-Path $repoDir $path;$hashes[$path]=(Get-FileHash $file).Hash.ToLower()
    if($file.EndsWith('.v')){
        (Get-Content -Raw $file).Replace('`include "../config/','`include "') | Set-Content (Join-Path $sourceDir 'touch_game_renderer_m1.v') -Encoding utf8
    }
}
[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');source_sha256=$hashes} |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'run.json') -Encoding utf8
Push-Location $runDir
try{
    & (Join-Path $ModelSimBin 'vmap.exe') -c > map.log 2>&1
    if($LASTEXITCODE){throw 'vmap failed'}
    & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
    if($LASTEXITCODE){throw 'vlib failed'}
    $ini=(Join-Path $runDir 'modelsim.ini').Replace('\','/')
    & (Join-Path $ModelSimBin 'vmap.exe') -modelsimini $ini work (Join-Path $runDir 'work') >> map.log 2>&1
    if($LASTEXITCODE){throw 'work map failed'}
    $sources=Get-ChildItem $sourceDir -Filter '*.v' | ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -modelsimini $ini -sv "+incdir+$sourceDir" `
        (Join-Path $GowinHome 'simlib/gw5a/prim_sim.v') @sources (Join-Path $repoDir 'sim/tb/tb_qing_ge_title_alignment.sv') > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Title compile diagnostics'}
    & (Join-Path $ModelSimBin 'vsim.exe') -modelsimini $ini -c -onfinish stop work.tb_qing_ge_title_alignment -l title.log `
        -do 'run -all; quit -code 0 -f' > title.console.log 2>&1
    $code=$LASTEXITCODE;$body=Get-Content -Raw title.log
    if($code -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw 'Title pixel comparison failed'}
    foreach($p in $hashes.GetEnumerator()){
        if((Get-FileHash (Join-Path $repoDir $p.Key)).Hash.ToLower() -ne $p.Value){throw "Changed title source $($p.Key)"}
    }
    [ordered]@{result='PASS';benches=@('tb_qing_ge_title_alignment');source_sha256=$hashes;
        log_sha256=(Get-FileHash title.log).Hash.ToLower();compile_log_sha256=(Get-FileHash compile.log).Hash.ToLower();
        scope='20 full screens; only requested Qing Ge title glyph/position boxes may change; legacy pixels preserved'} |
        ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8
    $body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
}finally{Pop-Location}
