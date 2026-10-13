param([string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$simDir=Join-Path $repoDir 'sim\temp\i2s'
$sourceDir=Join-Path $simDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$hashes=@{}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl\config') -Filter '*.vh')){
    Copy-Item -LiteralPath $file.FullName -Destination $sourceDir
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')){
    $body=(Get-Content -Raw -LiteralPath $file.FullName).Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $sourceDir $file.Name) -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
}
# Compare against the actual pre-I2S board chain; all tone/FX assets are retained.
$oldBody=& git -C $repoDir show 'e55c7cb:rtl/audio_io/four_string_board_audio_chain.v'
if($LASTEXITCODE){throw 'Cannot retrieve pre-I2S chain'}
$oldBody=($oldBody -join "`n").Replace('module four_string_board_audio_chain','module pre_i2s_four_string_board_audio_chain').Replace('`include "../config/','`include "')
Set-Content -LiteralPath (Join-Path $sourceDir 'pre_i2s_board.v') -Value $oldBody -Encoding UTF8
$benches=@('tb_i2s_tx','tb_board_dual_audio')
Push-Location $simDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work}
    $sources=Get-ChildItem -LiteralPath $sourceDir -Filter '*.v'|ForEach-Object FullName
    $testFiles=$benches|ForEach-Object {Join-Path $repoDir "sim\tb\$_.sv"}
    foreach($testFile in $testFiles){$hashes[$testFile.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $testFile).Hash.ToLower()}
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @sources @testFiles > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'I2S compile diagnostics'}
    $logHashes=@{}
    foreach($bench in $benches){
        # Preserve unit-test signal visibility so $dumpvars contains actual
        # pin transitions rather than an empty optimized VCD header.
        $visibilityOptions=@()
        if($bench -eq 'tb_i2s_tx'){$visibilityOptions=@('-voptargs=+acc')}
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop @visibilityOptions "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $simExit=$LASTEXITCODE;$log=Get-Content -Raw -LiteralPath "$bench.log"
        if($simExit -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):' -or $log -notmatch 'PASS:'){throw "I2S bench failed: $bench"}
        $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
        $logHashes[$bench]=(Get-FileHash -LiteralPath "$bench.log").Hash.ToLower()
    }
    if((Get-Item -LiteralPath i2s_tx.vcd).Length -lt 10000){throw 'I2S waveform is empty'}
    @{result='PASS';baseline_commit='e55c7cb';source_sha256=$hashes;log_sha256=$logHashes;
      waveform_sha256=(Get-FileHash -LiteralPath i2s_tx.vcd).Hash.ToLower()} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath verification.json -Encoding UTF8
}finally{Pop-Location}
