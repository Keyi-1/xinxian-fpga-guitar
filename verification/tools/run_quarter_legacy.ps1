param([string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string[]]$Benches=@('tb_i2c_fault_recovery','tb_gt911_touch','tb_touch_gesture_ui','tb_game_note_controller',
                          'tb_game_cdc','tb_game_chart_renderer','tb_game_audio_preservation','tb_game_miss_audio_cue',
                          'tb_game_competition_controls'),
      [string]$GowinHome='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE',
      [string]$PythonExe='E:\anaconda3\python.exe',[string]$RunName='touch_game')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'RunName must be a simple directory name'}
$simDir=Join-Path $repoDir ('sim\temp\'+$RunName)
$sourceDir=Join-Path $simDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$hashes=@{}
$hashes['tools/run_quarter_legacy.ps1']=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLower()
& $PythonExe (Join-Path $PSScriptRoot 'test_game_fingering.py') > (Join-Path $simDir 'fingering.log') 2>&1
if($LASTEXITCODE){throw 'Offline fingering/unchanged score regression failed'}
Write-Output 'Offline fingering: physical feasibility, alternate strings, exhaustive oracle and unchanged melody PASS'
foreach($name in @('game_fingering.py','generate_jasmine_score.py','generate_game_ui_font.py','test_game_fingering.py')){
    $file=Join-Path $PSScriptRoot $name
    $hashes["tools\$name"]=(Get-FileHash -LiteralPath $file).Hash.ToLower()
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'mem') -File)){
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl\config') -Filter '*.vh')){
    Copy-Item -LiteralPath $file.FullName -Destination $sourceDir
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
$baseline='655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7'
foreach($path in @('rtl/synth/piano_voice_core.v','rtl/audio_io/four_voice_piano_audio_core.v',
                   'rtl/audio_io/four_string_board_audio_chain.v')){
    $lines=& git -C $repoDir show "${baseline}:$path"
    if($LASTEXITCODE){throw "Cannot read accepted baseline: $path"}
    $body=($lines -join "`n").Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    if($path -eq 'rtl/synth/piano_voice_core.v'){
        foreach($change in @(@(0,112,64),@(1,160,128),@(2,208,192))){
            $oldLiteral="$($change[0]): gain_for_velocity=9'd$($change[1]);"
            $newLiteral="$($change[0]): gain_for_velocity=9'd$($change[2]);"
            if(([regex]::Matches($body,[regex]::Escape($oldLiteral))).Count -ne 1){throw 'Frozen gain edit requires exact baseline literal'}
            $body=$body.Replace($oldLiteral,$newLiteral)
        }
    }
    # Replace all three class names, including references within the frozen chain.
    $body=[regex]::Replace($body,'\b(four_string_board_audio_chain|four_voice_piano_audio_core|piano_voice_core)\b','accepted_$1')
    Set-Content -LiteralPath (Join-Path $sourceDir ('accepted_'+[IO.Path]::GetFileName($path))) -Value $body -Encoding UTF8
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')){
    $body=(Get-Content -Raw -LiteralPath $file.FullName).Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $sourceDir $file.Name) -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
foreach($path in @('sim/reference/game_p2/game_note_controller_p1.v','sim/reference/game_p2/game_score_rom_p1.v')){
    $file=Join-Path $repoDir $path
    $body=(Get-Content -Raw $file).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
    [IO.File]::WriteAllText((Join-Path $sourceDir (Split-Path $file -Leaf)),$body,[Text.UTF8Encoding]::new($false))
    $hashes[$path]=(Get-FileHash $file).Hash.ToLower()
}
Push-Location $simDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null}
    $sources=Get-ChildItem -LiteralPath $sourceDir -Filter '*.v'|ForEach-Object FullName
    $tests=@(foreach($bench in $Benches){
        $test=Join-Path $repoDir "sim/tb/$bench.sv"
        $hashes[$test.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $test).Hash.ToLower()
        # Some P2 benches predate sim/temp and use ../../mem. Freeze and
        # resolve that path exactly, rather than compiling a live bench with
        # a cwd-dependent missing ROM or ignoring its simulator diagnostic.
        $body=(Get-Content -Raw -LiteralPath $test).Replace('`include "../config/','`include "').Replace('"../../mem/',('"'+$repoDir.Replace('\','/')+'/mem/'))
        $copy=Join-Path $sourceDir "$bench.sv"
        [IO.File]::WriteAllText($copy,$body,[Text.UTF8Encoding]::new($false));$copy
    })
    [ordered]@{status='running';pid=$PID;started=(Get-Date).ToString('o');baseline_commit=$baseline;benches=$Benches;source_sha256=$hashes} | ConvertTo-Json -Depth 6 | Set-Content run.json -Encoding UTF8
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" (Join-Path $GowinHome 'simlib/gw5a/prim_sim.v') @sources @tests > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Touch/game compile diagnostics'}
    foreach($bench in $Benches){
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $log=Get-Content -Raw -LiteralPath "$bench.log"
        if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed; see $simDir"}
        $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
        Write-Output "$bench PASS"
    }
    $logHashes=@{};foreach($bench in $Benches){$logHashes[$bench]=(Get-FileHash -LiteralPath "$bench.log").Hash.ToLower()}
    [ordered]@{result='PASS';authorized_baseline_edit='Only authorized velocity gain literals112/160/208->64/128/192; max256 and other frozen audio code intact';baseline_commit=$baseline;benches=$Benches;source_sha256=$hashes;log_sha256=$logHashes} | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding UTF8
}finally{Pop-Location}
