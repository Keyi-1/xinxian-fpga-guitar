param([Parameter(Mandatory=$true)][string]$RunDir,
      [Parameter(Mandatory=$true)][ValidateSet('baseline','direct_log','balanced_log')][string]$Variant,
      [ValidateSet('synthesis','route')][string]$Stage='synthesis',
      [string]$GowinExe='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe')
$ErrorActionPreference='Stop'
$RunDir=(Resolve-Path -LiteralPath $RunDir).Path
$manifestPath=Join-Path $RunDir 'manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
foreach($entry in $manifest.processes){
    if(Get-Process -Id $entry.pid -ErrorAction SilentlyContinue){throw "Recorded build PID $($entry.pid) still exists; inspect before starting another stage"}
}
if($manifest.processes | Where-Object {$_.variant -eq $Variant -and $_.stage -eq $Stage}){
    throw 'Stage already attempted; existing logs are preserved'
}
$folder=Join-Path $RunDir $Variant
foreach($entry in $manifest.variants.$Variant.PSObject.Properties){
    if((Get-FileHash (Join-Path $folder $entry.Name)).Hash.ToLower() -ne $entry.Value){throw "Snapshot changed: $($entry.Name)"}
}
if($Stage -eq 'route'){
    $log=Get-Content (Join-Path $folder 'synthesis.log') -Raw
    if($log -notmatch 'GowinSynthesis finish' -or $log -match 'ERROR'){throw 'A successful synthesis is required'}
}
$script=if($Stage -eq 'route'){'route.tcl'}else{'synth.tcl'}
$proc=Start-Process -FilePath $GowinExe -ArgumentList $script -WorkingDirectory $folder -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $folder "$Stage.log") `
    -RedirectStandardError (Join-Path $folder "$Stage.stderr.log") -PassThru
$manifest.processes+=@{variant=$Variant;stage=$Stage;pid=$proc.Id;
    started=(Get-Date).ToString('o');log=(Join-Path $folder "$Stage.log")}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Output "$Variant $Stage PID=$($proc.Id); log=$(Join-Path $folder "$Stage.log")"
