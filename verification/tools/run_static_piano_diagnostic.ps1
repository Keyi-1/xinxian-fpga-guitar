param(
    [string]$ModelSimBin='S:\BaiduNetdiskDownload\modelsim\win64'
)
$ErrorActionPreference='Stop'
$repoDir=Split-Path $PSScriptRoot
$legacyPcm=Join-Path $repoDir 'sim\reference\piano_legacy\piano_hammer.mem'
if(!(Test-Path -LiteralPath $legacyPcm)){
    # Historical recording is only a simulation fixture, never a hardware source.
    $legacyText=& git -C $repoDir show 'fb574a4:mem/piano_hammer.mem'
    if($LASTEXITCODE){throw 'Cannot recover the historical piano comparison fixture'}
    Set-Content -LiteralPath $legacyPcm -Value $legacyText -Encoding ASCII
}
$simDir=Join-Path $repoDir 'sim\temp\procedural_static'
$sourceDir=Join-Path $simDir 'sources'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
$files=@(Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl') -Recurse -Filter '*.v')+
    @(Get-ChildItem -LiteralPath (Join-Path $repoDir 'sim\reference\piano_legacy') -Filter '*.v')
$hashes=@{}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $repoDir 'rtl\config') -Filter '*.vh')){
    Copy-Item -LiteralPath $file.FullName -Destination $sourceDir
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
}
foreach($file in $files){
    $body=Get-Content -Raw -LiteralPath $file.FullName
    $body=$body.Replace('`include "../config/','`include "').Replace('"../../mem/','"../../../mem/')
    $body=$body.Replace('"../reference/piano_legacy/','"../../reference/piano_legacy/')
    $name=$file.Name
    if($file.FullName -match 'reference\\piano_legacy'){$name='legacy_'+$name}
    Set-Content -LiteralPath (Join-Path $sourceDir $name) -Value $body -Encoding UTF8
    $hashes[$file.FullName.Substring($repoDir.Length+1)]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
}
$bench=Join-Path $repoDir 'sim\tb\tb_piano_static_triad.sv'
$hashes['sim\tb\tb_piano_static_triad.sv']=(Get-FileHash -LiteralPath $bench -Algorithm SHA256).Hash.ToLower()
Push-Location $simDir
try{
    if(!(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work}
    $sources=Get-ChildItem -LiteralPath $sourceDir -Filter '*.v' | ForEach-Object FullName
    & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$sourceDir" @sources $bench > compile.log 2>&1
    if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Static diagnostic compile failed'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish stop work.tb_piano_static_triad -l run.log -do 'run -all; quit -code 0 -f' > console.log 2>&1
    $code=$LASTEXITCODE;$log=Get-Content -Raw run.log
    if($code -or $log -match 'FAIL:|\*\* (Error|Fatal|Warning):' -or $log -notmatch 'PASS:'){throw 'Static diagnostic failed'}
    @{result='PASS';source_sha256=$hashes;log_sha256=(Get-FileHash run.log -Algorithm SHA256).Hash.ToLower()} |
        ConvertTo-Json -Depth 5 | Set-Content verification.json -Encoding UTF8
    $log -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
}finally{Pop-Location}
