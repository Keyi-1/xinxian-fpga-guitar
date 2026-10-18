param([Parameter(Mandatory=$true)][string]$RunName,
      [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Simple run name required'}
$repoDir=Split-Path $PSScriptRoot;$runDir=Join-Path $repoDir "sim/temp/$RunName"
$original=Get-Content -Raw (Join-Path $runDir 'run.json') | ConvertFrom-Json
$hashes=@{}
foreach($p in $original.source_sha256.PSObject.Properties){
    if((Get-FileHash (Join-Path $repoDir $p.Name)).Hash.ToLower() -ne $p.Value){throw "Source changed; cannot resume: $($p.Name)"}
    $hashes[$p.Name]=$p.Value
}
$paths=@('sim/reference/game_p2/game_note_controller_p1.v','sim/reference/game_p2/game_score_rom_p1.v')
$added=@()
foreach($path in $paths){
    $file=Join-Path $repoDir $path;$hashes[$path]=(Get-FileHash $file).Hash.ToLower()
    $body=(Get-Content -Raw $file).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    $copy=Join-Path $runDir ('sources/'+(Split-Path $file -Leaf))
    if(Test-Path $copy){if((Get-Content -Raw $copy).Trim() -ne $body.Trim()){throw 'Existing reference differs'}}
    else{[IO.File]::WriteAllText($copy,$body,[Text.UTF8Encoding]::new($false))}
    $added+=$copy
}
$record=[ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');reason='Shared runner originally omitted the two frozen P2 reference modules; retain passed benches and resume remaining tests';source_sha256=$hashes;original_run='run.json'}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'resume.json') -Encoding utf8
Push-Location $runDir
try{
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$runDir/sources" @added > resume_compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw resume_compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Reference compile failed'}
    $logs=@{};$reused=@();$rerun=@()
    foreach($bench in $original.benches){
        $logPath=Join-Path $runDir "$bench.log"
        $body=if(Test-Path $logPath){Get-Content -Raw $logPath}else{''}
        if($body -match 'PASS:' -and $body -notmatch 'FAIL:|\*\* (Error|Fatal|Warning):'){$reused+=$bench}
        else{
            foreach($file in @("$bench.log","$bench.console.log")){
                if(Test-Path -LiteralPath $file){
                    $archive="$file.failed_before_resume"
                    if(Test-Path -LiteralPath $archive){throw 'Do not overwrite prior failure'}
                    Move-Item -LiteralPath $file -Destination $archive
                }
            }
            & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
            $body=Get-Content -Raw "$bench.log"
            if($LASTEXITCODE -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed"}
            $rerun+=$bench;$body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
        }
        $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
    }
    foreach($p in $hashes.Keys){if((Get-FileHash (Join-Path $repoDir $p)).Hash.ToLower() -ne $hashes[$p]){throw "Source drift: $p"}}
    $record.status='PASS';$record['reused_passed_benches']=$reused;$record['continued_benches']=$rerun
    [ordered]@{result='PASS';baseline_commit=$original.baseline_commit;benches=$original.benches;source_sha256=$hashes;log_sha256=$logs;recovery='resume.json';scope='Current C2 sources; preserved successful benches plus resumed missing-reference tests'} | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding utf8
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{$record['finished']=(Get-Date).ToString('o');$record | ConvertTo-Json -Depth 6 | Set-Content resume.json -Encoding utf8;Pop-Location}
