param([string]$RunName='rtl_02',[ValidateSet('RTL','Gate')][string]$Mode='RTL')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($RunName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Invalid run name'}
$run=Join-Path $root ('build/mpu_lcd_diagnostic/'+$RunName)
if(Test-Path -LiteralPath $run){throw 'Preserve the existing test result; use a new run name.'}
$src=Join-Path $run 'sources';New-Item -ItemType Directory -Path $src | Out-Null
$sources=@(Get-ChildItem (Join-Path $root 'rtl/diagnostics') -Filter '*.v')
$sources+=Get-Item (Join-Path $root 'rtl/control/reset_sync.v'),(Join-Path $root 'rtl/display/lcd_rgb_scan_480x272.v')
$names=foreach($f in $sources){foreach($m in [regex]::Matches((Get-Content -Raw $f.FullName),'\bmodule\s+(\w+)')){$m.Groups[1].Value}}
$pattern='\b('+($names -join '|')+')\b'
$hashes=[ordered]@{}
foreach($f in $sources){
 $hashes[$f.FullName.Substring($root.Length+1)]=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLower()
 $body=Get-Content -Raw -LiteralPath $f.FullName
 if($Mode -eq 'Gate'){$body=[regex]::Replace($body,$pattern,{param($m)'ref_'+$m.Value})}
 [IO.File]::WriteAllText((Join-Path $src $f.Name),$body,[Text.UTF8Encoding]::new($false))
}
$tests=Get-ChildItem (Join-Path $root 'sim/diagnostics/mpu_lcd') -Filter '*.sv'
foreach($f in $tests){Copy-Item -LiteralPath $f.FullName -Destination $src;$hashes[$f.FullName.Substring($root.Length+1)]=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLower()}
$vg=Join-Path $root 'gowin/neo_mpu6050_lcd_diagnostic/impl/gwsynthesis/neo_mpu6050_lcd_diagnostic.vg'
$prim='S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v'
if($Mode -eq 'Gate'){Copy-Item -LiteralPath $vg -Destination (Join-Path $src 'compiled.vg');$hashes['actual_vg']=(Get-FileHash -LiteralPath $vg).Hash.ToLower();$hashes['gowin_prim_sim']=(Get-FileHash -LiteralPath $prim).Hash.ToLower()}
$record=[ordered]@{status='running';mode=$Mode;pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o');inputs_sha256=$hashes}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'run.json') -Encoding utf8
$bin='S:/BaiduNetdiskDownload/modelsim/win64'
Push-Location $run
try{
 & "$bin/vlib.exe" work > vlib.log 2>&1
 if($LASTEXITCODE){throw 'ModelSim library creation failed'}
 $hdl=@(Get-ChildItem $src -Filter '*.v' | ForEach-Object FullName)
 $bfm=Join-Path $src 'mpu_diag_slave.sv'
 $benches=if($Mode -eq 'Gate'){@('tb_mpu_diag_gate')}else{@('tb_mpu_lcd_diag','tb_mpu_diag_screen','tb_mpu_diag_top')}
 $benchFiles=@($benches | ForEach-Object {Join-Path $src ($_+'.sv')})
 if($Mode -eq 'Gate'){& "$bin/vlog.exe" -sv $prim (Join-Path $src 'compiled.vg') @hdl $bfm @benchFiles > compile.log 2>&1}
 else{& "$bin/vlog.exe" -sv @hdl $bfm @benchFiles > compile.log 2>&1}
 if($LASTEXITCODE -or (Get-Content -Raw compile.log) -match '\*\* (Error|Fatal|Warning):'){throw 'Compilation failed'}
 foreach($bench in $benches){
  & "$bin/vsim.exe" -c -onfinish stop "work.$bench" -l "$bench.log" -do 'run -all; quit -code 0 -f' > "$bench.console.log" 2>&1
  $body=Get-Content -Raw "$bench.log"
  $warnings=@($body -split "`n" | Where-Object {$_ -match '^# \*\* Warning:' -and $_ -notmatch 'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'})
  if($LASTEXITCODE -or $warnings.Count -or $body -notmatch 'PASS:' -or $body -match 'FAIL:|\*\* (Error|Fatal)'){throw "Failed test: $bench"}
  $body -split "`n" | Where-Object {$_ -match 'PASS:'} | Write-Output
 }
 if($Mode -eq 'RTL'){
  & 'E:/anaconda3/python.exe' -X utf8 (Join-Path $root 'tools/check_mpu_diag_pixels.py') $run
  if($LASTEXITCODE){throw 'LCD pixel check failed'}
 }
 $record.status='PASS'
}catch{$record.status='FAIL';$record['failure']=$_.Exception.Message;throw}
finally{$record['finished_utc']=[DateTime]::UtcNow.ToString('o');$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'verification.json') -Encoding utf8;Pop-Location}
