param(
    [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64',
    [string]$PythonExe='E:\anaconda3\python.exe'
)
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$legacyPcm=Join-Path $repoDir 'sim\reference\piano_legacy\piano_hammer.mem'
if(!(Test-Path -LiteralPath $legacyPcm)){
    $legacyText=& git -C $repoDir show 'fb574a4:mem/piano_hammer.mem'
    if($LASTEXITCODE){throw 'Cannot recover simulation-only historical PCM'}
    Set-Content -LiteralPath $legacyPcm -Value $legacyText -Encoding ASCII
}
$mainSim=Join-Path $repoDir 'sim\temp'
$simDir=Join-Path $mainSim 'procedural_piano'
$sourceDir=Join-Path $simDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$rtlFiles=Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v'
$referenceFiles=Get-ChildItem -LiteralPath (Join-Path $repoDir 'sim\reference\piano_legacy') -Filter '*.v'
$hashes=@{}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl\config') -Filter '*.vh')){
    Copy-Item -LiteralPath $file.FullName -Destination $sourceDir
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
}
$coefficientsHash=$hashes['rtl\config\piano_hammer_coeffs.vh']
foreach($file in @($rtlFiles)+@($referenceFiles)){
    $body=Get-Content -Raw -LiteralPath $file.FullName
    $body=$body.Replace('`include "../config/','`include "')
    $body=$body.Replace('"../../mem/','"../../../mem/')
    $body=$body.Replace('"../reference/piano_legacy/','"../../reference/piano_legacy/')
    $destination=Join-Path $sourceDir $file.Name
    if($file.FullName -match 'reference\\piano_legacy'){$destination=Join-Path $sourceDir ('legacy_'+$file.Name)}
    Set-Content -LiteralPath $destination -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
}
foreach($generator in @('gen_piano_golden.py','gen_full_piano_golden.py','gen_rock_golden.py')){
    & $PythonExe (Join-Path $PSScriptRoot $generator)
    if($LASTEXITCODE){throw "Oracle failed: $generator"}
}
foreach($golden in @('piano_voice_golden.txt','full_piano_golden.txt','rock_golden.txt')){
    Copy-Item -LiteralPath (Join-Path $mainSim $golden) -Destination $simDir
}
$benches=@('tb_piano_voice_core','tb_full_piano_voice','tb_full_piano_budget',
    'tb_rock_voice_core','tb_guitar_open_release','tb_procedural_hammer_properties','tb_procedural_piano_ab')
Push-Location $simDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work}
    $sources=Get-ChildItem -LiteralPath $sourceDir -Filter '*.v'|ForEach-Object FullName
    $testFiles=$benches|ForEach-Object {Join-Path $repoDir "sim\tb\$_.sv"}
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @sources @testFiles > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Procedural compile diagnostics'}
    foreach($bench in $benches){
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $simExit=$LASTEXITCODE
        $log=Get-Content -Raw -LiteralPath "$bench.log"
        Copy-Item -LiteralPath "$bench.log" -Destination (Join-Path $mainSim "$bench.log")
        if($simExit -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):' -or $log -notmatch 'PASS:'){throw "Procedural bench failed: $bench"}
        Write-Output "PASS $bench"
    }
    foreach($file in @('procedural_ab_legacy_pcm16.txt','procedural_ab_new_pcm16.txt')){
        Copy-Item -LiteralPath $file -Destination $mainSim
    }
    @{source_sha256=$hashes;
      hammer_coefficients_sha256=$coefficientsHash;
      test_results_sha256=@($benches|ForEach-Object {
          $benchName=$_
          @{bench=$benchName;sha256=(Get-FileHash -LiteralPath "$benchName.log" -Algorithm SHA256).Hash.ToLower()}
      });
      result='PASS'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath verification.json -Encoding UTF8
    Write-Output 'PROCEDURAL PIANO FINAL CHECKS PASSED: 7 benches'
}finally{Pop-Location}
