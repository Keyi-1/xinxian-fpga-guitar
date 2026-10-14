param([string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
      [string[]]$Benches=@('tb_i2c_fault_recovery','tb_gt911_touch','tb_touch_gesture_ui','tb_game_note_controller',
                          'tb_game_cdc','tb_game_chart_renderer','tb_game_audio_preservation','tb_game_miss_audio_cue',
                          'tb_game_competition_controls'))
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$simDir=Join-Path $repoDir 'sim\temp\touch_game'
$sourceDir=Join-Path $simDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$hashes=@{}
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
    # Replace all three class names, including references within the frozen chain.
    $body=[regex]::Replace($body,'\b(four_string_board_audio_chain|four_voice_piano_audio_core|piano_voice_core)\b','accepted_$1')
    Set-Content -LiteralPath (Join-Path $sourceDir ('accepted_'+[IO.Path]::GetFileName($path))) -Value $body -Encoding UTF8
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')){
    $body=(Get-Content -Raw -LiteralPath $file.FullName).Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $sourceDir $file.Name) -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
Push-Location $simDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null}
    $sources=Get-ChildItem -LiteralPath $sourceDir -Filter '*.v'|ForEach-Object FullName
    $tests=$Benches|ForEach-Object {Join-Path $repoDir "sim\tb\$_.sv"}
    foreach($test in $tests){$hashes[$test.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $test).Hash.ToLower()}
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @sources @tests > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Touch/game compile diagnostics'}
    foreach($bench in $Benches){
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $log=Get-Content -Raw -LiteralPath "$bench.log"
        if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed; see $simDir"}
        $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
        Write-Output "$bench PASS"
    }
    $logHashes=@{};foreach($bench in $Benches){$logHashes[$bench]=(Get-FileHash -LiteralPath "$bench.log").Hash.ToLower()}
    [ordered]@{result='PASS';baseline_commit=$baseline;benches=$Benches;source_sha256=$hashes;log_sha256=$logHashes} | ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding UTF8
}finally{Pop-Location}
