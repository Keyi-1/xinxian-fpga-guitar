param([string]$RunName='impl_01')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if ($RunName -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid run name' }
$active=Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue
if ($active) { throw ('Gowin is already running: '+($active.Id -join ',')) }
$project=Join-Path $root 'gowin/neo_mpu6050_lcd_diagnostic/neo_mpu6050_lcd_diagnostic.gprj'
$run=Join-Path $root ('build/mpu_lcd_diagnostic/'+$RunName)
if (Test-Path -LiteralPath $run) { throw 'Run directory exists; inspect the previous process and logs first.' }
New-Item -ItemType Directory -Path $run | Out-Null
$inputs=@('gowin/neo_mpu6050_lcd_diagnostic/neo_mpu6050_lcd_diagnostic.gprj',
 'gowin/neo_mpu6050_lcd_diagnostic/impl/neo_mpu6050_lcd_diagnostic_process_config.json',
 'rtl/diagnostics/neo_mpu6050_lcd_diagnostic_top.v','rtl/diagnostics/mpu_lcd_diag_reader.v',
 'rtl/diagnostics/mpu_diag_i2c_master.v','rtl/diagnostics/mpu_lcd_diag_screen.v',
 'rtl/control/reset_sync.v','rtl/display/lcd_rgb_scan_480x272.v',
 'constraints/neo_mpu6050_lcd_diagnostic.cst','constraints/neo_mpu6050_lcd_diagnostic.sdc')
$hashes=[ordered]@{}
foreach ($relative in $inputs) { $hashes[$relative]=(Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash.ToLower() }
$config=Join-Path $root $inputs[1]
Copy-Item -LiteralPath $config -Destination (Join-Path $run 'process_config.before.json')
$tcl=Join-Path $run 'build.tcl'
$projectTcl=$project.Replace('\','/')
@"
open_project {$projectTcl}
if {[catch {run syn} message]} {puts stderr `$message;puts SYNTHESIS_TCL_FAILED;exit 1}
if {[catch {run pnr} message]} {puts stderr `$message;puts PNR_TCL_FAILED;exit 1}
puts PNR_TCL_FINISHED
exit
"@ | Set-Content -LiteralPath $tcl -Encoding ascii
$stdout=Join-Path $run 'build.stdout.log'
$stderr=Join-Path $run 'build.stderr.log'
$tool='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe'
$proc=Start-Process -FilePath $tool -ArgumentList @($tcl) -WorkingDirectory (Split-Path -Parent $project) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
[ordered]@{pid=$proc.Id;started_utc=$proc.StartTime.ToUniversalTime().ToString('o');
 head=(git -C $root rev-parse HEAD);artifact_scope='isolated MPU6050 LCD diagnostic project only';
 project=$project;tool=$tool;inputs_sha256=$hashes;stdout=$stdout;stderr=$stderr
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'process.json') -Encoding utf8
Write-Output ('Diagnostic build PID '+$proc.Id+'; logs: '+$run)
$proc.WaitForExit()
[ordered]@{pid=$proc.Id;exit_code=$proc.ExitCode;finished_utc=[DateTime]::UtcNow.ToString('o')} |
 ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'completion.json') -Encoding utf8
exit $proc.ExitCode
