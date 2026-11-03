param([Parameter(Mandatory=$true)][string]$RunDir,
      [ValidateSet('synthesis','route')][string]$Stage='synthesis',
      [string]$GowinExe='S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe')
$ErrorActionPreference='Stop'
$RunDir=(Resolve-Path -LiteralPath $RunDir).Path
$manifestPath=Join-Path $RunDir 'manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
foreach($entry in $manifest.processes){
    if(Get-Process -Id $entry.pid -ErrorAction SilentlyContinue){throw "Recorded build PID $($entry.pid) is still running; inspect it before restarting"}
}
$repoDir=Split-Path $PSScriptRoot
foreach($entry in $manifest.source_sha256.PSObject.Properties){
    $current=(Get-FileHash -LiteralPath (Join-Path $repoDir $entry.Name)).Hash.ToLower()
    $frozen=(Get-FileHash -LiteralPath (Join-Path $RunDir "workspace/$($entry.Name)")).Hash.ToLower()
    if($current -ne $entry.Value -or $frozen -ne $entry.Value){throw "Source changed: $($entry.Name); prepare a new build"}
}
if($manifest.processes | Where-Object {$_.stage -eq $Stage}){throw "Stage already attempted; preserve its logs and choose a new run if retrying"}
$projectDir=$manifest.project
if($Stage -eq 'route'){
    $synLog=Get-Content -LiteralPath (Join-Path $RunDir 'synthesis.log') -Raw
    if($synLog -notmatch 'GowinSynthesis finish' -or $synLog -match 'ERROR'){throw 'A successful synthesis is required before P&R'}
    $vg=Join-Path $projectDir 'impl/gwsynthesis/neo_guitar_touch_game.vg'
    $vgHash=(Get-FileHash -LiteralPath $vg).Hash.ToLower()
    if($manifest.PSObject.Properties.Name -contains 'synthesized_netlist_sha256'){
        if($manifest.synthesized_netlist_sha256 -ne $vgHash){throw 'Netlist changed after synthesis'}
    }else{$manifest|Add-Member synthesized_netlist_sha256 $vgHash}
}
$script=if($Stage -eq 'route'){'route.tcl'}else{'synth.tcl'}
$proc=Start-Process -FilePath $GowinExe -ArgumentList $script -WorkingDirectory $projectDir -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $RunDir "$Stage.log") `
    -RedirectStandardError (Join-Path $RunDir "$Stage.stderr.log") -PassThru
$manifest.status=$Stage+'_running'
$manifest.processes+=@{stage=$Stage;pid=$proc.Id;started=(Get-Date).ToString('o');log=(Join-Path $RunDir "$Stage.log")}
$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath
Write-Output "$Stage PID=$($proc.Id); log=$(Join-Path $RunDir "$Stage.log")"
