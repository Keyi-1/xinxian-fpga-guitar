param([string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64')
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$simDir=Join-Path $repoDir 'sim\temp\display_game_p1'
$sourceDir=Join-Path $simDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$hashes=@{}
foreach($file in @((Get-ChildItem (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')) +
                 @((Get-ChildItem (Join-Path $repoDir 'sim\reference\display_game_p1') -Filter '*.v'))){
    $body=(Get-Content -Raw -LiteralPath $file.FullName).Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    Set-Content -LiteralPath (Join-Path $sourceDir $file.Name) -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $file.FullName).Hash.ToLower()
}
foreach($file in (Get-ChildItem (Join-Path $repoDir 'rtl\config') -Filter '*.vh')){
    Copy-Item $file.FullName $sourceDir
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $file.FullName).Hash.ToLower()
}
foreach($file in (Get-ChildItem (Join-Path $repoDir 'mem') -File)){
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash $file.FullName).Hash.ToLower()
}
$benches=@('tb_radial_palette_equivalence','tb_display_game_p1_integration')
$tests=@($benches|ForEach-Object {Join-Path $repoDir "sim\tb\$_.sv"})
foreach($file in $tests){$hashes[$file.Substring($repoDir.Length+1)]=(Get-FileHash $file).Hash.ToLower()}
Push-Location $simDir
try{
    if(!(Test-Path work)){& (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null}
    $sources=Get-ChildItem $sourceDir -Filter '*.v'|ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @sources @tests > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'P1 compilation failed'}
    $logs=@{}
    foreach($bench in $benches){
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
        $log=Get-Content -Raw "$bench.log"
        if($LASTEXITCODE -or $log -notmatch 'PASS:' -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):'){throw "$bench failed"}
        $log -split "`n"|Where-Object {$_ -match 'PASS:'}|Write-Output
        $logs[$bench]=(Get-FileHash "$bench.log").Hash.ToLower()
    }
    [ordered]@{result='PASS';frozen_commit='efdcf24277ab560b527ef1b24ab4348f77c9ae61';
        benches=$benches;source_sha256=$hashes;log_sha256=$logs} |
        ConvertTo-Json -Depth 6 | Set-Content verification.json -Encoding UTF8
}finally{Pop-Location}
